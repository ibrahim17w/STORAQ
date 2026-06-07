const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, requireStoreAccess, requireInventoryAccess } = require('../middleware/auth');
const { schemas, validate } = require('../middleware/validation');
const {
  getSubscriptionStatus,
  getTiers,
  generateReferenceCode,
  canAddOnlineProduct,
  withStoreLock,
  getOnlineLimit,
  getOnlineCount,
  enrichTiersWithPaymentPrices,
  invalidateActiveSubscription,
} = require('../services/subscription');

// GET subscription status for current store
router.get('/my-store/subscription', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const status = await getSubscriptionStatus(req.storeContext.store_id);
    res.json(status);
  } catch (err) {
    console.error('Subscription status error:', err);
    res.status(500).json({ error: 'Failed to load subscription status' });
  }
});

// GET all purchasable tiers
router.get('/subscription/tiers', async (req, res) => {
  try {
    const tiers = await getTiers();
    res.json(tiers);
  } catch (err) {
    console.error('Tiers error:', err);
    res.status(500).json({ error: 'Failed to load tiers' });
  }
});

// Request subscription payment
router.post('/my-store/subscription/request', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, validate(schemas.subscriptionRequest), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;
    const { tier_id, payment_track } = req.validatedBody;

    const tierResult = await pool.query(
      `SELECT * FROM subscription_tiers WHERE id = $1 AND slug != 'free'`,
      [tier_id]
    );
    if (tierResult.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid subscription tier' });
    }
    const [tier] = await enrichTiersWithPaymentPrices(tierResult.rows);

    if (payment_track === 'syria_agent') {
      const referenceCode = generateReferenceCode(storeId);
      const result = await pool.query(
        `INSERT INTO subscription_payments (store_id, tier_id, payment_track, reference_code, amount_usd, status)
         VALUES ($1, $2, 'syria_agent', $3, $4, 'pending') RETURNING *`,
        [storeId, tier.id, referenceCode, tier.price_usd_monthly]
      );
      return res.status(201).json({
        payment: result.rows[0],
        tier,
        instructions: 'Pay cash to an authorized agent and provide this reference code.',
      });
    }

    if (payment_track === 'stripe') {
      const result = await pool.query(
        `INSERT INTO subscription_payments (store_id, tier_id, payment_track, amount_usd, status, stripe_session_id)
         VALUES ($1, $2, 'stripe', $3, 'pending', $4) RETURNING *`,
        [storeId, tier.id, tier.price_usd_monthly, `stripe_placeholder_${Date.now()}`]
      );
      return res.status(201).json({
        payment: result.rows[0],
        tier,
        stripe_url: null,
        message: 'Stripe integration coming soon. Payment recorded as placeholder.',
      });
    }

    return res.status(400).json({ error: 'Invalid payment track' });
  } catch (err) {
    console.error('Subscription request error:', err);
    res.status(500).json({ error: 'Failed to create subscription request' });
  }
});

// GET full store catalog (online + offline) for owner/worker
router.get('/my-store/products', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM products WHERE store_id = $1 ORDER BY created_at DESC',
      [req.storeContext.store_id]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('My store products error:', err);
    res.status(500).json({ error: 'Failed to load products' });
  }
});

// GET products with online status for management screen
router.get('/my-store/products/online-status', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;
    const status = await getSubscriptionStatus(storeId);
    const products = await pool.query(
      `SELECT p.id, p.name, p.price, p.quantity, p.image_url, p.is_online, p.went_online_at, p.created_at,
              c.id AS sponsorship_id,
              c.scope_type AS sponsorship_scope,
              c.expires_at AS sponsorship_expires_at,
              c.radius_km AS sponsorship_radius_km,
              c.target_country AS sponsorship_target_country,
              c.target_city AS sponsorship_target_city,
              c.target_village AS sponsorship_target_village
       FROM products p
       LEFT JOIN LATERAL (
         SELECT id, scope_type, expires_at, radius_km,
                target_country, target_city, target_village
         FROM sponsored_product_campaigns
         WHERE product_id = p.id
           AND status = 'active'
           AND expires_at > NOW()
         ORDER BY expires_at DESC
         LIMIT 1
       ) c ON TRUE
       WHERE p.store_id = $1
       ORDER BY p.is_online DESC, p.name ASC`,
      [storeId]
    );
    const rows = products.rows.map((row) => ({
      ...row,
      is_sponsored: row.sponsorship_id != null,
    }));
    res.json({ ...status, products: rows });
  } catch (err) {
    console.error('Online status error:', err);
    res.status(500).json({ error: 'Failed to load products' });
  }
});

