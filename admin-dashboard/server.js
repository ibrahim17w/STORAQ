const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express = require('express');
const cookieParser = require('cookie-parser');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const nodemailer = require('nodemailer');

// ─── Database ───────────────────────────────────────────────────────────────
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

async function runMigrations() {
  const client = await pool.connect();
  try {
    await client.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='is_admin') THEN
            ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT FALSE;
          END IF;
        END IF;
      END $$;
    `);

    // Forensic audit trail for sensitive admin actions. Append-only from
    // the application's perspective (we only INSERT, never UPDATE/DELETE).
    // Detail is stored as JSONB so we can record per-action context without
    // schema churn. NEVER store raw passwords, tokens, or PII in `detail`.
    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_audit_log (
        id BIGSERIAL PRIMARY KEY,
        admin_user_id INTEGER NOT NULL,
        admin_ip VARCHAR(64),
        action VARCHAR(64) NOT NULL,
        target_type VARCHAR(32),
        target_id VARCHAR(64),
        detail JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    await client.query(
      `CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_time ON admin_audit_log(admin_user_id, created_at DESC);`
    );
    await client.query(
      `CREATE INDEX IF NOT EXISTS idx_admin_audit_log_target ON admin_audit_log(target_type, target_id, created_at DESC);`
    );
    await client.query(`
      CREATE TABLE IF NOT EXISTS promo_codes (
        id SERIAL PRIMARY KEY,
        code VARCHAR(50) NOT NULL UNIQUE,
        type VARCHAR(20) DEFAULT 'discount',
        discount_percent INTEGER DEFAULT 0,
        discount_fixed DECIMAL(10,2) DEFAULT 0,
        tier_slug VARCHAR(30),
        grant_days INTEGER DEFAULT 0,
        max_redemptions INTEGER,
        times_used INTEGER DEFAULT 0,
        expires_at TIMESTAMP,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    // Add new columns if table already exists without them
    await client.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'promo_codes') THEN
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='type') THEN
            ALTER TABLE promo_codes ADD COLUMN type VARCHAR(20) DEFAULT 'discount';
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='tier_slug') THEN
            ALTER TABLE promo_codes ADD COLUMN tier_slug VARCHAR(30);
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='grant_days') THEN
            ALTER TABLE promo_codes ADD COLUMN grant_days INTEGER DEFAULT 0;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='min_account_age_days') THEN
            ALTER TABLE promo_codes ADD COLUMN min_account_age_days INTEGER;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='promo_codes' AND column_name='max_account_age_days') THEN
            ALTER TABLE promo_codes ADD COLUMN max_account_age_days INTEGER;
          END IF;
        END IF;
      END $$;
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS promo_redemptions (
        id SERIAL PRIMARY KEY,
        promo_id INTEGER NOT NULL REFERENCES promo_codes(id),
        store_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        tier_id INTEGER,
        starts_at TIMESTAMP DEFAULT NOW(),
        expires_at TIMESTAMP,
        status VARCHAR(20) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(promo_id, store_id)
      );
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_promo_redemptions_store ON promo_redemptions(store_id);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_promo_redemptions_status ON promo_redemptions(status, expires_at);`);
    await client.query(`
      CREATE TABLE IF NOT EXISTS support_tickets (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL,
        subject VARCHAR(200) NOT NULL,
        category VARCHAR(50) DEFAULT 'general',
        status VARCHAR(20) DEFAULT 'open',
        priority VARCHAR(20) DEFAULT 'normal',
        assigned_admin_id INTEGER,
        last_message_at TIMESTAMP DEFAULT NOW(),
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS support_ticket_messages (
        id SERIAL PRIMARY KEY,
        ticket_id INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        sender_role VARCHAR(20) NOT NULL DEFAULT 'user',
        body TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        read_at TIMESTAMP
      );
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status, last_message_at DESC);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_support_messages_ticket ON support_ticket_messages(ticket_id, created_at);`);
    await client.query(`
      ALTER TABLE support_tickets
        ADD COLUMN IF NOT EXISTS image_quota INTEGER NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS images_sent INTEGER NOT NULL DEFAULT 0;
    `);
    await client.query(`
      ALTER TABLE support_ticket_messages
        ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) NOT NULL DEFAULT 'text',
        ADD COLUMN IF NOT EXISTS attachment_url VARCHAR(500),
        ADD COLUMN IF NOT EXISTS request_status VARCHAR(20);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS store_reviews (
        id SERIAL PRIMARY KEY,
        store_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
        comment TEXT,
        status VARCHAR(20) DEFAULT 'active',
        removed_at TIMESTAMP,
        removed_by_admin_id INTEGER,
        removal_reason TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(store_id, user_id)
      );
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_store_reviews_store ON store_reviews(store_id, status, created_at DESC);`);

    await client.query(`
      CREATE TABLE IF NOT EXISTS product_reviews (
        id SERIAL PRIMARY KEY,
        product_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
        comment TEXT,
        status VARCHAR(20) DEFAULT 'active',
        removed_at TIMESTAMP,
        removed_by_admin_id INTEGER,
        removal_reason TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(product_id, user_id)
      );
    `);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_product_reviews_product ON product_reviews(product_id, status, created_at DESC);`);
    await client.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products') THEN
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='rating') THEN
            ALTER TABLE products ADD COLUMN rating DECIMAL(2,1) DEFAULT 5.0;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='review_count') THEN
            ALTER TABLE products ADD COLUMN review_count INTEGER DEFAULT 0;
          END IF;
        END IF;
      END $$;
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS flagged_stores (
        id SERIAL PRIMARY KEY,
        store_id INTEGER NOT NULL,
        reason VARCHAR(50) NOT NULL,
        details JSONB DEFAULT '{}',
        flagged_at TIMESTAMP DEFAULT NOW(),
        resolved BOOLEAN DEFAULT FALSE,
        resolved_at TIMESTAMP,
        UNIQUE(store_id)
      );
    `);
    await client.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stores') THEN
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='manual_approval_mode') THEN
            ALTER TABLE stores ADD COLUMN manual_approval_mode BOOLEAN DEFAULT FALSE;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='is_active') THEN
            ALTER TABLE stores ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='deactivated_at') THEN
            ALTER TABLE stores ADD COLUMN deactivated_at TIMESTAMP;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='deactivation_reason') THEN
            ALTER TABLE stores ADD COLUMN deactivation_reason TEXT;
          END IF;
        END IF;
      END $$;
    `);

    // Seed FOUNDER30 if not exists
    await client.query(`
      INSERT INTO promo_codes (code, type, tier_slug, grant_days, max_redemptions, is_active)
      VALUES ('FOUNDER30', 'tier_grant', 'business', 90, 30, TRUE)
      ON CONFLICT (code) DO NOTHING;
    `);

    console.log('[admin] Migrations OK');
  } catch (err) {
    console.error('[admin] Migration warning:', err.message);
  } finally {
    client.release();
  }
}

// ─── Auth Middleware ─────────────────────────────────────────────────────────
const COOKIE_NAME = 'admin_token';

function setTokenCookie(res, token) {
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    // 'strict' kills CSRF entirely for admin actions: the browser will
    // never attach this cookie to cross-site top-level navigations or
    // sub-requests. The admin dashboard is a single first-party SPA so
    // there is no legitimate cross-site flow that needs it. ('lax' would
    // still leak the cookie on top-level GETs initiated from third-party
    // sites, which is an open door for "click this link" CSRF.)
    sameSite: 'strict',
    maxAge: 24 * 60 * 60 * 1000,
    path: '/',
  });
}

function isAdmin(req, res, next) {
  const token = req.cookies?.[COOKIE_NAME];
  if (!token) return res.status(401).json({ error: 'Not authenticated' });
  try {
    // Pin algorithm to HS256 — tokens are signed with HS256 in jwt.sign
    // below, so this guards against algorithm-confusion attacks without
    // changing behavior for legitimate sessions.
    const payload = jwt.verify(token, process.env.ADMIN_JWT_SECRET, { algorithms: ['HS256'] });
    if (!payload.isAdmin) return res.status(403).json({ error: 'Forbidden' });
    req.admin = payload;
    next();
  } catch (err) {
    res.clearCookie(COOKIE_NAME, { path: '/' });
    return res.status(401).json({ error: 'Session expired' });
  }
}

// Forensic audit logger for sensitive admin actions. Fire-and-forget: a
// logging failure must never fail the underlying request, so we swallow
// errors. Never put raw passwords, JWT contents, or PII into `detail`.
let emailTransporter = null;
if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
  emailTransporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: process.env.SMTP_SECURE === 'true',
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
}

async function sendAdminEmail({ to, subject, html }) {
  if (!emailTransporter) {
    throw new Error('SMTP not configured — set SMTP_HOST, SMTP_USER, SMTP_PASS in admin .env');
  }
  const from = process.env.FROM_EMAIL || process.env.SMTP_USER;
  return emailTransporter.sendMail({ from, to, subject, html });
}

async function recalcStoreRatingAdmin(storeId, client = pool) {
  await client.query(
    `UPDATE stores
     SET rating = COALESCE((
       SELECT ROUND(AVG(rating)::numeric, 1)
       FROM store_reviews
       WHERE store_id = $1 AND status = 'active'
     ), 5.0)
     WHERE id = $1`,
    [storeId]
  );
}

async function recalcProductRatingAdmin(productId, client = pool) {
  const stats = await client.query(
    `SELECT COUNT(*)::int AS total,
            COALESCE(ROUND(AVG(rating)::numeric, 1), 5.0) AS avg_rating
     FROM product_reviews
     WHERE product_id = $1 AND status = 'active'`,
    [productId]
  );
  const row = stats.rows[0] || { total: 0, avg_rating: 5.0 };
  await client.query(
    `UPDATE products SET rating = $2, review_count = $3 WHERE id = $1`,
    [productId, row.avg_rating, row.total]
  );
}

