//routes/geocode.js
const express = require('express');
const router = express.Router();
const crypto = require('crypto');

const { pool } = require('../config/database');
const { authenticateToken, optionalAuth, requireRealUser, genericIpRateLimit } = require('../middleware/auth');
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { reverseGeocodeLogic, createCanonicalCity } = require('../services/location');
const { nominatimFetch } = require('../services/location');

// ==================== GEOCODING ENDPOINTS ====================
// Per-IP rate limit: every cache miss here makes an outbound request to
// Nominatim (OpenStreetMap), whose policy caps us at ~1 req/sec from one
// IP for the whole project. Without per-caller throttling, a single
// attacker can blow through our quota in seconds and get the entire
// service IP-banned by Nominatim — taking down geocoding for every
// user. 60/hour is well above legitimate flows (one search per address
// the user types) but well below abuse rates.
router.get(
  '/geocode/search',
  genericIpRateLimit({ keyPrefix: 'geo-search', max: 60, windowMs: 60 * 60 * 1000 }),
  validateQuery(schemas.geocodeSearch),
  async (req, res) => {
  try {
    const { q: query, lang: userLang } = req.validatedQuery;
    const lang = userLang || 'en';
    if (!query) return res.status(400).json({ error: 'Query required' });

    const hash = crypto.createHash('sha256').update(`search|${query}|${lang}`).digest('hex');
    try {
      const cached = await pool.query(
        `SELECT result_json FROM geocode_cache WHERE query_hash = $1 AND created_at > NOW() - INTERVAL '7 days'`,
        [hash]
      );
      if (cached.rows.length > 0 && cached.rows[0].result_json) {
        return res.json(cached.rows[0].result_json);
      }
    } catch (cacheErr) {
      console.log('Search cache read skipped:', cacheErr.message);
    }

    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&addressdetails=1&namedetails=1&limit=5&accept-language=${encodeURIComponent(lang)}`;
    const data = await nominatimFetch(url);

    const results = [];
    for (const place of data) {
      if (!place.address?.country_code) continue;
      const canonical = await createCanonicalCity(place, lang);
      if (!canonical) continue;
      results.push({
        canonical_id: canonical.canonical_id,
        display_name: canonical.display_names?.[lang] || canonical.display_names?.en || place.display_name,
        lat: parseFloat(place.lat),
        lng: parseFloat(place.lon),
        country_code: canonical.country_code,
        osm_id: place.osm_id,
        type: place.type,
        class: place.class,
      });
    }

    try {
      await pool.query(
        `INSERT INTO geocode_cache (query_hash, query_text, lang, result_json) VALUES ($1,$2,$3,$4)
         ON CONFLICT (query_hash) DO UPDATE SET result_json=$4, created_at=NOW()`,
        [hash, query, lang, JSON.stringify(results)]
      );
    } catch (cacheErr) {
      console.log('Search cache write skipped:', cacheErr.message);
    }

    res.json(results);
  } catch (err) {
    console.error('Geocode search error:', err);
    res.status(500).json({ error: 'Geocoding service unavailable' });
  }
});

router.get(
  '/geocode/reverse',
  genericIpRateLimit({ keyPrefix: 'geo-reverse', max: 60, windowMs: 60 * 60 * 1000 }),
  validateQuery(schemas.geocodeReverse),
  async (req, res) => {
  try {
    const { lat, lng, lang: userLang } = req.validatedQuery;
    const lang = userLang || 'en';
    const result = await reverseGeocodeLogic(lat, lng, lang);
    if (!result) return res.status(404).json({ error: 'No location found' });
    res.json(result);
  } catch (err) {
    console.error('Reverse geocode error:', err);
    res.status(500).json({ error: 'Geocoding service unavailable' });
  }
});

router.post('/admin/migrate-locations', authenticateToken, validate(schemas.migrateLocations), async (req, res) => {
  try {
    const userResult = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
    if (userResult.rows.length === 0 || userResult.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const stores = await pool.query(
      `SELECT id, city, country, lat, lng FROM stores 
       WHERE city_id IS NULL AND lat IS NOT NULL AND lng IS NOT NULL 
       LIMIT 30`
    );

    let migrated = 0;
    for (const store of stores.rows) {
      try {
        const geo = await reverseGeocodeLogic(store.lat, store.lng, 'en');
        if (geo && geo.canonical_id) {
          await pool.query(
            'UPDATE stores SET city_id=$1, country_code=$2 WHERE id=$3',
            [geo.canonical_id, geo.country_code, store.id]
          );
          migrated++;
        }
      } catch (e) {
        console.error('Migrate failed for store', store.id, e.message);
      }
      await new Promise(r => setTimeout(r, 1100));
    }

    res.json({ message: `Migrated ${migrated} stores`, batch_size: stores.rows.length });
  } catch (err) {
    console.error('Migration error:', err);
    res.status(500).json({ error: 'Migration failed' });
  }
});

module.exports = router;
