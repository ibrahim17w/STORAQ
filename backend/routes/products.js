//routes/products.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { upload, productUpload, cleanupUploadedFiles } = require('../config/upload');
const { authenticateToken, optionalAuth, requireRealUser, attachStoreContext, requireStoreOwner, requireInventoryAccess } = require('../middleware/auth');
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { sanitizeString, getPagination, getBaseUrl, deleteUploadFiles } = require('../middleware/helpers');
const { processProductEmbeddings } = require('../services/embedding');
const { recalculateSingleProductDisplayPrice } = require('./store_currency');
const {
  checkDailyCreationLimit,
  canAddOnlineProduct,
  withStoreLock,
  getSubscriptionStatus,
  getOnlineLimit,
  DAILY_CREATION_LIMIT,
} = require('../services/subscription');
const {
  requireVerifiedEmail,
  checkFirstProductApproval,
  checkDuplicateImages,
  saveImageHashes,
  computeImageHash,
  rateLimit_onlineProductSubmission,
} = require('../middleware/antibot');

async function slotLimitResponse(res, storeId) {
  const status = await getSubscriptionStatus(storeId);
  return res.status(403).json({
    error: 'online_slot_limit_reached',
    message: 'You have reached your online product limit. Upgrade to list more products on the marketplace.',
    online_count: status.online_count,
    online_limit: status.online_limit,
    tiers: status.tiers,
  });
}