async function auditAdmin(req, action, target, detail) {
  try {
    await pool.query(
      `INSERT INTO admin_audit_log (admin_user_id, admin_ip, action, target_type, target_id, detail)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        req.admin?.userId ?? null,
        (req.ip || '').toString().substring(0, 64),
        action.substring(0, 64),
        target?.type ? String(target.type).substring(0, 32) : null,
        target?.id != null ? String(target.id).substring(0, 64) : null,
        detail ? JSON.stringify(detail) : null,
      ]
    );
  } catch (err) {
    console.error('[audit] insert failed:', err.message);
  }
}

// ─── Express App ─────────────────────────────────────────────────────────────
const app = express();
const PORT = process.env.PORT || 4400;

// Trust the reverse proxy so req.ip reflects the real client. Without this,
// the per-IP login rate limit below collapses to a single bucket behind a
// load balancer / Cloudflare.
app.set('trust proxy', 1);

// Per-request timeout — same rationale as backend/config/app.js: cap
// slowloris and held-socket DoS. Admin payloads are tiny JSON; 30s is
// generous.
app.use((req, res, next) => {
  req.setTimeout(30 * 1000, () => {
    try { req.destroy(); } catch (_) {}
  });
  res.setTimeout(30 * 1000, () => {
    try { res.end(); } catch (_) {}
  });
  next();
});

// Hide framework fingerprint.
app.disable('x-powered-by');

// ── Security headers (hand-rolled so we don't add a runtime dep here) ──
// Equivalent to the essentials helmet would set, scoped to what the admin
// dashboard actually needs. CSP is intentionally STRICT because the only
// HTML served from this origin is /public/index.html, which we control.
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  res.setHeader(
    'Permissions-Policy',
    'camera=(), microphone=(), geolocation=(), payment=(), usb=()'
  );
  if (process.env.NODE_ENV === 'production') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  }
  // 'unsafe-inline' for style+script is required by the existing inline
  // dashboard page; tighten later by extracting inline assets into files.
  res.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'self'",
      // Analytics page loads Chart.js + Leaflet from jsDelivr CDN.
      "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net",
      "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.googleapis.com",
      // Product images + OpenStreetMap raster tiles for the store map.
      "img-src 'self' data: blob: https: https://*.tile.openstreetmap.org https://tile.openstreetmap.org",
      "font-src 'self' data: https://fonts.gstatic.com",
      "connect-src 'self'",
      "object-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'",
    ].join('; ')
  );
  next();
});

// Log every API request without leaking request bodies (passwords/tokens).
app.use((req, res, next) => {
  if (req.path.startsWith('/api/')) {
    console.log(`[${req.method}] ${req.path}`);
  }
  next();
});

// Cap admin JSON body to 256kb — admin endpoints never accept media, only
// short JSON payloads (promo codes, payment IDs, notes). Express default is
// 100kb; we set explicitly to make the contract visible.
app.use(express.json({ limit: '256kb' }));
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public'), {
  dotfiles: 'deny',
  index: ['index.html'],
}));

const uploadsDir =
  process.env.UPLOADS_DIR || path.join(__dirname, '..', 'backend', 'uploads');
const mediaBaseUrl = (process.env.BACKEND_URL || process.env.MEDIA_BASE_URL || 'http://localhost:3000')
  .replace(/\/$/, '');
if (fs.existsSync(uploadsDir)) {
  app.use('/uploads', express.static(uploadsDir, { dotfiles: 'deny', maxAge: '1h' }));
  console.log('[admin] Serving uploads from', uploadsDir);
} else {
  console.warn('[admin] Uploads directory not found:', uploadsDir);
  console.warn('[admin] Support images will use BACKEND_URL:', mediaBaseUrl);
}

app.get('/api/config', (req, res) => {
  res.json({ mediaBaseUrl });
});

// ── Login rate limit (in-memory, per IP + per emailHash) ──
// Without this, /api/auth/login is open to unlimited credential-stuffing.
// We track failures both by IP (catches bot networks targeting one admin
// account) and by emailHash (catches one bot rotating many IPs against the
// same admin). The store is in-memory: good enough for the single-process
// admin dashboard; if the admin is ever scaled horizontally, swap for Redis.
const LOGIN_WINDOW_MS = 15 * 60 * 1000; // 15 min sliding window
const LOGIN_MAX_PER_IP = 20;            // 20 failed attempts / 15min / IP
const LOGIN_MAX_PER_EMAIL = 5;          // 5 failed attempts / 15min / email
const loginAttempts = new Map();        // key -> { count, firstAt }

function pruneLoginEntry(key, now) {
  const entry = loginAttempts.get(key);
  if (!entry) return null;
  if (now - entry.firstAt > LOGIN_WINDOW_MS) {
    loginAttempts.delete(key);
    return null;
  }
  return entry;
}

function checkLoginLimit(req, emailHash) {
  const now = Date.now();
  const ipKey = `ip:${req.ip}`;
  const emailKey = `em:${emailHash}`;
  const ipEntry = pruneLoginEntry(ipKey, now);
  const emailEntry = pruneLoginEntry(emailKey, now);
  if (ipEntry && ipEntry.count >= LOGIN_MAX_PER_IP) return { allowed: false, reason: 'ip' };
  if (emailEntry && emailEntry.count >= LOGIN_MAX_PER_EMAIL) return { allowed: false, reason: 'email' };
  return { allowed: true };
}

function recordLoginFailure(req, emailHash) {
  const now = Date.now();
  for (const key of [`ip:${req.ip}`, `em:${emailHash}`]) {
    const entry = pruneLoginEntry(key, now) || { count: 0, firstAt: now };
    entry.count += 1;
    loginAttempts.set(key, entry);
  }
}

function recordLoginSuccess(req, emailHash) {
  loginAttempts.delete(`ip:${req.ip}`);
  loginAttempts.delete(`em:${emailHash}`);
}

// Periodically sweep stale entries so the Map cannot grow unbounded.
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of loginAttempts.entries()) {
    if (now - entry.firstAt > LOGIN_WINDOW_MS) loginAttempts.delete(key);
  }
}, 60 * 1000).unref();

// Health check endpoint (no auth needed, useful for debugging)
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// ─── Auth Routes ─────────────────────────────────────────────────────────────
app.post('/api/auth/login', async (req, res) => {
  try {
    // Cap email/password sizes BEFORE any expensive work. Without this,
    // an attacker can POST a 256kb password (the json body limit) and
    // force the server to run bcrypt.compare across it, burning CPU per
    // request. bcrypt natively truncates to 72 bytes, but the input
    // allocation + initial hashing still costs. Cap to lengths no
    // real human types.
    const rawEmail = typeof req.body.email === 'string' ? req.body.email.substring(0, 320) : '';
    const password = typeof req.body.password === 'string' ? req.body.password.substring(0, 256) : '';
    if (!rawEmail || !password) return res.status(400).json({ error: 'Email and password required' });

    const normalizedEmail = rawEmail.toLowerCase().trim();
    const emailHashShort = require('crypto')
      .createHash('sha256').update(normalizedEmail).digest('hex').substring(0, 10);

    const gate = checkLoginLimit(req, emailHashShort);
    if (!gate.allowed) {
      console.log('[login] Rate-limited (', gate.reason, ') email#', emailHashShort, 'ip', req.ip);
      // 429 with no Retry-After detail — don't let attackers measure exact
      // window remaining to optimize their throttling.
      return res.status(429).json({ error: 'Too many attempts, try again later' });
    }

    console.log('[login] Attempt for email#', emailHashShort);

    const result = await pool.query(
      `SELECT id, full_name, email, password_hash, role,
              COALESCE(is_admin, FALSE) as is_admin
       FROM users WHERE email = $1`,
      [normalizedEmail]
    );

    if (result.rows.length === 0) {
      recordLoginFailure(req, emailHashShort);
      console.log('[login] No such user (email#', emailHashShort, ')');
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];

    const hasAdminAccess = user.is_admin === true || user.role === 'admin';
    if (!hasAdminAccess) {
      recordLoginFailure(req, emailHashShort);
      console.log('[login] Non-admin user id:', user.id);
      // Return the same generic message as the no-such-user branch so an
      // attacker can't enumerate which emails are linked to admin accounts
      // (the previous "not registered as an admin" reply was an oracle).
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      recordLoginFailure(req, emailHashShort);
      console.log('[login] Bad password for user id:', user.id);
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    recordLoginSuccess(req, emailHashShort);

    const token = jwt.sign({ userId: user.id, email: user.email, isAdmin: true }, process.env.ADMIN_JWT_SECRET, { expiresIn: '24h' });
    setTokenCookie(res, token);
    console.log('[login] Success for user id:', user.id);
    res.json({ user: { id: user.id, full_name: user.full_name, email: user.email } });
  } catch (err) {
    console.error('[login] Error:', err.message);
    // Never echo err.message: it can include DB connection strings,
    // bcrypt internals, or SQL syntax when the DB is misconfigured.
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/auth/logout', (req, res) => {
  res.clearCookie(COOKIE_NAME, { path: '/' });
  res.json({ message: 'Logged out' });
});

app.get('/api/auth/me', isAdmin, (req, res) => {
  res.json({ user: { id: req.admin.userId, email: req.admin.email } });
});

// ─── Stats ───────────────────────────────────────────────────────────────────
app.get('/api/stats', isAdmin, async (req, res) => {
  try {
    const [products, payments, promos, flagged, stores, users, deactivated, supportOpen, sponsorPayments, activeCampaigns] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int as count FROM products WHERE pending_approval = TRUE`),
      pool.query(`SELECT COUNT(*)::int as count FROM subscription_payments WHERE status = 'pending'`),
      pool.query(`SELECT COUNT(*)::int as count FROM promo_codes WHERE is_active = TRUE`),
      pool.query(`SELECT COUNT(*)::int as count FROM flagged_stores WHERE resolved = FALSE`),
      pool.query(`SELECT COUNT(*)::int as count FROM stores`),
      pool.query(`SELECT COUNT(*)::int as count FROM users`),
      pool.query(`SELECT COUNT(*)::int as count FROM stores WHERE is_active = FALSE`),
      pool.query(`SELECT COUNT(*)::int as count FROM support_tickets WHERE status IN ('open', 'in_progress')`),
      pool.query(`SELECT COUNT(*)::int as count FROM sponsored_product_payments WHERE status = 'pending'`).catch(() => ({ rows: [{ count: 0 }] })),
      pool.query(`SELECT COUNT(*)::int as count FROM sponsored_product_campaigns WHERE status = 'active' AND expires_at > NOW()`).catch(() => ({ rows: [{ count: 0 }] })),
    ]);
    res.json({
      pending_products: products.rows[0].count,
      pending_payments: payments.rows[0].count,
      pending_sponsor_payments: sponsorPayments.rows[0].count,
      active_sponsor_campaigns: activeCampaigns.rows[0].count,
      active_promos: promos.rows[0].count,
      flagged_stores: flagged.rows[0].count,
      total_stores: stores.rows[0].count,
      total_users: users.rows[0].count,
      deactivated_stores: deactivated.rows[0].count,
      open_support_tickets: supportOpen.rows[0].count,
    });
  } catch (err) {
    console.error('Stats error:', err.message);
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// ─── Analytics (platform monitoring) ─────────────────────────────────────────
// Aggregated read-only metrics for the admin Analytics tab: map pins, sales
// trends, engagement, and recent transactions. Every sub-query is defensive
// (empty array / zero on missing tables) so a fresh DB still renders.
app.get('/api/analytics/overview', isAdmin, async (req, res) => {
  const safeQuery = async (sql, params) => {
    try {
      const r = await pool.query(sql, params);
      return r.rows;
    } catch (err) {
      console.error('[analytics] sub-query failed:', err.message);
      return [];
    }
  };

  try {
    const [
      summaryRow,
      storesMap,
      signupsByDay,
      visitsByDay,
      viewsByDay,
      subscriptionRevenue,
      sponsorshipRevenue,
      pendingSubscriptionPayments,
      pendingSponsorshipPayments,
      subscriptionPaymentsByDay,
      sponsorshipPaymentsByDay,
      recentSubscriptionPayments,
      recentSponsorshipPayments,
      storesByDay,
    ] = await Promise.all([
      pool.query(`
        SELECT
          (SELECT COUNT(*)::int FROM users) AS total_users,
          (SELECT COUNT(*)::int FROM users WHERE created_at >= NOW() - INTERVAL '7 days') AS new_users_7d,
          (SELECT COUNT(*)::int FROM stores) AS total_stores,
          (SELECT COUNT(*)::int FROM stores WHERE COALESCE(is_active, TRUE) = TRUE) AS active_stores,
          (SELECT COUNT(*)::int FROM products WHERE is_online = TRUE) AS online_products,
          (SELECT COUNT(*)::int FROM products) AS total_products,
          (SELECT COUNT(*)::int FROM support_tickets WHERE status IN ('open', 'in_progress')) AS open_support_tickets,
          (SELECT COUNT(*)::int FROM subscription_payments WHERE status = 'pending') AS pending_subscription_payments,
          (SELECT COUNT(*)::int FROM sponsored_product_payments WHERE status = 'pending') AS pending_sponsorship_payments,
          (SELECT COALESCE(SUM(amount_usd), 0)::float FROM subscription_payments WHERE status = 'verified') AS verified_subscription_usd,
          (SELECT COALESCE(SUM(amount_usd), 0)::float FROM sponsored_product_payments WHERE status = 'verified') AS verified_sponsorship_usd,
          (SELECT COALESCE(SUM(amount_usd), 0)::float FROM subscription_payments
             WHERE status = 'verified' AND verified_at >= CURRENT_DATE) AS subscription_usd_today,
          (SELECT COALESCE(SUM(amount_usd), 0)::float FROM sponsored_product_payments
             WHERE status = 'verified' AND verified_at >= CURRENT_DATE) AS sponsorship_usd_today
      `).then((r) => r.rows[0]),

      safeQuery(`
        SELECT s.id, s.name, s.city, s.country, s.country_code,
               s.lat, s.lng,
               COALESCE(s.is_active, TRUE) AS is_active,
               s.created_at,
               (SELECT COUNT(*)::int FROM products p WHERE p.store_id = s.id) AS product_count,
               (SELECT COUNT(*)::int FROM products p2 WHERE p2.store_id = s.id AND p2.is_online = TRUE) AS online_product_count
        FROM stores s
        ORDER BY s.created_at DESC
        LIMIT 500
      `),

      safeQuery(`
        SELECT DATE(created_at) AS date, COUNT(*)::int AS count
        FROM users
        WHERE created_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(created_at)
        ORDER BY date ASC
      `),

      safeQuery(`
        SELECT DATE(visited_at) AS date, COUNT(*)::int AS count
        FROM store_visits
        WHERE visited_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(visited_at)
        ORDER BY date ASC
      `),

      safeQuery(`
        SELECT DATE(viewed_at) AS date, COUNT(*)::int AS count
        FROM product_views
        WHERE viewed_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(viewed_at)
        ORDER BY date ASC
      `),

      safeQuery(`
        SELECT COALESCE(SUM(amount_usd), 0)::float AS total_usd
        FROM subscription_payments
        WHERE status = 'verified'
      `).then((rows) => rows[0]?.total_usd ?? 0),

      safeQuery(`
        SELECT COALESCE(SUM(amount_usd), 0)::float AS total_usd
        FROM sponsored_product_payments
        WHERE status = 'verified'
      `).then((rows) => rows[0]?.total_usd ?? 0),

      safeQuery(`
        SELECT COUNT(*)::int AS count FROM subscription_payments WHERE status = 'pending'
      `).then((rows) => rows[0]?.count ?? 0),

      safeQuery(`
        SELECT COUNT(*)::int AS count FROM sponsored_product_payments WHERE status = 'pending'
      `).then((rows) => rows[0]?.count ?? 0),

      safeQuery(`
        SELECT DATE(verified_at) AS date,
               COALESCE(SUM(amount_usd), 0)::float AS revenue,
               COUNT(*)::int AS count
        FROM subscription_payments
        WHERE status = 'verified'
          AND verified_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(verified_at)
        ORDER BY date ASC
      `),

      safeQuery(`
        SELECT DATE(verified_at) AS date,
               COALESCE(SUM(amount_usd), 0)::float AS revenue,
               COUNT(*)::int AS count
        FROM sponsored_product_payments
        WHERE status = 'verified'
          AND verified_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(verified_at)
        ORDER BY date ASC
      `),

      safeQuery(`
        SELECT sp.id, sp.amount_usd, sp.payment_track, sp.reference_code,
               sp.verified_at, sp.created_at,
               s.name AS store_name, u.full_name AS owner_name, u.email AS owner_email,
               t.name AS tier_name
        FROM subscription_payments sp
        JOIN stores s ON s.id = sp.store_id
        JOIN users u ON u.id = s.owner_id
        LEFT JOIN subscription_tiers t ON t.id = sp.tier_id
        WHERE sp.status = 'verified'
        ORDER BY sp.verified_at DESC NULLS LAST, sp.created_at DESC
        LIMIT 15
      `),

      safeQuery(`
        SELECT sp.id, sp.amount_usd, sp.payment_track, sp.reference_code,
               sp.verified_at, sp.created_at,
               p.name AS product_name, s.name AS store_name,
               u.full_name AS owner_name, u.email AS owner_email
        FROM sponsored_product_payments sp
        JOIN products p ON p.id = sp.product_id
        JOIN stores s ON s.id = sp.store_id
        JOIN users u ON u.id = s.owner_id
        WHERE sp.status = 'verified'
        ORDER BY sp.verified_at DESC NULLS LAST, sp.created_at DESC
        LIMIT 15
      `),

      safeQuery(`
        SELECT DATE(created_at) AS date, COUNT(*)::int AS count
        FROM stores
        WHERE created_at >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(created_at)
        ORDER BY date ASC
      `),
    ]);

    // Engagement counts — separate queries so missing tables don't break summary.
    const visits7d = await safeQuery(
      `SELECT COUNT(*)::int AS c FROM store_visits WHERE visited_at >= NOW() - INTERVAL '7 days'`
    );
    const views7d = await safeQuery(
      `SELECT COUNT(*)::int AS c FROM product_views WHERE viewed_at >= NOW() - INTERVAL '7 days'`
    );
    const searches7d = await safeQuery(
      `SELECT COUNT(*)::int AS c FROM search_queries WHERE searched_at >= NOW() - INTERVAL '7 days'`
    );

    const mapStores = storesMap.filter(
      (s) => s.lat != null && s.lng != null && !Number.isNaN(parseFloat(s.lat)) && !Number.isNaN(parseFloat(s.lng))
    );

    res.json({
      summary: {
        total_users: summaryRow.total_users || 0,
        new_users_7d: summaryRow.new_users_7d || 0,
        total_stores: summaryRow.total_stores || 0,
        active_stores: summaryRow.active_stores || 0,
        online_products: summaryRow.online_products || 0,
        total_products: summaryRow.total_products || 0,
        open_support_tickets: summaryRow.open_support_tickets || 0,
        store_visits_7d: visits7d[0]?.c ?? 0,
        product_views_7d: views7d[0]?.c ?? 0,
        searches_7d: searches7d[0]?.c ?? 0,
        verified_subscription_usd: parseFloat(summaryRow.verified_subscription_usd) || parseFloat(subscriptionRevenue) || 0,
        verified_sponsorship_usd: parseFloat(summaryRow.verified_sponsorship_usd) || parseFloat(sponsorshipRevenue) || 0,
        verified_payments_usd:
          (parseFloat(summaryRow.verified_subscription_usd) || parseFloat(subscriptionRevenue) || 0) +
          (parseFloat(summaryRow.verified_sponsorship_usd) || parseFloat(sponsorshipRevenue) || 0),
        payments_usd_today:
          (parseFloat(summaryRow.subscription_usd_today) || 0) +
          (parseFloat(summaryRow.sponsorship_usd_today) || 0),
        pending_subscription_payments: summaryRow.pending_subscription_payments ?? pendingSubscriptionPayments ?? 0,
        pending_sponsorship_payments: summaryRow.pending_sponsorship_payments ?? pendingSponsorshipPayments ?? 0,
        stores_on_map: mapStores.length,
        stores_without_location: (storesMap.length - mapStores.length),
      },
      stores_map: mapStores,
      stores_all: storesMap,
      signups_by_day: signupsByDay,
      visits_by_day: visitsByDay,
      views_by_day: viewsByDay,
      stores_by_day: storesByDay,
      subscription_payments_by_day: subscriptionPaymentsByDay,
      sponsorship_payments_by_day: sponsorshipPaymentsByDay,
      recent_subscription_payments: recentSubscriptionPayments,
      recent_sponsorship_payments: recentSponsorshipPayments,
    });
  } catch (err) {
    console.error('Analytics overview error:', err.message);
    res.status(500).json({ error: 'Failed to load analytics' });
  }
});

// ─── Products (Pending Approval) ────────────────────────────────────────────
app.get('/api/products/pending', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.id, p.name, p.price, p.currency, p.image_url, p.images, p.description, p.created_at,
              s.id as store_id, s.name as store_name, u.full_name as owner_name, u.email as owner_email
       FROM products p JOIN stores s ON s.id = p.store_id JOIN users u ON u.id = s.owner_id
       WHERE p.pending_approval = TRUE ORDER BY p.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) { res.status(500).json({ error: 'Failed to fetch' }); }
});

