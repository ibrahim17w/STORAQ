//routes/categories.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');

router.get('/categories', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, icon, translations, sort_order, parent_id
       FROM categories
       ORDER BY sort_order, name`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Categories error:', err);
    res.status(500).json({ error: 'Failed to load categories' });
  }
});

router.get('/categories/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM categories WHERE id = $1', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Category not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

module.exports = router;