// PRODUCTS — specific routes MUST come before parameterized routes
router.get('/products/search', validateQuery(schemas.search), async (req, res) => {
  try {
    const { q, limit } = req.validatedQuery;
    const finalLimit = Math.min(limit || 20, 50);
    if (!q) return res.json([]);

    const result = await pool.query(
      `SELECT p.*, s.name as shop_name FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE (p.name ILIKE $1 OR p.barcode ILIKE $1) AND p.is_online = TRUE AND p.quantity > 0
       AND COALESCE(s.is_active, TRUE) = TRUE
       ORDER BY p.name
       LIMIT $2`,
      [`%${q}%`, finalLimit]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

router.get('/products/:storeId', async (req, res) => {
  try {
    const storeId = parseInt(req.params.storeId);
    if (isNaN(storeId) || storeId <= 0) {
      return res.status(400).json({ error: 'Invalid store ID' });
    }
    const { page, limit, offset } = getPagination(req, 20, 100);

    const countResult = await pool.query(
      'SELECT COUNT(*) as total FROM products WHERE store_id = $1 AND is_online=TRUE',
      [storeId]
    );
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(
      'SELECT * FROM products WHERE store_id=$1 AND is_online=TRUE ORDER BY created_at DESC LIMIT $2 OFFSET $3',
      [storeId, limit, offset]
    );

    res.json({
      data: result.rows,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) }
    });
  } catch (err) {
    console.error('Products list error:', err);
    res.status(500).json({ error: 'Failed to load products' });
  }
});

// CREATE PRODUCT — owner or worker with inventory permission
router.post('/products', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, requireVerifiedEmail, productUpload, rateLimit_onlineProductSubmission, checkDuplicateImages, validate(schemas.createProduct), checkFirstProductApproval, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const { name, price, quantity, description, barcode, category_id, low_stock_threshold } = req.body;

    try {
      await checkDailyCreationLimit(storeId);
    } catch (limitErr) {
      cleanupUploadedFiles(req);
      return res.status(429).json({
        error: limitErr.code,
        message: limitErr.message,
        limit: limitErr.limit,
        created_today: limitErr.created_today,
      });
    }

    if (barcode) {
      const existing = await pool.query('SELECT id FROM products WHERE barcode=$1', [barcode]);
      if (existing.rows.length > 0) {
        cleanupUploadedFiles(req);
        return res.status(409).json({ error: 'Barcode already exists', product_id: existing.rows[0].id });
      }
    }

    const wantsOnline = req.body.list_online === 'true' || req.body.list_online === true;
    const explicitOnline = req.body.list_online !== undefined && req.body.list_online !== '';
    const wantsOrDefaultsOnline = wantsOnline || !explicitOnline;

    const imageUrl = req.files?.['image']?.[0] ? `${getBaseUrl(req)}/uploads/${req.files['image'][0].filename}` : null;
    const extraImages = req.files?.['extra_images']?.map(f => `${getBaseUrl(req)}/uploads/${f.filename}`) || [];
    const allImages = imageUrl ? [imageUrl, ...extraImages] : extraImages;

    const currency = req.body.currency ? sanitizeString(req.body.currency, 10) : 'SYP';

    const INSERT_SQL = `INSERT INTO products (store_id, name, price, quantity, description, barcode, category_id, images, image_url, low_stock_threshold, currency, is_online, went_online_at, pending_approval)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING *`;
    const buildValues = (isOnlineFinal) => [
      storeId,
      sanitizeString(name, 200),
      parseFloat(price) || 0,
      parseInt(quantity) || 0,
      description ? sanitizeString(description, 1000) : null,
      barcode ? sanitizeString(barcode, 50) : null,
      category_id ? parseInt(category_id) : null,
      JSON.stringify(allImages),
      imageUrl,
      parseInt(low_stock_threshold) || 5,
      currency,
      req._pendingFirstProductApproval ? false : isOnlineFinal,
      isOnlineFinal && !req._pendingFirstProductApproval ? new Date() : null,
      req._pendingFirstProductApproval ? true : false,
    ];

    // If this product would consume an online slot, serialize the
    // slot-check + INSERT under a per-store advisory lock so two concurrent
    // creates cannot both grab the last available slot.
    // Pending-approval first products never go online, so they don't need
    // the lock and use the fast path.
    let result;
    if (wantsOrDefaultsOnline && !req._pendingFirstProductApproval) {
      result = await withStoreLock(storeId, async (lockClient) => {
        const hasSlot = await canAddOnlineProduct(storeId);
        if (hasSlot) {
          return await lockClient.query(INSERT_SQL, buildValues(true));
        }
        // No slot. If the caller explicitly asked for online, surface the
        // 403 to the route below. Otherwise fall through to an offline
        // insert (matches the legacy behavior of `!explicitOnline`).
        return { __slotDenied: true };
      });
      if (result && result.__slotDenied) {
        if (wantsOnline) {
          cleanupUploadedFiles(req);
          return slotLimitResponse(res, storeId);
        }
        result = null; // try offline insert below
      }
    }
    if (!result) {
      result = await pool.query(INSERT_SQL, buildValues(false));
    }

    const productId = result.rows[0].id;

    // Save image hashes for duplicate detection
    if (req._imageHashes && req._imageHashes.length > 0) {
      await saveImageHashes(productId, storeId, req._imageHashes);
    }

    // Recalculate display price using store currency settings (additive)
    let createdProduct = result.rows[0];
    try {
      await recalculateSingleProductDisplayPrice(productId, storeId);
      const refreshed = await pool.query('SELECT * FROM products WHERE id=$1', [productId]);
      if (refreshed.rows.length > 0) createdProduct = refreshed.rows[0];
    } catch (e) {
      console.error('Display price recalc (create) failed:', e.message);
    }

    // If pending first-product approval, add notice to response
    if (req._pendingFirstProductApproval) {
      createdProduct.pending_approval = true;
      createdProduct._notice = 'Your first product requires admin approval before going live. It will be reviewed shortly.';
    }

    res.status(201).json(createdProduct);

    const imagesForEmbed = allImages.filter(url => url != null && url.length > 0);
    if (imagesForEmbed.length > 0) {
      setTimeout(() => processProductEmbeddings(productId, imagesForEmbed).catch((e) => {
        console.error('Background embedding error for product', productId, e.message);
      }), 0);
    }
  } catch (err) {
    console.error(err);
    cleanupUploadedFiles(req);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Something went wrong. Please try again later.' });
    }
  }
});

