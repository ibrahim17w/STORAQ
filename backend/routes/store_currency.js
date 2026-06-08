//routes/store_currency.js
// Multi-currency display settings for stores.
// NOTE: This module only ADDS new functionality. It never modifies existing
// product/order/store core logic — it reads existing rows and writes only the
// new display_* / exchange_rates columns added by the migration.
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const {
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  requireStoreAccess,
  genericIpRateLimit,
} = require('../middleware/auth');
const {
  normCurrency,
  toNumber,
  preserveRate,
  roundConvertedPrice,
  fetchAutoRate,
  RATE_PROVIDERS,
} = require('../services/exchange_rates');
const { getEffectiveProductPrice } = require('../middleware/helpers');

// ============================================================
// HELPERS
// ============================================================

function parseRates(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw === 'string' && raw.trim().length > 0) {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

/**
 * Finds a conversion factor between two currencies using the provided rates.
 * Supports an exact (direct) rate and the inverse of an existing rate.
 * Returns null when no usable rate is available.
 */
function findDirectRate(rates, from, to) {
  const f = normCurrency(from).toLowerCase();
  const t = normCurrency(to).toLowerCase();
  if (!f || !t) return null;
  if (f === t) return 1;

  for (const r of rates) {
    const rf = normCurrency(r.from).toLowerCase();
    const rt = normCurrency(r.to).toLowerCase();
    const rate = toNumber(r.rate);
    if (rate == null || rate <= 0) continue;
    if (rf === f && rt === t) return rate;
  }
  // inverse
  for (const r of rates) {
    const rf = normCurrency(r.from).toLowerCase();
    const rt = normCurrency(r.to).toLowerCase();
    const rate = toNumber(r.rate);
    if (rate == null || rate <= 0) continue;
    if (rf === t && rt === f) return 1 / rate;
  }
  return null;
}

/**
 * Converts a price from one currency to another using direct rate first,
 * then a USD bridge (from -> USD -> to). Returns null when not convertible.
 */
function convertWithRates(price, from, to, rates) {
  const amount = toNumber(price);
  if (amount == null) return null;
  const direct = findDirectRate(rates, from, to);
  if (direct != null) return amount * direct;

  // USD bridge
  const fromToUsd = findDirectRate(rates, from, 'USD');
  const usdToTarget = findDirectRate(rates, 'USD', to);
  if (fromToUsd != null && usdToTarget != null) {
    return amount * fromToUsd * usdToTarget;
  }
  return null;
}

/**
 * Recalculates and persists display_price/display_currency for every product
 * in the store, based on the store's display currency and exchange rates.
 * Products that cannot be converted get NULL display values (UI falls back
 * to original price).
 */
async function recalculateProductDisplayPrices(storeId, displayCurrency, rates, client) {
  const db = client || pool;
  const target = normCurrency(displayCurrency);

  const productsResult = await db.query(
    'SELECT id, price, sale_price, currency FROM products WHERE store_id = $1',
    [storeId]
  );

  for (const product of productsResult.rows) {
    let displayPrice = null;
    let resolvedCurrency = null;
    const sellingPrice = getEffectiveProductPrice(product);

    if (target) {
      const originalCurrency = normCurrency(product.currency) || 'SYP';
      const converted = convertWithRates(sellingPrice, originalCurrency, target, rates);
      if (converted != null) {
        displayPrice = roundConvertedPrice(converted, target);
        resolvedCurrency = target;
      }
    }

    await db.query(
      'UPDATE products SET display_price = $1, display_currency = $2 WHERE id = $3',
      [displayPrice, resolvedCurrency, product.id]
    );
  }

  return productsResult.rows.length;
}

/**
 * Recalculates display_price/display_currency for a single product based on
 * its store's current currency settings. Safe to call after create/update.
 * Returns { display_price, display_currency } (values may be null).
 */
async function recalculateSingleProductDisplayPrice(productId, _storeId, client) {
  // Second argument (_storeId) is accepted for caller convenience but the
  // owning store is always resolved from the product row itself.
  const db = client || pool;
  const productResult = await db.query(
    'SELECT id, store_id, price, sale_price, currency FROM products WHERE id = $1',
    [productId]
  );
  if (productResult.rows.length === 0) {
    return { display_price: null, display_currency: null };
  }
  const product = productResult.rows[0];

  const storeResult = await db.query(
    'SELECT display_currency, exchange_rates FROM stores WHERE id = $1',
    [product.store_id]
  );
  const store = storeResult.rows[0] || {};
  const target = normCurrency(store.display_currency);
  const rates = parseRates(store.exchange_rates);

  let displayPrice = null;
  let resolvedCurrency = null;

  if (target) {
    const originalCurrency = normCurrency(product.currency) || 'SYP';
    const sellingPrice = getEffectiveProductPrice(product);
    const converted = convertWithRates(sellingPrice, originalCurrency, target, rates);
    if (converted != null) {
      displayPrice = roundConvertedPrice(converted, target);
      resolvedCurrency = target;
    }
  }

  await db.query(
    'UPDATE products SET display_price = $1, display_currency = $2 WHERE id = $3',
    [displayPrice, resolvedCurrency, product.id]
  );

  return { display_price: displayPrice, display_currency: resolvedCurrency };
}

// ============================================================
// ROUTES
// ============================================================

// GET current currency settings (owner or accepted worker can read)
router.get(
  '/my-store/currency-settings',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  async (req, res) => {
    try {
      const result = await pool.query(
        'SELECT display_currency, show_both_prices, exchange_rates FROM stores WHERE id = $1',
        [req.storeContext.store_id]
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'No store found' });
      }
      const row = result.rows[0];
      res.json({
        display_currency: row.display_currency || null,
        show_both_prices: row.show_both_prices === true,
        exchange_rates: parseRates(row.exchange_rates),
        providers: RATE_PROVIDERS,
      });
    } catch (err) {
      console.error('Get currency settings error:', err);
      res.status(500).json({ error: 'Failed to load currency settings' });
    }
  }
);

