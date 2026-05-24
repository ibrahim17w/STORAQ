// server.js
require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const multer = require('multer');
const path = require('path');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const nodemailer = require('nodemailer');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const app = express();

const PORT = process.env.PORT || 3000;
const genAI = process.env.GEMINI_API_KEY ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY) : null;

// ==================== LOCATION SYSTEM (Canonical IDs) ====================
let transliterate;
try {
  transliterate = require('transliteration').transliterate;
} catch (_) {
  transliterate = (s) => s;
}

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

async function nominatimFetch(url) {
  await new Promise(r => setTimeout(r, 1100));
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'MarketBridge/1.0 (contact@marketbridge.app)',
    },
  });
  if (!res.ok) throw new Error(`Nominatim HTTP ${res.status}`);
  return res.json();
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
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_geocode_cache_created 
    ON geocode_cache(created_at);
  `);
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
    END $$;
  `);
  console.log('✅ Location tables initialized');
}

// ==================== NEW: INVENTORY & CHECKOUT TABLES ====================
async function initInventoryTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS categories (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      icon VARCHAR(50),
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='barcode') THEN
        ALTER TABLE products ADD COLUMN barcode VARCHAR(50) UNIQUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='category_id') THEN
        ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES categories(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='images') THEN
        ALTER TABLE products ADD COLUMN images JSONB DEFAULT '[]';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='low_stock_threshold') THEN
        ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER DEFAULT 5;
      END IF;
    END $$;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      receipt_number VARCHAR(50) NOT NULL UNIQUE,
      total DECIMAL(12,2) NOT NULL DEFAULT 0,
      status VARCHAR(20) DEFAULT 'completed',
      payment_method VARCHAR(20) DEFAULT 'cash',
      notes TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS order_items (
      id SERIAL PRIMARY KEY,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id),
      quantity INTEGER NOT NULL,
      unit_price DECIMAL(12,2) NOT NULL,
      total_price DECIMAL(12,2) NOT NULL
    );
  `);

  // Seed default categories (idempotent)
  const categories = [
    { name: 'General', icon: 'category' },
    { name: 'Food & Beverages', icon: 'restaurant' },
    { name: 'Clothing & Apparel', icon: 'checkroom' },
    { name: 'Electronics', icon: 'devices' },
    { name: 'Home & Garden', icon: 'home' },
    { name: 'Health & Beauty', icon: 'healing' },
    { name: 'Toys & Games', icon: 'toys' },
    { name: 'Automotive', icon: 'directions_car' },
    { name: 'Books & Stationery', icon: 'menu_book' },
    { name: 'Sports & Outdoors', icon: 'sports' }
  ];
  for (const cat of categories) {
    await pool.query(
      `INSERT INTO categories (name, icon) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [cat.name, cat.icon]
    );
  }

  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_orders_store ON orders(store_id);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_orders_receipt ON orders(receipt_number);`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);`);

  console.log('✅ Inventory tables initialized');
}
// ==================== END INVENTORY TABLES ====================

// ==================== EMAIL TRANSPORT ====================
let transporter = null;
let emailReady = false;

if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '587'),
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  emailReady = true;
}

async function sendEmail({ from, to, subject, html }) {
  const sender = from || process.env.FROM_EMAIL || process.env.SMTP_USER;
  if (!emailReady || !transporter) {
    throw new Error('SMTP not configured. Check .env file.');
  }
  return await transporter.sendMail({ from: sender, to, subject, html });
}

if (emailReady) {
  transporter.verify((err, success) => {
    if (err) console.error('❌ SMTP connection failed:', err.message);
    else console.log('✅ SMTP Ready (Gmail)');
  });
} else {
  console.warn('⚠️ No SMTP configured. Set SMTP_HOST, SMTP_USER, SMTP_PASS in .env');
}

// ==================== HELPERS / MIDDLEWARE ====================
function getBaseUrl(req) {
  const forwardedProto = req.headers['x-forwarded-proto'];
  const forwardedHost = req.headers['x-forwarded-host'];
  if (forwardedProto && forwardedHost) {
    return `${forwardedProto}://${forwardedHost}`;
  }
  return process.env.BASE_URL || `http://localhost:${PORT}`;
}

app.use(cors({
  origin: ['http://localhost:3000'],
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use('/uploads', express.static('uploads'));

const authLimiter = rateLimit({
 windowMs: 15 * 60 * 1000,
 max: 20,
 standardHeaders: true,
 legacyHeaders: false,
 handler: (req, res) => res.status(429).json({ error: 'Too many requests. Please try again later.' }),
});
app.use('/api/auth/', authLimiter);

const loginIpLimiter = rateLimit({
 windowMs: 15 * 60 * 1000,
 max: 5,
 skipSuccessfulRequests: true,
 standardHeaders: true,
 legacyHeaders: false,
 handler: (req, res) => res.status(429).json({
 error: 'Too many login attempts from this device. Please try again in 15 minutes.'
 }),
});

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
});

const authenticateToken = (req, res, next) => {
 const authHeader = req.headers['authorization'];
 const token = authHeader && authHeader.split(' ')[1];
 if (!token) return res.sendStatus(401);
 jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
 if (err) return res.sendStatus(403);
 req.user = user;
 next();
 });
};

const optionalAuth = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) { req.user = null; return next(); }
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) req.user = null;
    else req.user = user;
    next();
  });
};

const requireRealUser = (req, res, next) => {
 authenticateToken(req, res, () => {
   if (req.user.role === 'guest') {
     return res.status(403).json({ error: 'Please log in or create an account to access this feature.' });
   }
   next();
 });
};

// ==================== HELPERS ====================
function sanitizeString(str, maxLen = 255) {
 if (typeof str !== 'string') return '';
 return str.trim().substring(0, maxLen);
}

function isValidEmail(email) {
 return /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/.test(email);
}

async function serverNow() {
 const result = await pool.query('SELECT NOW() as now');
 return new Date(result.rows[0].now);
}

function validatePasswordStrength(pwd) {
 if (!pwd || pwd.length < 8) return { valid: false, error: 'Password must be at least 8 characters' };

 let score = 0;
 if (pwd.length >= 8) score++;
 if (pwd.length >= 12) score++;
 if (pwd.length >= 16) score++;
 if (/[A-Z]/.test(pwd)) score++;
 if (/[a-z]/.test(pwd)) score++;
 if (/[0-9]/.test(pwd)) score++;
 if (/[^A-Za-z0-9]/.test(pwd)) score++;

 const lowerPwd = pwd.toLowerCase();
 const seqNums = ['012','123','234','345','456','567','678','789','890'];
 for (const seq of seqNums) if (pwd.includes(seq)) { score -= 2; break; }

 const seqLet = ['abc','bcd','cde','def','efg','fgh','ghi','hij','ijk','jkl','klm','lmn','mno','nop','opq','pqr','qrs','rst','stu','tuv','uvw','vwx','wxy','xyz'];
 for (const seq of seqLet) if (lowerPwd.includes(seq)) { score -= 2; break; }

 if (pwd.length >= 6) {
 for (let i = 0; i <= pwd.length - 6; i++) {
 const chunk = pwd.substring(i, i + 3);
 if (pwd.substring(i + 3).includes(chunk)) { score -= 2; break; }
 }
 }

 const weakPatterns = ['qwerty','asdf','zxcv','password','letmein','admin','123456','111111','000000'];
 for (const pattern of weakPatterns) if (lowerPwd.includes(pattern)) { score -= 3; break; }

 const typeCount = [/^[A-Z]/.test('A') ? /[A-Z]/.test(pwd) : false, /[a-z]/.test(pwd), /[0-9]/.test(pwd), /[^A-Za-z0-9]/.test(pwd)].filter(Boolean).length;
 if (typeCount < 3) score -= 1;

 if (score <= 2) return { valid: false, error: 'Password is too weak. Use 8+ chars with uppercase, lowercase, number, and symbol. Avoid patterns like 123, abc, or repeated words.' };
 if (score <= 4) return { valid: false, error: 'Password is medium strength. Make it stronger with more variety and length.' };
 return { valid: true };
}

async function checkLoginLockout(email) {
 const result = await pool.query(
 'SELECT count, locked_until FROM failed_logins WHERE email = $1',
 [email]
 );

 if (result.rows.length === 0) return { allowed: true, waitMin: 0 };

 const row = result.rows[0];
 const now = await serverNow();

 if (row.locked_until && new Date(row.locked_until) > now) {
 const waitMs = new Date(row.locked_until) - now;
 const waitMin = Math.ceil(waitMs / 60000);
 return { allowed: false, waitMin };
 }

 return { allowed: true, waitMin: 0 };
}

async function recordFailedLogin(email) {
 const now = await serverNow();
 const lock2h   = new Date(now.getTime() + 2 * 60 * 60 * 1000);
 const lock30m  = new Date(now.getTime() + 30 * 60 * 1000);
 const lock5m   = new Date(now.getTime() + 5 * 60 * 1000);

 const result = await pool.query(
   `INSERT INTO failed_logins (email, count, locked_until, last_attempt)
    VALUES ($1, 1, NULL, $2)
    ON CONFLICT (email) DO UPDATE SET
      count = failed_logins.count + 1,
      last_attempt = $2,
      locked_until = CASE
        WHEN failed_logins.count + 1 >= 15 THEN $3
        WHEN failed_logins.count + 1 >= 10 THEN $4
        WHEN failed_logins.count + 1 >= 5  THEN $5
        ELSE failed_logins.locked_until
      END
    RETURNING count, locked_until`,
   [email, now, lock2h, lock30m, lock5m]
 );

 return result.rows[0];
}

