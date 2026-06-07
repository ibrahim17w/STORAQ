const express = require('express');
const router = express.Router();

const PUBLIC_WEB_BASE = (process.env.PUBLIC_APP_URL || '').replace(/\/+$/, '');
const DOWNLOAD_URL = (process.env.APP_DOWNLOAD_URL || 'https://storaq.app/download').replace(/\/+$/, '');
const APP_SCHEME = 'storaq';

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function storeLandingHtml(storeId, req) {
  const id = parseInt(storeId, 10);
  if (!Number.isFinite(id) || id <= 0) {
    return null;
  }

  const deepLink = `${APP_SCHEME}://store/${id}`;
  const downloadWithStore = `${DOWNLOAD_URL}?store=${id}`;
  const safeDeep = escapeHtml(deepLink);
  const safeDownload = escapeHtml(downloadWithStore);

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open in STORAQ</title>
  <meta name="robots" content="noindex">
  <style>
    body { font-family: system-ui, sans-serif; max-width: 420px; margin: 48px auto; padding: 0 20px; text-align: center; color: #1a1a1a; }
    h1 { font-size: 1.35rem; margin-bottom: 8px; }
    p { color: #555; line-height: 1.5; }
    a.btn { display: inline-block; margin: 8px; padding: 12px 20px; border-radius: 10px; text-decoration: none; font-weight: 600; }
    .primary { background: #1565c0; color: #fff; }
    .secondary { background: #eee; color: #333; }
  </style>
</head>
<body>
  <h1>Opening STORAQ…</h1>
  <p>If the app is installed, you will be redirected to the store.</p>
  <p>
    <a class="btn primary" href="${safeDeep}">Open in app</a>
    <a class="btn secondary" href="${safeDownload}">Download STORAQ</a>
  </p>
  <script>
    (function () {
      var deep = ${JSON.stringify(deepLink)};
      var fallback = ${JSON.stringify(downloadWithStore)};
      var opened = false;
      function goDownload() {
        if (!opened) window.location.replace(fallback);
      }
      window.location.href = deep;
      setTimeout(goDownload, 2200);
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) opened = true;
      });
    })();
  </script>
</body>
</html>`;
}

function downloadPageHtml(storeId) {
  const sid = storeId ? parseInt(storeId, 10) : null;
  const storeNote = sid && sid > 0
    ? `<p>Store #${escapeHtml(sid)} — scan again after installing to visit the shop.</p>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Get STORAQ</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 480px; margin: 48px auto; padding: 0 20px; text-align: center; }
    h1 { font-size: 1.5rem; }
    p { color: #444; line-height: 1.55; }
    .links a { display: block; margin: 12px auto; padding: 14px 20px; max-width: 280px;
      border-radius: 10px; background: #1565c0; color: #fff; text-decoration: none; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Get STORAQ</h1>
  <p>Download the app to browse stores, products, and marketplace listings.</p>
  ${storeNote}
  <div class="links">
    <a href="https://play.google.com/store">Android — Google Play</a>
    <a href="https://apps.apple.com">iPhone — App Store</a>
  </div>
  <p style="font-size: 13px; color: #888;">Configure store links via APP_DOWNLOAD_URL on the server.</p>
</body>
</html>`;
}

router.get('/s/:storeId', (req, res) => {
  const html = storeLandingHtml(req.params.storeId, req);
  if (!html) {
    return res.status(400).send('Invalid store link');
  }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'"
  );
  res.send(html);
});

router.get('/download', (req, res) => {
  const storeId = req.query.store;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; style-src 'unsafe-inline'; img-src 'self' data: https:"
  );
  res.send(downloadPageHtml(storeId));
});

module.exports = router;
