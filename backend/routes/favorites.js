const express = require('express');
const router = express.Router();
const { pool } = require('../config/database');
const { authenticate } = require('../middleware/auth');

// ── PRODUCT FAVORITES ──

// GET /api/favorites
router.get('/', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const result = await pool.query(
      `SELECT p.*, s.name as shop_name, s.city, s.country, s.lat, s.lng, s.image_url as store_image_url
       FROM favorites f
       JOIN products p ON f.product_id = p.id
       LEFT JOIN stores s ON p.store_id = s.id
       WHERE f.user_id = $1
       ORDER BY f.created_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Fetch favorites error:', err);
    res.status(500).json({ error: 'Failed to load favorites' });
  }
});

// POST /api/favorites
router.post('/', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const { product_id } = req.body;
    if (!product_id) return res.status(400).json({ error: 'product_id required' });

    await pool.query(
      `INSERT INTO favorites (user_id, product_id) VALUES ($1, $2)
       ON CONFLICT (user_id, product_id) DO NOTHING`,
      [userId, product_id]
    );
    res.status(201).json({ success: true });
  } catch (err) {
    console.error('Add favorite error:', err);
    res.status(500).json({ error: 'Failed to add favorite' });
  }
});

// DELETE /api/favorites/:productId
router.delete('/:productId', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const productId = req.params.productId;
    await pool.query(
      'DELETE FROM favorites WHERE user_id = $1 AND product_id = $2',
      [userId, productId]
    );
    res.json({ success: true });
  } catch (err) {
    console.error('Remove favorite error:', err);
    res.status(500).json({ error: 'Failed to remove favorite' });
  }
});

// ── STORE FAVORITES ──

// GET /api/favorites/stores
router.get('/stores', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const result = await pool.query(
      `SELECT s.*
       FROM favorite_stores fs
       JOIN stores s ON fs.store_id = s.id
       WHERE fs.user_id = $1
       ORDER BY fs.created_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Fetch favorite stores error:', err);
    res.status(500).json({ error: 'Failed to load favorite stores' });
  }
});

// POST /api/favorites/stores
router.post('/stores', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const { store_id } = req.body;
    if (!store_id) return res.status(400).json({ error: 'store_id required' });

    await pool.query(
      `INSERT INTO favorite_stores (user_id, store_id) VALUES ($1, $2)
       ON CONFLICT (user_id, store_id) DO NOTHING`,
      [userId, store_id]
    );
    res.status(201).json({ success: true });
  } catch (err) {
    console.error('Add favorite store error:', err);
    res.status(500).json({ error: 'Failed to add favorite store' });
  }
});

// DELETE /api/favorites/stores/:storeId
router.delete('/stores/:storeId', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const storeId = req.params.storeId;
    await pool.query(
      'DELETE FROM favorite_stores WHERE user_id = $1 AND store_id = $2',
      [userId, storeId]
    );
    res.json({ success: true });
  } catch (err) {
    console.error('Remove favorite store error:', err);
    res.status(500).json({ error: 'Failed to remove favorite store' });
  }
});

module.exports = router;