async function clearLoginAttempts(email) {
 await pool.query('DELETE FROM failed_logins WHERE email = $1', [email]);
}

async function checkOtpRateLimit(email) {
  const now = await serverNow();
  const sixtySecondsAgo = new Date(now.getTime() - 60 * 1000);
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

  const cooldownResult = await pool.query(
    `SELECT MAX(created_at) as last FROM verification_codes
     WHERE email = $1 AND created_at > $2`,
    [email, sixtySecondsAgo]
  );
  const lastAttempt = cooldownResult.rows[0].last ? new Date(cooldownResult.rows[0].last) : null;
  if (lastAttempt) {
    const secondsSinceLast = (now - lastAttempt) / 1000;
    if (secondsSinceLast < 60) {
      const waitSeconds = Math.ceil(60 - secondsSinceLast);
      return { allowed: false, waitSeconds, reason: 'cooldown' };
    }
  }

  const hourResult = await pool.query(
    `SELECT COUNT(*) as c FROM verification_codes
     WHERE email = $1 AND created_at > $2`,
    [email, oneHourAgo]
  );
  const count = parseInt(hourResult.rows[0].c);
  if (count >= 5) {
    return { allowed: false, waitSeconds: 3600, reason: 'hourly_limit' };
  }

  return { allowed: true };
}

function generateOtp() {
 return crypto.randomInt(100000, 999999).toString();
}

async function storeOtp(email, type, code) {
 const now = await serverNow();
 const expires = new Date(now.getTime() + 10 * 60 * 1000);
 const codeHash = await bcrypt.hash(code, 10);

 const client = await pool.connect();
 try {
   await client.query('BEGIN');
   await client.query(
     `UPDATE verification_codes SET used = TRUE, invalidated_at = $1
      WHERE email = $2 AND type = $3 AND used = FALSE`,
     [now, email, type]
   );
   await client.query(
     `INSERT INTO verification_codes (email, type, code_hash, expires_at, created_at, attempts, used)
      VALUES ($1, $2, $3, $4, $5, 0, FALSE)`,
     [email, type, codeHash, expires, now]
   );
   await client.query('COMMIT');
 } catch (err) {
   await client.query('ROLLBACK');
   throw err;
 } finally {
   client.release();
 }
}

async function verifyOtp(email, type, inputCode) {
 const now = await serverNow();

 const result = await pool.query(
   `SELECT id, code_hash, attempts, used, expires_at
    FROM verification_codes
    WHERE email = $1 AND type = $2 AND used = FALSE AND expires_at > $3
    ORDER BY created_at DESC LIMIT 1`,
   [email, type, now]
 );

 if (result.rows.length === 0) {
   return { valid: false, error: 'invalid_or_expired' };
 }

 const record = result.rows[0];

 if (record.attempts >= 3) {
   await pool.query(
     'UPDATE verification_codes SET used = TRUE WHERE id = $1',
     [record.id]
   );
   return { valid: false, error: 'too_many_attempts' };
 }

 await pool.query(
   'UPDATE verification_codes SET attempts = attempts + 1 WHERE id = $1',
   [record.id]
 );

 const isMatch = await bcrypt.compare(inputCode, record.code_hash);

 if (!isMatch) {
   const updated = await pool.query(
     'SELECT attempts FROM verification_codes WHERE id = $1',
     [record.id]
   );
   if (updated.rows[0].attempts >= 3) {
     await pool.query(
       'UPDATE verification_codes SET used = TRUE WHERE id = $1',
       [record.id]
     );
     return { valid: false, error: 'too_many_attempts' };
   }
   return { valid: false, error: 'invalid_code' };
 }

 await pool.query(
   'UPDATE verification_codes SET used = TRUE, verified_at = $1 WHERE id = $2',
   [now, record.id]
 );

 return { valid: true };
}

function formatWaitTime(totalSeconds) {
  if (totalSeconds <= 0) return '0 seconds';
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  if (mins === 0) return `${secs} second${secs !== 1 ? 's' : ''}`;
  if (secs === 0) return `${mins} minute${mins !== 1 ? 's' : ''}`;
  return `${mins} minute${mins !== 1 ? 's' : ''} ${secs} second${secs !== 1 ? 's' : ''}`;
}

// ==================== EMAIL TEMPLATES ====================
function emailHtml({ title, subtitle, bodyContent, btnText, btnUrl, code, lang }) {
 const isRTL = ['ar','ur','he','fa'].includes(lang);
 const dir = isRTL ? 'rtl' : 'ltr';

 return `
<!DOCTYPE html>
<html lang="${lang}" dir="${dir}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);margin:0;padding:40px 20px;color:#333;direction:${dir};min-height:100vh;box-sizing:border-box;}
.wrapper{max-width:600px;margin:0 auto;}
.container{background:#fff;padding:40px;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,0.3);text-align:center;}
.logo{font-size:32px;font-weight:800;color:#667eea;margin-bottom:8px;}
.tagline{font-size:14px;color:#888;margin-bottom:30px;}
h1{color:#2c3e50;font-size:26px;margin:0 0 8px 0;}
h2{color:#555;font-size:17px;margin:0 0 20px 0;font-weight:400;}
p{line-height:1.7;font-size:16px;color:#555;margin:0 0 20px 0;}
.btn{display:inline-block;padding:14px 32px;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;text-decoration:none;border-radius:8px;font-weight:600;font-size:16px;margin:10px 0;transition:transform 0.2s;}
.btn:hover{transform:translateY(-2px);}
.code-box{background:linear-gradient(135deg,#f5f7fa 0%,#e4e8ec 100%);border:2px dashed #667eea;border-radius:12px;padding:24px;margin:20px 0;display:inline-block;min-width:200px;}
.code{font-size:36px;font-weight:800;letter-spacing:8px;color:#667eea;font-family:'Courier New',monospace;}
.code-label{font-size:12px;color:#888;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px;}
.timer{font-size:13px;color:#e74c3c;margin-top:8px;font-weight:500;}
.divider{height:1px;background:#e0e0e0;margin:24px 0;}
.footer{margin-top:30px;font-size:12px;color:#999;line-height:1.6;}
.security-tips{background:#f8f9fa;border-radius:8px;padding:16px;margin-top:20px;text-align:${isRTL ? 'right' : 'left'};}
.security-tips h3{font-size:13px;color:#555;margin:0 0 8px 0;text-transform:uppercase;letter-spacing:1px;}
.security-tips ul{margin:0;padding-${isRTL ? 'right' : 'left'}:20px;font-size:12px;color:#777;}
.security-tips li{margin-bottom:4px;}
</style>
</head>
<body>
<div class="wrapper">
<div class="container">
<div class="logo">🔗 Market Bridge</div>
<div class="tagline">${subtitle}</div>
<h1>${title}</h1>
<p>${bodyContent}</p>
${btnUrl ? `<a href="${btnUrl}" class="btn">${btnText}</a>` : ''}
${code ? `<div class="code-box"><div class="code-label">${isRTL ? 'رمز التحقق' : (lang === 'zh' ? '验证码' : (lang === 'ru' ? 'Код подтверждения' : 'Verification Code'))}</div><div class="code">${code}</div><div class="timer">⏱ ${isRTL ? 'ينتهي خلال 10 دقائق' : (lang === 'zh' ? '10分钟后过期' : (lang === 'ru' ? 'Истекает через 10 минут' : 'Expires in 10 minutes'))}</div></div>` : ''}
<div class="divider"></div>
<div class="security-tips">
<h3>${isRTL ? 'نصائح الأمان' : (lang === 'zh' ? '安全提示' : (lang === 'ru' ? 'Советы безопасности' : 'Security Tips'))}</h3>
<ul>
<li>${isRTL ? 'لا تشارك هذا الرمز مع أي شخص' : (lang === 'zh' ? '请勿与任何人分享此验证码' : (lang === 'ru' ? 'Никому не сообщайте этот код' : 'Never share this code with anyone'))}</li>
<li>${isRTL ? 'سيتم إلغاء الرمز بعد 3 محاولات خاطئة' : (lang === 'zh' ? '3次错误尝试后代码将失效' : (lang === 'ru' ? 'Код будет отменен после 3 неудачных попыток' : 'Code will be cancelled after 3 wrong attempts'))}</li>
<li>${isRTL ? 'إذا لم تطلب هذا، يمكنك تجاهل البريد بأمان' : (lang === 'zh' ? '如果您没有请求此操作，可以安全忽略此邮件' : (lang === 'ru' ? 'Если вы не запрашивали это, просто проигнорируйте письмо' : 'If you didn\'t request this, you can safely ignore this email'))}</li>
</ul>
</div>
<div class="footer">
${isRTL ? 'إذا لم تطلب هذا، يمكنك تجاهل البريد بأمان.' : (lang === 'zh' ? '如果您没有请求此操作，可以安全忽略此邮件。' : (lang === 'ru' ? 'Если вы не запрашивали это, просто проигнорируйте письмо.' : 'If you didn\'t request this, you can safely ignore this email.'))}<br>
© ${new Date().getFullYear()} Market Bridge. ${isRTL ? 'جميع الحقوق محفوظة.' : (lang === 'zh' ? '保留所有权利。' : (lang === 'ru' ? 'Все права защищены.' : 'All rights reserved.'))}
</div>
</div>
</div>
</body>
</html>
`;
}

