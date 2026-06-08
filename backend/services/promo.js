const { pool } = require('../config/database');
const { convertUsdToPaymentCurrencies } = require('./exchange_rates');

/**
 * Active discount promo for a store (redeemed, type=discount, still valid).
 * Does not apply to marketplace product purchases — only platform fees
 * (subscription tiers, product sponsorship).
 */
async function getActiveDiscountPromo(storeId) {
  const result = await pool.query(
    `SELECT pr.id AS redemption_id, pr.promo_id, pc.code, pc.type,
            pc.discount_percent, pc.discount_fixed, pc.expires_at
     FROM promo_redemptions pr
     JOIN promo_codes pc ON pr.promo_id = pc.id
     WHERE pr.store_id = $1
       AND pr.status = 'active'
       AND pc.type = 'discount'
       AND pc.is_active = TRUE
       AND (pc.expires_at IS NULL OR pc.expires_at > NOW())
     ORDER BY pr.created_at DESC
     LIMIT 1`,
    [storeId]
  );
  return result.rows[0] || null;
}

function applyPromoDiscount(baseUsd, promo) {
  const original = Math.round((parseFloat(baseUsd) || 0) * 100) / 100;
  if (!promo || original <= 0) {
    return {
      amount_usd: original,
      original_amount_usd: original,
      discount_usd: 0,
    };
  }

  const percent = parseInt(promo.discount_percent, 10) || 0;
  const fixed = parseFloat(promo.discount_fixed) || 0;
  let discount = 0;

  if (percent > 0) {
    discount += original * (percent / 100);
  }
  if (fixed > 0) {
    discount += fixed;
  }

  discount = Math.min(discount, original);
  discount = Math.round(discount * 100) / 100;
  const finalAmount = Math.max(0, Math.round((original - discount) * 100) / 100);

  return {
    amount_usd: finalAmount,
    original_amount_usd: original,
    discount_usd: discount,
    discount_percent: percent > 0 ? percent : undefined,
    discount_fixed: fixed > 0 ? fixed : undefined,
    promo_code: promo.code,
  };
}

function buildPromoPricing(baseUsd, promo, paymentRates) {
  const pricing = applyPromoDiscount(baseUsd, promo);
  const rates = paymentRates || null;
  return {
    ...pricing,
    payment_prices: convertUsdToPaymentCurrencies(pricing.amount_usd, rates),
    original_payment_prices: pricing.discount_usd > 0
      ? convertUsdToPaymentCurrencies(pricing.original_amount_usd, rates)
      : undefined,
  };
}

function formatActivePromoResponse(promo) {
  if (!promo) return null;
  return {
    code: promo.code,
    discount_percent: parseInt(promo.discount_percent, 10) || 0,
    discount_fixed: parseFloat(promo.discount_fixed) || 0,
  };
}

module.exports = {
  getActiveDiscountPromo,
  applyPromoDiscount,
  buildPromoPricing,
  formatActivePromoResponse,
};
