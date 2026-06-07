const express = require('express');
const router = express.Router();

const {
  getPlatformPaymentRates,
  convertUsdToPaymentCurrencies,
} = require('../services/exchange_rates');

router.get('/platform/payment-rates', async (req, res) => {
  try {
    const rates = await getPlatformPaymentRates();
    res.json(rates);
  } catch (err) {
    console.error('Platform payment rates error:', err);
    res.status(500).json({ error: 'Failed to load payment rates' });
  }
});

router.get('/platform/payment-rates/convert', async (req, res) => {
  try {
    const usd = parseFloat(req.query.usd);
    if (!Number.isFinite(usd) || usd < 0) {
      return res.status(400).json({ error: 'Invalid usd amount' });
    }
    const paymentRates = await getPlatformPaymentRates();
    res.json({
      usd,
      amounts: convertUsdToPaymentCurrencies(usd, paymentRates),
      rates: paymentRates.rates,
      sources: paymentRates.sources,
      fetched_at: paymentRates.fetched_at,
    });
  } catch (err) {
    console.error('Platform convert error:', err);
    res.status(500).json({ error: 'Failed to convert' });
  }
});

module.exports = router;