// UPDATE PRODUCT — owner or worker with inventory permission
router.put('/products/:id', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, requireVerifiedEmail, productUpload, checkDuplicateImages, validate(schemas.updateProduct), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const existing = await pool.query('SELECT * FROM products WHERE id=$1 AND store_id=$2', [req.params.id, storeId]);
    if (existing.rows.length === 0) {
      cleanupUploadedFiles(req);
      return res.status(404).json({ error: 'Product not found' });
    }

    const old = existing.rows[0];
    const name = req.body.name !== undefined ? sanitizeString(req.body.name, 200) : old.name;
    const price = req.body.price !== undefined ? parseFloat(req.body.price) : old.price;
    const quantity = req.body.quantity !== undefined ? parseInt(req.body.quantity) : old.quantity;
    const description = req.body.description !== undefined ? (req.body.description ? sanitizeString(req.body.description, 1000) : null) : old.description;
    const barcode = req.body.barcode !== undefined ? (req.body.barcode ? sanitizeString(req.body.barcode, 50) : null) : old.barcode;
    const category_id = req.body.category_id !== undefined ? (req.body.category_id ? parseInt(req.body.category_id) : null) : old.category_id;
    const low_stock_threshold = req.body.low_stock_threshold !== undefined ? parseInt(req.body.low_stock_threshold) : old.low_stock_threshold;
    const currency = req.body.currency !== undefined ? (req.body.currency ? sanitizeString(req.body.currency, 10) : null) : old.currency;

    let isOnline = old.is_online;
    let isOfflineToOnlineToggle = false;
    const onlineField = req.body.is_online !== undefined ? req.body.is_online : req.body.list_online;
    if (onlineField !== undefined && onlineField !== '') {
      const wantsOnline = onlineField === 'true' || onlineField === true;
      if (wantsOnline && !old.is_online) {
        // Defer the slot check + UPDATE to inside the per-store lock below,
        // so two concurrent edits (or an edit racing a create) cannot both
        // consume the last available slot.
        isOnline = true;
        isOfflineToOnlineToggle = true;
      } else if (!wantsOnline) {
        isOnline = false;
      }
    }

    if (barcode && barcode !== old.barcode) {
      const bcCheck = await pool.query('SELECT id FROM products WHERE barcode=$1 AND id != $2', [barcode, req.params.id]);
      if (bcCheck.rows.length > 0) {
        cleanupUploadedFiles(req);
        return res.status(409).json({ error: 'Barcode already exists', product_id: bcCheck.rows[0].id });
      }
    }

    const imageUrl = req.files?.['image']?.[0] ? `${getBaseUrl(req)}/uploads/${req.files['image'][0].filename}` : old.image_url;

    let allImages = old.images || [];
    if (req.body.existing_images) {
      try { allImages = JSON.parse(req.body.existing_images); } catch (_) { }
    }
    const newImages = req.files?.['extra_images']?.map(f => `${getBaseUrl(req)}/uploads/${f.filename}`) || [];
    allImages = [...allImages, ...newImages];
    if (imageUrl && !allImages.includes(imageUrl)) {
      allImages.unshift(imageUrl);
    }

    const UPDATE_SQL = `UPDATE products SET name=$1, price=$2, quantity=$3, description=$4, barcode=$5, category_id=$6, low_stock_threshold=$7, image_url=$8, images=$9, currency=$10,
       is_online=$11, went_online_at=CASE WHEN $11 THEN COALESCE(went_online_at, NOW()) ELSE NULL END, updated_at=NOW()
       WHERE id=$12 RETURNING *`;
    const updateParams = (isOnlineFinal) => [
      name, price, quantity, description, barcode, category_id, low_stock_threshold,
      imageUrl, JSON.stringify(allImages), currency, isOnlineFinal, req.params.id
    ];

    let result;
    if (isOfflineToOnlineToggle) {
      // Atomic slot-reserve + UPDATE under per-store advisory lock. Exclude
      // this product's id from the count so we don't double-count it after
      // a partial race where another transaction already saw it as offline.
      const lockOutcome = await withStoreLock(storeId, async (lockClient) => {
        const hasSlot = await canAddOnlineProduct(storeId, req.params.id);
        if (!hasSlot) return { denied: true };
        const upd = await lockClient.query(UPDATE_SQL, updateParams(true));
        return { denied: false, queryResult: upd };
      });
      if (lockOutcome.denied) {
        cleanupUploadedFiles(req);
        return slotLimitResponse(res, storeId);
      }
      result = lockOutcome.queryResult;
    } else {
      result = await pool.query(UPDATE_SQL, updateParams(isOnline));
    }

    // Recalculate display price using store currency settings (additive)
    let updatedProduct = result.rows[0];
    try {
      await recalculateSingleProductDisplayPrice(req.params.id, storeId);
      const refreshed = await pool.query('SELECT * FROM products WHERE id=$1', [req.params.id]);
      if (refreshed.rows.length > 0) updatedProduct = refreshed.rows[0];
    } catch (e) {
      console.error('Display price recalc (update) failed:', e.message);
    }
    res.json(updatedProduct);

    // Save image hashes for duplicate detection (new uploads only)
    if (req._imageHashes && req._imageHashes.length > 0) {
      saveImageHashes(req.params.id, storeId, req._imageHashes).catch(() => {});
    }

    const updatedImages = allImages.filter(url => url != null && url.length > 0);
    if (updatedImages.length > 0) {
      setTimeout(() => processProductEmbeddings(req.params.id, updatedImages).catch((e) => {
        console.error('Background embedding error for product', req.params.id, e.message);
      }), 0);
    }
  } catch (err) {
    console.error(err);
    cleanupUploadedFiles(req);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Something went wrong. Please try again later.' });
    }
  }
});

