//config/app.js
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const path = require('path');
const { uploadsDir } = require('./upload');

// Configure undici's global Dispatcher so all outbound `fetch()` calls
// (Turnstile, Frankfurter, ExchangeRate-API, Syriato, etc.) share a
// connection pool with aggressive keep-alive. The default Dispatcher
// works but caps to 6 connections per host and a short keep-alive window;
// tuning it removes the 50-200ms TLS handshake on every external call,
// which adds up to seconds across a user session.
//
// undici ships bundled with Node 18+, so `require('undici')` resolves to
// the same library that powers global fetch — no extra install needed.
try {
  const { Agent, setGlobalDispatcher } = require('undici');
  setGlobalDispatcher(new Agent({
    keepAliveTimeout: 30_000,
    keepAliveMaxTimeout: 60_000,
    connections: 100, // per origin (was 6)
    pipelining: 1,
  }));
} catch (_) {
  // Pre-Node-18 fallback — global fetch isn't available anyway, so callers
  // would have failed earlier. Swallow so this file still loads.
}

const app = express();

// Hide the Express advertisement so attackers can't fingerprint the
// framework version from `X-Powered-By` (helmet also disables this, but
// being explicit guards against helmet being reordered or removed later).
app.disable('x-powered-by');

// Trust the first reverse proxy (Render/Cloudflare/Nginx) so req.ip,
// X-Forwarded-For, and protocol detection reflect the real client.
// Without this every IP-based rate limit collapses to a single shared
// bucket (the proxy IP), which breaks abuse protections.
app.set('trust proxy', 1);

// Per-request timeout — bounds slowloris-style attacks where a client
// opens a connection and dribbles bytes to hold a Node socket forever.
// 60s is well above any legitimate request (largest is multipart upload
// of 5MB images, which completes in seconds on any real connection).
// Express doesn't apply timeouts by default; without this a single
// attacker can exhaust the event loop with cheap held-open sockets.
app.use((req, res, next) => {
  req.setTimeout(60 * 1000, () => {
    try { req.destroy(); } catch (_) {}
  });
  res.setTimeout(60 * 1000, () => {
    try { res.end(); } catch (_) {}
  });
  next();
});

// ==================== STRICT HELMET CONFIG ====================
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      // Allow embedding product images via data: URIs (Flutter web previews)
      // and any https source (we don't restrict by host because users
      // legitimately reference image_url from arbitrary CDNs).
      imgSrc: ["'self'", "data:", "blob:", "https:"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"], // belt-and-suspenders with X-Frame-Options
      baseUri: ["'self'"],
      formAction: ["'self'"],
      upgradeInsecureRequests: [],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
  referrerPolicy: { policy: 'no-referrer' }, // tighter than before; the API
  // never emits cross-origin links so no legitimate client needs a Referer.
  crossOriginOpenerPolicy: { policy: 'same-origin' },
  crossOriginEmbedderPolicy: false, // would break loading uploaded images
  // cross-origin from the Flutter app
  crossOriginResourcePolicy: { policy: 'cross-origin' }, // /uploads served
  // cross-origin to the mobile + web clients
  originAgentCluster: true,
}));

// Permissions-Policy: disable browser features the API has no business
// granting if a response is ever rendered inline in an iframe by mistake.
app.use((req, res, next) => {
  res.setHeader(
    'Permissions-Policy',
    'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()'
  );
  next();
});

const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim())
  : ['http://localhost:3000'];

// Allow:
//   * any explicitly whitelisted browser origin (ALLOWED_ORIGINS env var)
//   * non-browser callers that send NO Origin header (mobile apps,
//     server-to-server, curl) — these aren't subject to CORS anyway
// Block unknown browser origins by passing `false` (no CORS headers added,
// browser refuses the response). We never throw, which would surface as a
// generic 500.
app.use(cors({
  origin(origin, callback) {
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    return callback(null, false);
  },
  credentials: true,
}));
// gzip JSON / text responses. Largest payloads (marketplace listings,
// search results) compress 5-10x, which:
//   * cuts mobile bandwidth costs for end-users on slow networks
//   * cuts Node's outbound bytes by the same factor (less work for the
//     OS network stack)
//   * lowers perceived latency on lists/search by 200-500ms over 4G
// `threshold: 1024` skips tiny payloads where compression overhead
// outweighs the saving. `filter` honors clients sending the
// `x-no-compression` header (useful for debugging only).
app.use(compression({
  threshold: 1024,
  filter: (req, res) => {
    if (req.headers['x-no-compression']) return false;
    return compression.filter(req, res);
  },
}));

app.use(express.json({ limit: '2mb' })); // was 10mb — far larger than any
// legitimate JSON payload this API accepts; multipart uploads use multer
// which has its own 5MB-per-file limit.
app.use(express.urlencoded({ extended: false, limit: '256kb' }));

// Serve uploaded media. `fallthrough: false` returns 404 instead of
// leaking into the catch-all error handler; `dotfiles: 'deny'` prevents
// `/uploads/.env` style probes; `index: false` disables directory listing.
app.use(
  '/uploads',
  express.static(uploadsDir, {
    fallthrough: true, // keep legacy 404 behavior (next() instead of error)
    dotfiles: 'deny',
    index: false,
    setHeaders(res) {
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    },
  })
);

module.exports = { app };
