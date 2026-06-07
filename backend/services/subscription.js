const crypto = require('crypto');
const { pool } = require('../config/database');
const {
  getPlatformPaymentRates,
  convertUsdToPaymentCurrencies,
} = require('./exchange_rates');

const FREE_ONLINE_SLOTS = 5;
const DAILY_CREATION_LIMIT = 50;

// ==================== ACTIVE-SUBSCRIPTION CACHE ====================
// Every authenticated mutation on a store (create product, toggle online,
// etc.) ends up calling getActiveSubscription -> getOnlineLimit. A signed-
// in shop owner mashing the UI generates dozens of these per minute, and
// each one was an indexed but full-row join lookup against
// store_subscriptions + subscription_tiers. Caching the result per store
// for 30s cuts those calls to near-zero for active users.
//
// Cache invalidation happens explicitly in the code paths that mutate
// subscription state: payment verify, promo redeem, expireStaleSubscriptions
// (when it actually flips a row to 'expired'). A 30s stale window is the
// outer bound — and even at the bound the only visible effect is that an
// owner whose plan just expired keeps their slot limit for ≤30 extra
// seconds. Postgres still enforces the truth when products are written.
const SUB_CACHE_MS = 30 * 1000;
const subscriptionCache = new Map();
function _invalidateActiveSubscription(storeId) {
  subscriptionCache.delete(storeId);
}
// Sweep stale entries every 5 min so the Map doesn't grow unbounded with
// stores that visit once and never come back. .unref() so the timer never
// keeps the process alive past SIGTERM.
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of subscriptionCache.entries()) {
    if (now - v.at > SUB_CACHE_MS * 4) subscriptionCache.delete(k);
  }
}, 5 * 60 * 1000).unref();

async function getActiveSubscription(storeId) {
  const cached = subscriptionCache.get(storeId);
  if (cached && Date.now() - cached.at < SUB_CACHE_MS) return cached.value;
  const result = await pool.query(
    `SELECT ss.*, st.name as tier_name, st.slug as tier_slug, st.online_slots, st.price_usd_monthly
     FROM store_subscriptions ss
     JOIN subscription_tiers st ON ss.tier_id = st.id
     WHERE ss.store_id = $1 AND ss.status = 'active' AND ss.expires_at > NOW()
     ORDER BY ss.expires_at DESC
     LIMIT 1`,
    [storeId]
  );
  const value = result.rows[0] || null;
  subscriptionCache.set(storeId, { value, at: Date.now() });
  return value;
}

async function expireStaleSubscriptions(storeId) {
  const expired = await pool.query(
    `UPDATE store_subscriptions
     SET status = 'expired', updated_at = NOW()
     WHERE store_id = $1 AND status = 'active' AND expires_at <= NOW()
     RETURNING id`,
    [storeId]
  );
  if (expired.rows.length > 0) {
    _invalidateActiveSubscription(storeId);
    await enforceFreeTierLimit(storeId);
  }
}

async function getOnlineLimit(storeId) {
  await expireStaleSubscriptions(storeId);
  const sub = await getActiveSubscription(storeId);
  return sub ? sub.online_slots : FREE_ONLINE_SLOTS;
}

async function getOnlineCount(storeId) {
  const result = await pool.query(
    'SELECT COUNT(*)::int as count FROM products WHERE store_id = $1 AND is_online = TRUE',
    [storeId]
  );
  return result.rows[0].count;
}

async function getDailyCreationCount(storeId) {
  const result = await pool.query(
    `SELECT COUNT(*)::int as count FROM products
     WHERE store_id = $1 AND created_at >= CURRENT_DATE`,
    [storeId]
  );
  return result.rows[0].count;
}

async function checkDailyCreationLimit(storeId) {
  const count = await getDailyCreationCount(storeId);
  if (count >= DAILY_CREATION_LIMIT) {
    const err = new Error('Daily product creation limit reached');
    err.code = 'daily_creation_limit_reached';
    err.limit = DAILY_CREATION_LIMIT;
    err.created_today = count;
    throw err;
  }
}

async function canAddOnlineProduct(storeId, excludeProductId = null) {
  const limit = await getOnlineLimit(storeId);
  let query = 'SELECT COUNT(*)::int as count FROM products WHERE store_id = $1 AND is_online = TRUE';
  const params = [storeId];
  if (excludeProductId) {
    query += ' AND id != $2';
    params.push(excludeProductId);
  }
  const result = await pool.query(query, params);
  return result.rows[0].count < limit;
}

