const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const {
  authenticateToken,
  requireRealUser,
  attachStoreContext,
} = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');

function maskCustomerLabel(fullName, customerId) {
  if (!fullName || !String(fullName).trim()) {
    return `Customer #${customerId}`;
  }
  const parts = String(fullName).trim().split(/\s+/);
  const first = parts[0];
  if (parts.length === 1) {
    return first.length <= 1 ? 'Customer' : `${first.charAt(0)}***`;
  }
  return `${first} ${parts[parts.length - 1].charAt(0)}.`;
}

function sanitizeConversation(row, viewer) {
  const base = {
    id: row.id,
    store_id: row.store_id,
    last_message_at: row.last_message_at,
    created_at: row.created_at,
    last_message: row.last_message,
    unread_count: row.unread_count,
    store_name: row.store_name,
  };

  if (viewer.isCustomer) {
    return {
      ...base,
      store_image_url: row.store_image_url,
    };
  }

  return {
    ...base,
    customer_label: maskCustomerLabel(row.customer_full_name, row.customer_id),
  };
}

function sanitizeMessage(row, viewer, storeName) {
  const isMine = row.sender_id === viewer.userId;
  let displayName = 'User';

  if (isMine) {
    displayName = viewer.isCustomer ? 'You' : 'Your store';
  } else if (viewer.isCustomer) {
    displayName = storeName || 'Store';
  } else if (row.sender_role === 'customer' || row.customer_id === row.sender_id) {
    displayName = maskCustomerLabel(row.sender_full_name, row.customer_id);
  } else {
    displayName = storeName || 'Store';
  }

  return {
    id: row.id,
    conversation_id: row.conversation_id,
    body: row.body,
    created_at: row.created_at,
    read_at: row.read_at,
    is_mine: isMine,
    display_name: displayName,
  };
}

router.get('/chat/conversations', authenticateToken, requireRealUser, attachStoreContext, async (req, res) => {
  try {
    const userId = req.user.userId;
    const storeContext = req.storeContext;

    let result;
    if (storeContext?.store_id) {
      result = await pool.query(
        `SELECT c.id, c.store_id, c.customer_id, c.last_message_at, c.created_at,
                u.full_name AS customer_full_name,
                s.name AS store_name,
                (
                  SELECT body FROM chat_messages m
                  WHERE m.conversation_id = c.id
                  ORDER BY m.created_at DESC
                  LIMIT 1
                ) AS last_message,
                (
                  SELECT COUNT(*)::int FROM chat_messages m
                  WHERE m.conversation_id = c.id
                    AND m.read_at IS NULL
                    AND m.sender_id != $1
                ) AS unread_count
         FROM chat_conversations c
         JOIN users u ON u.id = c.customer_id
         JOIN stores s ON s.id = c.store_id
         WHERE c.store_id = $2
         ORDER BY c.last_message_at DESC`,
        [userId, storeContext.store_id]
      );

      res.json(result.rows.map((row) => sanitizeConversation(row, {
        userId,
        isCustomer: false,
      })));
      return;
    }

    result = await pool.query(
      `SELECT c.id, c.store_id, c.customer_id, c.last_message_at, c.created_at,
              s.name AS store_name,
              s.image_url AS store_image_url,
              (
                SELECT body FROM chat_messages m
                WHERE m.conversation_id = c.id
                ORDER BY m.created_at DESC
                LIMIT 1
              ) AS last_message,
              (
                SELECT COUNT(*)::int FROM chat_messages m
                WHERE m.conversation_id = c.id
                  AND m.read_at IS NULL
                  AND m.sender_id != $1
              ) AS unread_count
       FROM chat_conversations c
       JOIN stores s ON s.id = c.store_id
       WHERE c.customer_id = $1
       ORDER BY c.last_message_at DESC`,
      [userId]
    );

    res.json(result.rows.map((row) => sanitizeConversation(row, {
      userId,
      isCustomer: true,
    })));
  } catch (err) {
    console.error('Chat conversations error:', err);
    res.status(500).json({ error: 'Failed to load conversations' });
  }
});

