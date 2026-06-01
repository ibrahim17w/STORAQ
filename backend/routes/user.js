//routes/user.js
const express = require('express');
const bcrypt = require('bcryptjs');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, requireRealUser, attachStoreContext } = require('../middleware/auth');
const { sanitizeString, deleteUploadFiles } = require('../middleware/helpers');
const { validatePasswordStrength } = require('../middleware/security');

// GET CURRENT USER
router.get('/me', authenticateToken, attachStoreContext, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, full_name, email, phone, role, preferred_language, created_at FROM users WHERE id=$1',
      [req.user.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Account not found' });
    
    const user = result.rows[0];
    user.store = req.storeContext || null;
    res.json(user);
  } catch (err) {
    console.error('Get user error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// UPDATE PROFILE
router.put('/me', authenticateToken, requireRealUser, async (req, res) => {
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
router.put('/me/password', authenticateToken, requireRealUser, async (req, res) => {
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
router.put('/me/language', authenticateToken, requireRealUser, async (req, res) => {
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
router.delete('/me', authenticateToken, requireRealUser, attachStoreContext, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const userResult = await client.query(
      'SELECT id, email, role, full_name FROM users WHERE id = $1',
      [req.user.userId]
    );
    if (userResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Account not found' });
    }

    const user = userResult.rows[0];
    const isOwner = user.role === 'store_owner';

    // ==================== WORKER: fully delete account, order history preserved via cashier_name ====================
    if (!isOwner) {
      // cashier_name is already stored in orders at checkout time
      // order_items.product_name is already stored at checkout time
      // No store data is touched — the worker just ceases to exist as a user

      if (user.email) {
        await client.query('DELETE FROM failed_logins WHERE email = $1', [user.email]);
        await client.query('DELETE FROM verification_codes WHERE email = $1', [user.email]);
      }
      await client.query('DELETE FROM product_views WHERE user_id = $1', [req.user.userId]);
      await client.query('DELETE FROM search_queries WHERE user_id = $1', [req.user.userId]);
      // store_staff row auto-deleted via ON DELETE CASCADE

      await client.query('DELETE FROM users WHERE id = $1', [req.user.userId]);
      await client.query('COMMIT');
      return res.json({ message: 'Account deleted successfully' });
    }

    // ==================== OWNER: delete store, products, and all physical images ====================
    if (isOwner) {
      const storeResult = await client.query(
        'SELECT id, image_url, logo_url FROM stores WHERE owner_id = $1',
        [req.user.userId]
      );

      for (const store of storeResult.rows) {
        const filesToDelete = [];
        if (store.image_url) filesToDelete.push(store.image_url);
        if (store.logo_url) filesToDelete.push(store.logo_url);

        const productsResult = await client.query(
          'SELECT id, image_url, images FROM products WHERE store_id = $1',
          [store.id]
        );

        for (const product of productsResult.rows) {
          if (product.image_url) filesToDelete.push(product.image_url);
          if (product.images && Array.isArray(product.images)) {
            filesToDelete.push(...product.images.filter(u => u && typeof u === 'string'));
          }
        }

        const piResult = await client.query(
          `SELECT pi.image_url 
           FROM product_images pi
           JOIN products p ON p.id = pi.product_id
           WHERE p.store_id = $1`,
          [store.id]
        );
        for (const row of piResult.rows) {
          if (row.image_url) filesToDelete.push(row.image_url);
        }

        deleteUploadFiles(filesToDelete);

        for (const product of productsResult.rows) {
          try { await client.query('DELETE FROM image_embeddings WHERE product_id = $1', [product.id]); } catch (_) {}
        }

        // Store deletion cascades to products, receipt_settings, store_staff
        // Orders survive because orders.store_id is ON DELETE SET NULL
        await client.query('DELETE FROM stores WHERE id = $1', [store.id]);
      }
    }

    // ==================== COMMON CLEANUP (owner + regular customer) ====================
    if (user.email) {
      await client.query('DELETE FROM failed_logins WHERE email = $1', [user.email]);
      await client.query('DELETE FROM verification_codes WHERE email = $1', [user.email]);
    }
    await client.query('DELETE FROM product_views WHERE user_id = $1', [req.user.userId]);
    await client.query('DELETE FROM search_queries WHERE user_id = $1', [req.user.userId]);

    await client.query('DELETE FROM users WHERE id = $1', [req.user.userId]);
    await client.query('COMMIT');
    res.json({ message: 'Account deleted successfully' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Delete account error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  } finally {
    client.release();
  }
});

module.exports = router;