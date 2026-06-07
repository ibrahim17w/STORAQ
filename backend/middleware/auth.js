//middleware/auth.js
const jwt = require('jsonwebtoken');
const { pool } = require('../config/database');

// Pin the algorithm explicitly to guard against algorithm-confusion
// attacks (e.g. forged "none" or asymmetric-as-HMAC tokens). Tokens
// issued by this service are signed with HS256, so verification stays
// identical for legitimate clients.
const JWT_VERIFY_OPTS = { algorithms: ['HS256'] };

// ==================== TOKEN-REVOCATION WATERMARK CACHE ====================
// When a user changes/resets their password we set users.password_changed_at
// = NOW(). Any token with `iat` older than that timestamp is rejected,
// which logs out every session (including attacker sessions on stolen
// tokens) the moment the legitimate user takes defensive action.
//
// The lookup runs on every authenticated request, so we cache the
// watermark per-user with a short TTL. Cache miss = one indexed PK
// lookup. We INVALIDATE the cache on password change (see invalidatePwdCache).
//
// The cache is process-local: in a multi-process deployment, the worst
// case is that a stale token works for up to PWD_CACHE_TTL_MS extra.
// 60s is the tradeoff: short enough to bound the window, long enough
// that 99%+ of authed requests skip the DB hit.
const PWD_CACHE_TTL_MS = 60 * 1000;
const PWD_CACHE_NEG_TTL_MS = 5 * 60 * 1000; // cache "no row" longer
const pwdChangedCache = new Map();
function _isFreshlyCached(entry) {
  const ttl = entry.epoch === null ? PWD_CACHE_NEG_TTL_MS : PWD_CACHE_TTL_MS;
  return (Date.now() - entry.fetchedAt) < ttl;
}
async function _getPwdChangedEpoch(userId) {
  const cached = pwdChangedCache.get(userId);
  if (cached && _isFreshlyCached(cached)) return cached.epoch;
  try {
    const result = await pool.query(
      'SELECT password_changed_at FROM users WHERE id = $1',
      [userId]
    );
    const ts = result.rows[0]?.password_changed_at;
    const epoch = ts ? new Date(ts).getTime() : null;
    pwdChangedCache.set(userId, { epoch, fetchedAt: Date.now() });
    return epoch;
  } catch (_) {
    // If the lookup fails, fail-open ONLY for the column-missing case
    // (fresh deploy before migration). Other DB errors → don't cache,
    // let next request retry; the caller treats null as "no revocation".
    return null;
  }
}
function invalidatePwdCache(userId) {
  pwdChangedCache.delete(userId);
}
// Sweep stale entries every 5 min so the Map can't grow without bound.
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of pwdChangedCache.entries()) {
    const ttl = v.epoch === null ? PWD_CACHE_NEG_TTL_MS : PWD_CACHE_TTL_MS;
    if (now - v.fetchedAt > ttl) pwdChangedCache.delete(k);
  }
}, 5 * 60 * 1000).unref();

// Reject the token if it was issued before the user's most recent
// password change. iat is in seconds (JWT spec), password_changed_at is
// converted to ms. Guests have no DB row, so always pass.
async function _isTokenRevokedByPasswordChange(decoded) {
  if (!decoded || decoded.role === 'guest') return false;
  if (!decoded.iat || !decoded.userId) return false;
  // Guest userIds are strings starting with "guest_" — they have no DB
  // row, skip the lookup. Real users are numeric ids.
  if (typeof decoded.userId === 'string' && decoded.userId.startsWith('guest_')) return false;
  const epoch = await _getPwdChangedEpoch(decoded.userId);
  if (epoch == null) return false;
  // Allow a 5s skew for clock drift between web nodes / DB.
  return (decoded.iat * 1000) < (epoch - 5000);
}

// ==================== AUTHENTICATION ====================

async function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  let decoded;
  try {
    decoded = jwt.verify(token, process.env.JWT_SECRET, JWT_VERIFY_OPTS);
  } catch (err) {
    return res.status(403).json({ error: 'Invalid or expired token.' });
  }
  if (await _isTokenRevokedByPasswordChange(decoded)) {
    return res.status(401).json({ error: 'Session expired. Please log in again.' });
  }
  req.user = decoded;
  next();
}

async function optionalAuth(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token) {
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET, JWT_VERIFY_OPTS);
      // Silently drop the token (don't 401) if password-revoked; the
      // route still functions for anonymous users.
      if (!(await _isTokenRevokedByPasswordChange(decoded))) {
        req.user = decoded;
      }
    } catch (_) {
      // silently ignore invalid optional tokens
    }
  }
  next();
}

function requireRealUser(req, res, next) {
  if (!req.user || req.user.role === 'guest') {
    return res.status(403).json({ error: 'This action requires a real user account.' });
  }
  next();
}

// ==================== STORE CONTEXT ====================

async function attachStoreContext(req, res, next) {
  if (!req.user || req.user.role === 'guest') {
    return next();
  }

  try {
    let storeContext = null;

    if (req.user.role === 'store_owner') {
      const storeResult = await pool.query(
        'SELECT id, COALESCE(is_active, TRUE) as is_active, deactivation_reason FROM stores WHERE owner_id = $1 LIMIT 1',
        [req.user.userId]
      );
      if (storeResult.rows.length > 0) {
        const store = storeResult.rows[0];
        storeContext = {
          store_id: store.id,
          role: 'owner',
          can_manage_inventory: true,
          is_active: store.is_active,
          deactivation_reason: store.deactivation_reason
        };
      }
    } else {
      const staffResult = await pool.query(
        `SELECT ss.store_id, ss.can_manage_inventory, COALESCE(s.is_active, TRUE) as is_active, s.deactivation_reason
         FROM store_staff ss
         JOIN stores s ON s.id = ss.store_id
         WHERE ss.user_id = $1 AND ss.status = $2 LIMIT 1`,
        [req.user.userId, 'accepted']
      );
      if (staffResult.rows.length > 0) {
        const row = staffResult.rows[0];
        storeContext = {
          store_id: row.store_id,
          role: 'worker',
          can_manage_inventory: row.can_manage_inventory,
          is_active: row.is_active,
          deactivation_reason: row.deactivation_reason
        };
      }
    }

    req.storeContext = storeContext;
    next();
  } catch (err) {
    console.error('attachStoreContext error:', err);
    next();
  }
}