// Serialize per-store mutations of the online-slot count.
// Two concurrent product creates / online-toggles for the same store would
// otherwise both observe `count < limit` and both write `is_online = TRUE`,
// silently exceeding the subscription cap. `pg_advisory_xact_lock` queues
// callers that target the same store, while leaving everything else
// concurrent. The lock auto-releases on COMMIT / ROLLBACK, so even if `fn`
// throws we never leak it.
//
// Namespace key 7842 is arbitrary — picked so this lock space cannot clash
// with future advisory locks added elsewhere in the codebase.
const ONLINE_SLOT_LOCK_NAMESPACE = 7842;
async function withStoreLock(storeId, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      'SELECT pg_advisory_xact_lock($1::int, $2::int)',
      [ONLINE_SLOT_LOCK_NAMESPACE, storeId]
    );
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function getSubscriptionStatus(storeId) {
  await expireStaleSubscriptions(storeId);
  const sub = await getActiveSubscription(storeId);
  const onlineCount = await getOnlineCount(storeId);
  const onlineLimit = sub ? sub.online_slots : FREE_ONLINE_SLOTS;
  const createdToday = await getDailyCreationCount(storeId);

  const tierRows = await _getTiersCached();
  const paymentRates = await getPlatformPaymentRates();
  const tiers = await enrichTiersWithPaymentPrices(tierRows, paymentRates);

  return {
    online_count: onlineCount,
    online_limit: onlineLimit,
    free_slots: FREE_ONLINE_SLOTS,
    daily_creation_limit: DAILY_CREATION_LIMIT,
    created_today: createdToday,
    tier: sub ? {
      id: sub.tier_id,
      name: sub.tier_name,
      slug: sub.tier_slug,
      online_slots: sub.online_slots,
      expires_at: sub.expires_at,
    } : null,
    is_subscribed: !!sub,
    tiers,
    payment_rates: paymentRates,
  };
}

async function enforceFreeTierLimit(storeId) {
  const limit = FREE_ONLINE_SLOTS;
  await pool.query(
    `UPDATE products SET is_online = FALSE, updated_at = NOW()
     WHERE store_id = $1 AND is_online = TRUE
     AND id NOT IN (
       SELECT id FROM products
       WHERE store_id = $1 AND is_online = TRUE
       ORDER BY COALESCE(went_online_at, created_at) ASC
       LIMIT $2
     )`,
    [storeId, limit]
  );
}

async function expirePromoRedemptions() {
  try {
    const expired = await pool.query(
      `UPDATE promo_redemptions SET status = 'expired'
       WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= NOW()
       RETURNING store_id`
    );
    for (const row of expired.rows) {
      await expireStaleSubscriptions(row.store_id);
    }
    if (expired.rows.length > 0) {
      console.log(`[promo] Auto-expired ${expired.rows.length} promo redemption(s), enforced free tier limits`);
    }
  } catch (err) {
    console.error('[promo] Expire check error:', err.message);
  }
}

// Run expiry check every 30 minutes
setInterval(expirePromoRedemptions, 30 * 60 * 1000);
// Also run on first load (after 5s to let DB init)
setTimeout(expirePromoRedemptions, 5000);

// Reference codes prove which manual payment belongs to which store, so a
// predictable code lets an attacker guess a victim's pending code and have
// their own deposit retroactively credited to the victim. `Math.random()` is
// a Mulberry32-class PRNG seeded from the V8 startup state — easy to guess
// after observing a few outputs. Use crypto.randomBytes for unguessable codes.
function generateReferenceCode(storeId) {
  const rand = crypto.randomBytes(6).toString('base64')
    .replace(/[+/=]/g, '')
    .substring(0, 8)
    .toUpperCase();
  return `MB-${storeId}-${rand}`;
}

async function enrichTiersWithPaymentPrices(tiers, paymentRates) {
  const rates = paymentRates || (await getPlatformPaymentRates());
  return tiers.map((tier) => {
    const usd = parseFloat(tier.price_usd_monthly) || 0;
    return {
      ...tier,
      price_usd_monthly: usd,
      payment_prices: convertUsdToPaymentCurrencies(usd, rates),
    };
  });
}

// ==================== TIERS CACHE ====================
// subscription_tiers is admin-editable but in practice changes every few
// weeks at most, while it's read on every /subscription/status request
// and during every product creation. 5-minute TTL is conservative; admin
// pricing edits can call invalidateTiersCache() to make changes visible
// immediately.
const TIERS_CACHE_MS = 5 * 60 * 1000;
let _tiersCache = null;
let _tiersCacheAt = 0;
async function _getTiersCached() {
  if (_tiersCache && Date.now() - _tiersCacheAt < TIERS_CACHE_MS) {
    return _tiersCache;
  }
  const result = await pool.query(
    `SELECT id, name, slug, online_slots, price_usd_monthly, sort_order
     FROM subscription_tiers
     WHERE slug != 'free'
     ORDER BY sort_order ASC`
  );
  _tiersCache = result.rows;
  _tiersCacheAt = Date.now();
  return _tiersCache;
}
function invalidateTiersCache() {
  _tiersCache = null;
  _tiersCacheAt = 0;
}

async function getTiers() {
  const rows = await _getTiersCached();
  return enrichTiersWithPaymentPrices(rows);
}

// Public invalidator — call after admin verifies a payment, promo is
// redeemed, or subscription is otherwise mutated so the next read sees
// fresh data instead of waiting up to SUB_CACHE_MS.
function invalidateActiveSubscription(storeId) {
  _invalidateActiveSubscription(storeId);
}

module.exports = {
  FREE_ONLINE_SLOTS,
  DAILY_CREATION_LIMIT,
  getActiveSubscription,
  expireStaleSubscriptions,
  getOnlineLimit,
  getOnlineCount,
  getDailyCreationCount,
  checkDailyCreationLimit,
  canAddOnlineProduct,
  withStoreLock,
  getSubscriptionStatus,
  enforceFreeTierLimit,
  generateReferenceCode,
  getTiers,
  enrichTiersWithPaymentPrices,
  invalidateTiersCache,
  invalidateActiveSubscription,
};
