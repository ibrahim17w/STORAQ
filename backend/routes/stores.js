//routes/stores.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { upload } = require('../config/upload');
const { authenticateToken, optionalAuth, requireRealUser } = require('../middleware/auth');
const { sanitizeString, getPagination, getBaseUrl } = require('../middleware/helpers');

// MY STORE — MUST come BEFORE /api/stores/:id so "my-store" isn't captured as :id
router.get('/my-store', requireRealUser, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE s.owner_id=$1
    `, [req.user.userId]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'No store found' });

    const store = result.rows[0];
    const productsResult = await pool.query(
      'SELECT * FROM products WHERE store_id=$1 ORDER BY created_at DESC',
      [store.id]
    );
    store.products = productsResult.rows;

    res.json(store);
  } catch (err) {
    console.error('My store error:', err);
    res.status(500).json({ error: 'Failed to load store' });
  }
});

router.get('/stores', async (req, res) => {
  try {
    const { page, limit, offset } = getPagination(req, 20, 100);
    const countResult = await pool.query('SELECT COUNT(*) as total FROM stores');
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      ORDER BY s.id DESC
      LIMIT $1 OFFSET $2
    `, [limit, offset]);

    res.json({
      data: result.rows,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) }
    });
  } catch (err) {
    console.error('Stores list error:', err);
    res.status(500).json({ error: 'Failed to load stores' });
  }
});

router.get('/stores/:id', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE s.id=$1
    `, [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Store not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Get store error:', err);
    res.status(500).json({ error: 'Failed to load store' });
  }
});

router.put('/my-store', requireRealUser, upload.single('image'), async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT * FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store found' });

    const existing = storeResult.rows[0];
    const name = req.body.name !== undefined ? sanitizeString(req.body.name, 100) : existing.name;
    const city = req.body.city !== undefined ? sanitizeString(req.body.city, 100) : existing.city;
    const location_description = req.body.location_description !== undefined ? sanitizeString(req.body.location_description, 200) : existing.location_description;
    const country = req.body.country !== undefined ? sanitizeString(req.body.country, 100) : existing.country;
    const phone = req.body.phone !== undefined ? sanitizeString(req.body.phone, 50) : existing.phone;

    let lat = existing.lat;
    if (req.body.lat !== undefined) {
      const parsedLat = parseFloat(req.body.lat);
      if (isNaN(parsedLat) || parsedLat < -90 || parsedLat > 90) {
        return res.status(400).json({ error: 'Invalid latitude. Must be between -90 and 90.' });
      }
      lat = parsedLat;
    }

    let lng = existing.lng;
    if (req.body.lng !== undefined) {
      const parsedLng = parseFloat(req.body.lng);
      if (isNaN(parsedLng) || parsedLng < -180 || parsedLng > 180) {
        return res.status(400).json({ error: 'Invalid longitude. Must be between -180 and 180.' });
      }
      lng = parsedLng;
    }

    const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : existing.image_url;
    const city_id = req.body.city_id !== undefined ? sanitizeString(req.body.city_id, 100) : existing.city_id;
    const country_code = req.body.country_code !== undefined ? sanitizeString(req.body.country_code, 2).toLowerCase().substring(0, 2) : existing.country_code;

    const result = await pool.query(
      `UPDATE stores SET name=$1, city=$2, location_description=$3, country=$4, phone=$5, lat=$6, lng=$7, image_url=$8, city_id=$9, country_code=$10, updated_at=NOW() WHERE id=$11 RETURNING *`,
      [name, city, location_description, country, phone, lat, lng, imageUrl, city_id, country_code, existing.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// ADMIN: Set store as sponsored
router.put('/admin/stores/:id/sponsor', authenticateToken, async (req, res) => {
  try {
    const userResult = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
    if (userResult.rows.length === 0 || userResult.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const storeId = parseInt(req.params.id);
    const { tier, expiresAt } = req.body;

    await pool.query(
      `UPDATE stores
       SET is_sponsored = TRUE,
       sponsorship_tier = $1,
       sponsorship_expires_at = $2
       WHERE id = $3`,
      [tier || 1, expiresAt || null, storeId]
    );

    res.json({ message: 'Store sponsorship updated' });
  } catch (err) {
    console.error('Sponsor error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

module.exports = router;
