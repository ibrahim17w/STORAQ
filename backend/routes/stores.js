//routes/stores.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { upload } = require('../config/upload');
const { authenticateToken, optionalAuth, requireRealUser, attachStoreContext, requireStoreOwner, requireStoreAccess, requireInventoryAccess } = require('../middleware/auth');
const { sanitizeString, getPagination, getBaseUrl } = require('../middleware/helpers');

// ============================================================
// MY STORE (Owner + Accepted Worker)
// ============================================================

router.get('/my-store', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE s.id=$1
    `, [req.storeContext.store_id]);
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

router.put('/my-store', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, upload.single('image'), async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT * FROM stores WHERE id=$1', [req.storeContext.store_id]);
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

// ============================================================
// WORKER INVITATIONS — MUST come BEFORE /stores/:id
// ============================================================

router.get('/stores/my-invitations', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT ss.id, ss.store_id, ss.can_manage_inventory, ss.status, ss.invited_at, ss.responded_at,
              s.name AS store_name, s.city AS store_city, s.image_url AS store_image,
              inviter.full_name AS invited_by_name
       FROM store_staff ss
       JOIN stores s ON s.id = ss.store_id
       LEFT JOIN users inviter ON inviter.id = ss.invited_by
       WHERE ss.user_id = $1 AND ss.status = 'pending'
       ORDER BY ss.invited_at DESC`,
      [req.user.userId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Fetch invitations error:', err);
    res.status(500).json({ error: 'Failed to load invitations' });
  }
});

router.post('/stores/my-invitations/:id/accept', authenticateToken, requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const invitationId = parseInt(req.params.id);
    if (isNaN(invitationId)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid invitation ID' });
    }

    const checkResult = await client.query(
      'SELECT id, store_id, can_manage_inventory FROM store_staff WHERE id = $1 AND user_id = $2 AND status = $3',
      [invitationId, req.user.userId, 'pending']
    );
    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Invitation not found or already responded to.' });
    }

    const invitation = checkResult.rows[0];

    await client.query(
      "UPDATE store_staff SET status = 'rejected', responded_at = NOW() WHERE user_id = $1 AND id != $2 AND status = 'pending'",
      [req.user.userId, invitationId]
    );

    await client.query(
      "UPDATE store_staff SET status = 'accepted', responded_at = NOW() WHERE id = $1",
      [invitationId]
    );

    await client.query('COMMIT');

    res.json({
      message: 'Invitation accepted successfully.',
      store: {
        store_id: invitation.store_id,
        role: 'worker',
        can_manage_inventory: invitation.can_manage_inventory
      }
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Accept invitation error:', err);
    res.status(500).json({ error: 'Failed to accept invitation.' });
  } finally {
    client.release();
  }
});

router.post('/stores/my-invitations/:id/reject', authenticateToken, requireRealUser, async (req, res) => {
  try {
    const invitationId = parseInt(req.params.id);
    if (isNaN(invitationId)) return res.status(400).json({ error: 'Invalid invitation ID' });

    const checkResult = await pool.query(
      'SELECT id FROM store_staff WHERE id = $1 AND user_id = $2 AND status = $3',
      [invitationId, req.user.userId, 'pending']
    );
    if (checkResult.rows.length === 0) {
      return res.status(404).json({ error: 'Invitation not found or already responded to.' });
    }

    await pool.query(
      "UPDATE store_staff SET status = 'rejected', responded_at = NOW() WHERE id = $1",
      [invitationId]
    );

    res.json({ message: 'Invitation rejected.' });
  } catch (err) {
    console.error('Reject invitation error:', err);
    res.status(500).json({ error: 'Failed to reject invitation.' });
  }
});

// ============================================================
// PUBLIC STORES — /stores/sponsored MUST come BEFORE /stores/:id
// ============================================================