// Toggle single product online/offline
router.put('/my-store/products/:id/online', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, validate(schemas.setProductOnline), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;
    const productId = parseInt(req.params.id);
    const { is_online } = req.validatedBody;

    const product = await pool.query(
      'SELECT * FROM products WHERE id = $1 AND store_id = $2',
      [productId, storeId]
    );
    if (product.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Switching a product from offline -> online consumes a slot.
    // Serialize the slot check + UPDATE under a per-store advisory lock so
    // two concurrent toggles cannot both grab the last available slot.
    if (is_online && !product.rows[0].is_online) {
      const lockResult = await withStoreLock(storeId, async (lockClient) => {
        const allowed = await canAddOnlineProduct(storeId);
        if (!allowed) return { denied: true };
        const upd = await lockClient.query(
          `UPDATE products SET is_online = TRUE, went_online_at = COALESCE(went_online_at, NOW()), updated_at = NOW()
           WHERE id = $1 AND store_id = $2 RETURNING *`,
          [productId, storeId]
        );
        return { denied: false, row: upd.rows[0] };
      });
      if (lockResult.denied) {
        const status = await getSubscriptionStatus(storeId);
        return res.status(403).json({
          error: 'online_slot_limit_reached',
          message: 'You have reached your online product limit. Upgrade to list more products on the marketplace.',
          online_count: status.online_count,
          online_limit: status.online_limit,
          tiers: status.tiers,
        });
      }
      return res.json(lockResult.row);
    }

    // offline -> offline OR online -> offline: no slot pressure, plain UPDATE.
    const result = await pool.query(
      `UPDATE products SET is_online = $1, went_online_at = CASE WHEN $1 THEN COALESCE(went_online_at, NOW()) ELSE NULL END, updated_at = NOW()
       WHERE id = $2 AND store_id = $3 RETURNING *`,
      [is_online, productId, storeId]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Set online error:', err);
    res.status(500).json({ error: 'Failed to update product' });
  }
});

// Bulk set which products are online
router.put('/my-store/products/online/bulk', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, validate(schemas.bulkSetOnline), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;
    const { online_product_ids } = req.validatedBody;
    const limit = await getOnlineLimit(storeId);

    if (online_product_ids.length > limit) {
      const status = await getSubscriptionStatus(storeId);
      return res.status(403).json({
        error: 'online_slot_limit_reached',
        message: `You can only have ${limit} products online. Selected ${online_product_ids.length}.`,
        online_count: online_product_ids.length,
        online_limit: limit,
        tiers: status.tiers,
      });
    }

    const owned = await pool.query(
      'SELECT id FROM products WHERE store_id = $1',
      [storeId]
    );
    const ownedIds = new Set(owned.rows.map(r => r.id));
    for (const id of online_product_ids) {
      if (!ownedIds.has(id)) {
        return res.status(400).json({ error: `Product ${id} not found in your store` });
      }
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        'UPDATE products SET is_online = FALSE, went_online_at = NULL, updated_at = NOW() WHERE store_id = $1',
        [storeId]
      );
      if (online_product_ids.length > 0) {
        await client.query(
          `UPDATE products SET is_online = TRUE, went_online_at = COALESCE(went_online_at, NOW()), updated_at = NOW()
           WHERE store_id = $1 AND id = ANY($2::int[])`,
          [storeId, online_product_ids]
        );
      }
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }

    const onlineCount = await getOnlineCount(storeId);
    res.json({ online_count: onlineCount, online_limit: limit, online_product_ids });
  } catch (err) {
    console.error('Bulk online error:', err);
    res.status(500).json({ error: 'Failed to update products' });
  }
});

// ==================== ADMIN ====================

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

