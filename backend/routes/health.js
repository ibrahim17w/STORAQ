//routes/health.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');

// Public health endpoint — must NEVER leak internals (NODE_ENV, version,
// stack traces, error messages, uptime detail). Load balancers only need
// a 200/503 + a tiny JSON body. Anything more is fingerprint material for
// attackers (e.g. NODE_ENV='development' on prod, version='1.0.0' for
// CVE matching, raw err.message exposing pg connection strings).
router.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy' });
  } catch (err) {
    console.error('Health check DB error:', err.message);
    res.status(503).json({ status: 'unhealthy' });
  }
});

module.exports = router;
