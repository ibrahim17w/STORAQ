//routes/analytics.js
const express = require('express');
const router = express.Router();
const { pool } = require('../config/database');
const {
  authenticateToken,
  attachStoreContext,
  requireStoreOwner,
  genericIpRateLimit,
  JWT_VERIFY_OPTS,
} = require('../middleware/auth');

// GET /api/analytics/dashboard?days=7
router.get('/analytics/dashboard', authenticateToken, attachStoreContext, requireStoreOwner, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;
    const days = Math.min(parseInt(req.query.days) || 7, 90);

    // Get user's preferred language for category translations
    const userLangResult = await pool.query(
      'SELECT preferred_language FROM users WHERE id = $1',
      [req.user.userId]
    );
    const lang = userLangResult.rows[0]?.preferred_language || 'en';

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const periodStart = new Date();
    periodStart.setDate(periodStart.getDate() - days);

    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);

    const result = await pool.query(`
      WITH today_orders AS (
        SELECT COALESCE(SUM(total), 0) as revenue, COUNT(*) as count
        FROM orders WHERE store_id = $1 AND created_at >= $2 AND status != 'cancelled'
      ),
      low_stock AS (
        SELECT COUNT(*) as count FROM products
        WHERE store_id = $1 AND quantity <= low_stock_threshold AND quantity >= 0
      ),
      outstanding_credits AS (
        SELECT COALESCE(SUM(amount), 0) as total FROM customer_credits
        WHERE store_id = $1 AND status = 'outstanding'
      ),
      store_visits_today AS (
        SELECT COUNT(*) as count FROM store_visits
        WHERE store_id = $1 AND visited_at >= $2
      ),
      product_views_today AS (
        SELECT COUNT(*) as count FROM product_views pv
        JOIN products p ON pv.product_id = p.id
        WHERE p.store_id = $1 AND pv.viewed_at >= $2
      ),
      store_visits_month AS (
        SELECT COUNT(*) as count FROM store_visits
        WHERE store_id = $1 AND visited_at >= $3
      ),
      product_views_month AS (
        SELECT COUNT(*) as count FROM product_views pv
        JOIN products p ON pv.product_id = p.id
        WHERE p.store_id = $1 AND pv.viewed_at >= $3
      ),
      revenue_series AS (
        SELECT DATE(created_at) as day, COALESCE(SUM(total), 0) as revenue, COUNT(*) as order_count
        FROM orders WHERE store_id = $1 AND created_at >= $4 AND status != 'cancelled'
        GROUP BY DATE(created_at) ORDER BY day
      ),
      category_sales AS (
        SELECT COALESCE(c.translations->>$5, c.name, '—') as category,
               SUM(oi.total_price) as total
        FROM order_items oi
        JOIN orders o ON oi.order_id = o.id
        LEFT JOIN products p ON oi.product_id = p.id
        LEFT JOIN categories c ON p.category_id = c.id
        WHERE o.store_id = $1 AND o.created_at >= $4 AND o.status != 'cancelled'
        GROUP BY COALESCE(c.translations->>$5, c.name, '—') ORDER BY total DESC
      ),
      top_products AS (
        SELECT COALESCE(oi.product_name, p.name, 'Unknown') as name,
               SUM(oi.total_price) as revenue
        FROM order_items oi
        JOIN orders o ON oi.order_id = o.id
        LEFT JOIN products p ON oi.product_id = p.id
        WHERE o.store_id = $1 AND o.created_at >= $4 AND o.status != 'cancelled'
        GROUP BY COALESCE(oi.product_name, p.name, 'Unknown')
        ORDER BY revenue DESC LIMIT 10
      ),
      expense_categories AS (
        SELECT category, COALESCE(SUM(amount), 0) as total
        FROM expenses WHERE store_id = $1 AND expense_date >= (CURRENT_DATE - INTERVAL '30 days')
        GROUP BY category ORDER BY total DESC
      ),
      monthly_summary AS (
        SELECT TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM') as month,
               COALESCE(SUM(total), 0) as revenue
        FROM orders WHERE store_id = $1 AND created_at >= (NOW() - INTERVAL '12 months') AND status != 'cancelled'
        GROUP BY DATE_TRUNC('month', created_at) ORDER BY month
      ),
      monthly_expenses AS (
        SELECT TO_CHAR(DATE_TRUNC('month', expense_date), 'YYYY-MM') as month,
               COALESCE(SUM(amount), 0) as expenses
        FROM expenses WHERE store_id = $1 AND expense_date >= (CURRENT_DATE - INTERVAL '12 months')
        GROUP BY DATE_TRUNC('month', expense_date) ORDER BY month
      )
      SELECT
        (SELECT row_to_json(today_orders.*) FROM today_orders) as today,
        (SELECT count FROM low_stock) as low_stock_count,
        (SELECT total FROM outstanding_credits) as outstanding_credits,
        (SELECT count FROM store_visits_today) as store_visits_today,
        (SELECT count FROM product_views_today) as product_views_today,
        (SELECT count FROM store_visits_month) as store_visits_month,
        (SELECT count FROM product_views_month) as product_views_month,
        (SELECT json_agg(revenue_series.*) FROM revenue_series) as revenue_series,
        (SELECT json_agg(category_sales.*) FROM category_sales) as category_sales,
        (SELECT json_agg(top_products.*) FROM top_products) as top_products,
        (SELECT json_agg(expense_categories.*) FROM expense_categories) as expense_categories,
        (SELECT json_agg(monthly_summary.*) FROM monthly_summary) as monthly_revenue,
        (SELECT json_agg(monthly_expenses.*) FROM monthly_expenses) as monthly_expenses
    `, [storeId, todayStart.toISOString(), monthStart.toISOString(), periodStart.toISOString(), lang]);

    const row = result.rows[0];
    const today = row.today || { revenue: 0, count: 0 };

    res.json({
      today_revenue: parseFloat(today.revenue) || 0,
      today_orders: parseInt(today.count) || 0,
      low_stock_count: parseInt(row.low_stock_count) || 0,
      outstanding_credits: parseFloat(row.outstanding_credits) || 0,
      store_visits_today: parseInt(row.store_visits_today) || 0,
      product_views_today: parseInt(row.product_views_today) || 0,
      store_visits_month: parseInt(row.store_visits_month) || 0,
      product_views_month: parseInt(row.product_views_month) || 0,
      revenue_series: row.revenue_series || [],
      category_sales: row.category_sales || [],
      top_products: row.top_products || [],
      expense_categories: row.expense_categories || [],
      monthly_revenue: row.monthly_revenue || [],
      monthly_expenses: row.monthly_expenses || [],
    });
  } catch (err) {
    console.error('Analytics dashboard error:', err);
    res.status(500).json({ error: 'Failed to load analytics' });
  }
});