const emailTexts = {
 en: {
   verifySubject: 'Verify your Market Bridge account',
   verifySubtitle: 'Welcome aboard!',
   verifyBody: 'Thank you for joining Market Bridge! Please enter the verification code below in your app to verify your email address and activate your account.',
   verifyBtn: null,
   resetSubject: 'Your password reset code',
   resetSubtitle: 'Password Reset Request',
   resetBody: 'We received a request to reset your password. Use the code below to complete the process.',
   resetBtn: null,
 },
 ar: {
   verifySubject: 'تأكيد حسابك على Market Bridge',
   verifySubtitle: 'مرحباً بك!',
   verifyBody: 'شكراً لانضمامك إلى Market Bridge! أدخل رمز التحقق أدناه في التطبيق لتأكيد بريدك الإلكتروني وتفعيل حسابك.',
   verifyBtn: null,
   resetSubject: 'رمز إعادة تعيين كلمة المرور',
   resetSubtitle: 'طلب إعادة تعيين كلمة المرور',
   resetBody: 'تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بك. استخدم الرمز أدناه لإكمال العملية.',
   resetBtn: null,
 },
 fr: {
   verifySubject: 'Vérifiez votre compte Market Bridge',
   verifySubtitle: 'Bienvenue !',
   verifyBody: 'Merci d\'avoir rejoint Market Bridge ! Saisissez le code de vérification ci-dessous dans votre application pour vérifier votre adresse e-mail et activer votre compte.',
   verifyBtn: null,
   resetSubject: 'Votre code de réinitialisation',
   resetSubtitle: 'Demande de réinitialisation',
   resetBody: 'Nous avons reçu une demande de réinitialisation de votre mot de passe. Utilisez le code ci-dessous pour compléter le processus.',
   resetBtn: null,
 },
 es: {
   verifySubject: 'Verifica tu cuenta de Market Bridge',
   verifySubtitle: '¡Bienvenido!',
   verifyBody: '¡Gracias por unirte a Market Bridge! Introduce el código de verificación a continuación en tu aplicación para verificar tu correo y activar tu cuenta.',
   verifyBtn: null,
   resetSubject: 'Tu código de restablecimiento',
   resetSubtitle: 'Solicitud de restablecimiento',
   resetBody: 'Recibimos una solicitud para restablecer tu contraseña. Usa el código de abajo para completar el proceso.',
   resetBtn: null,
 },
 tr: {
   verifySubject: 'Market Bridge hesabınızı doğrulayın',
   verifySubtitle: 'Hoş geldiniz!',
   verifyBody: 'Market Bridge\'e katıldığınız için teşekkürler! E-posta adresinizi doğrulamak ve hesabınızı etkinleştirmek için uygulamaya aşağıdaki doğrulama kodunu girin.',
   verifyBtn: null,
   resetSubject: 'Şifre sıfırlama kodunuz',
   resetSubtitle: 'Şifre Sıfırlama Talebi',
   resetBody: 'Şifrenizi sıfırlama talebi aldık. İşlemi tamamlamak için aşağıdaki kodu kullanın.',
   resetBtn: null,
 },
 ur: {
   verifySubject: 'Market Bridge اکاؤنٹ کی تصدیق',
   verifySubtitle: 'خوش آمدید!',
   verifyBody: 'Market Bridge میں شامل ہونے کا شکریہ! اپنا ای میل تصدیق کرنے اور اکاؤنٹ فعال کرنے کے لیے ایپ میں نیچے دیا گیا تصدیقی کوڈ درج کریں۔',
   verifyBtn: null,
   resetSubject: 'پاس ورڈ ری سیٹ کوڈ',
   resetSubtitle: 'پاس ورڈ ری سیٹ کی درخواست',
   resetBody: 'ہمیں آپ کا پاس ورڈ ری سیٹ کرنے کی درخواست موصول ہوئی ہے۔ عمل مکمل کرنے کے لیے نیچے دیا گیا کوڈ استعمال کریں۔',
   resetBtn: null,
 },
 hi: {
   verifySubject: 'अपना Market Bridge खाता सत्यापित करें',
   verifySubtitle: 'स्वागत है!',
   verifyBody: 'Market Bridge में शामिल होने के लिए धन्यवाद! अपना ईमेल सत्यापित करने और खाता सक्रिय करने के लिए ऐप में नीचे दिया गया सत्यापन कोड दर्ज करें।',
   verifyBtn: null,
   resetSubject: 'आपका पासवर्ड रीसेट कोड',
   resetSubtitle: 'पासवर्ड रीसेट अनुरोध',
   resetBody: 'हमें आपका पासवर्ड रीसेट करने का अनुरोध प्राप्त हुआ। प्रक्रिया पूरी करने के लिए नीचे दिए कोड का उपयोग करें।',
   resetBtn: null,
 },
 bn: {
   verifySubject: 'আপনার Market Bridge অ্যাকাউন্ট যাচাই করুন',
   verifySubtitle: 'স্বাগতম!',
   verifyBody: 'Market Bridge-এ যোগ দেওয়ার জন্য ধন্যবাদ! আপনার ইমেইল যাচাই করতে এবং অ্যাকাউন্ট সক্রিয় করতে অ্যাপে নীচের যাচাইকরণ কোডটি লিখুন।',
   verifyBtn: null,
   resetSubject: 'আপনার পাসওয়ার্ড রিসেট কোড',
   resetSubtitle: 'পাসওয়ার্ড রিসেট অনুরোধ',
   resetBody: 'আমরা আপনার পাসওয়ার্ড রিসেট করার অনুরোধ পেয়েছি। প্রক্রিয়া সম্পূর্ণ করতে নীচের কোডটি ব্যবহার করুন।',
   resetBtn: null,
 },
 ru: {
   verifySubject: 'Подтвердите аккаунт Market Bridge',
   verifySubtitle: 'Добро пожаловать!',
   verifyBody: 'Спасибо за регистрацию в Market Bridge! Введите код подтверждения ниже в приложении, чтобы подтвердить адрес электронной почты и активировать аккаунт.',
   verifyBtn: null,
   resetSubject: 'Код сброса пароля',
   resetSubtitle: 'Запрос на сброс пароля',
   resetBody: 'Мы получили запрос на сброс вашего пароля. Используйте код ниже для завершения процесса.',
   resetBtn: null,
 },
 zh: {
   verifySubject: '验证您的 Market Bridge 账户',
   verifySubtitle: '欢迎！',
   verifyBody: '感谢加入 Market Bridge！请在应用中输入下方的验证码以验证您的电子邮件地址并激活账户。',
   verifyBtn: null,
   resetSubject: '您的密码重置验证码',
   resetSubtitle: '密码重置请求',
   resetBody: '我们收到了重置您密码的请求。请使用下方验证码完成操作。',
   resetBtn: null,
 },
};

function getLang(userLang) {
 return emailTexts[userLang] ? userLang : 'en';
}

const storage = multer.diskStorage({
 destination: (req, file, cb) => cb(null, 'uploads/'),
 filename: (req, file, cb) => {
 const unique = Date.now() + '-' + Math.round(Math.random() * 1e9);
 cb(null, unique + path.extname(file.originalname));
 },
});
const upload = multer({
 storage,
 limits: { fileSize: 5 * 1024 * 1024 },
 fileFilter: (req, file, cb) => {
 const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
 const allowedExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
 const ext = path.extname(file.originalname).toLowerCase();

 const isAllowedType = allowedTypes.includes(file.mimetype);
 const isAllowedExt = allowedExts.includes(ext);
 const isOctetStream = file.mimetype === 'application/octet-stream';

 if (isAllowedType || (isOctetStream && isAllowedExt)) {
 cb(null, true);
 } else {
 cb(new Error(`Unsupported file type (${file.mimetype || 'unknown'}). Only JPEG, PNG, WebP, and GIF images are allowed.`));
 }
 }
});

app.get('/', (req, res) => res.send('Market Bridge API'));

// Product image upload supports main + extras
const productUpload = upload.fields([
  { name: 'image', maxCount: 1 },
  { name: 'extra_images', maxCount: 5 }
]);

