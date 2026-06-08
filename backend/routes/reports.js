const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, requireRealUser } = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');

const VALID_TARGETS = new Set(['store', 'product', 'chat']);

router.post('/reports', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const userId = req.user.userId;
    const targetType = sanitizeString(req.body.target_type, 20);
    const targetId = parseInt(req.body.target_id, 10);
    const reason = sanitizeString(req.body.reason, 2000);
    const storeIdRaw = req.body.store_id;
    const storeId = storeIdRaw != null ? parseInt(storeIdRaw, 10) : null;
    const metadata = {};

    if (!VALID_TARGETS.has(targetType)) {
      return res.status(400).json({ error: 'Invalid target type' });
    }
    if (!Number.isInteger(targetId) || targetId <= 0) {
      return res.status(400).json({ error: 'Invalid target id' });
    }
    if (!reason || reason.length < 10) {
      return res.status(400).json({ error: 'Reason must be at least 10 characters' });
    }

    let resolvedStoreId = Number.isInteger(storeId) && storeId > 0 ? storeId : null;

    if (targetType === 'store') {
      const store = await pool.query('SELECT id, name FROM stores WHERE id = $1', [targetId]);
      if (store.rows.length === 0) return res.status(404).json({ error: 'Store not found' });
      metadata.store_name = store.rows[0].name;
      resolvedStoreId = targetId;
    } else if (targetType === 'product') {
      const product = await pool.query(
        `SELECT p.id, p.name, p.store_id, s.name AS store_name
         FROM products p JOIN stores s ON s.id = p.store_id WHERE p.id = $1`,
        [targetId]
      );
      if (product.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
      metadata.product_name = product.rows[0].name;
      metadata.store_name = product.rows[0].store_name;
      resolvedStoreId = resolvedStoreId || product.rows[0].store_id;
    } else if (targetType === 'chat') {
      const chat = await pool.query(
        `SELECT c.id, c.store_id, s.name AS store_name, u.full_name AS customer_name
         FROM chat_conversations c
         JOIN stores s ON s.id = c.store_id
         JOIN users u ON u.id = c.customer_id
         WHERE c.id = $1 AND c.customer_id = $2`,
        [targetId, userId]
      );
      if (chat.rows.length === 0) {
        return res.status(404).json({ error: 'Chat conversation not found' });
      }
      metadata.store_name = chat.rows[0].store_name;
      metadata.customer_name = chat.rows[0].customer_name;
      resolvedStoreId = resolvedStoreId || chat.rows[0].store_id;
    }

    const result = await pool.query(
      `INSERT INTO content_reports
         (target_type, target_id, store_id, reporter_id, reporter_role, reason, metadata)
       VALUES ($1, $2, $3, $4, 'user', $5, $6)
       RETURNING id, target_type, target_id, status, created_at`,
      [targetType, targetId, resolvedStoreId, userId, reason, JSON.stringify(metadata)]
    );

    res.status(201).json({
      message: 'Report submitted',
      report: result.rows[0],
    });
  } catch (err) {
    console.error('User report error:', err.message);
    res.status(500).json({ error: 'Failed to submit report' });
  }
});

module.exports = router;
