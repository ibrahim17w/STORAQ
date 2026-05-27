//middleware/helpers.js
const { pool } = require('../config/database');
const { PORT } = require('../config/constants');

function getBaseUrl(req) {
  const forwardedProto = req.headers['x-forwarded-proto'];
  const forwardedHost = req.headers['x-forwarded-host'] || req.headers['host'];
  if (forwardedProto && forwardedHost) {
    return `${forwardedProto}://${forwardedHost}`;
  }
  if (forwardedHost && !forwardedProto) {
    return `${req.secure ? 'https' : 'http'}://${forwardedHost}`;
  }
  // If client connects by IP (mobile/emulator), use that IP instead of localhost
  const clientHost = req.headers['host'];
  if (clientHost && !clientHost.includes('localhost')) {
    const proto = req.secure ? 'https' : 'http';
    return `${proto}://${clientHost}`;
  }
  return process.env.BASE_URL || `http://localhost:${PORT}`;
}

function sanitizeString(str, maxLen = 255) {
  if (typeof str !== 'string') return '';
  return str.trim().substring(0, maxLen);
}

function getPagination(req, defaultLimit = 20, maxLimit = 100) {
  const page = Math.max(1, parseInt(req.query.page) || 1);
  const limit = Math.min(maxLimit, Math.max(1, parseInt(req.query.limit) || defaultLimit));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

function isValidEmail(email) {
  return /^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/.test(email);
}

async function serverNow() {
  const result = await pool.query('SELECT NOW() as now');
  return new Date(result.rows[0].now);
}

function formatWaitTime(totalSeconds) {
  if (totalSeconds <= 0) return '0 seconds';
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  if (mins === 0) return `${secs} second${secs !== 1 ? 's' : ''}`;
  if (secs === 0) return `${mins} minute${mins !== 1 ? 's' : ''}`;
  return `${mins} minute${mins !== 1 ? 's' : ''} ${secs} second${secs !== 1 ? 's' : ''}`;
}

module.exports = { sanitizeString, getPagination, isValidEmail, serverNow, formatWaitTime, getBaseUrl };
