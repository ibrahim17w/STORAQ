const { pool } = require('../config/database');
const { PORT } = require('../config/constants');
const fs = require('fs');
const path = require('path');
const { uploadsDir } = require('../config/upload');

// SECURITY: the Host header is attacker-controlled. The URLs we mint here
// are persisted in the database (avatar_url, image_url) and later
// rendered in users' browsers — letting an attacker swap the host into
// stored URLs turns this into a phishing / image-replacement primitive.
//
// Resolution order (most-trusted first):
//   1. BASE_URL env var. Set by the operator, single source of truth.
//   2. ALLOWED_HOSTS whitelist: if the request's Host (or forwarded host)
//      is on the list, accept it. Useful for multi-domain deployments
//      where the operator can't pick one canonical BASE_URL.
//   3. Dev fallback: if not production, accept the request Host. (Server
//      startup also FATALs if BASE_URL is missing in production, so this
//      branch is unreachable in real prod traffic.)
//   4. Loopback fallback for tooling.
function getBaseUrl(req) {
  if (process.env.BASE_URL) return process.env.BASE_URL.replace(/\/+$/, '');

  const allowedHosts = (process.env.ALLOWED_HOSTS || '')
    .split(',')
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean);

  const forwardedProto = req.headers['x-forwarded-proto'];
  const rawHost = (req.headers['x-forwarded-host'] || req.headers['host'] || '').toString().toLowerCase();
  // Strip any port for whitelist comparison; the whitelist is host-only.
  const hostOnly = rawHost.split(':')[0];

  if (allowedHosts.length > 0 && hostOnly && allowedHosts.includes(hostOnly)) {
    const proto = forwardedProto || (req.secure ? 'https' : 'http');
    return `${proto}://${rawHost}`;
  }

  // No BASE_URL, no whitelist match. In production we refuse to fall back
  // to the request Host — the startup check forces operators to set
  // BASE_URL, so reaching here in prod indicates misconfiguration we want
  // to be loud about (broken image URLs > silent phishing primitive).
  if (process.env.NODE_ENV === 'production') {
    return 'https://invalid.local';
  }

  // Dev fallback only.
  if (rawHost) {
    const proto = forwardedProto || (req.secure ? 'https' : 'http');
    return `${proto}://${rawHost}`;
  }
  return `http://localhost:${PORT}`;
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

function extractFilenameFromUrl(url) {
  if (!url || typeof url !== 'string') return null;
  const parts = url.split('/');
  const filename = parts[parts.length - 1];
  if (!filename || filename.includes('/') || filename.includes('\\')) return null;
  return filename;
}

function deleteUploadFiles(urls) {
  if (!urls) return;
  const urlArray = Array.isArray(urls) ? urls : [urls];
  for (const url of urlArray) {
    const filename = extractFilenameFromUrl(url);
    if (!filename) continue;
    const filePath = path.join(uploadsDir, filename);
    try {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    } catch (err) {
      console.error('Failed to delete upload file:', filePath, err.message);
    }
  }
}

// Matches DECIMAL(18,2) — the widened money columns in orders/products.
const MAX_MONEY = 9999999999999999.99;

function isWithinMoneyLimit(value) {
  if (value == null || Number.isNaN(Number(value))) return true;
  return Math.abs(Number(value)) <= MAX_MONEY;
}

function assertMoneyLimit(value, fieldLabel = 'Amount') {
  if (!isWithinMoneyLimit(value)) {
    throw new Error(`${fieldLabel} is too large. Please reduce quantity or check product prices.`);
  }
}

function getEffectiveProductPrice(product) {
  const listPrice = parseFloat(product.price) || 0;
  if (product.sale_price == null || product.sale_price === '') return listPrice;
  const salePrice = parseFloat(product.sale_price);
  if (!Number.isFinite(salePrice) || salePrice <= 0 || salePrice >= listPrice) return listPrice;
  return salePrice;
}

function isProductOnSale(product) {
  const listPrice = parseFloat(product.price) || 0;
  if (product.sale_price == null || product.sale_price === '') return false;
  const salePrice = parseFloat(product.sale_price);
  return Number.isFinite(salePrice) && salePrice > 0 && salePrice < listPrice;
}

module.exports = {
  sanitizeString,
  getPagination,
  isValidEmail,
  serverNow,
  formatWaitTime,
  getBaseUrl,
  deleteUploadFiles,
  MAX_MONEY,
  isWithinMoneyLimit,
  assertMoneyLimit,
  getEffectiveProductPrice,
  isProductOnSale,
};