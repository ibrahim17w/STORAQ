const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const {
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  requireStoreAccess,
} = require('../middleware/auth');
const { schemas, validate } = require('../middleware/validation');
const {
  getPlatformPaymentRates,
  convertUsdToPaymentCurrencies,
} = require('../services/exchange_rates');
const {
  SCOPE_TYPES,
  MIN_DURATION_DAYS,
  MAX_DURATION_DAYS,
  MIN_RADIUS_KM,
  MAX_RADIUS_KM,
  filterCampaignsForViewer,
  getAllPricing,
  calculatePrice,
  generateSponsorReferenceCode,
  buildGeoTargets,
  expireCampaigns,
} = require('../services/sponsored_products');
const {
  getActiveDiscountPromo,
  buildPromoPricing,
} = require('../services/promo');

async function loadStoreAndProduct(storeId, productId) {
  const storeResult = await pool.query(`SELECT * FROM stores WHERE id = $1`, [storeId]);
  if (storeResult.rows.length === 0) return { error: 'Store not found', status: 404 };
  const store = storeResult.rows[0];

  const productResult = await pool.query(
    `SELECT * FROM products WHERE id = $1 AND store_id = $2`,
    [productId, storeId]
  );
  if (productResult.rows.length === 0) return { error: 'Product not found', status: 404 };
  const product = productResult.rows[0];

  if (!product.is_online) {
    return { error: 'Product must be listed online before sponsoring', status: 400 };
  }

  return { store, product };
}

function validateScopeTargets(store, scopeType, body) {
  if (scopeType === 'radius') {
    if (!store.lat || !store.lng) {
      return 'Store location is required for radius sponsorship. Update your store location first.';
    }
    const radius = parseInt(body.radius_km, 10);
    if (!Number.isFinite(radius) || radius < MIN_RADIUS_KM || radius > MAX_RADIUS_KM) {
      return `Radius must be between ${MIN_RADIUS_KM} and ${MAX_RADIUS_KM} km`;
    }
  }
  if (scopeType === 'village' && !(body.target_village || store.village)) {
    return 'Village is required. Set your store village or provide a target village.';
  }
  if (scopeType === 'city' && !(body.target_city || store.city)) {
    return 'City is required. Set your store city or provide a target city.';
  }
  if (scopeType === 'country' && !(body.target_country || store.country)) {
    return 'Country is required. Set your store country or provide a target country.';
  }
  return null;
}

// Public pricing list
router.get('/sponsorship/pricing', async (req, res) => {
  try {
    const [pricing, paymentRates] = await Promise.all([
      getAllPricing(),
      getPlatformPaymentRates(),
    ]);
    const pricingWithConverted = pricing.map((p) => ({
      ...p,
      payment_prices_daily: convertUsdToPaymentCurrencies(
        parseFloat(p.price_usd_per_day) || 0,
        paymentRates
      ),
    }));
    res.json({
      pricing: pricingWithConverted,
      payment_rates: paymentRates,
      limits: {
        min_duration_days: MIN_DURATION_DAYS,
        max_duration_days: MAX_DURATION_DAYS,
        min_radius_km: MIN_RADIUS_KM,
        max_radius_km: MAX_RADIUS_KM,
        scope_types: SCOPE_TYPES,
      },
    });
  } catch (err) {
    console.error('Sponsorship pricing error:', err);
    res.status(500).json({ error: 'Failed to load sponsorship pricing' });
  }
});

