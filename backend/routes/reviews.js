const express = require('express');
const { pool } = require('../config/database');
const { authenticateToken, requireRealUser, optionalAuth } = require('../middleware/auth');
const { validate, schemas } = require('../middleware/validation');

const router = express.Router();

async function recalcStoreRating(storeId, client = pool) {
  await client.query(
    `UPDATE stores
     SET rating = COALESCE((
       SELECT ROUND(AVG(rating)::numeric, 1)
       FROM store_reviews
       WHERE store_id = $1 AND status = 'active'
     ), 5.0)
     WHERE id = $1`,
    [storeId]
  );
}

async function recalcProductRating(productId, client = pool) {
  const stats = await client.query(
    `SELECT COUNT(*)::int AS total,
            COALESCE(ROUND(AVG(rating)::numeric, 1), 5.0) AS avg_rating
     FROM product_reviews
     WHERE product_id = $1 AND status = 'active'`,
    [productId]
  );
  const row = stats.rows[0] || { total: 0, avg_rating: 5.0 };
  await client.query(
    `UPDATE products
     SET rating = $2, review_count = $3
     WHERE id = $1`,
    [productId, row.avg_rating, row.total]
  );
}

async function userAffiliatedWithStore(userId, storeId) {
  const result = await pool.query(
    `SELECT 1
     FROM stores s
     WHERE s.id = $2 AND (
       s.owner_id = $1
       OR EXISTS (
         SELECT 1 FROM store_staff ss
         WHERE ss.store_id = s.id AND ss.user_id = $1 AND ss.status = 'accepted'
       )
     )
     LIMIT 1`,
    [userId, storeId]
  );
  return result.rows.length > 0;
}

// ─── Store reviews ───────────────────────────────────────────────────────────

router.get('/stores/:id/reviews', optionalAuth, async (req, res) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!Number.isFinite(storeId)) {
      return res.status(400).json({ error: 'Invalid store id' });
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 50);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    const storeCheck = await pool.query(
      'SELECT id, rating, owner_id FROM stores WHERE id = $1 AND is_active IS NOT FALSE',
      [storeId]
    );
    if (storeCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Store not found' });
    }

    const countResult = await pool.query(
      `SELECT COUNT(*)::int AS total
       FROM store_reviews
       WHERE store_id = $1 AND status = 'active'`,
      [storeId]
    );

    const reviewsResult = await pool.query(
      `SELECT r.id, r.store_id, r.user_id, r.rating, r.comment, r.created_at, r.updated_at,
              u.full_name AS user_name
       FROM store_reviews r
       JOIN users u ON u.id = r.user_id
       WHERE r.store_id = $1 AND r.status = 'active'
       ORDER BY r.created_at DESC
       LIMIT $2 OFFSET $3`,
      [storeId, limit, offset]
    );

    let myReview = null;
    let canRequestRemoval = false;
    if (req.user?.userId) {
      const mine = await pool.query(
        `SELECT id, store_id, user_id, rating, comment, created_at, updated_at, status
         FROM store_reviews
         WHERE store_id = $1 AND user_id = $2`,
        [storeId, req.user.userId]
      );
      if (mine.rows.length > 0 && mine.rows[0].status === 'active') {
        myReview = mine.rows[0];
      }
      canRequestRemoval = storeCheck.rows[0].owner_id === req.user.userId;
    }

    res.json({
      store_id: storeId,
      rating: parseFloat(storeCheck.rows[0].rating) || 5.0,
      total: countResult.rows[0]?.total || 0,
      reviews: reviewsResult.rows,
      my_review: myReview,
      can_request_removal: canRequestRemoval,
    });
  } catch (err) {
    console.error('List store reviews error:', err);
    res.status(500).json({ error: 'Failed to load reviews' });
  }
});

router.post(
  '/stores/:id/reviews',
  authenticateToken,
  requireRealUser,
  validate(schemas.storeReview),
  async (req, res) => {
    try {
      const storeId = parseInt(req.params.id, 10);
      const { rating, comment } = req.body;

      const storeResult = await pool.query(
        'SELECT id, owner_id FROM stores WHERE id = $1 AND is_active IS NOT FALSE',
        [storeId]
      );
      if (storeResult.rows.length === 0) {
        return res.status(404).json({ error: 'Store not found' });
      }
      if (await userAffiliatedWithStore(req.user.userId, storeId)) {
        return res.status(403).json({ error: 'Store team members cannot review their own store' });
      }

      const existing = await pool.query(
        'SELECT id, status FROM store_reviews WHERE store_id = $1 AND user_id = $2',
        [storeId, req.user.userId]
      );

      let review;
      if (existing.rows.length > 0) {
        if (existing.rows[0].status === 'active') {
          return res.status(409).json({ error: 'You already reviewed this store' });
        }
        const updated = await pool.query(
          `UPDATE store_reviews
           SET rating = $3, comment = $4, status = 'active',
               removed_at = NULL, removed_by_admin_id = NULL, removal_reason = NULL,
               updated_at = NOW()
           WHERE store_id = $1 AND user_id = $2
           RETURNING *`,
          [storeId, req.user.userId, rating, comment || null]
        );
        review = updated.rows[0];
      } else {
        const inserted = await pool.query(
          `INSERT INTO store_reviews (store_id, user_id, rating, comment)
           VALUES ($1, $2, $3, $4)
           RETURNING *`,
          [storeId, req.user.userId, rating, comment || null]
        );
        review = inserted.rows[0];
      }

      await recalcStoreRating(storeId);
      res.status(201).json(review);
    } catch (err) {
      console.error('Create store review error:', err);
      res.status(500).json({ error: 'Failed to submit review' });
    }
  }
);