// PUT update currency settings then recalc all product display prices (owner only)
router.put(
  '/my-store/currency-settings',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  async (req, res) => {
    const client = await pool.connect();
    try {
      const storeId = req.storeContext.store_id;
      const displayCurrency = req.body.display_currency != null
        ? normCurrency(req.body.display_currency).substring(0, 10)
        : null;
      const showBothPrices = req.body.show_both_prices === true;

      const incomingRates = parseRates(req.body.exchange_rates);
      const cleanedRates = incomingRates
        .map((r) => {
          const from = normCurrency(r.from).substring(0, 10);
          const to = normCurrency(r.to).substring(0, 10);
          const rate = toNumber(r.rate);
          if (!from || !to) return null;
          return {
            from,
            to,
            rate: rate != null ? preserveRate(rate) : 0,
            is_auto: r.is_auto === true,
            provider: r.provider ? normCurrency(r.provider).substring(0, 30) : null,
            auto_fetched_at: r.auto_fetched_at || null,
            auto_source: r.auto_source || null,
          };
        })
        .filter((r) => r != null);

      await client.query('BEGIN');

      await client.query(
        'UPDATE stores SET display_currency = $1, show_both_prices = $2, exchange_rates = $3 WHERE id = $4',
        [displayCurrency || null, showBothPrices, JSON.stringify(cleanedRates), storeId]
      );

      await recalculateProductDisplayPrices(storeId, displayCurrency, cleanedRates, client);

      await client.query('COMMIT');

      res.json({
        display_currency: displayCurrency || null,
        show_both_prices: showBothPrices,
        exchange_rates: cleanedRates,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      console.error('Update currency settings error:', err);
      res.status(500).json({ error: 'Failed to update currency settings' });
    } finally {
      client.release();
    }
  }
);

// POST refresh auto rates from free APIs (owner only)
// Per-IP rate limit: each call fan-outs to N external currency APIs
// (frankfurter, syriato, exchangerate-api). Without a cap, a single
// store owner refreshing in a loop can exhaust those services' free
// tiers and degrade the feature for everyone. 12/hour is one refresh
// every 5 minutes, far more than any human needs.
router.post(
  '/my-store/currency-settings/refresh-auto',
  genericIpRateLimit({ keyPrefix: 'fx-refresh', max: 12, windowMs: 60 * 60 * 1000 }),
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  async (req, res) => {
    const client = await pool.connect();
    try {
      const storeId = req.storeContext.store_id;

      const storeResult = await client.query(
        'SELECT display_currency, show_both_prices, exchange_rates FROM stores WHERE id = $1',
        [storeId]
      );
      if (storeResult.rows.length === 0) {
        return res.status(404).json({ error: 'No store found' });
      }

      const store = storeResult.rows[0];
      const displayCurrency = store.display_currency || null;
      const rates = parseRates(store.exchange_rates);

      const warnings = [];
      let updatedCount = 0;
      const nowIso = new Date().toISOString();

      for (const rate of rates) {
        if (rate.is_auto !== true) continue;
        const fetched = await fetchAutoRate(rate.from, rate.to, rate.provider);
        if (fetched != null) {
          rate.rate = preserveRate(fetched.rate);
          rate.auto_fetched_at = nowIso;
          rate.auto_source = fetched.source;
          updatedCount++;
        } else {
          // Keep the existing manual/previous rate, warn the user.
          warnings.push(
            `Could not fetch an automatic rate for ${rate.from} → ${rate.to}. Kept the existing rate.`
          );
        }
      }

      await client.query('BEGIN');
      await client.query(
        'UPDATE stores SET exchange_rates = $1 WHERE id = $2',
        [JSON.stringify(rates), storeId]
      );
      await recalculateProductDisplayPrices(storeId, displayCurrency, rates, client);
      await client.query('COMMIT');

      res.json({
        display_currency: displayCurrency,
        show_both_prices: store.show_both_prices === true,
        exchange_rates: rates,
        updated: updatedCount,
        warnings,
      });
    } catch (err) {
      try { await client.query('ROLLBACK'); } catch (_) {}
      console.error('Refresh auto rates error:', err);
      res.status(500).json({ error: 'Failed to refresh automatic rates' });
    } finally {
      client.release();
    }
  }
);

module.exports = router;
module.exports.recalculateProductDisplayPrices = recalculateProductDisplayPrices;
module.exports.recalculateSingleProductDisplayPrice = recalculateSingleProductDisplayPrice;
module.exports.convertWithRates = convertWithRates;
module.exports.findDirectRate = findDirectRate;
module.exports.parseRates = parseRates;
