//server.js
require('dotenv').config();
const { app } = require('./config/app');
const { mountRoutes } = require('./routes');
const { pool } = require('./config/database');
const { initLocationTables } = require('./services/location');
const { initInventoryTables, initAuthTables } = require('./db/init');
const { initEmbeddingTables } = require('./services/embedding');
const { authLimiter } = require('./middleware/auth');
const { PORT } = require('./config/constants');
const multer = require('multer');

// Root
app.get('/', (req, res) => res.send('Market Bridge API'));



// Mount all modular routes
mountRoutes(app);

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

// Startup IIFE (exact same code, just requiring the init functions from above)
(async () => {
  if (!process.env.JWT_SECRET) { console.error('FATAL: JWT_SECRET is not set'); process.exit(1); }
  if (!process.env.DATABASE_URL) { console.error('FATAL: DATABASE_URL is not set'); process.exit(1); }

  await initLocationTables();
  await initInventoryTables();
  await initAuthTables();
  await initEmbeddingTables();

  process.on('SIGTERM', async () => { console.log('SIGTERM received, closing pool...'); await pool.end(); process.exit(0); });
  process.on('SIGINT', async () => { console.log('SIGINT received, closing pool...'); await pool.end(); process.exit(0); });

  app.listen(PORT, '0.0.0.0', () => console.log(`Server on port ${PORT}`));
})();