// POST /api/stores/:id/visit — track store profile visit
// Per-IP rate limit caps counter-inflation abuse. 60/hour/IP is far above
// any organic user but blocks bot loops that would otherwise poison the
// store_visits table and skew "trending" / "popular store" rankings.
router.post(
  '/stores/:id/visit',
  genericIpRateLimit({ keyPrefix: 'visit', max: 60, windowMs: 60 * 60 * 1000 }),
  async (req, res) => {
    try {
      const storeId = parseInt(req.params.id);
      if (!storeId) return res.status(400).json({ error: 'Invalid store ID' });

      let userId = null;
      try {
        const jwt = require('jsonwebtoken');
        const authHeader = req.headers['authorization'];
        const token = authHeader && authHeader.split(' ')[1];
        if (token) {
          // Pin HS256 here too — without it the endpoint accepts any
          // algorithm including "none" and asymmetric-as-HMAC forgeries,
          // letting an attacker attribute visits to any victim user id.
          const decoded = jwt.verify(token, process.env.JWT_SECRET, JWT_VERIFY_OPTS);
          userId = decoded.id?.toString() || decoded.userId?.toString();
        }
      } catch (_) {}

      await pool.query(
        'INSERT INTO store_visits (store_id, user_id) VALUES ($1, $2)',
        [storeId, userId]
      );
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: 'Failed to track visit' });
    }
  }
);

module.exports = router;