// DELETE PRODUCT — owner or worker with inventory permission
router.delete('/products/:id', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    // Fetch product and all related image URLs before deleting
    const productResult = await pool.query(
      'SELECT image_url, images FROM products WHERE id = $1 AND store_id = $2',
      [req.params.id, storeId]
    );
    if (productResult.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    const product = productResult.rows[0];
    const filesToDelete = [];
    if (product.image_url) filesToDelete.push(product.image_url);

    if (product.images) {
      const images = Array.isArray(product.images) ? product.images : [];
      filesToDelete.push(...images.filter(u => u && typeof u === 'string'));
    }

    const piResult = await pool.query(
      'SELECT image_url FROM product_images WHERE product_id = $1',
      [req.params.id]
    );
    for (const row of piResult.rows) {
      if (row.image_url) filesToDelete.push(row.image_url);
    }

    // Delete physical files from disk
    deleteUploadFiles(filesToDelete);

    // Defensive: clean up embeddings if table exists
    try { await pool.query('DELETE FROM image_embeddings WHERE product_id = $1', [req.params.id]); } catch (_) {}

    const result = await pool.query(
      'DELETE FROM products WHERE id = $1 AND store_id = $2 RETURNING id',
      [req.params.id, storeId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Product not found' });
    res.json({ message: 'Product deleted successfully' });
  } catch (err) {
    console.error('Delete product error:', err);
    res.status(500).json({ error: 'Something went wrong. Please try again later.' });
  }
});

// `POST /api/upload` removed: it was an orphan endpoint — any authenticated
// user (including guests via /guest-login) could upload arbitrary images
// that were never associated with a product or store, returning a public
// URL. That made it a free file-hosting service and a storage-exhaustion
// vector. Verified the Flutter client never calls `/api/upload`; all real
// uploads go through `POST /api/products` (multipart with auth+store
// scoping) or `POST /api/products/:id/images` (also scoped).

// ==================== PRODUCT IMAGES ====================
router.get('/products/:id/images', async (req, res) => {
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

router.post('/products/:id/images', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, upload.single('image'), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const productCheck = await pool.query(
      'SELECT p.id FROM products p WHERE p.id=$1 AND p.store_id=$2',
      [req.params.id, storeId]
    );
    if (productCheck.rows.length === 0) return res.status(403).json({ error: 'Not your product' });

    if (!req.file) return res.status(400).json({ error: 'No image' });
    const imageUrl = `${getBaseUrl(req)}/uploads/${req.file.filename}`;

    const result = await pool.query(
      'INSERT INTO product_images (product_id, image_url) VALUES ($1, $2) RETURNING *',
      [req.params.id, imageUrl]
    );
    res.status(201).json(result.rows[0]);

    const productId = req.params.id;
    const allImagesForEmbed = imageUrl ? [imageUrl] : [];
    if (allImagesForEmbed.length > 0) {
      setTimeout(() => processProductEmbeddings(productId, allImagesForEmbed).catch(() => { }), 0);
    }
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed' });
  }
});

router.delete('/products/:id/images/:imageId', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const result = await pool.query(
      `DELETE FROM product_images pi
       USING products p
       WHERE pi.id=$1 AND pi.product_id=$2 AND p.id=pi.product_id AND p.store_id=$3
       RETURNING pi.*`,
      [req.params.imageId, req.params.id, storeId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Image not found' });
    res.json({ message: 'Deleted' });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== PRODUCT SEARCH ====================
router.get('/products/:storeId/search', validateQuery(schemas.productSearch), async (req, res) => {
  try {
    const storeId = parseInt(req.params.storeId);
    if (isNaN(storeId) || storeId <= 0) {
      return res.status(400).json({ error: 'Invalid store ID' });
    }
    const { q, limit } = req.validatedQuery;
    const finalLimit = Math.min(limit || 20, 50);
    if (!q) return res.json([]);

    const result = await pool.query(
      `SELECT p.* FROM products p
       WHERE p.store_id = $1 AND (p.name ILIKE $2 OR p.barcode ILIKE $2) AND p.is_online = TRUE
       ORDER BY p.name
       LIMIT $3`,
      [storeId, `%${q}%`, finalLimit]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== BULK SYNC (Offline Support) ====================
router.post('/products/sync', authenticateToken, requireRealUser, attachStoreContext, requireInventoryAccess, async (req, res) => {
  const storeId = req.storeContext.store_id;
  const { creates = [], updates = [], deletes = [], stock_changes = [] } = req.body;
  const results = { creates: [], updates: [], deletes: [], stock_changes: [] };
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    // Serialize concurrent sync batches for the same store so multiple
    // devices syncing offline edits cannot collectively exceed the
    // subscription's online-slot cap. Released on COMMIT/ROLLBACK below.
    await client.query(
      'SELECT pg_advisory_xact_lock($1::int, $2::int)',
      [7842, storeId]
    );

    let createdToday = 0;
    const onlineLimit = await getOnlineLimit(storeId);
    try {
      const dailyCount = await client.query(
        `SELECT COUNT(*)::int as count FROM products WHERE store_id = $1 AND created_at >= CURRENT_DATE`,
        [storeId]
      );
      createdToday = dailyCount.rows[0].count;
    } catch (_) {}

    // --- CREATES ---
    for (const item of creates) {
      try {
        if (createdToday >= DAILY_CREATION_LIMIT) {
          results.creates.push({ local_id: item.local_id, status: 'error', error: 'daily_creation_limit_reached' });
          continue;
        }

        const { name, price, quantity, description, barcode, category_id, low_stock_threshold, currency } = item;

        if (barcode) {
          const existing = await client.query(
            'SELECT id FROM products WHERE barcode=$1 AND store_id=$2',
            [barcode, storeId]
          );
          if (existing.rows.length > 0) {
            results.creates.push({
              local_id: item.local_id,
              status: 'success',
              server_id: existing.rows[0].id,
              note: 'linked_existing_barcode',
            });
            continue;
          }
        }

        const wantsOnline = item.list_online === true;
        let isOnline = false;
        const slotCheck = await client.query(
          'SELECT COUNT(*)::int as count FROM products WHERE store_id = $1 AND is_online = TRUE',
          [storeId]
        );
        const hasSlot = slotCheck.rows[0].count < onlineLimit;
        if ((wantsOnline || item.list_online === undefined) && hasSlot) {
          isOnline = true;
        } else if (wantsOnline && !hasSlot) {
          results.creates.push({ local_id: item.local_id, status: 'error', error: 'online_slot_limit_reached' });
          continue;
        }

        const result = await client.query(
          `INSERT INTO products (store_id, name, price, quantity, description, barcode, category_id, low_stock_threshold, currency, images, is_online, went_online_at, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,NOW()) RETURNING *`,
          [
            storeId,
            sanitizeString(name, 200),
            parseFloat(price) || 0,
            parseInt(quantity) || 0,
            description ? sanitizeString(description, 1000) : null,
            barcode ? sanitizeString(barcode, 50) : null,
            category_id ? parseInt(category_id) : null,
            parseInt(low_stock_threshold) || 5,
            currency ? sanitizeString(currency, 10) : 'SYP',
            JSON.stringify([]),
            isOnline,
            isOnline ? new Date() : null,
          ]
        );
        createdToday++;
        results.creates.push({ local_id: item.local_id, status: 'success', server_id: result.rows[0].id, product: result.rows[0] });
      } catch (err) {
        console.error('Sync create error:', err);
        results.creates.push({ local_id: item.local_id, status: 'error', error: err.message });
      }
    }

    // --- UPDATES ---
    for (const item of updates) {
      try {
        const existing = await client.query('SELECT * FROM products WHERE id=$1 AND store_id=$2', [item.server_id, storeId]);
        if (existing.rows.length === 0) {
          results.updates.push({ local_id: item.local_id, status: 'error', error: 'Product not found' });
          continue;
        }

        const { name, price, quantity, description, barcode, category_id, low_stock_threshold, currency } = item;
        const old = existing.rows[0];

        if (barcode && barcode !== old.barcode) {
          const bcCheck = await client.query('SELECT id FROM products WHERE barcode=$1 AND id != $2', [barcode, item.server_id]);
          if (bcCheck.rows.length > 0) {
            results.updates.push({ local_id: item.local_id, status: 'error', error: 'Barcode already exists' });
            continue;
          }
        }

        const result = await client.query(
          `UPDATE products SET name=$1, price=$2, quantity=$3, description=$4, barcode=$5, category_id=$6, low_stock_threshold=$7, currency=$8, updated_at=NOW() WHERE id=$9 AND store_id=$10 RETURNING *`,
          [
            sanitizeString(name, 200),
            parseFloat(price) || 0,
            parseInt(quantity) || 0,
            description ? sanitizeString(description, 1000) : null,
            barcode ? sanitizeString(barcode, 50) : null,
            category_id ? parseInt(category_id) : null,
            parseInt(low_stock_threshold) || 5,
            currency ? sanitizeString(currency, 10) : 'SYP',
            item.server_id,
            storeId
          ]
        );
        results.updates.push({ local_id: item.local_id, status: 'success', product: result.rows[0] });
      } catch (err) {
        console.error('Sync update error:', err);
        results.updates.push({ local_id: item.local_id, status: 'error', error: err.message });
      }
    }

    // --- DELETES ---
    for (const item of deletes) {
      try {
        const result = await client.query(
          'DELETE FROM products WHERE id = $1 AND store_id = $2 RETURNING id',
          [item.product_id, storeId]
        );
        if (result.rows.length === 0) {
          results.deletes.push({ local_id: item.local_id, status: 'error', error: 'Product not found' });
        } else {
          results.deletes.push({ local_id: item.local_id, status: 'success', product_id: item.product_id });
        }
      } catch (err) {
        results.deletes.push({ local_id: item.local_id, status: 'error', error: err.message });
      }
    }

    // --- STOCK CHANGES ---
    for (const item of stock_changes) {
      try {
        const product = await client.query('SELECT quantity FROM products WHERE id=$1 AND store_id=$2', [item.product_id, storeId]);
        if (product.rows.length === 0) {
          results.stock_changes.push({ local_id: item.local_id, status: 'error', error: 'Product not found' });
          continue;
        }
        const newQty = Math.max(0, (product.rows[0].quantity || 0) + (parseInt(item.delta) || 0));
        await client.query(
          'UPDATE products SET quantity=$1, updated_at=NOW() WHERE id=$2',
          [newQty, item.product_id]
        );
        results.stock_changes.push({ local_id: item.local_id, status: 'success', product_id: item.product_id, new_quantity: newQty });
      } catch (err) {
        results.stock_changes.push({ local_id: item.local_id, status: 'error', error: err.message });
      }
    }

    await client.query('COMMIT');
    res.json(results);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Bulk sync error:', err);
    // Do not leak err.message — sync errors often surface SQL detail
    // (column names, constraint names) that aid SQL-injection probing.
    res.status(500).json({ error: 'Sync failed' });
  } finally {
    client.release();
  }
});

// ==================== ADMIN: FIRST-PRODUCT APPROVAL ====================
async function requireAdmin(req, res, next) {
  try {
    const result = await pool.query('SELECT role FROM users WHERE id = $1', [req.user.userId]);
    if (result.rows.length === 0 || result.rows[0].role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    next();
  } catch (err) {
    res.status(500).json({ error: 'Authorization failed' });
  }
}

router.get('/admin/pending-products', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.*, s.name as store_name, u.full_name as owner_name, u.email as owner_email
       FROM products p
       JOIN stores s ON s.id = p.store_id
       JOIN users u ON u.id = s.owner_id
       WHERE p.pending_approval = TRUE
       ORDER BY p.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Pending products error:', err);
    res.status(500).json({ error: 'Failed to fetch pending products' });
  }
});

router.put('/admin/products/:id/approve', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  try {
    const productId = parseInt(req.params.id);
    if (!Number.isInteger(productId) || productId <= 0) {
      return res.status(400).json({ error: 'Invalid product id' });
    }
    // Atomic claim — same race-fix as admin-dashboard. Without this, a
    // double-click on Approve flips is_online twice and could bypass the
    // free-tier slot cap (no slot check is done here, but the cap is
    // enforced by the slot-reserve lock elsewhere; we still avoid
    // double-emitting "approved" events).
    const claim = await pool.query(
      `UPDATE products
         SET pending_approval = FALSE, is_online = TRUE, went_online_at = NOW()
       WHERE id = $1 AND pending_approval = TRUE
       RETURNING id, store_id`,
      [productId]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Product is not pending approval' });
    }
    await pool.query(
      'UPDATE stores SET first_product_approved = TRUE WHERE id = $1',
      [claim.rows[0].store_id]
    );
    res.json({ message: 'Product approved and now live.', product_id: productId });
  } catch (err) {
    console.error('Approve product error:', err);
    res.status(500).json({ error: 'Failed to approve product' });
  }
});

router.put('/admin/products/:id/reject', authenticateToken, requireRealUser, requireAdmin, async (req, res) => {
  try {
    const productId = parseInt(req.params.id);
    if (!Number.isInteger(productId) || productId <= 0) {
      return res.status(400).json({ error: 'Invalid product id' });
    }
    // Atomic claim restricted to currently-pending products — prevents a
    // double-reject silently overwriting a previous decision and clears
    // went_online_at so the timeline reflects the rejection.
    const claim = await pool.query(
      `UPDATE products
         SET pending_approval = FALSE, is_online = FALSE, went_online_at = NULL
       WHERE id = $1 AND pending_approval = TRUE
       RETURNING id`,
      [productId]
    );
    if (claim.rows.length === 0) {
      return res.status(409).json({ error: 'Product is not pending approval' });
    }
    res.json({ message: 'Product rejected.', product_id: productId });
  } catch (err) {
    console.error('Reject product error:', err);
    res.status(500).json({ error: 'Failed to reject product' });
  }
});

module.exports = router;