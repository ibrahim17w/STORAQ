//services/location.js
const crypto = require('crypto');

let transliterate;
try {
  transliterate = require('transliteration').transliterate;
} catch (_) {
  transliterate = (s) => s;
}

const { pool } = require('../config/database');

function slugify(str) {
  if (!str) return 'unknown';
  let s = transliterate(str.toString().trim());
  return s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .substring(0, 50);
}

async function nominatimFetch(url, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      await new Promise(r => setTimeout(r, 1100));
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'MarketBridge/1.0 (contact@marketbridge.app)',
        },
      });
      if (!res.ok) {
        if (res.status === 429 && attempt < retries) {
          console.log(`Nominatim rate limited, retry ${attempt}/${retries}...`);
          await new Promise(r => setTimeout(r, 2000 * attempt));
          continue;
        }
        throw new Error(`Nominatim HTTP ${res.status}`);
      }
      return res.json();
    } catch (err) {
      if (attempt === retries) throw err;
      console.log(`Nominatim attempt ${attempt} failed, retrying...`);
      await new Promise(r => setTimeout(r, 1000 * attempt));
    }
  }
}

async function findCanonicalCityByCoords(lat, lng, radiusKm = 2) {
  const result = await pool.query(
    `SELECT * FROM (
      SELECT canonical_id, display_names, country_code,
        (6371 * acos(
          GREATEST(LEAST(
            cos(radians($1)) * cos(radians(lat)) *
            cos(radians(lng) - radians($2)) +
            sin(radians($1)) * sin(radians(lat))
          , 1), -1)
        )) AS distance
       FROM canonical_cities
       WHERE lat IS NOT NULL AND lng IS NOT NULL
     ) AS nearby
     WHERE distance <= $3
     ORDER BY distance ASC
     LIMIT 1`,
    [lat, lng, radiusKm]
  );
  return result.rows[0] || null;
}

async function fetchEnglishPlaceDetails(osmType, osmId) {
  const typeChar = osmType ? osmType.toUpperCase()[0] : 'N';
  const url = `https://nominatim.openstreetmap.org/reverse?osm_type=${typeChar}&osm_id=${osmId}&format=json&addressdetails=1&namedetails=1&accept-language=en`;
  return nominatimFetch(url);
}

async function createCanonicalCity(place, userLang) {
  const countryCode = (place.address?.country_code || '').toLowerCase().substring(0, 2);
  if (!countryCode) return null;

  const lat = parseFloat(place.lat);
  const lng = parseFloat(place.lon);

  const existing = await findCanonicalCityByCoords(lat, lng, 2);
  if (existing) return existing;

  let enPlace = place;
  if (userLang !== 'en' && place.osm_id && place.osm_type) {
    try {
      enPlace = await fetchEnglishPlaceDetails(place.osm_type, place.osm_id);
    } catch (_) {
      enPlace = place;
    }
  }

  const addr = enPlace?.address || place?.address || {};
  const stateName = addr.state || addr.county || addr.region || addr.state_district || 'unknown';
  const cityName = addr.city || addr.town || addr.village || addr.hamlet || addr.suburb || addr.municipality || 'unknown';

  const stateCode = slugify(stateName);
  const cityCode = slugify(cityName);
  const canonicalId = `${countryCode}-${stateCode}-${cityCode}`;

  const displayNames = {};
  const userDisplay = place.display_name || place.name || cityName;
  if (userDisplay) displayNames[userLang] = userDisplay;
  const enDisplay = enPlace?.display_name || enPlace?.name || place?.name || cityName;
  if (enDisplay) displayNames.en = enDisplay;

  await pool.query(
    `INSERT INTO canonical_cities (canonical_id, country_code, state_code, city_code, display_names, lat, lng, osm_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (canonical_id) DO UPDATE SET
       display_names = canonical_cities.display_names || EXCLUDED.display_names,
       lat = EXCLUDED.lat,
       lng = EXCLUDED.lng,
       osm_id = EXCLUDED.osm_id`,
    [canonicalId, countryCode, stateCode, cityCode, JSON.stringify(displayNames), lat, lng, place.osm_id]
  );

  return { canonical_id: canonicalId, country_code: countryCode, display_names: displayNames, lat, lng };
}