router.post('/chat/conversations', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const userId = req.user.userId;
    const storeId = parseInt(req.body.store_id);
    if (isNaN(storeId) || storeId <= 0) {
      return res.status(400).json({ error: 'Valid store_id is required' });
    }

    const storeCheck = await pool.query(
      'SELECT id, name, image_url FROM stores WHERE id = $1 AND COALESCE(is_active, TRUE) = TRUE',
      [storeId]
    );
    if (storeCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Store not found' });
    }

    const existing = await pool.query(
      'SELECT * FROM chat_conversations WHERE customer_id = $1 AND store_id = $2',
      [userId, storeId]
    );
    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      return res.json(sanitizeConversation({
        ...row,
        store_name: storeCheck.rows[0].name,
        store_image_url: storeCheck.rows[0].image_url,
        last_message: null,
        unread_count: 0,
      }, { userId, isCustomer: true }));
    }

    const created = await pool.query(
      `INSERT INTO chat_conversations (customer_id, store_id)
       VALUES ($1, $2)
       RETURNING *`,
      [userId, storeId]
    );

    res.status(201).json(sanitizeConversation({
      ...created.rows[0],
      store_name: storeCheck.rows[0].name,
      store_image_url: storeCheck.rows[0].image_url,
      last_message: null,
      unread_count: 0,
    }, { userId, isCustomer: true }));
  } catch (err) {
    console.error('Create conversation error:', err);
    res.status(500).json({ error: 'Failed to start conversation' });
  }
});

router.get('/chat/conversations/:id/messages', authenticateToken, requireRealUser, attachStoreContext, async (req, res) => {
  try {
    const conversationId = parseInt(req.params.id);
    const userId = req.user.userId;
    const since = req.query.since;

    const convo = await pool.query(
      `SELECT c.*, s.name AS store_name
       FROM chat_conversations c
       JOIN stores s ON s.id = c.store_id
       WHERE c.id = $1`,
      [conversationId]
    );
    if (convo.rows.length === 0) {
      return res.status(404).json({ error: 'Conversation not found' });
    }

    const row = convo.rows[0];
    const storeContext = req.storeContext;
    const isCustomer = row.customer_id === userId;
    const isStoreStaff =
      storeContext?.store_id && storeContext.store_id === row.store_id;

    if (!isCustomer && !isStoreStaff) {
      return res.status(403).json({ error: 'Access denied' });
    }

    let query = `
      SELECT m.*,
             u.full_name AS sender_full_name,
             c.customer_id
      FROM chat_messages m
      JOIN users u ON u.id = m.sender_id
      JOIN chat_conversations c ON c.id = m.conversation_id
      WHERE m.conversation_id = $1
    `;
    const params = [conversationId];

    if (since) {
      params.push(since);
      query += ` AND m.created_at > $${params.length}`;
    }

    query += ' ORDER BY m.created_at ASC LIMIT 200';

    const messages = await pool.query(query, params);

    await pool.query(
      `UPDATE chat_messages
       SET read_at = NOW()
       WHERE conversation_id = $1
         AND sender_id != $2
         AND read_at IS NULL`,
      [conversationId, userId]
    );

    const viewer = { userId, isCustomer };
    res.json(messages.rows.map((m) => sanitizeMessage(m, viewer, row.store_name)));
  } catch (err) {
    console.error('Chat messages error:', err);
    res.status(500).json({ error: 'Failed to load messages' });
  }
});

router.post('/chat/conversations/:id/messages', authenticateToken, requireRealUser, attachStoreContext, async (req, res) => {
  try {
    const conversationId = parseInt(req.params.id);
    const userId = req.user.userId;
    const body = sanitizeString(req.body.body, 2000);

    if (!body || body.trim().length === 0) {
      return res.status(400).json({ error: 'Message cannot be empty' });
    }

    const convo = await pool.query(
      `SELECT c.*, s.name AS store_name
       FROM chat_conversations c
       JOIN stores s ON s.id = c.store_id
       WHERE c.id = $1`,
      [conversationId]
    );
    if (convo.rows.length === 0) {
      return res.status(404).json({ error: 'Conversation not found' });
    }

    const row = convo.rows[0];
    const storeContext = req.storeContext;
    const isCustomer = row.customer_id === userId;
    const isStoreStaff =
      storeContext?.store_id && storeContext.store_id === row.store_id;

    if (!isCustomer && !isStoreStaff) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const inserted = await pool.query(
      `INSERT INTO chat_messages (conversation_id, sender_id, body)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [conversationId, userId, body.trim()]
    );

    await pool.query(
      'UPDATE chat_conversations SET last_message_at = NOW() WHERE id = $1',
      [conversationId]
    );

    const messageRow = {
      ...inserted.rows[0],
      sender_full_name: null,
      customer_id: row.customer_id,
    };

    res.status(201).json(sanitizeMessage(
      messageRow,
      { userId, isCustomer },
      row.store_name,
    ));
  } catch (err) {
    console.error('Send message error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

module.exports = router;