// ==================== GEOCODING ENDPOINTS ====================
app.get('/api/geocode/search', async (req, res) => {
  try {
    const query = sanitizeString(req.query.q, 200);
    const lang = sanitizeString(req.query.lang, 10) || 'en';
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

app.get('/api/geocode/reverse', async (req, res) => {
  try {
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const lang = sanitizeString(req.query.lang, 10) || 'en';
    if (isNaN(lat) || isNaN(lng)) return res.status(400).json({ error: 'lat and lng query params are required' });

    const result = await reverseGeocodeLogic(lat, lng, lang);
    if (!result) return res.status(404).json({ error: 'No location found' });
    res.json(result);
  } catch (err) {
    console.error('Reverse geocode error:', err);
    res.status(500).json({ error: 'Geocoding service unavailable' });
  }
});

app.post('/api/admin/migrate-locations', authenticateToken, async (req, res) => {
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
// ==================== END GEOCODING ====================

// ==================== IMAGE SEARCH ====================
app.post('/api/search/image', optionalAuth, async (req, res) => {
  try {
    if (!genAI) {
      return res.status(503).json({ error: 'Image search not configured. Set GEMINI_API_KEY in .env' });
    }

    const { image, mimeType } = req.body;
    if (!image || !mimeType) {
      return res.status(400).json({ error: 'image (base64) and mimeType are required' });
    }

    const allowedMime = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
    if (!allowedMime.includes(mimeType)) {
      return res.status(400).json({ error: `Unsupported mimeType ${mimeType}. Use image/jpeg, image/png, image/webp, or image/gif.` });
    }

    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });
    const result = await model.generateContent([
      'Describe the main product in this image in 2-4 words suitable for a marketplace search query. Return ONLY the search query text, nothing else.',
      { inlineData: { mimeType, data: image } },
    ]);

    let query = null;
    try {
      const response = result.response;
      if (response && typeof response.text === 'function') {
        query = response.text()?.trim();
      } else if (response && response.candidates && response.candidates[0]?.content?.parts?.[0]?.text) {
        query = response.candidates[0].content.parts[0].text.trim();
      }
    } catch (parseErr) {
      console.error('Gemini response parse error:', parseErr.message);
    }

    if (!query) {
      return res.status(422).json({ error: 'Could not identify product in image' });
    }

    res.json({ query });
  } catch (err) {
    console.error('Image search error:', err);
    res.status(500).json({ error: err.message || 'Image search failed. Please try again.' });
  }
});
// ==================== END IMAGE SEARCH ====================

// ==================== CATEGORIES ====================
app.get('/api/categories', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM categories ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to load categories' });
  }
});
// ==================== END CATEGORIES ====================

// ==================== BARCODE LOOKUP ====================
app.get('/api/products/barcode/:barcode', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store found' });
    const storeId = storeResult.rows[0].id;

    const result = await pool.query(
      'SELECT * FROM products WHERE barcode=$1 AND store_id=$2',
      [req.params.barcode, storeId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Barcode lookup failed' });
  }
});

app.get('/api/products/check-barcode', requireRealUser, async (req, res) => {
  try {
    const barcode = req.query.barcode;
    const excludeId = req.query.exclude_id;
    if (!barcode) return res.status(400).json({ error: 'Barcode required' });

    let sql = 'SELECT id, name FROM products WHERE barcode=$1';
    const params = [barcode];
    if (excludeId) {
      sql += ' AND id != $2';
      params.push(excludeId);
    }
    const result = await pool.query(sql, params);
    res.json({ exists: result.rows.length > 0, product: result.rows[0] || null });
  } catch (err) {
    res.status(500).json({ error: 'Barcode check failed' });
  }
});
// ==================== END BARCODE ====================

// ==================== CHECKOUT & ORDERS ====================
app.post('/api/checkout', requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const storeResult = await client.query(
      'SELECT id, name, city, country, phone, image_url FROM stores WHERE owner_id=$1',
      [req.user.userId]
    );
    if (storeResult.rows.length === 0) throw new Error('No store found');
    const store = storeResult.rows[0];

    const { items, payment_method, notes } = req.body;
    if (!items || !Array.isArray(items) || items.length === 0) {
      throw new Error('Cart is empty');
    }

    const now = await serverNow();
    const dateStr = now.toISOString().slice(0,10).replace(/-/g,'');
    const randomSuffix = Math.floor(1000 + Math.random() * 9000);
    const receiptNumber = `MB-${dateStr}-${randomSuffix}`;

    let total = 0;
    const validatedItems = [];

    for (const item of items) {
      const product = await client.query(
        'SELECT id, name, price, quantity FROM products WHERE id=$1 AND store_id=$2 FOR UPDATE',
        [item.product_id, store.id]
      );
      if (product.rows.length === 0) throw new Error(`Product not found`);
      if (product.rows[0].quantity < item.quantity) {
        throw new Error(`Insufficient stock for "${product.rows[0].name}". Available: ${product.rows[0].quantity}, Requested: ${item.quantity}`);
      }

      const unitPrice = parseFloat(product.rows[0].price);
      const itemTotal = unitPrice * item.quantity;
      total += itemTotal;

      validatedItems.push({
        product_id: item.product_id,
        quantity: item.quantity,
        unit_price: unitPrice,
        total_price: itemTotal,
        product_name: product.rows[0].name
      });
    }

    const orderResult = await client.query(
      `INSERT INTO orders (store_id, receipt_number, total, status, payment_method, notes)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [store.id, receiptNumber, total, 'completed', payment_method || 'cash', notes || null]
    );
    const order = orderResult.rows[0];

    for (const item of validatedItems) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
         VALUES ($1,$2,$3,$4,$5)`,
        [order.id, item.product_id, item.quantity, item.unit_price, item.total_price]
      );
      await client.query(
        'UPDATE products SET quantity = quantity - $1 WHERE id = $2',
        [item.quantity, item.product_id]
      );
    }

    await client.query('COMMIT');

    const itemsResult = await pool.query(
      `SELECT oi.*, p.name as product_name, p.barcode
       FROM order_items oi
       JOIN products p ON oi.product_id = p.id
       WHERE oi.order_id=$1`,
      [order.id]
    );

    res.status(201).json({
      order: { ...order, store_name: store.name },
      items: itemsResult.rows
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Checkout error:', err);
    res.status(400).json({ error: err.message || 'Checkout failed' });
  } finally {
    client.release();
  }
});

app.get('/api/orders', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });

    const result = await pool.query(
      `SELECT o.*,
        (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) as item_count
       FROM orders o
       WHERE o.store_id=$1
       ORDER BY o.created_at DESC
       LIMIT 100`,
      [storeResult.rows[0].id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to load orders' });
  }
});

app.get('/api/orders/:id', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });
    const storeId = storeResult.rows[0].id;

    const orderResult = await pool.query(
      'SELECT * FROM orders WHERE id=$1 AND store_id=$2',
      [req.params.id, storeId]
    );
    if (orderResult.rows.length === 0) return res.status(404).json({ error: 'Order not found' });

    const itemsResult = await pool.query(
      `SELECT oi.*, p.name as product_name, p.barcode, p.image_url
       FROM order_items oi
       JOIN products p ON oi.product_id = p.id
       WHERE oi.order_id=$1`,
      [req.params.id]
    );

    res.json({ order: orderResult.rows[0], items: itemsResult.rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load order' });
  }
});
// ==================== END CHECKOUT & ORDERS ====================

