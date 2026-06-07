/**
 * Exchange rate fetching with full decimal precision (important for SYP).
 * Syria market rates come from syriato.com (same figures as sp-today).
 */

const RATE_DECIMALS = 6;

const RATE_PROVIDERS = [
  { id: 'frankfurter', label: 'Frankfurter (official)' },
  { id: 'exchangerate', label: 'ExchangeRate-API (official)' },
  { id: 'syria_market', label: 'Syria market rate (sp-today / syriato)' },
  { id: 'syria_official', label: 'Syria central bank rate' },
];

const PAYMENT_CURRENCIES = [
  'USD', 'SYP', 'EUR', 'GBP', 'TRY', 'SAR', 'AED', 'JOD', 'QAR', 'CAD', 'CHF',
];

function normCurrency(value) {
  return (value == null ? '' : value.toString()).trim();
}

function toNumber(value) {
  if (value == null) return null;
  const n = parseFloat(String(value).replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

/** Preserve fractional rates (e.g. 140.1 SYP per USD) — never round to integers. */
function preserveRate(value) {
  const n = toNumber(value);
  if (n == null) return null;
  const factor = 10 ** RATE_DECIMALS;
  return Math.round(n * factor) / factor;
}

function roundConvertedPrice(amount, currency) {
  const n = toNumber(amount);
  if (n == null) return null;
  const c = normCurrency(currency).toUpperCase();
  if (c === 'SYP') return Math.round(n);
  return Math.round(n * 100) / 100;
}

async function fetchFrankfurter(f, t) {
  const res = await fetch(
    `https://api.frankfurter.app/latest?from=${encodeURIComponent(f)}&to=${encodeURIComponent(t)}`
  );
  if (!res.ok) return null;
  const data = await res.json();
  const rate = data && data.rates ? toNumber(data.rates[t]) : null;
  return rate != null && rate > 0
    ? { rate: preserveRate(rate), source: 'frankfurter.app' }
    : null;
}

async function fetchFrankfurterMulti(from, targets) {
  const list = targets.filter((t) => t !== from);
  if (list.length === 0) return {};
  const res = await fetch(
    `https://api.frankfurter.app/latest?from=${encodeURIComponent(from)}&to=${list.join(',')}`
  );
  if (!res.ok) return {};
  const data = await res.json();
  const out = {};
  for (const [cur, rate] of Object.entries(data.rates || {})) {
    const r = preserveRate(rate);
    if (r != null && r > 0) out[cur] = { rate: r, source: 'frankfurter.app' };
  }
  return out;
}

async function fetchExchangeRateApi(f, t) {
  const res = await fetch(`https://open.er-api.com/v6/latest/${encodeURIComponent(f)}`);
  if (!res.ok) return null;
  const data = await res.json();
  const rate = data && data.rates ? toNumber(data.rates[t]) : null;
  return rate != null && rate > 0
    ? { rate: preserveRate(rate), source: 'exchangerate-api.com' }
    : null;
}

/**
 * Syrian-pound rates from syriato.com (aggregates sp-today market figures).
 * Uses sell price first, then buy — keeps decimals from the API.
 */
async function fetchSyriaRate(f, t, marketType) {
  const wanted = marketType === 'official' ? 'central_bank' : 'market';

  async function rateToSyp(base) {
    const res = await fetch(
      `https://syriato.com/api/v1/latest-rates?base=${encodeURIComponent(base)}`
    );
    if (!res.ok) return null;
    const json = await res.json();
    const arr = Array.isArray(json && json.data)
      ? json.data
      : Array.isArray(json)
      ? json
      : [];
    const matches = arr.filter(
      (r) => normCurrency(r.target).toUpperCase() === 'SYP'
    );
    const entry =
      matches.find((r) => r.source === wanted) || matches[0] || null;
    if (!entry) return null;
    const sell = toNumber(entry.sell);
    const buy = toNumber(entry.buy);
    const rate = sell != null && sell > 0 ? sell : buy;
    return rate != null && rate > 0 ? preserveRate(rate) : null;
  }

  const sourceLabel = `syriato.com / sp-today (${wanted === 'central_bank' ? 'official' : 'market'})`;
  if (t === 'SYP') {
    const r = await rateToSyp(f);
    return r != null ? { rate: r, source: sourceLabel } : null;
  }
  if (f === 'SYP') {
    const r = await rateToSyp(t);
    return r != null ? { rate: preserveRate(1 / r), source: sourceLabel } : null;
  }
  return null;
}

async function fetchAutoRate(from, to, preferred) {
  const f = normCurrency(from).toUpperCase();
  const t = normCurrency(to).toUpperCase();
  if (!f || !t) return null;
  if (f === t) return { rate: 1, source: 'identity' };

  const tryFrankfurter = () => fetchFrankfurter(f, t);
  const tryExchangeRate = () => fetchExchangeRateApi(f, t);
  const trySyriaMarket = () => fetchSyriaRate(f, t, 'market');
  const trySyriaOfficial = () => fetchSyriaRate(f, t, 'official');

  const involvesSyp = f === 'SYP' || t === 'SYP';

  let order;
  switch (preferred) {
    case 'syria_market':
      order = [trySyriaMarket, trySyriaOfficial, tryFrankfurter, tryExchangeRate];
      break;
    case 'syria_official':
      order = [trySyriaOfficial, trySyriaMarket, tryFrankfurter, tryExchangeRate];
      break;
    case 'exchangerate':
      order = [tryExchangeRate, tryFrankfurter];
      break;
    case 'frankfurter':
      order = [tryFrankfurter, tryExchangeRate];
      break;
    default:
      order = involvesSyp
        ? [trySyriaMarket, trySyriaOfficial, tryFrankfurter, tryExchangeRate]
        : [tryFrankfurter, tryExchangeRate];
  }

  for (const fn of order) {
    try {
      const result = await fn();
      if (result != null) return result;
    } catch (_) {
      // try next
    }
  }
  return null;
}

let paymentRatesCache = null;
let paymentRatesCacheAt = 0;
const PAYMENT_CACHE_MS = 15 * 60 * 1000;

async function getPlatformPaymentRates() {
  if (paymentRatesCache && Date.now() - paymentRatesCacheAt < PAYMENT_CACHE_MS) {
    return paymentRatesCache;
  }

  const rates = { USD: 1 };
  const sources = { USD: 'base' };

  const syp = await fetchSyriaRate('USD', 'SYP', 'market');
  if (syp) {
    rates.SYP = syp.rate;
    sources.SYP = syp.source;
  }

  const frankTargets = PAYMENT_CURRENCIES.filter(
    (c) => c !== 'USD' && c !== 'SYP'
  );
  const frank = await fetchFrankfurterMulti('USD', frankTargets);
  for (const [cur, info] of Object.entries(frank)) {
    rates[cur] = info.rate;
    sources[cur] = info.source;
  }

  for (const cur of frankTargets) {
    if (rates[cur] != null) continue;
    const fallback = await fetchExchangeRateApi('USD', cur);
    if (fallback) {
      rates[cur] = fallback.rate;
      sources[cur] = fallback.source;
    }
  }

  paymentRatesCache = {
    base: 'USD',
    rates,
    sources,
    currencies: PAYMENT_CURRENCIES.filter((c) => rates[c] != null),
    fetched_at: new Date().toISOString(),
  };
  paymentRatesCacheAt = Date.now();
  return paymentRatesCache;
}

function convertUsdToPaymentCurrencies(usdAmount, paymentRates) {
  const usd = toNumber(usdAmount);
  if (usd == null) return {};
  const rateMap = paymentRates?.rates || {};
  const amounts = {};
  for (const [cur, rate] of Object.entries(rateMap)) {
    const converted = usd * rate;
    amounts[cur] =
      cur === 'SYP' ? Math.round(converted) : preserveRate(converted);
  }
  return amounts;
}

module.exports = {
  RATE_PROVIDERS,
  RATE_DECIMALS,
  PAYMENT_CURRENCIES,
  normCurrency,
  toNumber,
  preserveRate,
  roundConvertedPrice,
  fetchFrankfurter,
  fetchFrankfurterMulti,
  fetchExchangeRateApi,
  fetchSyriaRate,
  fetchAutoRate,
  getPlatformPaymentRates,
  convertUsdToPaymentCurrencies,
};