app.post('/api/products/:id/approve', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'Invalid id' });
    // Atomic claim: only one admin can flip pending_approval. The old
    // SELECT-then-UPDATE pattern let a double-click bypass the
    // "Not pending" guard, push the product online twice, and (on free
    // tier) silently exceed the slot cap by flipping is_online without
    // a slot check. Doing the flip in a single UPDATE-RETURNING is
    // race-free.
    const claim = await pool.query(
      `UPDATE products
         SET pending_approval = FALSE, is_online = TRUE, went_online_at = NOW()
       WHERE id = $1 AND pending_approval = TRUE
       RETURNING id, store_id`,
      [id]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Product is not pending approval' });
    }
    await pool.query('UPDATE stores SET first_product_approved = TRUE WHERE id = $1', [claim.rows[0].store_id]);
    auditAdmin(req, 'product.approve', { type: 'product', id }, { store_id: claim.rows[0].store_id });
    res.json({ message: 'Approved', product_id: id });
  } catch (err) {
    console.error('Product approve error:', err.message);
    res.status(500).json({ error: 'Failed' });
  }
});

app.post('/api/products/:id/reject', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'Invalid id' });
    // Atomic claim — same shape as approve. Also restricts to currently
    // pending rows so a rejected/already-rejected row can't be silently
    // double-rejected with different reasons.
    const claim = await pool.query(
      `UPDATE products
         SET pending_approval = FALSE, is_online = FALSE, went_online_at = NULL
       WHERE id = $1 AND pending_approval = TRUE
       RETURNING id`,
      [id]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Product is not pending approval' });
    }
    const reason = typeof req.body.reason === 'string' ? req.body.reason.substring(0, 500) : null;
    auditAdmin(req, 'product.reject', { type: 'product', id }, { reason });
    res.json({ message: 'Rejected', product_id: id, reason });
  } catch (err) {
    console.error('Product reject error:', err.message);
    res.status(500).json({ error: 'Failed' });
  }
});

