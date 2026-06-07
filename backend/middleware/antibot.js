// middleware/antibot.js
const crypto = require('crypto');
const { pool } = require('../config/database');

// ==================== 1. EMAIL VERIFICATION GATE ====================

async function requireVerifiedEmail(req, res, next) {
  if (!req.user || !req.user.userId) {
    return res.status(401).json({ error: 'Authentication required.' });
  }

  try {
    const result = await pool.query(
      'SELECT email_verified FROM users WHERE id = $1',
      [req.user.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }
    if (!result.rows[0].email_verified) {
      return res.status(403).json({
        error: 'email_not_verified',
        message: 'You must verify your email before listing products online. Check your inbox for the verification code.',
      });
    }
    next();
  } catch (err) {
    console.error('requireVerifiedEmail error:', err.message);
    next(err);
  }
}

// ==================== 2. CLOUDFLARE TURNSTILE ====================

const TURNSTILE_SECRET = process.env.TURNSTILE_SECRET_KEY || '';
const TURNSTILE_VERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

async function verifyTurnstile(req, res, next) {
  if (!TURNSTILE_SECRET) {
    if (process.env.NODE_ENV === 'production') {
      return res.status(500).json({
        error: 'turnstile_not_configured',
        message: 'Human verification is not configured.',
      });
    }
    // If no secret is configured outside production, skip for local development.
    return next();
  }

  const token = req.body.turnstile_token || req.headers['x-turnstile-token'];
  if (!token) {
    return res.status(400).json({
      error: 'turnstile_required',
      message: 'Human verification is required. Please complete the captcha.',
    });
  }

  try {
    const response = await fetch(TURNSTILE_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        secret: TURNSTILE_SECRET,
        response: token,
        remoteip: req.ip || req.connection?.remoteAddress || '',
      }),
    });
    const data = await response.json();

    if (!data.success) {
      return res.status(403).json({
        error: 'turnstile_failed',
        message: 'Human verification failed. Please try again.',
      });
    }
    next();
  } catch (err) {
    console.error('Turnstile verification error:', err.message);
    if (process.env.NODE_ENV === 'production') {
      return res.status(503).json({
        error: 'turnstile_unavailable',
        message: 'Human verification is temporarily unavailable. Please try again later.',
      });
    }
    // Keep local development unblocked if Cloudflare cannot be reached.
    next();
  }
}

// ==================== 3. FIRST PRODUCT ADMIN APPROVAL ====================

async function checkFirstProductApproval(req, res, next) {
  if (!req.storeContext) return next();

  const storeId = req.storeContext.store_id;

  try {
    const storeResult = await pool.query(
      'SELECT first_product_approved FROM stores WHERE id = $1',
      [storeId]
    );
    if (storeResult.rows.length === 0) return next();

    const approved = storeResult.rows[0].first_product_approved;

    // If already approved, skip check
    if (approved === true) return next();

    // Check if this store already has ANY online product (i.e. was approved before)
    const onlineCount = await pool.query(
      'SELECT COUNT(*)::int as count FROM products WHERE store_id = $1 AND is_online = TRUE',
      [storeId]
    );
    if (onlineCount.rows[0].count > 0) {
      // Already has products online — mark as approved
      await pool.query('UPDATE stores SET first_product_approved = TRUE WHERE id = $1', [storeId]);
      return next();
    }

    // First product: mark as pending approval
    req._pendingFirstProductApproval = true;
    next();
  } catch (err) {
    console.error('checkFirstProductApproval error:', err.message);
    next();
  }
}

// ==================== 4. DUPLICATE IMAGE CHECK (SAME STORE) ====================