// Sponsored products for home feed (geo-filtered)
router.get('/products/sponsored', async (req, res) => {
  try {
    await expireCampaigns();

    const viewer = {
      lat: req.query.lat,
      lng: req.query.lng,
      village: req.query.village,
      city: req.query.city,
      country: req.query.country,
      country_code: req.query.country_code,
      city_id: req.query.city_id,
    };

    const campaigns = await pool.query(
      `SELECT c.*, p.name, p.price, p.sale_price, p.quantity, p.description, p.image_url, p.images, p.currency,
              p.display_price, p.display_currency,
              s.id AS shop_id, s.name AS shop_name, s.city AS store_city, s.country AS store_country,
              s.lat AS store_lat, s.lng AS store_lng
       FROM sponsored_product_campaigns c
       JOIN products p ON c.product_id = p.id
       JOIN stores s ON c.store_id = s.id
       WHERE c.status = 'active'
         AND c.expires_at > NOW()
         AND p.is_online = TRUE
         AND p.quantity > 0
         AND s.is_active IS NOT FALSE
       ORDER BY c.created_at DESC
       LIMIT 100`
    );

    const matched = filterCampaignsForViewer(campaigns.rows, viewer);
    const seen = new Set();
    const products = [];
    for (const row of matched) {
      if (seen.has(row.product_id)) continue;
      seen.add(row.product_id);
      products.push({
        id: row.product_id,
        name: row.name,
        price: row.price,
        sale_price: row.sale_price,
        quantity: row.quantity,
        description: row.description,
        image_url: row.image_url,
        images: row.images,
        currency: row.currency,
        display_price: row.display_price,
        display_currency: row.display_currency,
        shop_id: row.shop_id,
        shop_name: row.shop_name,
        city: row.store_city,
        country: row.store_country,
        lat: row.store_lat,
        lng: row.store_lng,
        is_sponsored: true,
        sponsorship_scope: row.scope_type,
        sponsorship_expires_at: row.expires_at,
      });
      if (products.length >= 20) break;
    }

    res.json(products);
  } catch (err) {
    console.error('Sponsored products error:', err);
    res.status(500).json({ error: 'Failed to load sponsored products' });
  }
});

// Store owner: quote price
router.post(
  '/my-store/products/:id/sponsorship/quote',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  validate(schemas.sponsorshipQuote),
  async (req, res) => {
    try {
      const productId = parseInt(req.params.id, 10);
      const storeId = req.storeContext.store_id;
      const loaded = await loadStoreAndProduct(storeId, productId);
      if (loaded.error) return res.status(loaded.status).json({ error: loaded.error });

      const { scope_type, radius_km, duration_days } = req.validatedBody;
      const scopeErr = validateScopeTargets(loaded.store, scope_type, req.validatedBody);
      if (scopeErr) return res.status(400).json({ error: scopeErr });

      const quote = await calculatePrice(scope_type, radius_km, duration_days);
      const geo = buildGeoTargets(loaded.store, scope_type, req.validatedBody);

      const paymentRates = await getPlatformPaymentRates();
      const activePromo = await getActiveDiscountPromo(storeId);
      const promoPricing = buildPromoPricing(quote.amount_usd, activePromo, paymentRates);

      res.json({
        product_id: productId,
        scope_type,
        ...geo,
        ...quote,
        amount_usd: promoPricing.amount_usd,
        original_amount_usd: promoPricing.original_amount_usd,
        discount_usd: promoPricing.discount_usd,
        currency: 'USD',
        payment_prices: promoPricing.payment_prices,
        original_payment_prices: promoPricing.original_payment_prices,
        promo: promoPricing.discount_usd > 0
          ? {
              code: promoPricing.promo_code,
              discount_usd: promoPricing.discount_usd,
              discount_percent: promoPricing.discount_percent,
              discount_fixed: promoPricing.discount_fixed,
            }
          : undefined,
        payment_rates: paymentRates,
      });
    } catch (err) {
      console.error('Sponsorship quote error:', err);
      res.status(500).json({ error: 'Failed to calculate quote' });
    }
  }
);