// ─── Payments (Pending Subscription) ────────────────────────────────────────
app.get('/api/payments/pending', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT sp.*, st.name as tier_name, st.online_slots, st.price_usd_monthly,
              s.name as store_name, u.full_name as owner_name, u.email as owner_email
       FROM subscription_payments sp
       JOIN subscription_tiers st ON sp.tier_id = st.id
       JOIN stores s ON sp.store_id = s.id
       JOIN users u ON s.owner_id = u.id
       WHERE sp.status = 'pending' ORDER BY sp.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) { res.status(500).json({ error: 'Failed to fetch' }); }
});

app.post('/api/payments/:id/verify', isAdmin, async (req, res) => {
  const client = await pool.connect();
  let inTx = false;
  try {
    const id = parseInt(req.params.id);
    await client.query('BEGIN');
    inTx = true;
    // Atomic claim: only ONE caller can flip status from 'pending' to
    // 'verified'. The previous SELECT-then-UPDATE pattern let two admins
    // (or one admin double-clicking) both succeed and provision two
    // 30-day subscriptions for the same payment.
    const claim = await client.query(
      `UPDATE subscription_payments
         SET status = 'verified', verified_by = $1, verified_at = NOW()
       WHERE id = $2 AND status = 'pending'
       RETURNING *`,
      [req.admin.userId, id]
    );
    if (claim.rows.length === 0) {
      await client.query('ROLLBACK');
      inTx = false;
      return res.status(409).json({ error: 'Payment is not pending (already verified or rejected)' });
    }
    const p = claim.rows[0];
    await client.query(
      `UPDATE store_subscriptions SET status = 'expired', updated_at = NOW()
       WHERE store_id = $1 AND status = 'active'`,
      [p.store_id]
    );
    const exp = new Date(); exp.setDate(exp.getDate() + 30);
    await client.query(
      `INSERT INTO store_subscriptions (store_id, tier_id, status, starts_at, expires_at)
       VALUES ($1, $2, 'active', NOW(), $3)`,
      [p.store_id, p.tier_id, exp]
    );
    await client.query('COMMIT');
    inTx = false;
    auditAdmin(req, 'subscription_payment.verify',
      { type: 'subscription_payment', id: p.id },
      { store_id: p.store_id, tier_id: p.tier_id, amount_usd: p.amount_usd });
    res.json({ message: 'Payment verified, subscription active for 30 days' });
  } catch (err) {
    if (inTx) { try { await client.query('ROLLBACK'); } catch (_) {} }
    console.error('Subscription verify error:', err.message);
    res.status(500).json({ error: 'Failed' });
  } finally { client.release(); }
});

// ─── Promo Codes ─────────────────────────────────────────────────────────────
app.get('/api/promos', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT pc.*, 
        (SELECT COUNT(*)::int FROM promo_redemptions pr WHERE pr.promo_id = pc.id) as total_redemptions,
        (SELECT COUNT(*)::int FROM promo_redemptions pr WHERE pr.promo_id = pc.id AND pr.status = 'active') as active_redemptions
      FROM promo_codes pc ORDER BY pc.created_at DESC
    `);
    res.json(result.rows);
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// Whitelist of accepted promo types — kept aligned with the redemption
// path so a typo in the admin form can't create a code that's later
// rejected during redemption with an unhelpful error.
const ALLOWED_PROMO_TYPES = new Set(['discount', 'tier_grant']);

app.post('/api/promos', isAdmin, async (req, res) => {
  try {
    const {
      code, type, discount_percent, discount_fixed, tier_slug, grant_days,
      max_redemptions, expires_at, min_account_age_days, max_account_age_days,
    } = req.body;
    if (!code || code.trim().length < 3 || code.trim().length > 50) {
      return res.status(400).json({ error: 'Code must be 3–50 chars' });
    }

    const promoType = type || 'discount';
    if (!ALLOWED_PROMO_TYPES.has(promoType)) {
      return res.status(400).json({ error: 'Invalid promo type' });
    }
    if (promoType === 'tier_grant' && (!tier_slug || !grant_days)) {
      return res.status(400).json({ error: 'tier_slug and grant_days required for tier_grant type' });
    }

    const minAge = min_account_age_days != null && min_account_age_days !== ''
      ? parseInt(min_account_age_days) : null;
    const maxAge = max_account_age_days != null && max_account_age_days !== ''
      ? parseInt(max_account_age_days) : null;

    const result = await pool.query(
      `INSERT INTO promo_codes (
         code, type, discount_percent, discount_fixed, tier_slug, grant_days,
         max_redemptions, expires_at, min_account_age_days, max_account_age_days
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [
        code.trim().toUpperCase(),
        promoType,
        parseInt(discount_percent) || 0,
        parseFloat(discount_fixed) || 0,
        tier_slug || null,
        parseInt(grant_days) || 0,
        max_redemptions ? parseInt(max_redemptions) : null,
        expires_at || null,
        Number.isInteger(minAge) && minAge > 0 ? minAge : null,
        Number.isInteger(maxAge) && maxAge > 0 ? maxAge : null,
      ]
    );
    auditAdmin(req, 'promo.create', { type: 'promo', id: result.rows[0].id },
      { code: result.rows[0].code, type: promoType, tier_slug: result.rows[0].tier_slug });
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Code already exists' });
    res.status(500).json({ error: 'Failed' });
  }
});

