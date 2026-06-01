//middleware/auth.js
const jwt = require('jsonwebtoken');
const { pool } = require('../config/database');

// ==================== AUTHENTICATION ====================

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(403).json({ error: 'Invalid or expired token.' });
  }
}

function optionalAuth(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token) {
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      req.user = decoded;
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
        'SELECT id FROM stores WHERE owner_id = $1 LIMIT 1',
        [req.user.userId]
      );
      if (storeResult.rows.length > 0) {
        storeContext = {
          store_id: storeResult.rows[0].id,
          role: 'owner',
          can_manage_inventory: true
        };
      }
    } else {
      const staffResult = await pool.query(
        'SELECT store_id, can_manage_inventory FROM store_staff WHERE user_id = $1 AND status = $2 LIMIT 1',
        [req.user.userId, 'accepted']
      );
      if (staffResult.rows.length > 0) {
        storeContext = {
          store_id: staffResult.rows[0].store_id,
          role: 'worker',
          can_manage_inventory: staffResult.rows[0].can_manage_inventory
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
};