// ─── Product reviews ─────────────────────────────────────────────────────────

router.get('/products/:id/reviews', optionalAuth, async (req, res) => {
  try {
    const productId = parseInt(req.params.id, 10);
    if (!Number.isFinite(productId)) {
      return res.status(400).json({ error: 'Invalid product id' });
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 50);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

    const productCheck = await pool.query(
      `SELECT p.id, p.rating, p.review_count, p.store_id, p.name
       FROM products p
       JOIN stores s ON s.id = p.store_id
       WHERE p.id = $1 AND COALESCE(s.is_active, TRUE) = TRUE`,
      [productId]
    );
    if (productCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    const product = productCheck.rows[0];

    const countResult = await pool.query(
      `SELECT COUNT(*)::int AS total
       FROM product_reviews
       WHERE product_id = $1 AND status = 'active'`,
      [productId]
    );

    const reviewsResult = await pool.query(
      `SELECT r.id, r.product_id, r.user_id, r.rating, r.comment, r.created_at, r.updated_at,
              u.full_name AS user_name
       FROM product_reviews r
       JOIN users u ON u.id = r.user_id
       WHERE r.product_id = $1 AND r.status = 'active'
       ORDER BY r.created_at DESC
       LIMIT $2 OFFSET $3`,
      [productId, limit, offset]
    );

    let myReview = null;
    let canRequestRemoval = false;
    if (req.user?.userId) {
      const mine = await pool.query(
        `SELECT id, product_id, user_id, rating, comment, created_at, updated_at, status
         FROM product_reviews
         WHERE product_id = $1 AND user_id = $2`,
        [productId, req.user.userId]
      );
      if (mine.rows.length > 0 && mine.rows[0].status === 'active') {
        myReview = mine.rows[0];
      }
      canRequestRemoval = await userAffiliatedWithStore(req.user.userId, product.store_id);
    }

    res.json({
      product_id: productId,
      product_name: product.name,
      rating: parseFloat(product.rating) || 5.0,
      total: countResult.rows[0]?.total || product.review_count || 0,
      reviews: reviewsResult.rows,
      my_review: myReview,
      can_request_removal: canRequestRemoval,
    });
  } catch (err) {
    console.error('List product reviews error:', err);
    res.status(500).json({ error: 'Failed to load reviews' });
  }
});

router.post(
  '/products/:id/reviews',
  authenticateToken,
  requireRealUser,
  validate(schemas.storeReview),
  async (req, res) => {
    try {
      const productId = parseInt(req.params.id, 10);
      const { rating, comment } = req.body;

      const productResult = await pool.query(
        `SELECT p.id, p.store_id
         FROM products p
         JOIN stores s ON s.id = p.store_id
         WHERE p.id = $1 AND COALESCE(s.is_active, TRUE) = TRUE`,
        [productId]
      );
      if (productResult.rows.length === 0) {
        return res.status(404).json({ error: 'Product not found' });
      }
      const storeId = productResult.rows[0].store_id;
      if (await userAffiliatedWithStore(req.user.userId, storeId)) {
        return res.status(403).json({ error: 'Store team members cannot review their own products' });
      }

      const existing = await pool.query(
        'SELECT id, status FROM product_reviews WHERE product_id = $1 AND user_id = $2',
        [productId, req.user.userId]
      );

      let review;
      if (existing.rows.length > 0) {
        if (existing.rows[0].status === 'active') {
          return res.status(409).json({ error: 'You already reviewed this product' });
        }
        const updated = await pool.query(
          `UPDATE product_reviews
           SET rating = $3, comment = $4, status = 'active',
               removed_at = NULL, removed_by_admin_id = NULL, removal_reason = NULL,
               updated_at = NOW()
           WHERE product_id = $1 AND user_id = $2
           RETURNING *`,
          [productId, req.user.userId, rating, comment || null]
        );
        review = updated.rows[0];
      } else {
        const inserted = await pool.query(
          `INSERT INTO product_reviews (product_id, user_id, rating, comment)
           VALUES ($1, $2, $3, $4)
           RETURNING *`,
          [productId, req.user.userId, rating, comment || null]
        );
        review = inserted.rows[0];
      }

      await recalcProductRating(productId);
      res.status(201).json(review);
    } catch (err) {
      console.error('Create product review error:', err);
      res.status(500).json({ error: 'Failed to submit review' });
    }
  }
);

module.exports = router;