app.patch('/api/promos/:id', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const {
      is_active, max_redemptions, expires_at, min_account_age_days, max_account_age_days,
    } = req.body;
    const fields = []; const values = []; let idx = 1;
    if (is_active !== undefined) { fields.push(`is_active = $${idx++}`); values.push(is_active); }
    if (max_redemptions !== undefined) { fields.push(`max_redemptions = $${idx++}`); values.push(max_redemptions ? parseInt(max_redemptions) : null); }
    if (expires_at !== undefined) { fields.push(`expires_at = $${idx++}`); values.push(expires_at || null); }
    if (min_account_age_days !== undefined) {
      const v = min_account_age_days === '' || min_account_age_days == null
        ? null : parseInt(min_account_age_days);
      fields.push(`min_account_age_days = $${idx++}`);
      values.push(Number.isInteger(v) && v > 0 ? v : null);
    }
    if (max_account_age_days !== undefined) {
      const v = max_account_age_days === '' || max_account_age_days == null
        ? null : parseInt(max_account_age_days);
      fields.push(`max_account_age_days = $${idx++}`);
      values.push(Number.isInteger(v) && v > 0 ? v : null);
    }
    if (fields.length === 0) return res.status(400).json({ error: 'Nothing to update' });
    fields.push('updated_at = NOW()');
    values.push(id);
    const result = await pool.query(`UPDATE promo_codes SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`, values);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    auditAdmin(req, 'promo.update', { type: 'promo', id }, {
      changed: Object.keys(req.body).filter((k) => req.body[k] !== undefined),
    });
    res.json(result.rows[0]);
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.delete('/api/promos/:id', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'Invalid id' });
    const result = await pool.query('DELETE FROM promo_codes WHERE id = $1 RETURNING id, code', [id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    auditAdmin(req, 'promo.delete', { type: 'promo', id }, { code: result.rows[0].code });
    res.json({ message: 'Deleted' });
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// View redemptions for a specific promo
app.get('/api/promos/:id/redemptions', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT pr.*, s.name as store_name, u.full_name as user_name, u.email
       FROM promo_redemptions pr
       JOIN stores s ON s.id = pr.store_id
       JOIN users u ON u.id = pr.user_id
       WHERE pr.promo_id = $1
       ORDER BY pr.created_at DESC`,
      [parseInt(req.params.id)]
    );
    res.json(result.rows);
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ─── Flagged Stores ──────────────────────────────────────────────────────────
app.get('/api/flagged', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT fs.*, s.name as store_name, u.full_name as owner_name, u.email as owner_email
       FROM flagged_stores fs JOIN stores s ON s.id = fs.store_id JOIN users u ON u.id = s.owner_id
       WHERE fs.resolved = FALSE ORDER BY fs.flagged_at DESC`
    );
    res.json(result.rows);
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.post('/api/flagged/scan', isAdmin, async (req, res) => {
  try {
    const flagged = [];

    const bulk = await pool.query(
      `SELECT store_id, COUNT(*)::int as cnt, s.name FROM products p JOIN stores s ON s.id = p.store_id
       WHERE p.created_at >= NOW() - INTERVAL '1 hour' GROUP BY store_id, s.name HAVING COUNT(*) >= 50`
    );
    for (const r of bulk.rows) flagged.push({ store_id: r.store_id, store_name: r.name, reason: 'bulk_upload', details: { product_count: r.cnt } });

    const dup = await pool.query(
      `SELECT image_hash, array_agg(DISTINCT store_id) as sids FROM product_image_hashes GROUP BY image_hash HAVING COUNT(DISTINCT store_id) >= 2`
    );
    const crossStores = new Set();
    for (const r of dup.rows) r.sids.forEach(s => crossStores.add(s));
    if (crossStores.size > 0) {
      const names = await pool.query(`SELECT id, name FROM stores WHERE id = ANY($1::int[])`, [Array.from(crossStores)]);
      const nm = Object.fromEntries(names.rows.map(r => [r.id, r.name]));
      for (const sid of crossStores) flagged.push({ store_id: sid, store_name: nm[sid] || `#${sid}`, reason: 'duplicate_images_cross_account', details: {} });
    }

    const ret = await pool.query(
      `SELECT o.store_id, s.name, COUNT(*) FILTER (WHERE o.status='returned')::int as returned, COUNT(*)::int as total
       FROM orders o JOIN stores s ON s.id = o.store_id WHERE o.store_id IS NOT NULL
       GROUP BY o.store_id, s.name HAVING COUNT(*) >= 10 AND COUNT(*) FILTER (WHERE o.status='returned')::float / COUNT(*) > 0.3`
    );
    for (const r of ret.rows) flagged.push({ store_id: r.store_id, store_name: r.name, reason: 'high_return_rate', details: { returned: r.returned, total: r.total } });

    let inserted = 0;
    for (const f of flagged) {
      const ex = await pool.query('SELECT id FROM flagged_stores WHERE store_id = $1 AND resolved = FALSE', [f.store_id]);
      if (ex.rows.length === 0) {
        await pool.query(`INSERT INTO flagged_stores (store_id, reason, details) VALUES ($1,$2,$3) ON CONFLICT (store_id) DO UPDATE SET reason=$2, details=$3, flagged_at=NOW(), resolved=FALSE`,
          [f.store_id, f.reason, JSON.stringify(f.details)]);
        inserted++;
      }
    }
    res.json({ scanned: true, new_flags: inserted, total_found: flagged.length });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Scan failed' }); }
});

app.post('/api/flagged/:storeId/manual-approval', isAdmin, async (req, res) => {
  try {
    const sid = parseInt(req.params.storeId);
    await pool.query('UPDATE stores SET manual_approval_mode = TRUE, first_product_approved = FALSE WHERE id = $1', [sid]);
    await pool.query(`UPDATE flagged_stores SET resolved = TRUE, resolved_at = NOW() WHERE store_id = $1`, [sid]);
    res.json({ message: 'Reverted to manual approval' });
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.post('/api/flagged/:storeId/dismiss', isAdmin, async (req, res) => {
  try {
    await pool.query(`UPDATE flagged_stores SET resolved = TRUE, resolved_at = NOW() WHERE store_id = $1`, [parseInt(req.params.storeId)]);
    res.json({ message: 'Dismissed' });
  } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ─── Store Management ─────────────────────────────────────────────────────────
app.get('/api/tiers', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(`SELECT id, name, slug, online_slots, price_usd_monthly FROM subscription_tiers ORDER BY sort_order`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch tiers' });
  }
});

app.get('/api/stores', isAdmin, async (req, res) => {
  try {
    const { search, status } = req.query;
    let query = `
      SELECT s.id, s.name, s.city, s.country, s.created_at,
             COALESCE(s.is_active, TRUE) as is_active,
             s.deactivated_at, s.deactivation_reason,
             u.full_name as owner_name, u.email as owner_email,
             (SELECT COUNT(*)::int FROM products WHERE store_id = s.id) as product_count
      FROM stores s
      JOIN users u ON u.id = s.owner_id
    `;
    const conditions = [];
    const values = [];
    let idx = 1;

    if (status === 'active') { conditions.push(`COALESCE(s.is_active, TRUE) = TRUE`); }
    else if (status === 'deactivated') { conditions.push(`s.is_active = FALSE`); }

    if (search) {
      conditions.push(`(s.name ILIKE $${idx} OR u.full_name ILIKE $${idx} OR u.email ILIKE $${idx})`);
      values.push(`%${search}%`);
      idx++;
    }

    if (conditions.length > 0) query += ' WHERE ' + conditions.join(' AND ');
    query += ' ORDER BY s.created_at DESC LIMIT 100';

    const result = await pool.query(query, values);
    res.json(result.rows);
  } catch (err) {
    console.error('Stores list error:', err.message);
    res.status(500).json({ error: 'Failed to fetch stores' });
  }
});

app.post('/api/stores/:id/deactivate', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'Invalid id' });
    const rawReason = typeof req.body.reason === 'string' ? req.body.reason : '';
    const reason = rawReason.trim().substring(0, 500);
    if (!reason || reason.length < 3) {
      return res.status(400).json({ error: 'A reason is required (min 3 chars)' });
    }
    // Atomic claim: only deactivates currently-active stores. Without
    // this, a double-click can overwrite the original deactivation
    // reason and timestamp with whatever the second request carried.
    const claim = await pool.query(
      `UPDATE stores
         SET is_active = FALSE, deactivated_at = NOW(), deactivation_reason = $2
       WHERE id = $1 AND COALESCE(is_active, TRUE) = TRUE
       RETURNING id, name`,
      [id, reason]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Store not found or already deactivated' });
    }
    auditAdmin(req, 'store.deactivate', { type: 'store', id }, { reason, name: claim.rows[0].name });
    res.json({ message: 'Store deactivated', store_id: id });
  } catch (err) {
    console.error('Deactivate error:', err.message);
    res.status(500).json({ error: 'Failed to deactivate store' });
  }
});

app.post('/api/stores/:id/reactivate', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'Invalid id' });
    const claim = await pool.query(
      `UPDATE stores
         SET is_active = TRUE, deactivated_at = NULL, deactivation_reason = NULL
       WHERE id = $1 AND is_active = FALSE
       RETURNING id, name`,
      [id]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Store not found or not deactivated' });
    }
    auditAdmin(req, 'store.reactivate', { type: 'store', id }, { name: claim.rows[0].name });
    res.json({ message: 'Store reactivated', store_id: id });
  } catch (err) {
    console.error('Reactivate error:', err.message);
    res.status(500).json({ error: 'Failed to reactivate store' });
  }
});

