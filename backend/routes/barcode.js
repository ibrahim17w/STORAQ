//routes/barcode.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, optionalAuth, requireRealUser } = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');

// ==================== PUBLIC BARCODE ROUTES (must come before parameterized auth route) ====================
router.get('/products/barcode/validate', async (req, res) => {
  try {
    const code = sanitizeString(req.query.code, 50);
    if (!code) return res.status(400).json({ error: 'Code required' });

    const result = await pool.query(
      'SELECT id, name, barcode, quantity FROM products WHERE barcode = $1 LIMIT 1',
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

router.get('/products/barcode/public/:code', async (req, res) => {
  try {
    const code = sanitizeString(req.params.code, 50);
    const result = await pool.query(
      `SELECT p.*, s.name as shop_name, s.city, s.country, s.lat, s.lng
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.barcode = $1
       LIMIT 1`,
      [code]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== BARCODE LOOKUP (auth required) ====================
router.get('/products/barcode/:barcode', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store found' });
    const storeId = storeResult.rows[0].id;

    const result = await pool.query(
      'SELECT * FROM products WHERE barcode=$1 AND store_id=$2',
      [req.params.barcode, storeId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Barcode lookup failed' });
  }
});

router.get('/products/check-barcode', requireRealUser, async (req, res) => {
  try {
    const barcode = req.query.barcode;
    const excludeId = req.query.exclude_id;
    if (!barcode) return res.status(400).json({ error: 'Barcode required' });

    let sql = 'SELECT id, name FROM products WHERE barcode=$1';
    const params = [barcode];
    if (excludeId) {
      sql += ' AND id != $2';
      params.push(excludeId);
    }
    const result = await pool.query(sql, params);
    res.json({ exists: result.rows.length > 0, product: result.rows[0] || null });
  } catch (err) {
    res.status(500).json({ error: 'Barcode check failed' });
  }
});

module.exports = router;