// Store owner: request payment
router.post(
  '/my-store/products/:id/sponsorship/request',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreOwner,
  validate(schemas.sponsorshipRequest),
  async (req, res) => {
    try {
      const productId = parseInt(req.params.id, 10);
      const storeId = req.storeContext.store_id;
      const loaded = await loadStoreAndProduct(storeId, productId);
      if (loaded.error) return res.status(loaded.status).json({ error: loaded.error });

      const { scope_type, radius_km, duration_days, payment_track } = req.validatedBody;
      const scopeErr = validateScopeTargets(loaded.store, scope_type, req.validatedBody);
      if (scopeErr) return res.status(400).json({ error: scopeErr });

      // Avoid duplicate requests for the same product.
      const [activeCampaign, pendingPayment] = await Promise.all([
        pool.query(
          `SELECT id
             FROM sponsored_product_campaigns
            WHERE product_id = $1
              AND status = 'active'
              AND expires_at > NOW()
            LIMIT 1`,
          [productId]
        ),
        pool.query(
          `SELECT id, reference_code
             FROM sponsored_product_payments
            WHERE product_id = $1
              AND status = 'pending'
            ORDER BY created_at DESC
            LIMIT 1`,
          [productId]
        ),
      ]);
      if (activeCampaign.rows.length > 0) {
        return res.status(409).json({ error: 'This product already has an active sponsorship campaign' });
      }
      if (pendingPayment.rows.length > 0) {
        return res.status(409).json({
          error: `Sponsorship request already pending${pendingPayment.rows[0].reference_code ? ` (${pendingPayment.rows[0].reference_code})` : ''}`,
        });
      }

      const quote = await calculatePrice(scope_type, radius_km, duration_days);
      const geo = buildGeoTargets(loaded.store, scope_type, {
        ...req.validatedBody,
        radius_km: quote.radius_km ?? radius_km,
      });

      const activePromo = await getActiveDiscountPromo(storeId);
      const promoPricing = buildPromoPricing(quote.amount_usd, activePromo);
      const amountDue = promoPricing.amount_usd;

      if (payment_track !== 'syria_agent') {
        return res.status(400).json({ error: 'Only syria_agent payment is available for sponsorship' });
      }

      const referenceCode = generateSponsorReferenceCode(storeId);
      const result = await pool.query(
        `INSERT INTO sponsored_product_payments (
           store_id, product_id, scope_type, radius_km, duration_days,
           target_village, target_city, target_country, target_country_code, target_city_id,
           center_lat, center_lng, amount_usd, payment_track, reference_code, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,'pending')
         RETURNING *`,
        [
          storeId,
          productId,
          scope_type,
          geo.radius_km,
          quote.duration_days,
          geo.target_village,
          geo.target_city,
          geo.target_country,
          geo.target_country_code,
          geo.target_city_id,
          geo.center_lat,
          geo.center_lng,
          amountDue,
          payment_track,
          referenceCode,
        ]
      );

      res.status(201).json({
        payment: result.rows[0],
        quote: {
          ...quote,
          amount_usd: amountDue,
          original_amount_usd: promoPricing.original_amount_usd,
          discount_usd: promoPricing.discount_usd,
        },
        promo_pricing: promoPricing.discount_usd > 0 ? promoPricing : undefined,
        product: { id: loaded.product.id, name: loaded.product.name },
        instructions: 'Pay cash to an authorized agent and provide this reference code.',
      });
    } catch (err) {
      console.error('Sponsorship request error:', err);
      res.status(500).json({ error: 'Failed to create sponsorship request' });
    }
  }
);

// Store owner: list campaigns
router.get(
  '/my-store/sponsorship/campaigns',
  authenticateToken,
  requireRealUser,
  attachStoreContext,
  requireStoreAccess,
  async (req, res) => {
    try {
      await expireCampaigns();
      const storeId = req.storeContext.store_id;

      const [campaigns, pending] = await Promise.all([
        pool.query(
          `SELECT c.*, p.name AS product_name, p.image_url AS product_image
           FROM sponsored_product_campaigns c
           JOIN products p ON c.product_id = p.id
           WHERE c.store_id = $1
           ORDER BY c.created_at DESC`,
          [storeId]
        ),
        pool.query(
          `SELECT sp.*, p.name AS product_name
           FROM sponsored_product_payments sp
           JOIN products p ON sp.product_id = p.id
           WHERE sp.store_id = $1 AND sp.status = 'pending'
           ORDER BY sp.created_at DESC`,
          [storeId]
        ),
      ]);

      res.json({
        campaigns: campaigns.rows,
        pending_payments: pending.rows,
      });
    } catch (err) {
      console.error('Store sponsorship campaigns error:', err);
      res.status(500).json({ error: 'Failed to load sponsorship campaigns' });
    }
  }
);

module.exports = router;
