const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, requireRealUser } = require('../middleware/auth');
const { sanitizeString } = require('../middleware/helpers');

const VALID_CATEGORIES = new Set([
  'general',
  'account',
  'billing',
  'technical',
  'report',
]);

router.get('/support/tickets', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const userId = req.user.userId;
    const result = await pool.query(
      `SELECT t.*,
              (
                SELECT body FROM support_ticket_messages m
                WHERE m.ticket_id = t.id
                ORDER BY m.created_at DESC
                LIMIT 1
              ) AS last_message,
              (
                SELECT COUNT(*)::int FROM support_ticket_messages m
                WHERE m.ticket_id = t.id
                  AND m.sender_role = 'admin'
                  AND m.read_at IS NULL
              ) AS unread_count
       FROM support_tickets t
       WHERE t.user_id = $1
       ORDER BY t.last_message_at DESC`,
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Support tickets list error:', err);
    res.status(500).json({ error: 'Failed to load support tickets' });
  }
});

router.post('/support/tickets', authenticateToken, requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    const userId = req.user.userId;
    const subject = sanitizeString(req.body.subject, 200);
    const category = sanitizeString(req.body.category, 50) || 'general';
    const body = sanitizeString(req.body.body, 4000);

    if (!subject || subject.length < 3) {
      return res.status(400).json({ error: 'Subject must be at least 3 characters' });
    }
    if (!body || body.length < 3) {
      return res.status(400).json({ error: 'Message must be at least 3 characters' });
    }
    if (!VALID_CATEGORIES.has(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    await client.query('BEGIN');

    const ticket = await client.query(
      `INSERT INTO support_tickets (user_id, subject, category, status)
       VALUES ($1, $2, $3, 'open')
       RETURNING *`,
      [userId, subject, category]
    );

    const message = await client.query(
      `INSERT INTO support_ticket_messages (ticket_id, sender_id, sender_role, body)
       VALUES ($1, $2, 'user', $3)
       RETURNING *`,
      [ticket.rows[0].id, userId, body.trim()]
    );

    await client.query('COMMIT');

    res.status(201).json({
      ticket: ticket.rows[0],
      message: message.rows[0],
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Create support ticket error:', err);
    res.status(500).json({ error: 'Failed to create support ticket' });
  } finally {
    client.release();
  }
});

router.get('/support/tickets/:id/messages', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const userId = req.user.userId;

    const ticket = await pool.query(
      'SELECT * FROM support_tickets WHERE id = $1 AND user_id = $2',
      [ticketId, userId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }

    const messages = await pool.query(
      `SELECT m.*, u.full_name AS sender_name
       FROM support_ticket_messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.ticket_id = $1
       ORDER BY m.created_at ASC`,
      [ticketId]
    );

    await pool.query(
      `UPDATE support_ticket_messages
       SET read_at = NOW()
       WHERE ticket_id = $1
         AND sender_role = 'admin'
         AND read_at IS NULL`,
      [ticketId]
    );

    res.json({
      ticket: ticket.rows[0],
      messages: messages.rows,
    });
  } catch (err) {
    console.error('Support messages error:', err);
    res.status(500).json({ error: 'Failed to load messages' });
  }
});

router.post('/support/tickets/:id/messages', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const ticketId = parseInt(req.params.id);
    const userId = req.user.userId;
    const body = sanitizeString(req.body.body, 4000);

    if (!body || body.trim().length < 1) {
      return res.status(400).json({ error: 'Message cannot be empty' });
    }

    const ticket = await pool.query(
      'SELECT * FROM support_tickets WHERE id = $1 AND user_id = $2',
      [ticketId, userId]
    );
    if (ticket.rows.length === 0) {
      return res.status(404).json({ error: 'Ticket not found' });
    }
    if (ticket.rows[0].status === 'closed') {
      return res.status(400).json({ error: 'This ticket is closed. Open a new ticket instead.' });
    }

    const inserted = await pool.query(
      `INSERT INTO support_ticket_messages (ticket_id, sender_id, sender_role, body)
       VALUES ($1, $2, 'user', $3)
       RETURNING *`,
      [ticketId, userId, body.trim()]
    );

    await pool.query(
      `UPDATE support_tickets
       SET last_message_at = NOW(), updated_at = NOW(), status = 'open'
       WHERE id = $1`,
      [ticketId]
    );

    const sender = await pool.query(
      'SELECT full_name FROM users WHERE id = $1',
      [userId]
    );

    res.status(201).json({
      ...inserted.rows[0],
      sender_name: sender.rows[0]?.full_name,
    });
  } catch (err) {
    console.error('Support reply error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

module.exports = router;
