//routes/marketplace.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, optionalAuth, requireRealUser, genericIpRateLimit } = require('../middleware/auth');
const JWT_VERIFY_OPTS = { algorithms: ['HS256'] };
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { sanitizeString, getPagination, serverNow, assertMoneyLimit } = require('../middleware/helpers');
const jwt = require('jsonwebtoken');

// MARKETPLACE FEED
router.get('/marketplace/feed', async (req, res) => {
  try {
    const { page, limit, offset } = getPagination(req, 20, 100);

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.quantity > 0 AND p.is_online = TRUE`
    );
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(
      `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.images, p.created_at,
       p.currency, p.display_price, p.display_currency,
       s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.quantity > 0 AND p.is_online = TRUE
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
         SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.images, p.created_at,
                p.currency, p.display_price, p.display_currency,
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
         WHERE p.quantity > 0 AND p.is_online = TRUE
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
      `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.images, p.view_count,
      p.currency, p.display_price, p.display_currency,
      s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
      FROM products p
      JOIN stores s ON p.store_id = s.id
      WHERE p.quantity > 0 AND p.is_online = TRUE
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
router.get('/recommendations', authenticateToken, requireRealUser, async (req, res) => {
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
      SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.images,
      p.currency, p.display_price, p.display_currency,
      s.id as shop_id, s.name as shop_name, s.city, s.country
      FROM products p
      JOIN stores s ON p.store_id = s.id
      WHERE p.quantity > 0 AND p.is_online = TRUE
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
        `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.images,
        p.currency, p.display_price, p.display_currency,
        s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
        FROM products p
        JOIN stores s ON p.store_id = s.id
        WHERE p.quantity > 0 AND p.is_online = TRUE
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

// CONSUMER CHECKOUT — place an order as a logged-in buyer (not store POS)
router.post('/marketplace/checkout', authenticateToken, requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    const userId = req.user.userId;
    const items = req.body.items;
    const notes = sanitizeString(req.body.notes, 500);
    const paymentMethod = sanitizeString(req.body.payment_method, 20) || 'cash';

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'Cart is empty' });
    }

    const buyer = await pool.query(
      'SELECT full_name FROM users WHERE id = $1',
      [userId]
    );
    const buyerName = buyer.rows[0]?.full_name || 'Customer';

    await client.query('BEGIN');

    const storeIds = new Set();
    const validatedItems = [];

    for (const item of items) {
      const productId = parseInt(item.product_id);
      const quantity = parseInt(item.quantity);
      if (isNaN(productId) || isNaN(quantity) || quantity <= 0) {
        throw new Error('Invalid item in cart');
      }

      const product = await client.query(
        `SELECT p.id, p.name, p.price, p.quantity, p.store_id, p.currency,
                p.display_price, p.display_currency, s.name AS store_name
         FROM products p
         JOIN stores s ON s.id = p.store_id
         WHERE p.id = $1 AND p.is_online = TRUE AND COALESCE(s.is_active, TRUE) = TRUE
         FOR UPDATE`,
        [productId]
      );
      if (product.rows.length === 0) throw new Error('Product not available');
      const row = product.rows[0];
      if (row.quantity < quantity) {
        throw new Error(`Insufficient stock for "${row.name}"`);
      }

      storeIds.add(row.store_id);
      if (storeIds.size > 1) {
        throw new Error('Please order from one store at a time');
      }

      const unitPrice = parseFloat(row.price);
      const lineTotal = unitPrice * quantity;
      assertMoneyLimit(unitPrice, 'Product price');
      assertMoneyLimit(lineTotal, 'Line total');
      validatedItems.push({
        product_id: row.id,
        product_name: row.name,
        quantity,
        unit_price: unitPrice,
        total_price: lineTotal,
        currency: row.currency,
        display_price: row.display_price,
        display_currency: row.display_currency,
      });
    }

    const storeId = [...storeIds][0];
    const storeResult = await client.query(
      'SELECT id, name FROM stores WHERE id = $1',
      [storeId]
    );
    const store = storeResult.rows[0];

    const receiptNumber = `ST-${Date.now()}-${require('crypto').randomInt(1000, 9999)}`;
    const subtotal = validatedItems.reduce((sum, i) => sum + i.total_price, 0);
    assertMoneyLimit(subtotal, 'Order total');

    const orderResult = await client.query(
      `INSERT INTO orders (
         store_id, customer_user_id, customer_name, customer_phone,
         receipt_number, subtotal, total, status, payment_method, notes
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING *`,
      [
        storeId,
        userId,
        buyerName,
        null,
        receiptNumber,
        subtotal,
        subtotal,
        'pending',
        paymentMethod,
        notes || null,
      ]
    );
    const order = orderResult.rows[0];

    for (const item of validatedItems) {
      await client.query(
        `INSERT INTO order_items (
           order_id, product_id, product_name, quantity, unit_price, total_price,
           currency, display_price, display_currency
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [
          order.id,
          item.product_id,
          item.product_name,
          item.quantity,
          item.unit_price,
          item.total_price,
          item.currency,
          item.display_price,
          item.display_currency,
        ]
      );
      await client.query(
        'UPDATE products SET quantity = quantity - $1 WHERE id = $2',
        [item.quantity, item.product_id]
      );
    }

    await client.query('COMMIT');

    const itemsResult = await pool.query(
      `SELECT oi.*, p.image_url
       FROM order_items oi
       LEFT JOIN products p ON p.id = oi.product_id
       WHERE oi.order_id = $1`,
      [order.id]
    );

    res.status(201).json({
      order: { ...order, store_name: store.name },
      items: itemsResult.rows,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Marketplace checkout error:', err);
    res.status(400).json({ error: err.message || 'Checkout failed' });
  } finally {
    client.release();
  }
});

// SINGLE PRODUCT DETAIL (full images + store info)
router.get('/marketplace/products/:id', async (req, res) => {
  try {
    const productId = parseInt(req.params.id);
    if (isNaN(productId) || productId <= 0) {
      return res.status(400).json({ error: 'Invalid product ID' });
    }

    const result = await pool.query(
      `SELECT p.*,
              COALESCE(p.rating, 5.0) AS rating,
              COALESCE(p.review_count, 0) AS review_count,
              s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng,
              s.image_url as store_image_url, s.rating AS store_rating
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.id = $1 AND p.is_online = TRUE
         AND COALESCE(s.is_active, TRUE) = TRUE`,
      [productId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Product detail error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// TRACK PRODUCT VIEW
// Per-IP rate limit (300/hour). Far above any organic browsing rate;
// caps bot loops that inflate `view_count` to game the "trending" feed.
// Over-cap returns 429 — the Flutter telemetry path treats failures as
// no-ops so legitimate users see no UX change.
router.post(
  '/products/:id/view',
  genericIpRateLimit({ keyPrefix: 'view', max: 300, windowMs: 60 * 60 * 1000 }),
  async (req, res) => {
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
        const decoded = jwt.verify(token, process.env.JWT_SECRET, JWT_VERIFY_OPTS);
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
// Per-IP rate limit: search_queries feeds the recommendation engine and
// trending-keywords analytics. Without a cap, an attacker can flood it
// with crafted queries to poison both ("most-searched: <victim brand>").
router.post(
  '/search/track',
  genericIpRateLimit({ keyPrefix: 'search-track', max: 200, windowMs: 60 * 60 * 1000 }),
  async (req, res) => {
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
        const decoded = jwt.verify(token, process.env.JWT_SECRET, JWT_VERIFY_OPTS);
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