app.get('/api/stores/:id/products', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const result = await pool.query(
      `SELECT id, name, price, currency, quantity, is_online, image_url, created_at
       FROM products WHERE store_id = $1 ORDER BY created_at DESC`,
      [id]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Store products error:', err.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

app.delete('/api/stores/:storeId/products/:productId', isAdmin, async (req, res) => {
  try {
    const storeId = parseInt(req.params.storeId);
    const productId = parseInt(req.params.productId);
    if (!Number.isInteger(storeId) || storeId <= 0 ||
        !Number.isInteger(productId) || productId <= 0) {
      return res.status(400).json({ error: 'Invalid id' });
    }
    const result = await pool.query(
      'DELETE FROM products WHERE id = $1 AND store_id = $2 RETURNING id, name',
      [productId, storeId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    auditAdmin(req, 'product.delete', { type: 'product', id: productId }, { store_id: storeId, name: result.rows[0].name });
    res.json({ message: 'Product deleted', product: result.rows[0] });
  } catch (err) {
    console.error('Delete product error:', err.message);
    res.status(500).json({ error: 'Failed to delete product' });
  }
});

// ─── Support Tickets ─────────────────────────────────────────────────────────
function extractPaymentReference(subject, messages) {
  const chunks = [subject || ''];
  if (Array.isArray(messages)) {
    for (const m of messages) {
      if (m?.body) chunks.push(String(m.body));
    }
  }
  const match = chunks.join(' ').match(/(MB|SP)-\d+-[A-Z0-9]+/i);
  return match ? match[0].toUpperCase() : null;
}

app.get('/api/support/tickets', isAdmin, async (req, res) => {
  try {
    const status = req.query.status;
    const category = req.query.category;
    let query = `
      SELECT t.*,
             u.full_name AS user_name,
             u.email AS user_email,
             (
               SELECT body FROM support_ticket_messages m
               WHERE m.ticket_id = t.id
               ORDER BY m.created_at DESC
               LIMIT 1
             ) AS last_message,
             (
               SELECT COUNT(*)::int FROM support_ticket_messages m
               WHERE m.ticket_id = t.id
                 AND m.sender_role = 'user'
                 AND m.read_at IS NULL
             ) AS unread_count
      FROM support_tickets t
      JOIN users u ON u.id = t.user_id
    `;
    const params = [];
    const clauses = [];
    if (status && status !== 'all') {
      params.push(status);
      clauses.push(`t.status = $${params.length}`);
    }
    if (category && category !== 'all') {
      params.push(category);
      clauses.push(`t.category = $${params.length}`);
    }
    if (clauses.length) {
      query += ` WHERE ${clauses.join(' AND ')}`;
    }
    query += ' ORDER BY t.last_message_at DESC LIMIT 200';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Admin support list error:', err.message);
    res.status(500).json({ error: 'Failed to fetch support tickets' });
  }
});

app.get('/api/support/tickets/:id/messages', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const ticket = await pool.query(
      `SELECT t.*, u.full_name AS user_name, u.email AS user_email
       FROM support_tickets t
       JOIN users u ON u.id = t.user_id
       WHERE t.id = $1`,
      [ticketId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }

    const messages = await pool.query(
      `SELECT m.*, u.full_name AS sender_name
       FROM support_ticket_messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.ticket_id = $1
       ORDER BY m.created_at ASC`,
      [ticketId]
    );

    await pool.query(
      `UPDATE support_ticket_messages
       SET read_at = NOW()
       WHERE ticket_id = $1
         AND sender_role = 'user'
         AND read_at IS NULL`,
      [ticketId]
    );

    res.json({
      ticket: ticket.rows[0],
      messages: messages.rows,
    });
  } catch (err) {
    console.error('Admin support messages error:', err.message);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

app.post('/api/support/tickets/:id/messages', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const body = (req.body.body || '').toString().trim();
    if (!body || body.length < 1) {
      return res.status(400).json({ error: 'Message cannot be empty' });
    }

    const ticket = await pool.query(
      'SELECT id, status FROM support_tickets WHERE id = $1',
      [ticketId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }
    if (ticket.rows[0].status === 'closed') {
      return res.status(400).json({ error: 'Ticket is closed' });
    }

    const inserted = await pool.query(
      `INSERT INTO support_ticket_messages (ticket_id, sender_id, sender_role, body)
       VALUES ($1, $2, 'admin', $3)
       RETURNING *`,
      [ticketId, req.admin.userId, body]
    );

    await pool.query(
      `UPDATE support_tickets
       SET status = 'in_progress',
           assigned_admin_id = $2,
           last_message_at = NOW(),
           updated_at = NOW()
       WHERE id = $1`,
      [ticketId, req.admin.userId]
    );

    res.status(201).json(inserted.rows[0]);
  } catch (err) {
    console.error('Admin support reply error:', err.message);
    res.status(500).json({ error: 'Failed to send reply' });
  }
});

async function grantUserImageQuota(userId, count, adminUserId) {
  const body =
    count === 1
      ? 'Support approved 1 image upload. You can attach an image now in any of your open tickets.'
      : `Support approved ${count} image uploads. You can attach images now in any of your open tickets.`;

  const tickets = await pool.query(
    `SELECT id FROM support_tickets
     WHERE user_id = $1 AND status != 'closed'`,
    [userId]
  );

  if (tickets.rows.length === 0) {
    return null;
  }

  await pool.query(
    `UPDATE support_tickets
     SET image_quota = image_quota + $2,
         updated_at = NOW()
     WHERE user_id = $1 AND status != 'closed'`,
    [userId, count]
  );

  await pool.query(
    `UPDATE support_ticket_messages m
     SET request_status = 'approved'
     FROM support_tickets t
     WHERE m.ticket_id = t.id
       AND t.user_id = $1
       AND m.message_type = 'image_request'
       AND (m.request_status IS NULL OR m.request_status = 'pending')`,
    [userId]
  );

  for (const row of tickets.rows) {
    await pool.query(
      `INSERT INTO support_ticket_messages (ticket_id, sender_id, sender_role, body, message_type)
       VALUES ($1, $2, 'admin', $3, 'system')`,
      [row.id, adminUserId, body]
    );
    await pool.query(
      `UPDATE support_tickets
       SET last_message_at = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [row.id]
    );
  }

  return tickets.rows.length;
}

app.post('/api/support/tickets/:id/allow-images', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const count = Math.min(Math.max(parseInt(req.body.count, 10) || 1, 1), 10);

    const ticket = await pool.query(
      'SELECT id, user_id, status FROM support_tickets WHERE id = $1',
      [ticketId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }
    if (ticket.rows[0].status === 'closed') {
      return res.status(400).json({ error: 'Ticket is closed' });
    }

    const affected = await grantUserImageQuota(ticket.rows[0].user_id, count, req.admin.userId);
    if (!affected) {
      return res.status(400).json({ error: 'User has no open tickets to grant image access' });
    }

    const updated = await pool.query(
      'SELECT * FROM support_tickets WHERE id = $1',
      [ticketId]
    );
    res.json({
      ...updated.rows[0],
      tickets_updated: affected,
    });
  } catch (err) {
    console.error('Admin allow images error:', err.message);
    res.status(500).json({ error: 'Failed to allow image uploads' });
  }
});

app.post('/api/support/allow-all-images', isAdmin, async (req, res) => {
  try {
    const count = Math.min(Math.max(parseInt(req.body.count, 10) || 1, 1), 10);
    const pending = await pool.query(
      `SELECT DISTINCT t.user_id
       FROM support_ticket_messages m
       JOIN support_tickets t ON t.id = m.ticket_id
       WHERE m.message_type = 'image_request'
         AND (m.request_status IS NULL OR m.request_status = 'pending')
         AND t.status != 'closed'`
    );

    let usersUpdated = 0;
    let ticketsUpdated = 0;
    for (const row of pending.rows) {
      const affected = await grantUserImageQuota(row.user_id, count, req.admin.userId);
      if (affected) {
        usersUpdated += 1;
        ticketsUpdated += affected;
      }
    }

    res.json({
      users_updated: usersUpdated,
      tickets_updated: ticketsUpdated,
      count_per_user: count,
    });
  } catch (err) {
    console.error('Admin allow all images error:', err.message);
    res.status(500).json({ error: 'Failed to approve pending image requests' });
  }
});

app.delete('/api/support/tickets/:id', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const result = await pool.query(
      'DELETE FROM support_tickets WHERE id = $1 RETURNING id',
      [ticketId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }
    auditAdmin(req, 'support.delete', { type: 'support_ticket', id: ticketId });
    res.json({ message: 'Support ticket deleted', id: ticketId });
  } catch (err) {
    console.error('Admin delete support ticket error:', err.message);
    res.status(500).json({ error: 'Failed to delete support ticket' });
  }
});

app.get('/api/support/tickets/:id/related-payment', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const ticket = await pool.query(
      `SELECT t.*, u.full_name AS user_name, u.email AS user_email
       FROM support_tickets t
       JOIN users u ON u.id = t.user_id
       WHERE t.id = $1`,
      [ticketId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }

    const messages = await pool.query(
      `SELECT body FROM support_ticket_messages WHERE ticket_id = $1 ORDER BY created_at ASC`,
      [ticketId]
    );

    const ref = extractPaymentReference(
      ticket.rows[0].subject,
      messages.rows
    );
    if (!ref) {
      return res.json({ payment: null });
    }

    if (ref.startsWith('SP-')) {
      const sponsor = await pool.query(
        `SELECT sp.id, sp.reference_code, sp.amount_usd, sp.status, sp.created_at,
                p.name AS product_name, s.name AS store_name, u.full_name AS owner_name
         FROM sponsored_product_payments sp
         JOIN products p ON p.id = sp.product_id
         JOIN stores s ON s.id = sp.store_id
         JOIN users u ON u.id = s.owner_id
         WHERE sp.reference_code = $1
         ORDER BY sp.created_at DESC
         LIMIT 1`,
        [ref]
      );
      if (sponsor.rows.length === 0) {
        return res.json({ payment: null, reference_code: ref });
      }
      return res.json({
        payment: { ...sponsor.rows[0], type: 'sponsorship' },
        reference_code: ref,
      });
    }

    const sub = await pool.query(
      `SELECT sp.id, sp.reference_code, sp.amount_usd, sp.status, sp.created_at,
              st.name AS tier_name, s.name AS store_name, u.full_name AS owner_name
       FROM subscription_payments sp
       JOIN subscription_tiers st ON st.id = sp.tier_id
       JOIN stores s ON s.id = sp.store_id
       JOIN users u ON u.id = s.owner_id
       WHERE sp.reference_code = $1
       ORDER BY sp.created_at DESC
       LIMIT 1`,
      [ref]
    );
    if (sub.rows.length === 0) {
      return res.json({ payment: null, reference_code: ref });
    }
    res.json({
      payment: { ...sub.rows[0], type: 'subscription' },
      reference_code: ref,
    });
  } catch (err) {
    console.error('Admin related payment error:', err.message);
    res.status(500).json({ error: 'Failed to load related payment' });
  }
});

app.patch('/api/support/tickets/:id', isAdmin, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const { status, category } = req.body;
    const validCategories = new Set([
      'general', 'account', 'billing', 'technical', 'report', 'review_removal',
    ]);
    const validStatuses = new Set(['open', 'in_progress', 'closed']);

    if (!status && !category) {
      return res.status(400).json({ error: 'Nothing to update' });
    }
    if (status && !validStatuses.has(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }
    if (category && !validCategories.has(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    const fields = [];
    const params = [ticketId];
    if (status) {
      params.push(status);
      fields.push(`status = $${params.length}`);
    }
    if (category) {
      params.push(category);
      fields.push(`category = $${params.length}`);
    }
    fields.push('updated_at = NOW()');

    const result = await pool.query(
      `UPDATE support_tickets SET ${fields.join(', ')} WHERE id = $1 RETURNING *`,
      params
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Admin support update error:', err.message);
    res.status(500).json({ error: 'Failed to update ticket' });
  }
});

// ─── Store Chats ────────────────────────────────────────────────────────────
app.get('/api/chat/conversations', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT c.id, c.store_id, c.customer_id, c.last_message_at, c.created_at,
              s.name AS store_name,
              u.full_name AS customer_name,
              u.email AS customer_email,
              (
                SELECT body FROM chat_messages m
                WHERE m.conversation_id = c.id
                ORDER BY m.created_at DESC
                LIMIT 1
              ) AS last_message,
              (
                SELECT COUNT(*)::int FROM chat_messages m
                WHERE m.conversation_id = c.id
              ) AS message_count
       FROM chat_conversations c
       JOIN stores s ON s.id = c.store_id
       JOIN users u ON u.id = c.customer_id
       ORDER BY c.last_message_at DESC NULLS LAST
       LIMIT 300`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Admin chat list error:', err.message);
    res.status(500).json({ error: 'Failed to load chat conversations' });
  }
});

app.delete('/api/chat/conversations/:id', isAdmin, async (req, res) => {
  try {
    const conversationId = parseInt(req.params.id);
    const result = await pool.query(
      'DELETE FROM chat_conversations WHERE id = $1 RETURNING id',
      [conversationId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    auditAdmin(req, 'chat.delete', { type: 'chat_conversation', id: conversationId });
    res.json({ message: 'Chat conversation deleted', id: conversationId });
  } catch (err) {
    console.error('Admin delete chat error:', err.message);
    res.status(500).json({ error: 'Failed to delete chat conversation' });
  }
});

// ─── Sponsored Products ─────────────────────────────────────────────────────
app.get('/api/sponsorship/pricing', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(`SELECT * FROM sponsorship_pricing ORDER BY sort_order ASC`);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to load pricing' });
  }
});

// Whitelist of valid sponsorship scope types — must match the keys the
// backend uses in services/sponsored_products.js. Without this whitelist
// an admin typo silently no-ops (UPDATE … WHERE scope_type = '…' matches
// no rows → 404) and a price intended for "city" gets stored under a
// garbage key with no effect.
const ALLOWED_SPONSORSHIP_SCOPES = new Set(['radius', 'village', 'city', 'country']);

app.put('/api/sponsorship/pricing/:scopeType', isAdmin, async (req, res) => {
  try {
    const scopeType = req.params.scopeType;
    if (!ALLOWED_SPONSORSHIP_SCOPES.has(scopeType)) {
      return res.status(400).json({ error: 'Invalid scope type' });
    }
    const { price_usd_per_day, radius_unit_km, label } = req.body;
    const price = parseFloat(price_usd_per_day);
    // Sanity-cap the price to prevent fat-finger errors that lock owners
    // out of sponsoring (price=$10,000/day) or undercut economics
    // (price < 0 is already blocked, but huge values are equally toxic).
    if (!Number.isFinite(price) || price < 0 || price > 10000) {
      return res.status(400).json({ error: 'Price must be between 0 and 10000 USD/day' });
    }
    const result = await pool.query(
      `UPDATE sponsorship_pricing
       SET price_usd_per_day = $2,
           radius_unit_km = COALESCE($3, radius_unit_km),
           label = COALESCE($4, label),
           updated_at = NOW()
       WHERE scope_type = $1
       RETURNING *`,
      [scopeType, price, radius_unit_km != null ? parseInt(radius_unit_km, 10) : null, label || null]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Scope not found' });
    auditAdmin(req, 'sponsorship_pricing.update',
      { type: 'sponsorship_pricing', id: scopeType },
      { price_usd_per_day: price, radius_unit_km });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to update pricing' });
  }
});

app.get('/api/sponsorship/payments/pending', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT sp.*, p.name AS product_name, s.name AS store_name,
              u.full_name AS owner_name, u.email AS owner_email
       FROM sponsored_product_payments sp
       JOIN products p ON sp.product_id = p.id
       JOIN stores s ON sp.store_id = s.id
       JOIN users u ON s.owner_id = u.id
       WHERE sp.status = 'pending'
       ORDER BY sp.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch sponsorship payments' });
  }
});

app.post('/api/sponsorship/payments/:id/verify', isAdmin, async (req, res) => {
  const client = await pool.connect();
  let inTx = false;
  try {
    const id = parseInt(req.params.id, 10);
    await client.query('BEGIN');
    inTx = true;

    // Atomic claim — same race fix as /api/payments/:id/verify above.
    // Without this, double-clicking "Verify" provisions two parallel
    // sponsorship campaigns for one payment.
    const claim = await client.query(
      `UPDATE sponsored_product_payments
         SET status = 'verified', verified_by = $1, verified_at = NOW()
       WHERE id = $2 AND status = 'pending'
       RETURNING *`,
      [req.admin.userId, id]
    );
    if (claim.rows.length === 0) {
      await client.query('ROLLBACK');
      inTx = false;
      return res.status(409).json({ error: 'Payment is not pending (already verified or rejected)' });
    }
    const p = claim.rows[0];

    await client.query(
      `UPDATE sponsored_product_campaigns
       SET status = 'superseded', updated_at = NOW()
       WHERE product_id = $1 AND status = 'active'`,
      [p.product_id]
    );

    const exp = new Date();
    exp.setDate(exp.getDate() + parseInt(p.duration_days, 10));

    await client.query(
      `INSERT INTO sponsored_product_campaigns (
         payment_id, store_id, product_id, scope_type, radius_km, duration_days,
         target_village, target_city, target_country, target_country_code, target_city_id,
         center_lat, center_lng, amount_usd, status, starts_at, expires_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'active',NOW(),$15)`,
      [
        p.id, p.store_id, p.product_id, p.scope_type, p.radius_km, p.duration_days,
        p.target_village, p.target_city, p.target_country, p.target_country_code, p.target_city_id,
        p.center_lat, p.center_lng, p.amount_usd, exp,
      ]
    );

    await client.query('COMMIT');
    inTx = false;
    auditAdmin(req, 'sponsorship_payment.verify',
      { type: 'sponsored_product_payment', id: p.id },
      { store_id: p.store_id, product_id: p.product_id, amount_usd: p.amount_usd,
        duration_days: p.duration_days, scope_type: p.scope_type });
    res.json({ message: 'Sponsorship payment verified and campaign activated' });
  } catch (err) {
    if (inTx) { try { await client.query('ROLLBACK'); } catch (_) {} }
    console.error('Sponsor verify error:', err.message);
    res.status(500).json({ error: 'Failed to verify sponsorship payment' });
  } finally {
    client.release();
  }
});

app.get('/api/sponsorship/campaigns', isAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT c.*, p.name AS product_name, s.name AS store_name, u.full_name AS owner_name
       FROM sponsored_product_campaigns c
       JOIN products p ON c.product_id = p.id
       JOIN stores s ON c.store_id = s.id
       JOIN users u ON s.owner_id = u.id
       WHERE c.status = 'active' AND c.expires_at > NOW()
       ORDER BY c.expires_at ASC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch campaigns' });
  }
});

app.post('/api/sponsorship/campaigns/:id/cancel', isAdmin, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    const result = await pool.query(
      `UPDATE sponsored_product_campaigns SET status = 'cancelled', updated_at = NOW()
       WHERE id = $1 AND status = 'active' RETURNING *`,
      [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to cancel campaign' });
  }
});

// ─── Users ───────────────────────────────────────────────────────────────────
app.get('/api/users', isAdmin, async (req, res) => {
  try {
    const type = (req.query.type || 'all').toString();
    const search = (req.query.search || '').toString().trim();
    const params = [];
    const conditions = [];

    if (type === 'store_owner') {
      conditions.push(`u.role = 'store_owner'`);
    } else if (type === 'worker') {
      conditions.push(`EXISTS (
        SELECT 1 FROM store_staff ss
        WHERE ss.user_id = u.id AND ss.status = 'accepted'
      )`);
    } else if (type === 'consumer') {
      conditions.push(`u.role = 'customer'`);
      conditions.push(`NOT EXISTS (
        SELECT 1 FROM store_staff ss
        WHERE ss.user_id = u.id AND ss.status = 'accepted'
      )`);
    } else if (type === 'admin') {
      conditions.push(`(u.is_admin = TRUE OR u.role = 'admin')`);
    }

    if (search) {
      params.push(`%${search}%`);
      const idx = params.length;
      conditions.push(`(
        u.full_name ILIKE $${idx} OR u.email ILIKE $${idx} OR COALESCE(u.phone, '') ILIKE $${idx}
      )`);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT
         u.id, u.full_name, u.email, u.phone, u.role, u.is_admin, u.created_at,
         CASE
           WHEN u.is_admin = TRUE OR u.role = 'admin' THEN 'admin'
           WHEN u.role = 'store_owner' THEN 'store_owner'
           WHEN EXISTS (
             SELECT 1 FROM store_staff ss
             WHERE ss.user_id = u.id AND ss.status = 'accepted'
           ) THEN 'worker'
           ELSE 'consumer'
         END AS user_type,
         owned.id AS owned_store_id,
         owned.name AS owned_store_name,
         (
           SELECT COALESCE(json_agg(json_build_object(
             'store_id', st.id,
             'store_name', st.name,
             'can_manage_inventory', ss.can_manage_inventory
           ) ORDER BY st.name), '[]'::json)
           FROM store_staff ss
           JOIN stores st ON st.id = ss.store_id
           WHERE ss.user_id = u.id AND ss.status = 'accepted'
         ) AS worker_stores
       FROM users u
       LEFT JOIN stores owned ON owned.owner_id = u.id AND u.role = 'store_owner'
       ${where}
       ORDER BY u.created_at DESC
       LIMIT 500`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Admin users error:', err.message);
    res.status(500).json({ error: 'Failed to load users' });
  }
});

// ─── Reviews (admin-only removal; store owners use support tickets) ────────────
app.get('/api/reviews', isAdmin, async (req, res) => {
  try {
    const status = (req.query.status || 'active').toString();
    const type = (req.query.type || 'all').toString();
    const allowedStatus = new Set(['active', 'removed', 'all']);
    const allowedType = new Set(['all', 'store', 'product']);
    if (!allowedStatus.has(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    if (!allowedType.has(type)) {
      return res.status(400).json({ error: 'Invalid type filter' });
    }

    const params = [];
    let statusParam = null;
    if (status !== 'all') {
      params.push(status);
      statusParam = `$${params.length}`;
    }
    const statusFilter = (alias) =>
      statusParam ? ` AND ${alias}.status = ${statusParam}` : '';

    const parts = [];
    if (type === 'all' || type === 'store') {
      parts.push(`
        SELECT r.id, 'store' AS review_type, r.store_id AS target_id, NULL::int AS product_id,
               r.store_id, r.user_id, r.rating, r.comment, r.status,
               r.created_at, r.removed_at, r.removal_reason,
               u.full_name AS user_name, u.email AS user_email,
               s.name AS target_name, s.name AS store_name, NULL::text AS product_name
        FROM store_reviews r
        JOIN users u ON u.id = r.user_id
        JOIN stores s ON s.id = r.store_id
        WHERE 1=1${statusFilter('r')}
      `);
    }
    if (type === 'all' || type === 'product') {
      parts.push(`
        SELECT r.id, 'product' AS review_type, r.product_id AS target_id, r.product_id,
               p.store_id, r.user_id, r.rating, r.comment, r.status,
               r.created_at, r.removed_at, r.removal_reason,
               u.full_name AS user_name, u.email AS user_email,
               p.name AS target_name, s.name AS store_name, p.name AS product_name
        FROM product_reviews r
        JOIN users u ON u.id = r.user_id
        JOIN products p ON p.id = r.product_id
        JOIN stores s ON s.id = p.store_id
        WHERE 1=1${statusFilter('r')}
      `);
    }

    const result = await pool.query(
      `SELECT * FROM (${parts.join(' UNION ALL ')}) combined
       ORDER BY created_at DESC
       LIMIT 200`,
      params
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Admin reviews error:', err.message);
    res.status(500).json({ error: 'Failed to load reviews' });
  }
});

app.post('/api/reviews/:id/remove', isAdmin, async (req, res) => {
  const client = await pool.connect();
  let inTx = false;
  try {
    const reviewId = parseInt(req.params.id, 10);
    const reviewType = (req.body?.type || 'store').toString();
    const reason = (req.body?.reason || '').toString().trim();
    if (!Number.isFinite(reviewId)) {
      return res.status(400).json({ error: 'Invalid review id' });
    }
    if (!['store', 'product'].includes(reviewType)) {
      return res.status(400).json({ error: 'Invalid review type' });
    }
    if (reason.length < 10) {
      return res.status(400).json({ error: 'Removal reason must be at least 10 characters' });
    }

    await client.query('BEGIN');
    inTx = true;

    let review;
    if (reviewType === 'product') {
      const reviewResult = await client.query(
        `SELECT r.*, u.email AS user_email, u.full_name AS user_name,
                p.name AS product_name, s.name AS store_name
         FROM product_reviews r
         JOIN users u ON u.id = r.user_id
         JOIN products p ON p.id = r.product_id
         JOIN stores s ON s.id = p.store_id
         WHERE r.id = $1 AND r.status = 'active'
         FOR UPDATE`,
        [reviewId]
      );
      if (reviewResult.rows.length === 0) {
        await client.query('ROLLBACK');
        inTx = false;
        return res.status(404).json({ error: 'Review not found or already removed' });
      }
      review = reviewResult.rows[0];
      await client.query(
        `UPDATE product_reviews
         SET status = 'removed', removed_at = NOW(), updated_at = NOW(),
             removed_by_admin_id = $2, removal_reason = $3
         WHERE id = $1`,
        [reviewId, req.admin.userId, reason]
      );
      await recalcProductRatingAdmin(review.product_id, client);
    } else {
      const reviewResult = await client.query(
        `SELECT r.*, u.email AS user_email, u.full_name AS user_name, s.name AS store_name
         FROM store_reviews r
         JOIN users u ON u.id = r.user_id
         JOIN stores s ON s.id = r.store_id
         WHERE r.id = $1 AND r.status = 'active'
         FOR UPDATE`,
        [reviewId]
      );
      if (reviewResult.rows.length === 0) {
        await client.query('ROLLBACK');
        inTx = false;
        return res.status(404).json({ error: 'Review not found or already removed' });
      }
      review = reviewResult.rows[0];
      await client.query(
        `UPDATE store_reviews
         SET status = 'removed', removed_at = NOW(), updated_at = NOW(),
             removed_by_admin_id = $2, removal_reason = $3
         WHERE id = $1`,
        [reviewId, req.admin.userId, reason]
      );
      await recalcStoreRatingAdmin(review.store_id, client);
    }

    const stars = '★'.repeat(review.rating) + '☆'.repeat(5 - review.rating);
    const targetLabel = reviewType === 'product'
      ? `product <strong>${review.product_name}</strong> at ${review.store_name}`
      : `store <strong>${review.store_name}</strong>`;
    const commentBlock = review.comment
      ? `<p style="background:#f5f5f5;padding:12px;border-radius:8px;font-style:italic;">"${review.comment.replace(/</g, '&lt;')}"</p>`
      : '';
    await sendAdminEmail({
      to: review.user_email,
      subject: 'Your STORAQ review was removed',
      html: `
        <div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
          <h2 style="color:#333;">Review removed</h2>
          <p>Hello ${review.user_name || 'there'},</p>
          <p>Your review for ${targetLabel} (${stars}) was removed by a STORAQ administrator.</p>
          ${commentBlock}
          <p><strong>Reason:</strong></p>
          <p style="background:#fff3f3;padding:12px;border-left:4px solid #e74c3c;border-radius:4px;">${reason.replace(/</g, '&lt;')}</p>
          <p style="color:#666;font-size:13px;">If you believe this was a mistake, contact support from the app.</p>
          <p>— STORAQ Team</p>
        </div>`,
    });

    await client.query('COMMIT');
    inTx = false;

    auditAdmin(req, 'review.remove', { type: `${reviewType}_review`, id: reviewId }, {
      target_id: reviewType === 'product' ? review.product_id : review.store_id,
      user_id: review.user_id,
      reason_length: reason.length,
    });

    res.json({ ok: true });
  } catch (err) {
    if (inTx) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    console.error('Admin remove review error:', err.message);
    const msg = err.message?.includes('SMTP')
      ? err.message
      : 'Failed to remove review';
    res.status(500).json({ error: msg });
  } finally {
    client.release();
  }
});

// ─── SPA fallback ────────────────────────────────────────────────────────────
app.get('*', (req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'Not found' });
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ─── Start ───────────────────────────────────────────────────────────────────
(async () => {
  if (!process.env.ADMIN_JWT_SECRET) { console.error('FATAL: Set ADMIN_JWT_SECRET in .env'); process.exit(1); }
  if (!process.env.DATABASE_URL) { console.error('FATAL: Set DATABASE_URL in .env'); process.exit(1); }
  // Floor on secret strength — see backend/server.js for the rationale.
  if (process.env.ADMIN_JWT_SECRET.length < 32) {
    console.error('FATAL: ADMIN_JWT_SECRET must be at least 32 chars (use `openssl rand -hex 32`)');
    process.exit(1);
  }
  // Refuse to reuse the backend JWT secret — admin tokens must live in a
  // separate trust domain so that an attacker compromising a regular user
  // session can never escalate to an admin session.
  if (process.env.JWT_SECRET && process.env.JWT_SECRET === process.env.ADMIN_JWT_SECRET) {
    console.error('FATAL: ADMIN_JWT_SECRET must NOT equal JWT_SECRET — admin sessions must be a separate trust domain.');
    process.exit(1);
  }
  try { await runMigrations(); } catch (e) { console.error('Migration err:', e.message); }
  app.listen(PORT, '0.0.0.0', () => console.log(`[admin] http://localhost:${PORT}`));
})();
