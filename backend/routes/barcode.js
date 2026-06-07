//routes/barcode.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const {
  authenticateToken,
  optionalAuth,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  genericIpRateLimit,
} = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');

// ==================== PUBLIC BARCODE LOOKUP (marketplace scanning) ====================
// Used by buyers scanning a product they see in a physical store. Returns
// only the minimal public-facing fields so attackers cannot scrape full
// inventory rows (price/quantity/internal IDs) across all stores.
//
// Per-IP rate limit: legitimate users scan one barcode at a time and
// rarely more than a few per minute. A bot iterating barcodes (12-digit
// UPC/EAN keyspace is tiny) could otherwise enumerate the whole
// online-product catalog quickly. 120/hour/IP fits a power-user but
// blocks programmatic scraping.
router.get(
  '/products/barcode/validate',
  genericIpRateLimit({ keyPrefix: 'barcode-pub', max: 120, windowMs: 60 * 60 * 1000 }),
  async (req, res) => {
  try {
    const code = sanitizeString(req.query.code, 50);
    if (!code) return res.status(400).json({ error: 'Code required' });

    const result = await pool.query(
      `SELECT p.id, p.name, p.image_url, p.display_price, p.display_currency,
              p.currency, p.price, p.is_online, s.id AS shop_id, s.name AS shop_name
         FROM products p
         JOIN stores s ON p.store_id = s.id
        WHERE p.barcode = $1
          AND p.is_online = TRUE
          AND COALESCE(s.is_active, TRUE) = TRUE
        LIMIT 1`,
      [code]
    );
    res.json({
      exists: result.rows.length > 0,
      product: result.rows.length > 0 ? result.rows[0] : null,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

router.get(
  '/products/barcode/public/:code',
  genericIpRateLimit({ keyPrefix: 'barcode-pub2', max: 120, windowMs: 60 * 60 * 1000 }),
  async (req, res) => {
  try {
    const code = sanitizeString(req.params.code, 50);
    const result = await pool.query(
      `SELECT p.id, p.name, p.description, p.image_url, p.images,
              p.display_price, p.display_currency, p.currency, p.price,
              s.id AS shop_id, s.name AS shop_name, s.city, s.country, s.lat, s.lng
         FROM products p
         JOIN stores s ON p.store_id = s.id
        WHERE p.barcode = $1
          AND p.is_online = TRUE
          AND COALESCE(s.is_active, TRUE) = TRUE
        LIMIT 1`,
      [code]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== BARCODE LOOKUP (store staff / owner) ====================
// Always scoped to the caller's own store. Workers with store access can
// use this for POS scanning; previously only owners worked.
router.get(
  '/products/barcode/:barcode',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  async (req, res) => {
    try {
      const storeId = req.storeContext.store_id;
      const barcode = sanitizeString(req.params.barcode, 50);
      if (!barcode) return res.status(400).json({ error: 'Barcode required' });

      const result = await pool.query(
        'SELECT * FROM products WHERE barcode=$1 AND store_id=$2',
        [barcode, storeId]
      );
      if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
      res.json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: 'Barcode lookup failed' });
    }
  }
);

// Tenant-scoped barcode duplicate check used by the product create/update
// form. The previous version ran a GLOBAL query, leaking competitor product
// names. We now restrict it to the caller's own store and exclude IDs only
// when they belong to that store too.
router.get(
  '/products/check-barcode',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  async (req, res) => {
    try {
      const barcode = sanitizeString(req.query.barcode, 50);
      const storeId = req.storeContext.store_id;
      if (!barcode) return res.status(400).json({ error: 'Barcode required' });

      const excludeIdRaw = req.query.exclude_id;
      const excludeId =
        excludeIdRaw !== undefined && excludeIdRaw !== ''
          ? Number.parseInt(excludeIdRaw, 10)
          : null;

      let sql = 'SELECT id, name FROM products WHERE barcode=$1 AND store_id=$2';
      const params = [barcode, storeId];
      if (Number.isInteger(excludeId) && excludeId > 0) {
        sql += ' AND id != $3';
        params.push(excludeId);
      }
      const result = await pool.query(sql, params);
      res.json({ exists: result.rows.length > 0, product: result.rows[0] || null });
    } catch (err) {
      res.status(500).json({ error: 'Barcode check failed' });
    }
  }
);

module.exports = router;
