// backend/routes/favorites.js
const express = require('express');
const router = express.Router();
const { pool } = require('../config/database');
const { authenticate } = require('../middleware/auth');

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

module.exports = router;
