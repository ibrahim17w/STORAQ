const crypto = require('crypto');
const { pool } = require('../config/database');

const SCOPE_TYPES = ['radius', 'village', 'city', 'country', 'world'];
const MIN_DURATION_DAYS = 3;
const MAX_DURATION_DAYS = 90;
const MIN_RADIUS_KM = 5;
const MAX_RADIUS_KM = 100;

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizeStr(s) {
  return (s || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function stringsMatch(a, b) {
  const x = normalizeStr(a);
  const y = normalizeStr(b);
  if (!x || !y) return false;
  if (x === y) return true;
  if (x.length >= 3 && y.length >= 3 && (x.includes(y) || y.includes(x))) return true;
  return false;
}

function countryCodesMatch(viewerCode, campaignCode) {
  const v = normalizeStr(viewerCode);
  const c = normalizeStr(campaignCode);
  if (!v || !c) return false;
  if (v === c) return true;
  const aliases = {
    sy: 'syr',
    syr: 'sy',
    lb: 'lbn',
    lbn: 'lb',
    jo: 'jor',
    jor: 'jo',
    iq: 'irq',
    irq: 'iq',
    tr: 'tur',
    tur: 'tr',
    sa: 'sau',
    sau: 'sa',
    ae: 'are',
    are: 'ae',
  };
  return aliases[v] === c || aliases[c] === v;
}

function viewerHasGeo(viewer) {
  if (!viewer) return false;
  return !!(
    viewer.lat ||
    viewer.lng ||
    viewer.village ||
    viewer.city ||
    viewer.country ||
    viewer.country_code ||
    viewer.city_id
  );
}

function campaignMatchesViewer(campaign, viewer) {
  const scope = campaign.scope_type;
  if (scope === 'world') return true;

  if (scope === 'country') {
    if (
      viewer.country_code &&
      campaign.target_country_code &&
      countryCodesMatch(viewer.country_code, campaign.target_country_code)
    ) {
      return true;
    }
    if (stringsMatch(viewer.country, campaign.target_country)) return true;
    if (stringsMatch(viewer.country, campaign.store_country)) return true;
    return false;
  }

  if (scope === 'city') {
    if (
      viewer.city_id &&
      campaign.target_city_id &&
      normalizeStr(viewer.city_id) === normalizeStr(campaign.target_city_id)
    ) {
      return true;
    }
    if (stringsMatch(viewer.city, campaign.target_city)) return true;
    if (stringsMatch(viewer.city, campaign.store_city)) return true;
    return false;
  }

  if (scope === 'village') {
    return stringsMatch(viewer.village, campaign.target_village);
  }

  if (scope === 'radius') {
    const cLat = parseFloat(campaign.center_lat ?? campaign.store_lat);
    const cLng = parseFloat(campaign.center_lng ?? campaign.store_lng);
    if (!Number.isFinite(cLat) || !Number.isFinite(cLng)) return false;

    const lat = parseFloat(viewer.lat);
    const lng = parseFloat(viewer.lng);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      const radius = parseFloat(campaign.radius_km) || MIN_RADIUS_KM;
      return haversineKm(lat, lng, cLat, cLng) <= radius;
    }

    // Without GPS, radius campaigns are visible when the viewer's city
    // matches the store/campaign city (same metro area).
    return (
      stringsMatch(viewer.city, campaign.target_city) ||
      stringsMatch(viewer.city, campaign.store_city)
    );
  }

  return false;
}

function filterCampaignsForViewer(campaigns, viewer) {
  return campaigns.filter((row) => campaignMatchesViewer(row, viewer));
}

async function getPricing(scopeType) {
  const result = await pool.query(
    `SELECT * FROM sponsorship_pricing WHERE scope_type = $1`,
    [scopeType]
  );
  return result.rows[0] || null;
}

async function getAllPricing() {
  const result = await pool.query(
    `SELECT * FROM sponsorship_pricing ORDER BY sort_order ASC`
  );
  return result.rows;
}

async function calculatePrice(scopeType, radiusKm, durationDays) {
  const pricing = await getPricing(scopeType);
  if (!pricing) throw new Error('Invalid sponsorship scope');

  const days = Math.max(
    MIN_DURATION_DAYS,
    Math.min(MAX_DURATION_DAYS, parseInt(durationDays, 10) || MIN_DURATION_DAYS)
  );
  let daily = parseFloat(pricing.price_usd_per_day);
  let radius = null;

  if (scopeType === 'radius') {
    const unit = parseInt(pricing.radius_unit_km, 10) || 5;
    radius = Math.max(
      MIN_RADIUS_KM,
      Math.min(MAX_RADIUS_KM, parseInt(radiusKm, 10) || unit)
    );
    daily = daily * (radius / unit);
  }

  const amount = Math.round(daily * days * 100) / 100;
  return { amount_usd: amount, duration_days: days, radius_km: radius, daily_rate: daily };
}

// See subscription.generateReferenceCode for why Math.random is unsafe here.
function generateSponsorReferenceCode(storeId) {
  const rand = crypto.randomBytes(6).toString('base64')
    .replace(/[+/=]/g, '')
    .substring(0, 8)
    .toUpperCase();
  return `SP-${storeId}-${rand}`;
}

function buildGeoTargets(store, scopeType, overrides = {}) {
  const targets = {
    scope_type: scopeType,
    radius_km: null,
    target_village: null,
    target_city: null,
    target_country: null,
    target_country_code: null,
    target_city_id: null,
    center_lat: store.lat,
    center_lng: store.lng,
  };

  if (scopeType === 'radius') {
    targets.radius_km = overrides.radius_km;
  } else if (scopeType === 'village') {
    targets.target_village = overrides.target_village || store.village;
  } else if (scopeType === 'city') {
    targets.target_city = overrides.target_city || store.city;
    targets.target_city_id = overrides.target_city_id || store.city_id;
  } else if (scopeType === 'country') {
    targets.target_country = overrides.target_country || store.country;
    targets.target_country_code = overrides.target_country_code || store.country_code;
  }

  return targets;
}

async function expireCampaigns() {
  await pool.query(
    `UPDATE sponsored_product_campaigns
     SET status = 'expired', updated_at = NOW()
     WHERE status = 'active' AND expires_at < NOW()`
  );
}

module.exports = {
  SCOPE_TYPES,
  MIN_DURATION_DAYS,
  MAX_DURATION_DAYS,
  MIN_RADIUS_KM,
  MAX_RADIUS_KM,
  viewerHasGeo,
  campaignMatchesViewer,
  filterCampaignsForViewer,
  getPricing,
  getAllPricing,
  calculatePrice,
  generateSponsorReferenceCode,
  buildGeoTargets,
  expireCampaigns,
  haversineKm,
};