router.get('/admin/subscription/payments', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  try {
    const status = req.query.status || 'pending';
    const result = await pool.query(
      `SELECT sp.*, st.name as tier_name, st.online_slots, s.name as store_name, u.full_name as owner_name, u.email as owner_email
       FROM subscription_payments sp
       JOIN subscription_tiers st ON sp.tier_id = st.id
       JOIN stores s ON sp.store_id = s.id
       JOIN users u ON s.owner_id = u.id
       WHERE sp.status = $1
       ORDER BY sp.created_at DESC
       LIMIT 100`,
      [status]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Admin payments error:', err);
    res.status(500).json({ error: 'Failed to load payments' });
  }
});

router.put('/admin/subscription/payments/:id/verify', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  const client = await pool.connect();
  let inTx = false;
  try {
    const paymentId = parseInt(req.params.id);
    if (!Number.isInteger(paymentId) || paymentId <= 0) {
      return res.status(400).json({ error: 'Invalid payment id' });
    }

    await client.query('BEGIN');
    inTx = true;

    // Atomic claim — same race-fix as the admin-dashboard mirror endpoint.
    // The old SELECT-then-UPDATE let a double-click provision two parallel
    // 30-day subscriptions for one bank deposit.
    const claim = await client.query(
      `UPDATE subscription_payments
         SET status = 'verified', verified_by = $1, verified_at = NOW()
       WHERE id = $2 AND status = 'pending'
       RETURNING *`,
      [req.user.userId, paymentId]
    );
    if (claim.rows.length === 0) {
      await client.query('ROLLBACK');
      inTx = false;
      return res.status(409).json({ error: 'Payment is not pending (already verified or rejected)' });
    }
    const p = claim.rows[0];

    await client.query(
      `UPDATE store_subscriptions SET status = 'expired', updated_at = NOW()
       WHERE store_id = $1 AND status = 'active'`,
      [p.store_id]
    );

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await client.query(
      `INSERT INTO store_subscriptions (store_id, tier_id, status, starts_at, expires_at)
       VALUES ($1, $2, 'active', NOW(), $3)`,
      [p.store_id, p.tier_id, expiresAt]
    );

    await client.query('COMMIT');
    inTx = false;
    // Bust the per-store active-subscription cache so the owner's next
    // /subscription/status call returns the freshly-activated tier instead
    // of the cached pre-payment state.
    invalidateActiveSubscription(p.store_id);

    res.json({ message: 'Payment verified and subscription activated for 30 days' });
  } catch (err) {
    if (inTx) { try { await client.query('ROLLBACK'); } catch (_) {} }
    console.error('Verify payment error:', err);
    res.status(500).json({ error: 'Failed to verify payment' });
  } finally {
    client.release();
  }
});

