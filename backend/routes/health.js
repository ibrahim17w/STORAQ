//routes/health.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');

router.get('/health', async (req, res) => {
  try {
    const dbStart = Date.now();
    await pool.query('SELECT 1');
    const dbLatency = Date.now() - dbStart;

    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      database: {
        connected: true,
        latency_ms: dbLatency,
      },
      environment: process.env.NODE_ENV || 'development',
      version: '1.0.0',
    });
  } catch (err) {
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: 'Database connection failed',
      detail: err.message,
    });
  }
});

module.exports = router;