function computeImageHash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function checkDuplicateImages(req, res, next) {
  if (!req.storeContext) return next();
  if (!req.files) return next();

  const storeId = req.storeContext.store_id;
  const allFiles = [
    ...(req.files['image'] || []),
    ...(req.files['extra_images'] || []),
  ];

  if (allFiles.length === 0) return next();

  try {
    const fs = require('fs');
    const hashes = allFiles.map(f => {
      const buffer = f.buffer || fs.readFileSync(f.path);
      return computeImageHash(buffer);
    });

    // Check for duplicates within THIS store only
    const placeholders = hashes.map((_, i) => `$${i + 2}`).join(',');
    const result = await pool.query(
      `SELECT image_hash, p.name as product_name FROM product_image_hashes pih
       JOIN products p ON p.id = pih.product_id
       WHERE pih.store_id = $1 AND pih.image_hash IN (${placeholders})`,
      [storeId, ...hashes]
    );

    if (result.rows.length > 0) {
      const dupProductName = result.rows[0].product_name;
      return res.status(409).json({
        error: 'duplicate_image',
        message: `This image already exists in your store (product: "${dupProductName}"). Each product should have unique images.`,
        duplicate_product: dupProductName,
      });
    }

    // Attach hashes for saving after successful creation
    req._imageHashes = hashes;
    req._imageFiles = allFiles;
    next();
  } catch (err) {
    // If table doesn't exist yet, skip gracefully
    if (err.code === '42P01') return next();
    console.error('checkDuplicateImages error:', err.message);
    next();
  }
}

async function saveImageHashes(productId, storeId, hashes) {
  if (!hashes || hashes.length === 0) return;
  try {
    for (const hash of hashes) {
      await pool.query(
        `INSERT INTO product_image_hashes (product_id, store_id, image_hash)
         VALUES ($1, $2, $3) ON CONFLICT (store_id, image_hash) DO NOTHING`,
        [productId, storeId, hash]
      );
    }
  } catch (err) {
    console.error('saveImageHashes error:', err.message);
  }
}

// ==================== 5. RATE LIMIT: 2 ONLINE PRODUCTS PER MINUTE PER STORE ====================

const onlineSubmitTimestamps = new Map(); // storeId -> [timestamps]
const ONLINE_SUBMIT_LIMIT = 2;
const ONLINE_SUBMIT_WINDOW_MS = 60 * 1000; // 1 minute

function rateLimit_onlineProductSubmission(req, res, next) {
  if (!req.storeContext) return next();

  const wantsOnline = req.body.list_online === 'true' || req.body.list_online === true;
  const explicitOnline = req.body.list_online !== undefined && req.body.list_online !== '';

  // Only rate-limit online product submissions
  if (!wantsOnline && explicitOnline) return next();

  const storeId = req.storeContext.store_id;
  const now = Date.now();

  if (!onlineSubmitTimestamps.has(storeId)) {
    onlineSubmitTimestamps.set(storeId, []);
  }

  const timestamps = onlineSubmitTimestamps.get(storeId);

  // Remove expired entries
  while (timestamps.length > 0 && (now - timestamps[0]) > ONLINE_SUBMIT_WINDOW_MS) {
    timestamps.shift();
  }

  if (timestamps.length >= ONLINE_SUBMIT_LIMIT) {
    const oldestTs = timestamps[0];
    const waitSec = Math.ceil((ONLINE_SUBMIT_WINDOW_MS - (now - oldestTs)) / 1000);
    return res.status(429).json({
      error: 'online_rate_limit',
      message: `You can only submit ${ONLINE_SUBMIT_LIMIT} online products per minute. Please wait ${waitSec} seconds.`,
      retry_after_seconds: waitSec,
    });
  }

  timestamps.push(now);
  next();
}

// Cleanup stale entries every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [storeId, timestamps] of onlineSubmitTimestamps.entries()) {
    while (timestamps.length > 0 && (now - timestamps[0]) > ONLINE_SUBMIT_WINDOW_MS) {
      timestamps.shift();
    }
    if (timestamps.length === 0) onlineSubmitTimestamps.delete(storeId);
  }
}, 5 * 60 * 1000);

module.exports = {
  requireVerifiedEmail,
  verifyTurnstile,
  checkFirstProductApproval,
  checkDuplicateImages,
  saveImageHashes,
  computeImageHash,
  rateLimit_onlineProductSubmission,
};