// ─── PROMO CODE REDEMPTION ──────────────────────────────────────────────────
router.post('/my-store/redeem-promo', authenticateToken, requireRealUser, attachStoreContext, requireStoreOwner, async (req, res) => {
  const client = await pool.connect();
  try {
    const storeId = req.storeContext.store_id;
    const userId = req.user.userId;
    const { code } = req.body;

    if (!code || !code.trim()) return res.status(400).json({ error: 'Promo code is required' });

    const normalizedCode = code.trim().toUpperCase();

    // 1. Find the promo code
    const promoResult = await client.query(
      `SELECT * FROM promo_codes WHERE code = $1`,
      [normalizedCode]
    );
    if (promoResult.rows.length === 0) return res.status(404).json({ error: 'Invalid promo code' });
    const promo = promoResult.rows[0];

    // 2. Check promo is active
    if (!promo.is_active) return res.status(400).json({ error: 'This promo code is no longer active' });

    // 3. Check expiry
    if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
      return res.status(400).json({ error: 'This promo code has expired' });
    }

    // 4. Check max redemptions
    if (promo.max_redemptions && promo.times_used >= promo.max_redemptions) {
      return res.status(400).json({ error: 'This promo code has reached its maximum number of uses' });
    }

    // 5. Check if this store already redeemed this code
    const existing = await client.query(
      `SELECT id FROM promo_redemptions WHERE promo_id = $1 AND store_id = $2`,
      [promo.id, storeId]
    );
    if (existing.rows.length > 0) {
      return res.status(400).json({ error: 'You have already used this promo code' });
    }

    // 6. Eligibility checks
    const userResult = await client.query(
      `SELECT email_verified, created_at FROM users WHERE id = $1`, [userId]
    );
    const user = userResult.rows[0];

    if (!user.email_verified) {
      return res.status(403).json({ error: 'You must verify your email before using promo codes' });
    }

    const accountAgeDays =
      (Date.now() - new Date(user.created_at).getTime()) / (1000 * 60 * 60 * 24);

    const minAccountAgeDays = promo.min_account_age_days != null
      ? parseInt(promo.min_account_age_days)
      : null;
    if (minAccountAgeDays != null && minAccountAgeDays > 0) {
      if (accountAgeDays < minAccountAgeDays) {
        const daysLeft = Math.ceil(minAccountAgeDays - accountAgeDays);
        return res.status(403).json({
          error: `Your account must be at least ${minAccountAgeDays} days old to use this code (${daysLeft} day${daysLeft === 1 ? '' : 's'} remaining)`,
        });
      }
    }

    const maxAccountAgeDays = promo.max_account_age_days != null
      ? parseInt(promo.max_account_age_days)
      : null;
    if (maxAccountAgeDays != null && maxAccountAgeDays > 0) {
      if (accountAgeDays > maxAccountAgeDays) {
        return res.status(403).json({
          error: `This promo is only for accounts created within the last ${maxAccountAgeDays} days`,
        });
      }
    }

    const storeResult = await client.query(
      `SELECT name, city, first_product_approved FROM stores WHERE id = $1`, [storeId]
    );
    const store = storeResult.rows[0];

    if (!store.name || !store.city) {
      return res.status(403).json({ error: 'Complete your store profile (name and city) before using promo codes' });
    }

    if (!store.first_product_approved) {
      return res.status(403).json({ error: 'Your first product must be approved by admin before using promo codes' });
    }

    // 7. Apply the promo
    await client.query('BEGIN');

    if (promo.type === 'tier_grant' && promo.tier_slug && promo.grant_days > 0) {
      // Find the tier
      const tierResult = await client.query(
        `SELECT id, online_slots FROM subscription_tiers WHERE slug = $1`, [promo.tier_slug]
      );
      if (tierResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(500).json({ error: 'Promo tier configuration error' });
      }
      const tier = tierResult.rows[0];

      // Expire current active subscriptions
      await client.query(
        `UPDATE store_subscriptions SET status = 'expired', updated_at = NOW()
         WHERE store_id = $1 AND status = 'active'`, [storeId]
      );

      // Create new subscription
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + promo.grant_days);

      await client.query(
        `INSERT INTO store_subscriptions (store_id, tier_id, status, starts_at, expires_at)
         VALUES ($1, $2, 'active', NOW(), $3)`,
        [storeId, tier.id, expiresAt]
      );

      // Record redemption
      await client.query(
        `INSERT INTO promo_redemptions (promo_id, store_id, user_id, tier_id, expires_at, status)
         VALUES ($1, $2, $3, $4, $5, 'active')`,
        [promo.id, storeId, userId, tier.id, expiresAt]
      );

      // Increment usage counter
      await client.query(
        `UPDATE promo_codes SET times_used = times_used + 1, updated_at = NOW() WHERE id = $1`, [promo.id]
      );

      await client.query('COMMIT');
      // Bust the cache — owner just got a new tier; their next product
      // create/toggle should see the new online_slots limit.
      invalidateActiveSubscription(storeId);

      return res.json({
        message: `Promo applied! You now have ${promo.tier_slug.charAt(0).toUpperCase() + promo.tier_slug.slice(1)} tier (${tier.online_slots} online slots) free for ${promo.grant_days} days.`,
        tier: promo.tier_slug,
        online_slots: tier.online_slots,
        expires_at: expiresAt,
      });
    }

    // Regular discount promo (just record it, no subscription change)
    await client.query(
      `INSERT INTO promo_redemptions (promo_id, store_id, user_id, status)
       VALUES ($1, $2, $3, 'active')`,
      [promo.id, storeId, userId]
    );
    await client.query(
      `UPDATE promo_codes SET times_used = times_used + 1, updated_at = NOW() WHERE id = $1`, [promo.id]
    );
    await client.query('COMMIT');

    res.json({ message: 'Promo code applied!', discount_percent: promo.discount_percent, discount_fixed: promo.discount_fixed });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Redeem promo error:', err);
    res.status(500).json({ error: 'Failed to redeem promo code' });
  } finally {
    client.release();
  }
});

module.exports = router;
