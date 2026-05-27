//routes/user.js
const express = require('express');
const bcrypt = require('bcryptjs');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, requireRealUser } = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');
const { validatePasswordStrength } = require('../middleware/security');

// GET CURRENT USER
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, full_name, email, phone, role, preferred_language, created_at FROM users WHERE id=$1',
      [req.user.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Account not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Get user error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// UPDATE PROFILE
router.put('/me', requireRealUser, async (req, res) => {
  try {
    const full_name = sanitizeString(req.body.full_name, 100);
    const phone = sanitizeString(req.body.phone, 50);
    const result = await pool.query(
      'UPDATE users SET full_name=$1, phone=$2 WHERE id=$3 RETURNING id, full_name, email, phone, role, preferred_language, created_at',
      [full_name, phone, req.user.userId]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Update profile error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// CHANGE PASSWORD
router.put('/me/password', requireRealUser, async (req, res) => {
  try {
    const { current_password, new_password } = req.body;
    if (!current_password || !new_password) {
      return res.status(400).json({ error: 'Current password and new password are required.' });
    }

    const strength = validatePasswordStrength(new_password);
    if (!strength.valid) {
      return res.status(400).json({ error: strength.error });
    }

    const user = await pool.query('SELECT password_hash FROM users WHERE id=$1', [req.user.userId]);
    if (!await bcrypt.compare(current_password, user.rows[0].password_hash)) {
      return res.status(400).json({ error: 'Current password is incorrect' });
    }

    const isSamePassword = await bcrypt.compare(new_password, user.rows[0].password_hash);
    if (isSamePassword) {
      return res.status(400).json({ error: 'New password cannot be the same as your current password. Please choose a different password.' });
    }

    const hashed = await bcrypt.hash(new_password, 10);
    await pool.query('UPDATE users SET password_hash=$1 WHERE id=$2', [hashed, req.user.userId]);
    res.json({ message: 'Password updated successfully' });
  } catch (err) {
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// UPDATE PREFERRED LANGUAGE
router.put('/me/language', requireRealUser, async (req, res) => {
  try {
    const preferred_language = sanitizeString(req.body.preferred_language, 10);
    await pool.query(
      'UPDATE users SET preferred_language=$1 WHERE id=$2',
      [preferred_language, req.user.userId]
    );
    res.json({ message: 'Language preference updated' });
  } catch (err) {
    console.error('Update language error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// DELETE ACCOUNT
router.delete('/me', requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const storeResult = await client.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    for (const row of storeResult.rows) {
      const productIds = await client.query('SELECT id FROM products WHERE store_id=$1', [row.id]);
      for (const p of productIds.rows) {
        await client.query('DELETE FROM image_embeddings WHERE product_id=$1', [p.id]);
        await client.query('DELETE FROM product_images WHERE product_id=$1', [p.id]);
      }
      await client.query(
        'DELETE FROM order_items USING orders WHERE order_items.order_id = orders.id AND orders.store_id = $1',
        [row.id]
      );
      await client.query('DELETE FROM orders WHERE store_id=$1', [row.id]);
      await client.query('DELETE FROM products WHERE store_id=$1', [row.id]);
    }

    await client.query('DELETE FROM stores WHERE owner_id=$1', [req.user.userId]);
    const userResult = await client.query('SELECT email FROM users WHERE id=$1', [req.user.userId]);
    if (userResult.rows.length > 0) {
      const email = userResult.rows[0].email;
      await client.query('DELETE FROM failed_logins WHERE email=$1', [email]);
      await client.query('DELETE FROM verification_codes WHERE email=$1', [email]);
    }
    await client.query('DELETE FROM product_views WHERE user_id=$1', [req.user.userId]);
    await client.query('DELETE FROM search_queries WHERE user_id=$1', [req.user.userId]);

    await client.query('DELETE FROM users WHERE id=$1', [req.user.userId]);
    await client.query('COMMIT');
    res.json({ message: 'Account deleted successfully' });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  } finally {
    client.release();
  }
});

module.exports = router;