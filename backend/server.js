//server.js
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}
const cluster = require('cluster');
const os = require('os');
const { app } = require('./config/app');
const { mountRoutes } = require('./routes');
const { pool } = require('./config/database');
const { initLocationTables } = require('./services/location');
const {
  initInventoryTables,
  initAuthTables,
  initSubscriptionTables,
  initChatTables,
  initSupportTables,
  initSponsoredProductTables,
  initPromoTables,
  initReviewTables,
  initReportTables,
} = require('./db/init');
const { initEmbeddingTables } = require('./services/embedding');
const { authLimiter } = require('./middleware/auth');
const { PORT } = require('./config/constants');
const multer = require('multer');

function getWorkerCount() {
  const v = process.env.CLUSTER_WORKERS;
  if (!v || v === '1') return 1;
  if (v === 'auto') return Math.max(1, os.cpus().length);
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}
const WORKER_COUNT = getWorkerCount();

// Root
app.get('/', (req, res) => res.send('STORAQ API'));

// Store QR smart links (/s/:id opens app or download page)
const storeLinkRoutes = require('./routes/store_links');
app.use(storeLinkRoutes);

// Mount all modular routes
mountRoutes(app);

// Currency display settings (multi-currency feature)
const storeCurrencyRoutes = require('./routes/store_currency');
app.use('/api', storeCurrencyRoutes);

// Multer error handler (exact same code)
app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') return res.status(400).json({ error: 'File too large. Max 5MB.' });
    return res.status(400).json({ error: err.message });
  }
  if (err && err.message && err.message.includes('Only JPEG')) {
    return res.status(400).json({ error: err.message });
  }
  next(err);
});

// Final catch-all (exact same code)
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong. Please try again later.' });
});


function validateEnvOrExit() {
  if (!process.env.JWT_SECRET) { console.error('FATAL: JWT_SECRET is not set'); process.exit(1); }
  if (!process.env.DATABASE_URL) { console.error('FATAL: DATABASE_URL is not set'); process.exit(1); }

  if (process.env.JWT_SECRET.length < 32) {
    console.error('FATAL: JWT_SECRET must be at least 32 characters (preferably 64+ from `openssl rand -hex 32`)');
    process.exit(1);
  }

  if (process.env.NODE_ENV === 'production' && !process.env.BASE_URL) {
    console.error('FATAL: BASE_URL must be set in production (e.g. https://api.example.com) — otherwise persisted upload URLs are derived from the Host header, which is attacker-controlled.');
    process.exit(1);
  }
  if (!process.env.BASE_URL) {
    console.warn('[startup] BASE_URL not set — falling back to Host header for URL generation. Set BASE_URL before going to production.');
  }
}

async function startWorker() {
  await initLocationTables();
  await initInventoryTables();
  await initAuthTables();
  await initSubscriptionTables();
  await initChatTables();
  await initSupportTables();
  await initSponsoredProductTables();
  await initPromoTables();
  await initReviewTables();
  await initReportTables();
  await initEmbeddingTables();

  process.on('SIGTERM', async () => { console.log(`[${process.pid}] SIGTERM received, closing pool...`); await pool.end(); process.exit(0); });
  process.on('SIGINT', async () => { console.log(`[${process.pid}] SIGINT received, closing pool...`); await pool.end(); process.exit(0); });

  app.listen(PORT, '0.0.0.0', () => {
    const tag = cluster.isWorker ? ` (worker ${process.pid})` : '';
    console.log(`Server on port ${PORT}${tag}`);
  });
}

if (cluster.isPrimary && WORKER_COUNT > 1) {
  // Primary in cluster mode: validate env once, fork workers, supervise.
  validateEnvOrExit();
  console.log(`[cluster] Primary ${process.pid} spawning ${WORKER_COUNT} worker(s)`);
  for (let i = 0; i < WORKER_COUNT; i++) cluster.fork();

  // Respawn crashed workers so a single OOM / segfault doesn't take the
  // whole API down. (If a worker dies during shutdown we skip respawn.)
  let shuttingDown = false;
  cluster.on('exit', (worker, code, signal) => {
    if (shuttingDown) return;
    console.log(`[cluster] Worker ${worker.process.pid} died (${signal || code}). Respawning.`);
    cluster.fork();
  });

  function shutdown(sig) {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`[cluster] ${sig} received, shutting down workers...`);
    for (const id in cluster.workers) {
      try { cluster.workers[id].kill(sig); } catch (_) {}
    }
    // Give workers a few seconds to close in-flight requests, then exit.
    setTimeout(() => process.exit(0), 5000).unref();
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
} else {
  // Single-process mode (default) OR a forked worker — both serve requests.
  validateEnvOrExit();
  startWorker().catch((err) => {
    console.error('FATAL: server startup failed:', err);
    process.exit(1);
  });
}
