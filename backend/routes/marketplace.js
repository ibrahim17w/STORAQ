//routes/marketplace.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, optionalAuth, requireRealUser } = require('../middleware/auth');
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { sanitizeString, getPagination, serverNow } = require('../middleware/helpers');
const jwt = require('jsonwebtoken');

// MARKETPLACE FEED
router.get('/marketplace/feed', async (req, res) => {
  try {
    const { page, limit, offset } = getPagination(req, 20, 100);

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.quantity > 0`
    );
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(
      `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
       s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.quantity > 0
       ORDER BY p.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );

    res.json({
      data: result.rows,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) }
    });
  } catch (err) {
    console.error('Feed error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// NEARBY PRODUCTS
router.get('/marketplace/nearby', validateQuery(schemas.nearby), async (req, res) => {
  try {
    const { lat, lng, radius: radiusKm = 15 } = req.validatedQuery;
    const result = await pool.query(
      `SELECT * FROM (
         SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
                s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng,
                (6371 * acos(
                   GREATEST(LEAST(
                     cos(radians($1)) * cos(radians(s.lat)) *
                     cos(radians(s.lng) - radians($2)) +
                     sin(radians($1)) * sin(radians(s.lat))
                   , 1), -1)
                 )) AS distance_km
         FROM products p
         JOIN stores s ON p.store_id = s.id
         WHERE p.quantity > 0
           AND s.lat IS NOT NULL AND s.lng IS NOT NULL
       ) sub
       WHERE distance_km <= $3
       ORDER BY distance_km ASC
       LIMIT 50`,
      [lat, lng, radiusKm]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Nearby error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// GET TRENDING PRODUCTS
router.get('/products/trending', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.view_count,
      s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
      FROM products p
      JOIN stores s ON p.store_id = s.id
      WHERE p.quantity > 0
      ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
      LIMIT 20`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Trending error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// GET SPONSORED STORES
router.get('/stores/sponsored', async (req, res) => {
  try {
    const now = await serverNow();
    const result = await pool.query(
      `SELECT id, name, city, country, image_url, lat, lng, sponsorship_tier
      FROM stores
      WHERE is_sponsored = TRUE
      AND (sponsorship_expires_at IS NULL OR sponsorship_expires_at > $1)
      ORDER BY sponsorship_tier DESC, RANDOM()
      LIMIT 10`,
      [now]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Sponsored error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// GET PERSONALIZED RECOMMENDATIONS
router.get('/recommendations', requireRealUser, async (req, res) => {
  try {
    const userId = req.user.userId;
    const now = await serverNow();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const viewsResult = await pool.query(
      `SELECT DISTINCT p.name, p.store_id
      FROM product_views pv
      JOIN products p ON pv.product_id = p.id
      WHERE pv.user_id = $1 AND pv.viewed_at > $2
      LIMIT 20`,
      [userId, sevenDaysAgo]
    );

    const searchesResult = await pool.query(
      `SELECT DISTINCT query FROM search_queries
      WHERE user_id = $1 AND searched_at > $2
      LIMIT 10`,
      [userId, sevenDaysAgo]
    );

    let query = `
      SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
      s.id as shop_id, s.name as shop_name, s.city, s.country
      FROM products p
      JOIN stores s ON p.store_id = s.id
      WHERE p.quantity > 0
      `;

    const params = [];
    const conditions = [];

    if (viewsResult.rows.length > 0) {
      const storeIds = [...new Set(viewsResult.rows.map(r => r.store_id).filter(Boolean))];
      if (storeIds.length > 0) {
        params.push(...storeIds);
        conditions.push(`s.id IN (${storeIds.map((_, i) => '$' + (params.length - storeIds.length + i + 1)).join(',')})`);
      }
    }

    if (searchesResult.rows.length > 0) {
      const searchTerms = searchesResult.rows.map(r => r.query).filter(t => t && typeof t === 'string');
      for (const term of searchTerms) {
        const safeTerm = term.replace(/[%_\\]/g, '').substring(0, 50);
        if (safeTerm.length > 0) {
          params.push('%' + safeTerm + '%');
          conditions.push(`(p.name ILIKE $${params.length} OR p.description ILIKE $${params.length})`);
        }
      }
    }

    if (conditions.length > 0) {
      query += ' AND (' + conditions.join(' OR ') + ')';
    }

    query += ' ORDER BY p.created_at DESC LIMIT 20';

    const result = await pool.query(query, params);

    if (result.rows.length === 0) {
      const fallback = await pool.query(
        `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
        s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
        FROM products p
        JOIN stores s ON p.store_id = s.id
        WHERE p.quantity > 0
        ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
        LIMIT 20`
      );
      return res.json(fallback.rows);
    }

    res.json(result.rows);
  } catch (err) {
    console.error('Recommendations error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// TRACK PRODUCT VIEW
router.post('/products/:id/view', async (req, res) => {
  try {
    const productId = parseInt(req.params.id);
    if (isNaN(productId)) return res.status(400).json({ error: 'Invalid product ID' });

    await pool.query(
      'UPDATE products SET view_count = COALESCE(view_count, 0) + 1 WHERE id = $1',
      [productId]
    );

    const authHeader = req.headers['authorization'];
    if (authHeader) {
      const token = authHeader.split(' ')[1];
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        await pool.query(
          'INSERT INTO product_views (product_id, user_id, viewed_at) VALUES ($1, $2, NOW())',
          [productId, decoded.userId]
        );
      } catch (_) { }
    }

    res.json({ message: 'View tracked' });
  } catch (err) {
    console.error('Track view error:', err);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

// TRACK SEARCH QUERY
router.post('/search/track', async (req, res) => {
  try {
    const query = sanitizeString(req.body.query, 200);
    if (!query || query.length < 2) {
      return res.status(400).json({ error: 'Query too short' });
    }

    const authHeader = req.headers['authorization'];
    let userId = null;
    if (authHeader) {
      const token = authHeader.split(' ')[1];
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        userId = decoded.userId;
      } catch (_) { }
    }

    await pool.query(
      'INSERT INTO search_queries (query, user_id, searched_at) VALUES ($1, $2, NOW())',
      [query.toLowerCase(), userId]
    );

    res.json({ message: 'Search tracked' });
  } catch (err) {
    console.error('Track search error:', err);
    res.status(500).json({ error: 'Something went wrong' });
  }
});

module.exports = router;