// REGISTER
app.post('/api/auth/register', async (req, res) => {
 const client = await pool.connect();
 try {
 await client.query('BEGIN');

 const full_name = sanitizeString(req.body.full_name, 100);
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const phone = sanitizeString(req.body.phone, 50);
 const password = req.body.password;
 const role = req.body.role;
 const store = req.body.store;
 const preferred_language = sanitizeString(req.body.preferred_language, 10) || 'en';

 if (!isValidEmail(email)) {
   return res.status(400).json({ error: 'Please enter a valid email address.' });
 }

 const allowedRoles = ['store_owner', 'customer'];
 const userRole = allowedRoles.includes(role) ? role : 'customer';
 const lang = getLang(preferred_language);
 const hashedPassword = await bcrypt.hash(password, 10);

 const userResult = await client.query(
   'INSERT INTO users (full_name, email, phone, password_hash, role, email_verified, preferred_language) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, full_name, email, role',
   [full_name, email, phone, hashedPassword, userRole, false, lang]
 );

 if (userRole === 'store_owner' && store) {
   await client.query(
     'INSERT INTO stores (name, city, location_description, country, lat, lng, phone, owner_id, city_id, country_code) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
     [
       sanitizeString(store.name, 100),
       sanitizeString(store.city, 100),
       store.location_description ? sanitizeString(store.location_description, 200) : null,
       sanitizeString(store.country, 100) || 'Syria',
       store.lat,
       store.lng,
       sanitizeString(store.phone, 50),
       userResult.rows[0].id,
       store.city_id ? sanitizeString(store.city_id, 100) : null,
       store.country_code ? sanitizeString(store.country_code, 2).toLowerCase().substring(0, 2) : null
     ]
   );
 }
 await client.query('COMMIT');

 const code = generateOtp();
 await storeOtp(email, 'email_verification', code);

 res.status(201).json({ message: 'Created. Check email for verification code.', email });

 const texts = emailTexts[lang];
 (async () => {
   try {
     await sendEmail({
       from: process.env.FROM_EMAIL || process.env.SMTP_USER,
       to: email,
       subject: texts.verifySubject,
       html: emailHtml({ title: texts.verifySubject, subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody, btnText: texts.verifyBtn, btnUrl: null, code, lang }),
     });
     console.log('\n📧 VERIFY CODE for', email, ':', code, '(expires in 10 min)\n');
   } catch (e) {
     console.error('Email failed:', e.message);
   }
 })();
 } catch (err) {
 await client.query('ROLLBACK');
 if (err.code === '23505') return res.status(400).json({ error: 'This email is already registered. Please log in or use a different email.' });
 console.error(err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 } finally {
 client.release();
 }
});

// VERIFY EMAIL
app.post('/api/auth/verify-email', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const code = req.body.code;

 if (!email || !code) {
   return res.status(400).json({ error: 'Email and verification code are required.' });
 }

 const userResult = await pool.query('SELECT id, email_verified FROM users WHERE email = $1', [email]);
 if (userResult.rows.length === 0) {
   return res.status(400).json({ error: 'Invalid email address.' });
 }
 if (userResult.rows[0].email_verified) {
   return res.status(400).json({ error: 'This email is already verified. Please log in.' });
 }

 const otpResult = await verifyOtp(email, 'email_verification', code);
 if (!otpResult.valid) {
   if (otpResult.error === 'too_many_attempts') {
     return res.status(429).json({ error: 'Too many failed attempts. This verification code has been locked. Please request a new one.' });
   }
   if (otpResult.error === 'invalid_or_expired') {
     return res.status(400).json({ error: 'This code has expired or is no longer valid. Please request a new one.' });
   }
   return res.status(400).json({ error: 'Incorrect code. Please try again.' });
 }

 await pool.query('UPDATE users SET email_verified = TRUE WHERE email = $1', [email]);

 res.json({ message: '✅ Email verified successfully! You can now log in.' });
 } catch (err) {
 console.error('Verify email error:', err.message);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// RESEND VERIFICATION
app.post('/api/auth/resend-verification', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

 if (result.rows.length === 0) {
   return res.json({ message: 'If this email is registered, a verification code will be sent.' });
 }

 const user = result.rows[0];
 if (user.email_verified) {
   return res.json({ message: 'If this email is registered, a verification code will be sent.' });
 }

 const limit = await checkOtpRateLimit(email);
 if (!limit.allowed) {
   if (limit.reason === 'hourly_limit') {
     return res.status(429).json({ error: 'Too many verification attempts. Please try again in 1 hour.' });
   }
   return res.status(429).json({ error: `Please wait ${formatWaitTime(limit.waitSeconds)} before requesting another code.` });
 }

 const lang = getLang(user.preferred_language);
 const code = generateOtp();
 await storeOtp(email, 'email_verification', code);

 res.json({ message: 'If this email is registered, a verification code has been sent.' });

 const texts = emailTexts[lang];
 (async () => {
   try {
     await sendEmail({
       from: process.env.FROM_EMAIL || process.env.SMTP_USER,
       to: email,
       subject: texts.verifySubject,
       html: emailHtml({ title: texts.verifySubject, subtitle: texts.verifySubtitle, bodyContent: texts.verifyBody, btnText: texts.verifyBtn, btnUrl: null, code, lang }),
     });
     console.log('\n📧 RESEND VERIFY CODE for', email, ':', code, '(expires in 10 min)\n');
   } catch (e) {
     console.error('Email failed:', e.message);
   }
 })();
 } catch (err) {
 console.error('Resend verification error:', err.message);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// LOGIN
app.post('/api/auth/login', loginIpLimiter, async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const password = req.body.password;

 const lockout = await checkLoginLockout(email);
 if (!lockout.allowed) {
   return res.status(429).json({
     error: `Too many failed attempts. Please try again in ${lockout.waitMin} minutes.`
   });
 }

 const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);
 if (result.rows.length === 0) {
   return res.status(400).json({ error: 'Email or password is incorrect. Please try again.' });
 }

 const user = result.rows[0];

 const validPassword = await bcrypt.compare(password, user.password_hash);
 if (!validPassword) {
   const attempts = await recordFailedLogin(email);
   if (attempts.locked_until) {
     const now = await serverNow();
     const waitMin = Math.ceil((new Date(attempts.locked_until) - now) / 60000);
     return res.status(429).json({
       error: `Too many failed attempts. Account locked for ${waitMin} minutes.`
     });
   }
   return res.status(400).json({ error: 'Email or password is incorrect. Please try again.' });
 }

 if (!user.email_verified) {
   return res.status(403).json({ error: 'Please verify your email before logging in. Check your inbox for the verification code.' });
 }

 await clearLoginAttempts(email);

 const token = jwt.sign(
   { userId: user.id, email: user.email, role: user.role },
   process.env.JWT_SECRET,
   { expiresIn: '7d' }
 );
 res.json({
   token,
   user: {
     id: user.id,
     full_name: user.full_name,
     email: user.email,
     role: user.role
   }
 });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GUEST LOGIN
app.post('/api/auth/guest-login', async (req, res) => {
 try {
   const guestId = 'guest_' + crypto.randomBytes(16).toString('hex');
   const token = jwt.sign(
     { userId: guestId, email: null, role: 'guest' },
     process.env.JWT_SECRET,
     { expiresIn: '7d' }
   );
   res.json({
     token,
     user: {
       id: guestId,
       full_name: 'Guest',
       email: null,
       role: 'guest'
     }
   });
 } catch (err) {
   res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// FORGOT PASSWORD
app.post('/api/auth/forgot-password', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const result = await pool.query('SELECT * FROM users WHERE email=$1', [email]);

 if (result.rows.length === 0) {
   return res.json({ message: 'If this email is registered, a reset code will be sent.' });
 }

 const limit = await checkOtpRateLimit(email);
 if (!limit.allowed) {
   if (limit.reason === 'hourly_limit') {
     return res.status(429).json({ error: 'You\'ve requested too many reset codes. Please try again in 1 hour.' });
   }
   return res.status(429).json({ error: `Please wait ${formatWaitTime(limit.waitSeconds)} before requesting another code.` });
 }

 const user = result.rows[0];
 const lang = getLang(user.preferred_language);

 const code = generateOtp();
 await storeOtp(email, 'password_reset', code);

 res.json({ message: 'If this email is registered, a reset code has been sent.' });

 const texts = emailTexts[lang];
 (async () => {
   try {
     await sendEmail({
       from: process.env.FROM_EMAIL || process.env.SMTP_USER,
       to: email,
       subject: texts.resetSubject,
       html: emailHtml({ title: texts.resetSubject, subtitle: texts.resetSubtitle, bodyContent: texts.resetBody, btnText: null, btnUrl: null, code, lang }),
     });
     console.log('\n🔑 RESET CODE for', email, ':', code, '(expires in 10 min)\n');
   } catch (e) {
     console.error('❌ Reset email failed:', e.message);
   }
 })();
 } catch (err) {
 console.error('❌ Forgot password error:', err.message);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// RESET PASSWORD
app.post('/api/auth/reset-password', async (req, res) => {
 try {
 const email = sanitizeString(req.body.email, 255).toLowerCase();
 const code = req.body.code;
 const new_password = req.body.new_password;

 const strength = validatePasswordStrength(new_password);
 if (!strength.valid) {
   return res.status(400).json({ error: strength.error });
 }

 const otpResult = await verifyOtp(email, 'password_reset', code);
 if (!otpResult.valid) {
   if (otpResult.error === 'too_many_attempts') {
     return res.status(429).json({ error: 'Too many failed attempts. This code has been locked for your security. Please request a new reset code.' });
   }
   if (otpResult.error === 'invalid_or_expired') {
     return res.status(400).json({ error: 'This code has expired or is no longer valid. Please request a new one.' });
   }
   return res.status(400).json({ error: 'Incorrect code. Please try again.' });
 }

 const userResult = await pool.query('SELECT password_hash FROM users WHERE email=$1', [email]);
 if (userResult.rows.length > 0) {
   const isSamePassword = await bcrypt.compare(new_password, userResult.rows[0].password_hash);
   if (isSamePassword) {
     return res.status(400).json({ error: 'New password cannot be the same as your previous password. Please choose a different password.' });
   }
 }

 const hashed = await bcrypt.hash(new_password, 10);
 await pool.query('UPDATE users SET password_hash=$1 WHERE email=$2', [hashed, email]);

 res.json({ message: 'Your password has been updated. You can now log in.' });
 } catch (err) {
 console.error('❌ Reset password error:', err.message);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET CURRENT USER
app.get('/api/me', authenticateToken, async (req, res) => {
 const result = await pool.query(
 'SELECT id, full_name, email, phone, role, preferred_language, created_at FROM users WHERE id=$1',
 [req.user.userId]
 );
 if (result.rows.length === 0) return res.status(404).json({ error: 'Account not found' });
 res.json(result.rows[0]);
});

// UPDATE PROFILE
app.put('/api/me', requireRealUser, async (req, res) => {
 const full_name = sanitizeString(req.body.full_name, 100);
 const phone = sanitizeString(req.body.phone, 50);
 const result = await pool.query(
 'UPDATE users SET full_name=$1, phone=$2 WHERE id=$3 RETURNING id, full_name, email, phone, role, preferred_language, created_at',
 [full_name, phone, req.user.userId]
 );
 res.json(result.rows[0]);
});

// CHANGE PASSWORD
app.put('/api/me/password', requireRealUser, async (req, res) => {
 try {
 const { current_password, new_password } = req.body;
 if (!current_password || !new_password) {
   return res.status(400).json({ error: 'Current password and new password are required.' });
 }

 const strength = validatePasswordStrength(new_password);
 if (!strength.valid) {
   return res.status(400).json({ error: strength.error });
 }

 const user = await pool.query('SELECT password_hash FROM users WHERE id=$1', [req.user.userId]);
 if (!await bcrypt.compare(current_password, user.rows[0].password_hash)) {
   return res.status(400).json({ error: 'Current password is incorrect' });
 }
 const hashed = await bcrypt.hash(new_password, 10);
 await pool.query('UPDATE users SET password_hash=$1 WHERE id=$2', [hashed, req.user.userId]);
 res.json({ message: 'Password updated successfully' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// DELETE ACCOUNT
app.delete('/api/me', requireRealUser, async (req, res) => {
 const client = await pool.connect();
 try {
 await client.query('BEGIN');

 const storeResult = await client.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 for (const row of storeResult.rows) {
 await client.query('DELETE FROM products WHERE store_id=$1', [row.id]);
 }

 await client.query('DELETE FROM stores WHERE owner_id=$1', [req.user.userId]);

 const userResult = await client.query('SELECT email FROM users WHERE id=$1', [req.user.userId]);
 if (userResult.rows.length > 0) {
   const email = userResult.rows[0].email;
   await client.query('DELETE FROM failed_logins WHERE email=$1', [email]);
   await client.query('DELETE FROM password_resets WHERE email=$1', [email]);
   await client.query('DELETE FROM verification_codes WHERE email=$1', [email]);
 }
 await client.query('DELETE FROM product_views WHERE user_id=$1', [req.user.userId]);
 await client.query('DELETE FROM search_queries WHERE user_id=$1', [req.user.userId]);

 await client.query('DELETE FROM users WHERE id=$1', [req.user.userId]);
 await client.query('COMMIT');
 res.json({ message: 'Account deleted successfully' });
 } catch (err) {
 await client.query('ROLLBACK');
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 } finally {
 client.release();
 }
});

// TRACK PRODUCT VIEW
app.post('/api/products/:id/view', async (req, res) => {
 try {
 const productId = parseInt(req.params.id);
 if (isNaN(productId)) return res.status(400).json({ error: 'Invalid product ID' });

 await pool.query(
 'UPDATE products SET view_count = COALESCE(view_count, 0) + 1 WHERE id = $1',
 [productId]
 );

 const authHeader = req.headers['authorization'];
 if (authHeader) {
 const token = authHeader.split(' ')[1];
 try {
 const decoded = jwt.verify(token, process.env.JWT_SECRET);
 await pool.query(
 'INSERT INTO product_views (product_id, user_id, viewed_at) VALUES ($1, $2, NOW())',
 [productId, decoded.userId]
 );
 } catch (_) {}
 }

 res.json({ message: 'View tracked' });
 } catch (err) {
 console.error('Track view error:', err);
 res.status(500).json({ error: 'Something went wrong' });
 }
});

// TRACK SEARCH QUERY
app.post('/api/search/track', async (req, res) => {
 try {
 const query = sanitizeString(req.body.query, 200);
 if (!query || query.length < 2) {
 return res.status(400).json({ error: 'Query too short' });
 }

 const authHeader = req.headers['authorization'];
 let userId = null;
 if (authHeader) {
 const token = authHeader.split(' ')[1];
 try {
 const decoded = jwt.verify(token, process.env.JWT_SECRET);
 userId = decoded.userId;
 } catch (_) {}
 }

 await pool.query(
 'INSERT INTO search_queries (query, user_id, searched_at) VALUES ($1, $2, NOW())',
 [query.toLowerCase(), userId]
 );

 res.json({ message: 'Search tracked' });
 } catch (err) {
 console.error('Track search error:', err);
 res.status(500).json({ error: 'Something went wrong' });
 }
});

// GET TRENDING PRODUCTS
app.get('/api/products/trending', async (req, res) => {
 try {
 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.view_count,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
 LIMIT 20`
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Trending error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET SPONSORED STORES
app.get('/api/stores/sponsored', async (req, res) => {
 try {
 const now = await serverNow();
 const result = await pool.query(
 `SELECT id, name, city, country, image_url, lat, lng, sponsorship_tier
 FROM stores
 WHERE is_sponsored = TRUE
 AND (sponsorship_expires_at IS NULL OR sponsorship_expires_at > $1)
 ORDER BY sponsorship_tier DESC, RANDOM()
 LIMIT 10`,
 [now]
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Sponsored error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// GET PERSONALIZED RECOMMENDATIONS
app.get('/api/recommendations', requireRealUser, async (req, res) => {
 try {
 const userId = req.user.userId;
 const now = await serverNow();
 const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

 const viewsResult = await pool.query(
 `SELECT DISTINCT p.name, p.store_id
 FROM product_views pv
 JOIN products p ON pv.product_id = p.id
 WHERE pv.user_id = $1 AND pv.viewed_at > $2
 LIMIT 20`,
 [userId, sevenDaysAgo]
 );

 const searchesResult = await pool.query(
 `SELECT DISTINCT query FROM search_queries
 WHERE user_id = $1 AND searched_at > $2
 LIMIT 10`,
 [userId, sevenDaysAgo]
 );

 let query = `
 SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
 s.id as shop_id, s.name as shop_name, s.city, s.country
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 `;

 const params = [];
 const conditions = [];

 if (viewsResult.rows.length > 0) {
 const storeIds = [...new Set(viewsResult.rows.map(r => r.store_id).filter(Boolean))];
 if (storeIds.length > 0) {
 params.push(...storeIds);
 conditions.push(`s.id IN (${storeIds.map((_, i) => '$' + (params.length - storeIds.length + i + 1)).join(',')})`);
 }
 }

 if (searchesResult.rows.length > 0) {
 const searchTerms = searchesResult.rows.map(r => r.query);
 for (const term of searchTerms) {
 params.push('%' + term + '%');
 conditions.push(`(p.name ILIKE $${params.length} OR p.description ILIKE $${params.length})`);
 }
 }

 if (conditions.length > 0) {
 query += ' AND (' + conditions.join(' OR ') + ')';
 }

 query += ' ORDER BY p.created_at DESC LIMIT 20';

 const result = await pool.query(query, params);

 if (result.rows.length === 0) {
 const fallback = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.view_count DESC NULLS LAST, p.created_at DESC
 LIMIT 20`
 );
 return res.json(fallback.rows);
 }

 res.json(result.rows);
 } catch (err) {
 console.error('Recommendations error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.get('/api/stores', async (req, res) => {
 const result = await pool.query(`
   SELECT s.*, c.display_names as city_display_names
   FROM stores s
   LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
 `);
 res.json(result.rows);
});

app.get('/api/stores/:id', async (req, res) => {
 const result = await pool.query(`
   SELECT s.*, c.display_names as city_display_names
   FROM stores s
   LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
   WHERE s.id=$1
 `, [req.params.id]);
 if (result.rows.length === 0) return res.status(404).json({ error: 'Store not found' });
 res.json(result.rows[0]);
});

// MY STORE
app.get('/api/my-store', requireRealUser, async (req, res) => {
 const result = await pool.query(`
   SELECT s.*, c.display_names as city_display_names
   FROM stores s
   LEFT JOIN canonical_cities c ON s.city_id = c.canonical_id
   WHERE s.owner_id=$1
 `, [req.user.userId]);
 if (result.rows.length === 0) return res.status(404).json({ error: 'No store found' });
 res.json(result.rows[0]);
});

// PRODUCTS
app.get('/api/products/:storeId', async (req, res) => {
 const result = await pool.query('SELECT * FROM products WHERE store_id=$1 ORDER BY created_at DESC', [req.params.storeId]);
 res.json(result.rows);
});

// CREATE PRODUCT (with barcode, category, multiple images)
app.post('/api/products', requireRealUser, productUpload, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(403).json({ error: 'You do not own a store' });
    const storeId = storeResult.rows[0].id;

    const { name, price, quantity, description, barcode, category_id, low_stock_threshold } = req.body;

    if (barcode) {
      const existing = await pool.query('SELECT id FROM products WHERE barcode=$1', [barcode]);
      if (existing.rows.length > 0) {
        return res.status(409).json({ error: 'Barcode already exists', product_id: existing.rows[0].id });
      }
    }

    const imageUrl = req.files?.['image']?.[0] ? `${getBaseUrl(req)}/uploads/${req.files['image'][0].filename}` : null;
    const extraImages = req.files?.['extra_images']?.map(f => `${getBaseUrl(req)}/uploads/${f.filename}`) || [];
    const allImages = imageUrl ? [imageUrl, ...extraImages] : extraImages;

    const result = await pool.query(
      `INSERT INTO products (store_id, name, price, quantity, description, barcode, category_id, images, image_url, low_stock_threshold)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [
        storeId,
        sanitizeString(name, 200),
        parseFloat(price) || 0,
        parseInt(quantity) || 0,
        description ? sanitizeString(description, 1000) : null,
        barcode ? sanitizeString(barcode, 50) : null,
        category_id ? parseInt(category_id) : null,
        JSON.stringify(allImages),
        imageUrl,
        parseInt(low_stock_threshold) || 5
      ]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// UPDATE PRODUCT
app.put('/api/products/:id', requireRealUser, productUpload, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });
    const storeId = storeResult.rows[0].id;

    const existing = await pool.query('SELECT * FROM products WHERE id=$1 AND store_id=$2', [req.params.id, storeId]);
    if (existing.rows.length === 0) return res.status(404).json({ error: 'Product not found' });

    const old = existing.rows[0];
    const name = req.body.name !== undefined ? sanitizeString(req.body.name, 200) : old.name;
    const price = req.body.price !== undefined ? parseFloat(req.body.price) : old.price;
    const quantity = req.body.quantity !== undefined ? parseInt(req.body.quantity) : old.quantity;
    const description = req.body.description !== undefined ? (req.body.description ? sanitizeString(req.body.description, 1000) : null) : old.description;
    const barcode = req.body.barcode !== undefined ? (req.body.barcode ? sanitizeString(req.body.barcode, 50) : null) : old.barcode;
    const category_id = req.body.category_id !== undefined ? (req.body.category_id ? parseInt(req.body.category_id) : null) : old.category_id;
    const low_stock_threshold = req.body.low_stock_threshold !== undefined ? parseInt(req.body.low_stock_threshold) : old.low_stock_threshold;

    if (barcode && barcode !== old.barcode) {
      const bcCheck = await pool.query('SELECT id FROM products WHERE barcode=$1 AND id != $2', [barcode, req.params.id]);
      if (bcCheck.rows.length > 0) {
        return res.status(409).json({ error: 'Barcode already exists', product_id: bcCheck.rows[0].id });
      }
    }

    const imageUrl = req.files?.['image']?.[0] ? `${getBaseUrl(req)}/uploads/${req.files['image'][0].filename}` : old.image_url;

    let allImages = old.images || [];
    if (req.body.existing_images) {
      try { allImages = JSON.parse(req.body.existing_images); } catch (_) {}
    }
    const newImages = req.files?.['extra_images']?.map(f => `${getBaseUrl(req)}/uploads/${f.filename}`) || [];
    allImages = [...allImages, ...newImages];
    if (imageUrl && !allImages.includes(imageUrl)) {
      allImages.unshift(imageUrl);
    }

    const result = await pool.query(
      `UPDATE products SET name=$1, price=$2, quantity=$3, description=$4, barcode=$5, category_id=$6, low_stock_threshold=$7, image_url=$8, images=$9, updated_at=NOW() WHERE id=$10 RETURNING *`,
      [name, price, quantity, description, barcode, category_id, low_stock_threshold, imageUrl, JSON.stringify(allImages), req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

app.delete('/api/products/:id', requireRealUser, async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });
 const storeId = storeResult.rows[0].id;
 await pool.query('DELETE FROM products WHERE id=$1 AND store_id=$2', [req.params.id, storeId]);
 res.json({ message: 'Product deleted successfully' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

app.post('/api/upload', requireRealUser, upload.single('image'), (req, res) => {
 if (!req.file) return res.status(400).json({ error: 'No image uploaded' });

 res.json({ url: `${getBaseUrl(req)}/uploads/${req.file.filename}` });
});

// UPDATE PREFERRED LANGUAGE
app.put('/api/me/language', requireRealUser, async (req, res) => {
 try {
 const preferred_language = sanitizeString(req.body.preferred_language, 10);
 await pool.query(
 'UPDATE users SET preferred_language=$1 WHERE id=$2',
 [preferred_language, req.user.userId]
 );
 res.json({ message: 'Language preference updated' });
 } catch (err) {
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// MARKETPLACE FEED
app.get('/api/marketplace/feed', async (req, res) => {
 try {
 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 ORDER BY p.created_at DESC
 LIMIT 50`
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Feed error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// UPDATE MY STORE
app.put('/api/my-store', requireRealUser, upload.single('image'), async (req, res) => {
 try {
 const storeResult = await pool.query('SELECT * FROM stores WHERE owner_id=$1', [req.user.userId]);
 if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store found' });

 const existing = storeResult.rows[0];
 const name = req.body.name !== undefined ? sanitizeString(req.body.name, 100) : existing.name;
 const city = req.body.city !== undefined ? sanitizeString(req.body.city, 100) : existing.city;
 const location_description = req.body.location_description !== undefined ? sanitizeString(req.body.location_description, 200) : existing.location_description;
 const country = req.body.country !== undefined ? sanitizeString(req.body.country, 100) : existing.country;
 const phone = req.body.phone !== undefined ? sanitizeString(req.body.phone, 50) : existing.phone;
 const lat = req.body.lat !== undefined ? parseFloat(req.body.lat) : existing.lat;
 const lng = req.body.lng !== undefined ? parseFloat(req.body.lng) : existing.lng;
 const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : existing.image_url;

 const city_id = req.body.city_id !== undefined ? sanitizeString(req.body.city_id, 100) : existing.city_id;
 const country_code = req.body.country_code !== undefined ? sanitizeString(req.body.country_code, 2).toLowerCase().substring(0, 2) : existing.country_code;

 const result = await pool.query(
 `UPDATE stores SET name=$1, city=$2, location_description=$3, country=$4, phone=$5, lat=$6, lng=$7, image_url=$8, city_id=$9, country_code=$10, updated_at=NOW() WHERE id=$11 RETURNING *`,
 [name, city, location_description, country, phone, lat, lng, imageUrl, city_id, country_code, existing.id]
 );
 res.json(result.rows[0]);
 } catch (err) {
 console.error(err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// NEARBY PRODUCTS
app.get('/api/marketplace/nearby', async (req, res) => {
 try {
 const lat = parseFloat(req.query.lat);
 const lng = parseFloat(req.query.lng);
 const radiusKm = parseFloat(req.query.radius) || 15;

 if (isNaN(lat) || isNaN(lng)) {
 return res.status(400).json({ error: 'lat and lng query params are required' });
 }

 const result = await pool.query(
 `SELECT p.id, p.name, p.price, p.quantity, p.description, p.image_url, p.created_at,
 s.id as shop_id, s.name as shop_name, s.city, s.country, s.lat, s.lng,
 (6371 * acos(
 cos(radians($1)) * cos(radians(s.lat)) *
 cos(radians(s.lng) - radians($2)) +
 sin(radians($1)) * sin(radians(s.lat))
 )) AS distance_km
 FROM products p
 JOIN stores s ON p.store_id = s.id
 WHERE p.quantity > 0
 AND s.lat IS NOT NULL AND s.lng IS NOT NULL
 HAVING (6371 * acos(
 cos(radians($1)) * cos(radians(s.lat)) *
 cos(radians(s.lng) - radians($2)) +
 sin(radians($1)) * sin(radians(s.lat))
 )) <= $3
 ORDER BY distance_km ASC
 LIMIT 50`,
 [lat, lng, radiusKm]
 );
 res.json(result.rows);
 } catch (err) {
 console.error('Nearby error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// ADMIN: Set store as sponsored
app.put('/api/admin/stores/:id/sponsor', authenticateToken, async (req, res) => {
 try {
 const userResult = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
 if (userResult.rows.length === 0 || userResult.rows[0].role !== 'admin') {
 return res.status(403).json({ error: 'Admin access required' });
 }

 const storeId = parseInt(req.params.id);
 const { tier, expiresAt } = req.body;

 await pool.query(
 `UPDATE stores
 SET is_sponsored = TRUE,
 sponsorship_tier = $1,
 sponsorship_expires_at = $2
 WHERE id = $3`,
 [tier || 1, expiresAt || null, storeId]
 );

 res.json({ message: 'Store sponsorship updated' });
 } catch (err) {
 console.error('Sponsor error:', err);
 res.status(500).json({ error: 'Something went wrong. Please try again later.' });
 }
});

// Multer error handler
app.use((err, req, res, next) => {
 if (err instanceof multer.MulterError) {
 if (err.code === 'LIMIT_FILE_SIZE') {
 return res.status(400).json({ error: 'File too large. Max 5MB.' });
 }
 return res.status(400).json({ error: err.message });
 }
 if (err && err.message && err.message.includes('Only JPEG')) {
 return res.status(400).json({ error: err.message });
 }
 next(err);
});
// ==================== BACKEND EXTENSIONS ====================
// Append these routes to your existing server.js BEFORE the error handler and listen() call.
// Do NOT modify existing routes above.

// ==================== CATEGORIES ====================

app.get('/api/categories', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT c.*, p.name as parent_name
       FROM categories c
       LEFT JOIN categories p ON c.parent_id = p.id
       ORDER BY c.sort_order, c.name`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Categories error:', err);
    res.status(500).json({ error: 'Failed to load categories' });
  }
});

app.get('/api/categories/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM categories WHERE id = $1', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Category not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== PRODUCT IMAGES ====================

app.get('/api/products/:id/images', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM product_images WHERE product_id = $1 ORDER BY sort_order, id',
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.post('/api/products/:id/images', requireRealUser, upload.single('image'), async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });

    const productCheck = await pool.query(
      'SELECT p.id FROM products p JOIN stores s ON p.store_id = s.id WHERE p.id=$1 AND s.owner_id=$2',
      [req.params.id, req.user.userId]
    );
    if (productCheck.rows.length === 0) return res.status(403).json({ error: 'Not your product' });

    if (!req.file) return res.status(400).json({ error: 'No image' });
    const imageUrl = `${getBaseUrl(req)}/uploads/${req.file.filename}`;

    const result = await pool.query(
      'INSERT INTO product_images (product_id, image_url) VALUES ($1, $2) RETURNING *',
      [req.params.id, imageUrl]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed' });
  }
});

app.delete('/api/products/:id/images/:imageId', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });

    const result = await pool.query(
      `DELETE FROM product_images pi
       USING products p, stores s
       WHERE pi.id=$1 AND pi.product_id=$2 AND p.id=pi.product_id AND s.id=p.store_id AND s.owner_id=$3
       RETURNING pi.*`,
      [req.params.imageId, req.params.id, req.user.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Image not found' });
    res.json({ message: 'Deleted' });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== BARCODE ====================

app.get('/api/products/barcode/validate', async (req, res) => {
  try {
    const code = sanitizeString(req.query.code, 50);
    if (!code) return res.status(400).json({ error: 'Code required' });

    const result = await pool.query(
      'SELECT id, name, barcode, quantity FROM products WHERE barcode = $1 LIMIT 1',
      [code]
    );
    res.json({
      exists: result.rows.length > 0,
      product: result.rows.length > 0 ? result.rows[0] : null,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.get('/api/products/barcode/:code', async (req, res) => {
  try {
    const code = sanitizeString(req.params.code, 50);
    const result = await pool.query(
      `SELECT p.*, s.name as shop_name, s.city, s.country, s.lat, s.lng
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.barcode = $1
       LIMIT 1`,
      [code]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== PRODUCT SEARCH ====================

app.get('/api/products/:storeId/search', async (req, res) => {
  try {
    const storeId = parseInt(req.params.storeId);
    const q = sanitizeString(req.query.q, 100);
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    if (!q) return res.json([]);

    const result = await pool.query(
      `SELECT p.* FROM products p
       WHERE p.store_id = $1 AND (p.name ILIKE $2 OR p.barcode ILIKE $2)
       ORDER BY p.name
       LIMIT $3`,
      [storeId, `%${q}%`, limit]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.get('/api/products/search', async (req, res) => {
  try {
    const q = sanitizeString(req.query.q, 100);
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    if (!q) return res.json([]);

    const result = await pool.query(
      `SELECT p.*, s.name as shop_name FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.name ILIKE $1 OR p.barcode ILIKE $1
       ORDER BY p.name
       LIMIT $2`,
      [`%${q}%`, limit]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== LOW STOCK ====================

app.get('/api/my-store/low-stock', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });
    const storeId = storeResult.rows[0].id;

    const result = await pool.query(
      `SELECT id, name, quantity, barcode, price FROM products
       WHERE store_id = $1 AND quantity <= 5 AND quantity >= 0
       ORDER BY quantity ASC, name`,
      [storeId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== ORDERS / CHECKOUT ====================

function generateReceiptNumber() {
  const now = new Date();
  const ts = now.getFullYear().toString().slice(2)
    + String(now.getMonth() + 1).padStart(2, '0')
    + String(now.getDate()).padStart(2, '0')
    + String(now.getHours()).padStart(2, '0')
    + String(now.getMinutes()).padStart(2, '0')
    + String(now.getSeconds()).padStart(2, '0');
  const rnd = crypto.randomInt(1000, 9999).toString();
  return `MB-${ts}-${rnd}`;
}

app.post('/api/orders', requireRealUser, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const storeResult = await client.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You do not own a store' });
    }
    const storeId = storeResult.rows[0].id;

    const items = req.body.items;
    if (!Array.isArray(items) || items.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Items required' });
    }

    // Validate stock and calculate totals
    let subtotal = 0;
    for (const item of items) {
      const productId = item.product_id;
      const qty = parseInt(item.quantity);
      if (!productId || isNaN(qty) || qty < 1) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid item data' });
      }

      const stockCheck = await client.query(
        'SELECT quantity, name FROM products WHERE id = $1 AND store_id = $2 FOR UPDATE',
        [productId, storeId]
      );
      if (stockCheck.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: `Product ${productId} not found` });
      }
      const available = stockCheck.rows[0].quantity;
      if (available < qty) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          error: `Insufficient stock for "${stockCheck.rows[0].name}". Available: ${available}, Requested: ${qty}`
        });
      }

      const unitPrice = parseFloat(item.unit_price) || 0;
      subtotal += unitPrice * qty;
    }

    const discount = parseFloat(req.body.discount) || 0;
    const tax = parseFloat(req.body.tax) || 0;
    const total = Math.max(0, subtotal - discount + tax);
    const receiptNumber = generateReceiptNumber();

    const orderResult = await client.query(
      `INSERT INTO orders (store_id, cashier_id, customer_name, customer_phone, subtotal, discount, tax, total, status, payment_method, receipt_number, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING *`,
      [
        storeId,
        req.user.userId,
        req.body.customer_name || null,
        req.body.customer_phone || null,
        subtotal,
        discount,
        tax,
        total,
        'completed',
        req.body.payment_method || 'cash',
        receiptNumber,
        req.body.notes || null,
      ]
    );
    const orderId = orderResult.rows[0].id;

    // Insert items and reduce stock
    for (const item of items) {
      const productId = item.product_id;
      const qty = parseInt(item.quantity);
      const unitPrice = parseFloat(item.unit_price) || 0;
      const lineTotal = parseFloat(item.total_price) || (unitPrice * qty);

      await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price, total_price, barcode)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [orderId, productId, item.product_name, qty, unitPrice, lineTotal, item.barcode || null]
      );

      await client.query(
        'UPDATE products SET quantity = quantity - $1, updated_at = NOW() WHERE id = $2',
        [qty, productId]
      );
    }

    await client.query('COMMIT');
    res.status(201).json(orderResult.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Checkout error:', err);
    res.status(500).json({ error: 'Checkout failed. Please try again.' });
  } finally {
    client.release();
  }
});

app.get('/api/orders', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.json([]);
    const storeId = storeResult.rows[0].id;

    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const offset = parseInt(req.query.offset) || 0;

    const result = await pool.query(
      `SELECT o.*, u.full_name as cashier_name
       FROM orders o
       LEFT JOIN users u ON o.cashier_id = u.id
       WHERE o.store_id = $1
       ORDER BY o.created_at DESC
       LIMIT $2 OFFSET $3`,
      [storeId, limit, offset]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.get('/api/orders/:id', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });
    const storeId = storeResult.rows[0].id;

    const orderResult = await pool.query(
      `SELECT o.*, u.full_name as cashier_name
       FROM orders o
       LEFT JOIN users u ON o.cashier_id = u.id
       WHERE o.id = $1 AND o.store_id = $2`,
      [req.params.id, storeId]
    );
    if (orderResult.rows.length === 0) return res.status(404).json({ error: 'Order not found' });

    const itemsResult = await pool.query(
      'SELECT * FROM order_items WHERE order_id = $1 ORDER BY id',
      [req.params.id]
    );

    const order = orderResult.rows[0];
    order.items = itemsResult.rows;
    res.json(order);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== RECEIPT SETTINGS ====================

app.get('/api/my-store/receipt-settings', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });
    const storeId = storeResult.rows[0].id;

    const result = await pool.query(
      'SELECT * FROM receipt_settings WHERE store_id = $1',
      [storeId]
    );
    if (result.rows.length > 0) return res.json(result.rows[0]);

    // Return defaults
    res.json({
      store_id: storeId,
      footer_message: 'Thank you for your purchase!',
      show_logo: true,
      show_barcode: true,
      currency_symbol: 'SYP',
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.put('/api/my-store/receipt-settings', requireRealUser, async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(404).json({ error: 'No store' });
    const storeId = storeResult.rows[0].id;

    const existing = await pool.query('SELECT id FROM receipt_settings WHERE store_id = $1', [storeId]);
    const hasRecord = existing.rows.length > 0;

    const footer = req.body.footer_message !== undefined ? sanitizeString(req.body.footer_message, 255) : null;
    const showLogo = req.body.show_logo !== undefined ? !!req.body.show_logo : null;
    const showBarcode = req.body.show_barcode !== undefined ? !!req.body.show_barcode : null;
    const currency = req.body.currency_symbol !== undefined ? sanitizeString(req.body.currency_symbol, 10) : null;

    let result;
    if (hasRecord) {
      result = await pool.query(
        `UPDATE receipt_settings SET
          footer_message = COALESCE($1, footer_message),
          show_logo = COALESCE($2, show_logo),
          show_barcode = COALESCE($3, show_barcode),
          currency_symbol = COALESCE($4, currency_symbol),
          updated_at = NOW()
         WHERE store_id = $5
         RETURNING *`,
        [footer, showLogo, showBarcode, currency, storeId]
      );
    } else {
      result = await pool.query(
        `INSERT INTO receipt_settings (store_id, footer_message, show_logo, show_barcode, currency_symbol)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [storeId, footer || 'Thank you for your purchase!', showLogo ?? true, showBarcode ?? true, currency || 'SYP']
      );
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== PRODUCT UPDATE WITH CATEGORIES ====================
// Extend existing PUT /api/products/:id to handle categories and images

app.put('/api/products/:id', requireRealUser, upload.single('image'), async (req, res) => {
  try {
    const storeResult = await pool.query('SELECT id FROM stores WHERE owner_id=$1', [req.user.userId]);
    if (storeResult.rows.length === 0) return res.status(403).json({ error: 'No store found' });
    const storeId = storeResult.rows[0].id;

    const existing = await pool.query(
      'SELECT * FROM products WHERE id=$1 AND store_id=$2',
      [req.params.id, storeId]
    );
    if (existing.rows.length === 0) return res.status(404).json({ error: 'Product not found' });

    const { name, price, quantity, description, barcode } = req.body;
    const imageUrl = req.file ? `${getBaseUrl(req)}/uploads/${req.file.filename}` : existing.rows[0].image_url;

    const result = await pool.query(
      `UPDATE products SET name=$1, price=$2, quantity=$3, description=$4, barcode=$5, image_url=$6, updated_at=NOW()
       WHERE id=$7 AND store_id=$8 RETURNING *`,
      [name, price, quantity, description, barcode, imageUrl, req.params.id, storeId]
    );

    // Handle category_ids if provided
    if (req.body.category_ids) {
      let catIds = req.body.category_ids;
      if (typeof catIds === 'string') {
        try { catIds = JSON.parse(catIds); } catch (_) { catIds = []; }
      }
      if (Array.isArray(catIds)) {
        await pool.query('DELETE FROM product_categories WHERE product_id=$1', [req.params.id]);
        for (const cid of catIds) {
          await pool.query(
            'INSERT INTO product_categories (product_id, category_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [req.params.id, parseInt(cid)]
          );
        }
      }
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// ==================== END BACKEND EXTENSIONS ====================
(async () => {
  await initLocationTables();
  await initInventoryTables();
  app.listen(PORT, '0.0.0.0', () => console.log(`Server on ${getBaseUrl({ headers: {} })} (port ${PORT})`));
})();