async function reverseGeocodeLogic(lat, lng, lang) {
  const roundedLat = Math.round(lat * 1000) / 1000;
  const roundedLng = Math.round(lng * 1000) / 1000;
  const hash = crypto.createHash('sha256').update(`reverse|${roundedLat}|${roundedLng}|${lang}`).digest('hex');

  try {
    const cached = await pool.query(
      `SELECT result_json FROM geocode_cache WHERE query_hash = $1 AND created_at > NOW() - INTERVAL '7 days'`,
      [hash]
    );
    if (cached.rows.length > 0 && cached.rows[0].result_json) {
      const c = cached.rows[0].result_json;
      return {
        canonical_id: c.canonical_id,
        country_code: c.country_code,
        display_name: c.display_name,
        lat: c.lat,
        lng: c.lng,
      };
    }
  } catch (cacheErr) {
    console.log('Cache read skipped:', cacheErr.message);
  }

  const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1&namedetails=1&accept-language=${encodeURIComponent(lang)}`;
  const data = await nominatimFetch(url);

  if (!data || !data.address) return null;

  let canonical = await findCanonicalCityByCoords(lat, lng, 2);
  if (!canonical) {
    canonical = await createCanonicalCity(data, lang);
  }

  const result = {
    canonical_id: canonical.canonical_id,
    display_name: canonical.display_names?.[lang] || canonical.display_names?.en || data.display_name,
    lat,
    lng,
    country_code: canonical.country_code,
    address: data.address,
  };

  try {
    await pool.query(
      `INSERT INTO geocode_cache (query_hash, query_text, lang, result_json)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (query_hash) DO UPDATE SET result_json = EXCLUDED.result_json, created_at = NOW()`,
      [hash, `${lat},${lng}`, lang, JSON.stringify(result)]
    );
  } catch (cacheErr) {
    console.log('Cache write skipped:', cacheErr.message);
  }

  return result;
}

async function initLocationTables() {
  // Create base users table first (stores FK depends on it)
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      full_name VARCHAR(100) NOT NULL,
      email VARCHAR(255) NOT NULL UNIQUE,
      phone VARCHAR(50),
      password_hash VARCHAR(255) NOT NULL,
      role VARCHAR(20) DEFAULT 'customer',
      email_verified BOOLEAN DEFAULT FALSE,
      preferred_language VARCHAR(10) DEFAULT 'en',
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  // Create base stores table before any ALTER TABLE on it
  await pool.query(`
    CREATE TABLE IF NOT EXISTS stores (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      city VARCHAR(100),
      location_description VARCHAR(200),
      country VARCHAR(100) DEFAULT 'Syria',
      lat DECIMAL(10,8),
      lng DECIMAL(11,8),
      phone VARCHAR(50),
      owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      city_id VARCHAR(100),
      country_code VARCHAR(2),
      village VARCHAR(100),
      is_sponsored BOOLEAN DEFAULT FALSE,
      sponsorship_tier INTEGER DEFAULT 1,
      sponsorship_expires_at TIMESTAMP,
      image_url TEXT,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS canonical_cities (
      canonical_id VARCHAR(100) PRIMARY KEY,
      country_code VARCHAR(2) NOT NULL,
      state_code VARCHAR(50),
      city_code VARCHAR(50) NOT NULL,
      display_names JSONB NOT NULL DEFAULT '{}',
      lat DECIMAL(10,8),
      lng DECIMAL(11,8),
      osm_id BIGINT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_canonical_cities_coords 
    ON canonical_cities(lat, lng) 
    WHERE lat IS NOT NULL AND lng IS NOT NULL;
  `);

  const cacheCheck = await pool.query(`
    SELECT column_name 
    FROM information_schema.columns 
    WHERE table_name = 'geocode_cache' 
    ORDER BY ordinal_position
  `).catch(() => ({ rows: [] }));

  const existingColumns = cacheCheck.rows.map(r => r.column_name);
  const requiredColumns = ['query_hash', 'query_text', 'lang', 'result_json', 'created_at'];
  const hasAllColumns = requiredColumns.every(col => existingColumns.includes(col));

  if (existingColumns.length > 0 && !hasAllColumns) {
    console.log('⚠️  geocode_cache has old schema, recreating...');
    await pool.query(`DROP TABLE IF EXISTS geocode_cache_backup`);
    await pool.query(`ALTER TABLE geocode_cache RENAME TO geocode_cache_backup`);
    console.log('✅ Old geocode_cache backed up to geocode_cache_backup');
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS geocode_cache (
      query_hash VARCHAR(64) PRIMARY KEY,
      query_text VARCHAR(500),
      lang VARCHAR(10),
      result_json JSONB NOT NULL DEFAULT '{}',
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_geocode_cache_created 
    ON geocode_cache(created_at);
  `);

  // Safe ALTER TABLEs — tables are guaranteed to exist now
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='city_id') THEN
        ALTER TABLE stores ADD COLUMN city_id VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='country_code') THEN
        ALTER TABLE stores ADD COLUMN country_code VARCHAR(2);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='location_description') THEN
        ALTER TABLE stores ADD COLUMN location_description VARCHAR(200);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='village') THEN
        ALTER TABLE stores ADD COLUMN village VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='is_sponsored') THEN
        ALTER TABLE stores ADD COLUMN is_sponsored BOOLEAN DEFAULT FALSE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='sponsorship_tier') THEN
        ALTER TABLE stores ADD COLUMN sponsorship_tier INTEGER DEFAULT 1;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='sponsorship_expires_at') THEN
        ALTER TABLE stores ADD COLUMN sponsorship_expires_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='image_url') THEN
        ALTER TABLE stores ADD COLUMN image_url TEXT;
      END IF;
    END $$;
  `);
  console.log('✅ Location tables initialized');
}

module.exports = {
  slugify,
  nominatimFetch,
  findCanonicalCityByCoords,
  fetchEnglishPlaceDetails,
  createCanonicalCity,
  reverseGeocodeLogic,
  initLocationTables
};