router.get('/stores', async (req, res) => {
  try {
    const { page, limit, offset } = getPagination(req, 20, 100);
    const countResult = await pool.query('SELECT COUNT(*) as total FROM stores WHERE COALESCE(is_active, TRUE) = TRUE');
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE COALESCE(s.is_active, TRUE) = TRUE
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

router.get('/stores/sponsored', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE s.is_sponsored = TRUE
      AND COALESCE(s.is_active, TRUE) = TRUE
      AND (s.sponsorship_expires_at IS NULL OR s.sponsorship_expires_at > NOW())
      ORDER BY s.sponsorship_tier DESC, s.rating DESC
      LIMIT 10
    `);
    res.json(result.rows);
  } catch (err) {
    console.error('Sponsored stores error:', err);
    res.status(500).json({ error: 'Failed to load sponsored stores' });
  }
});

router.get('/stores/:id', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT s.*, c.display_names as city_display_names,
             (SELECT COUNT(*)::int FROM store_reviews r
              WHERE r.store_id = s.id AND r.status = 'active') AS review_count
      FROM stores s
      LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
      WHERE s.id=$1
    `, [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Store not found' });
    const store = result.rows[0];
    if (store.is_active === false) return res.status(403).json({ error: 'This store has been deactivated' });
    res.json(store);
  } catch (err) {
    console.error('Get store error:', err);
    res.status(500).json({ error: 'Failed to load store' });
  }
});

// ============================================================
// STAFF MANAGEMENT (Owner Only)
// ============================================================

router.get('/my-store/staff', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT ss.id, ss.user_id, ss.can_manage_inventory, ss.status, ss.invited_at, ss.responded_at, u.full_name, u.email, u.phone
      FROM store_staff ss
      JOIN users u ON ss.user_id = u.id
      WHERE ss.store_id = $1
      ORDER BY ss.created_at DESC
    `, [req.storeContext.store_id]);
    res.json(result.rows);
  } catch (err) {
    console.error('List staff error:', err);
    res.status(500).json({ error: 'Failed to load staff members' });
  }
});

router.post('/my-store/staff', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { email, can_manage_inventory } = req.body;
    const normalizedEmail = (email || '').toLowerCase().trim();

    if (!normalizedEmail) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Email is required' });
    }

    const userResult = await client.query('SELECT id, email_verified, full_name FROM users WHERE email = $1', [normalizedEmail]);
    if (userResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'No user found with this email. They must register first.' });
    }
    const targetUser = userResult.rows[0];
    if (!targetUser.email_verified) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'This user has not verified their email yet.' });
    }

    const ownerId = parseInt(req.user.userId, 10);
    if (targetUser.id === ownerId) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'You cannot add yourself as staff.' });
    }

    const existingInThisStore = await client.query(
      'SELECT id, status FROM store_staff WHERE store_id = $1 AND user_id = $2',
      [req.storeContext.store_id, targetUser.id]
    );
    if (existingInThisStore.rows.length > 0) {
      const existing = existingInThisStore.rows[0];
      if (existing.status === 'accepted') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'This user is already a staff member.' });
      }
      if (existing.status === 'pending') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'This user already has a pending invitation.' });
      }
      await client.query(
        'UPDATE store_staff SET status = $1, can_manage_inventory = $2, invited_by = $3, invited_at = NOW(), responded_at = NULL WHERE id = $4',
        ['pending', can_manage_inventory === true, ownerId, existing.id]
      );
    } else {
      const alreadyOtherStore = await client.query(
        'SELECT id FROM store_staff WHERE user_id = $1 AND status = $2',
        [targetUser.id, 'accepted']
      );
      if (alreadyOtherStore.rows.length > 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'This user is already assigned to another store.' });
      }

      await client.query(
        'INSERT INTO store_staff (store_id, user_id, can_manage_inventory, status, invited_by, invited_at) VALUES ($1, $2, $3, $4, $5, NOW()) RETURNING *',
        [req.storeContext.store_id, targetUser.id, can_manage_inventory === true, 'pending', ownerId]
      );
    }

    await client.query('COMMIT');
    res.status(201).json({
      message: 'Invitation sent successfully.',
      user: { id: targetUser.id, full_name: targetUser.full_name, email: normalizedEmail }
    });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') {
      return res.status(400).json({ error: 'This user is already a staff member.' });
    }
    console.error('Add staff error:', err);
    res.status(500).json({ error: 'Failed to add staff member' });
  } finally {
    client.release();
  }
});

router.delete('/my-store/staff/:id', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, async (req, res) => {
  try {
    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      return res.status(400).json({ error: 'Invalid staff ID' });
    }

    const result = await pool.query(
      'DELETE FROM store_staff WHERE id = $1 AND store_id = $2 RETURNING *',
      [staffId, req.storeContext.store_id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }
    res.json({ message: 'Staff member removed' });
  } catch (err) {
    console.error('Remove staff error:', err);
    res.status(500).json({ error: 'Failed to remove staff member' });
  }
});

router.put('/my-store/staff/:id/permissions', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, async (req, res) => {
  try {
    const staffId = parseInt(req.params.id);
    if (isNaN(staffId)) {
      return res.status(400).json({ error: 'Invalid staff ID' });
    }
    const { can_manage_inventory } = req.body;

    const result = await pool.query(
      'UPDATE store_staff SET can_manage_inventory = $1 WHERE id = $2 AND store_id = $3 RETURNING *',
      [can_manage_inventory === true, staffId, req.storeContext.store_id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Staff member not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Update permissions error:', err);
    res.status(500).json({ error: 'Failed to update permissions' });
  }
});

// ============================================================
// ADMIN
// ============================================================

// Local requireAdmin (matches the pattern in routes/products.js and
// routes/subscriptions.js — TODO consolidate into middleware/auth.js).
async function requireAdmin(req, res, next) {
  try {
    const result = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
    if (result.rows.length === 0 || result.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    next();
  } catch (err) {
    res.status(500).json({ error: 'Authorization failed' });
  }
}

router.put('/admin/stores/:id/sponsor', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  try {
    const storeId = parseInt(req.params.id);
    if (!Number.isInteger(storeId) || storeId <= 0) {
      return res.status(400).json({ error: 'Invalid store id' });
    }
    const tier = Number.isInteger(parseInt(req.body.tier)) ? parseInt(req.body.tier) : 1;
    // Validate expiresAt — accept ISO date strings only, reject garbage
    // that Postgres would otherwise reject with a 500 leaking detail.
    let expiresAt = null;
    if (req.body.expiresAt) {
      const parsed = new Date(req.body.expiresAt);
      if (isNaN(parsed.getTime())) {
        return res.status(400).json({ error: 'Invalid expiresAt' });
      }
      expiresAt = parsed.toISOString();
    }

    const result = await pool.query(
      `UPDATE stores
         SET is_sponsored = TRUE,
             sponsorship_tier = $1,
             sponsorship_expires_at = $2
       WHERE id = $3
       RETURNING id`,
      [tier, expiresAt, storeId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Store not found' });
    }

    res.json({ message: 'Store sponsorship updated' });
  } catch (err) {
    console.error('Sponsor error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

module.exports = router;