// ==================== PERMISSION GUARDS ====================

function requireStoreOwner(req, res, next) {
  if (!req.storeContext || req.storeContext.role !== 'owner') {
    return res.status(403).json({ error: 'This action requires store owner privileges.' });
  }
  next();
}

function requireStoreAccess(req, res, next) {
  if (!req.storeContext) {
    return res.status(403).json({ error: 'You do not have access to any store.' });
  }
  if (req.storeContext.is_active === false) {
    return res.status(403).json({
      error: 'Your store has been deactivated due to a terms of use violation.',
      reason: req.storeContext.deactivation_reason || null,
      store_deactivated: true
    });
  }
  next();
}

function requireInventoryAccess(req, res, next) {
  if (!req.storeContext) {
    return res.status(403).json({ error: 'You do not have access to any store.' });
  }
  if (req.storeContext.role !== 'owner' && !req.storeContext.can_manage_inventory) {
    return res.status(403).json({
      error: 'You do not have permission to manage inventory. Ask your store owner to enable inventory management for your account.'
    });
  }
  next();
}

// ==================== RATE LIMITERS ====================

const loginAttempts = new Map();
const MAX_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 15;

function authLimiter(req, res, next) {
  const key = req.ip || req.connection.remoteAddress;
  const now = Date.now();

  if (loginAttempts.has(key)) {
    const record = loginAttempts.get(key);
    if (record.lockedUntil && now < record.lockedUntil) {
      const waitMin = Math.ceil((record.lockedUntil - now) / 60000);
      return res.status(429).json({
        error: `Too many requests. Please try again in ${waitMin} minutes.`
      });
    }
    if (now > record.lockedUntil) {
      loginAttempts.delete(key);
    }
  }
  next();
}

function loginIpLimiter(req, res, next) {
  const key = req.ip || req.connection.remoteAddress;
  const now = Date.now();

  if (loginAttempts.has(key)) {
    const record = loginAttempts.get(key);
    if (record.lockedUntil && now < record.lockedUntil) {
      const waitMin = Math.ceil((record.lockedUntil - now) / 60000);
      return res.status(429).json({
        error: `Too many failed attempts. Account locked for ${waitMin} minutes.`
      });
    }
  }
  next();
}

function recordFailedAttempt(ip) {
  const now = Date.now();
  if (!loginAttempts.has(ip)) {
    loginAttempts.set(ip, { count: 1, lockedUntil: null, lastAttempt: now });
  } else {
    const record = loginAttempts.get(ip);
    record.count++;
    record.lastAttempt = now;
    if (record.count >= MAX_ATTEMPTS) {
      record.lockedUntil = now + (LOCKOUT_MINUTES * 60 * 1000);
    }
  }
}

function clearFailedAttempts(ip) {
  loginAttempts.delete(ip);
}

// ==================== GENERIC PER-IP RATE LIMIT ====================
// Sliding-window counter, in-memory, suitable for single-process backend.
// Returns an express middleware function bound to (max, windowMs, keyPrefix).
// On exceed: HTTP 429 with a generic message (no Retry-After to avoid giving
// attackers exact reset timing). On success: increments counter and calls
// next() — counters are NOT cleared on success, since these endpoints are
// not "credentials right/wrong"; they just need to cap request rate.
//
// Keyed by `${keyPrefix}:${req.ip}`. Trust-proxy is set in config/app.js
// so req.ip reflects the real client behind a reverse proxy.
const rateBuckets = new Map();
function genericIpRateLimit({ max, windowMs, keyPrefix, message }) {
  const msg = message || 'Too many requests. Please try again later.';
  return function rateLimitMiddleware(req, res, next) {
    const ip = req.ip || (req.connection && req.connection.remoteAddress) || 'unknown';
    const key = `${keyPrefix}:${ip}`;
    const now = Date.now();
    const entry = rateBuckets.get(key);
    if (!entry || now - entry.firstAt > windowMs) {
      rateBuckets.set(key, { count: 1, firstAt: now });
      return next();
    }
    if (entry.count >= max) {
      return res.status(429).json({ error: msg });
    }
    entry.count += 1;
    next();
  };
}

// Sweep stale rate-limit buckets every 5 min so the Map can't grow without
// bound on a long-running process. .unref() so the timer never blocks exit.
setInterval(() => {
  const now = Date.now();
  // Use the largest sane window any bucket might use (24h) as the GC horizon.
  const HORIZON = 24 * 60 * 60 * 1000;
  for (const [key, entry] of rateBuckets.entries()) {
    if (now - entry.firstAt > HORIZON) rateBuckets.delete(key);
  }
}, 5 * 60 * 1000).unref();

// ==================== EXPORTS ====================

module.exports = {
  authenticateToken,
  optionalAuth,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  requireStoreAccess,
  requireInventoryAccess,
  authLimiter,
  loginIpLimiter,
  recordFailedAttempt,
  clearFailedAttempts,
  genericIpRateLimit,
  invalidatePwdCache,
  JWT_VERIFY_OPTS,
};