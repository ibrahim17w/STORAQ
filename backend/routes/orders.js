//routes/orders.js
const express = require('express');
const router = express.Router();

const { pool } = require('../config/database');
const { authenticateToken, optionalAuth, requireRealUser, attachStoreContext, requireStoreAccess, requireStoreOwner } = require('../middleware/auth');
const { schemas, validate, validateQuery } = require('../middleware/validation');
const { sanitizeString, getPagination, getBaseUrl } = require('../middleware/helpers');

function generateReceiptNumber() {
  const now = new Date();
  const ts = now.getFullYear().toString().slice(2)
    + String(now.getMonth() + 1).padStart(2, '0')
    + String(now.getDate()).padStart(2, '0')
    + String(now.getHours()).padStart(2, '0')
    + String(now.getMinutes()).padStart(2, '0')
    + String(now.getSeconds()).padStart(2, '0');
  const rnd = require('crypto').randomInt(1000, 9999).toString();
  return `MB-${ts}-${rnd}`;
}

// ==================== CHECKOUT & ORDERS ====================
router.post('/checkout', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, validate(schemas.checkout), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const storeId = req.storeContext.store_id;

    const storeResult = await client.query(
      'SELECT id, name, city, country, phone, image_url FROM stores WHERE id=$1',
      [storeId]
    );
    if (storeResult.rows.length === 0) throw new Error('No store found');
    const store = storeResult.rows[0];

    const { items, payment_method, notes } = req.validatedBody;
    if (!items || !Array.isArray(items) || items.length === 0) {
      throw new Error('Cart is empty');
    }

    const receiptNumber = generateReceiptNumber();
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

    // Get cashier name for receipt (survives account deletion)
    const cashierResult = await client.query(
      'SELECT full_name FROM users WHERE id = $1',
      [req.user.userId]
    );
    const cashierName = cashierResult.rows[0]?.full_name || 'Unknown';

    const orderResult = await client.query(
      `INSERT INTO orders (store_id, cashier_id, cashier_name, customer_name, receipt_number, total, status, payment_method, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [store.id, req.user.userId, cashierName, req.validatedBody.customer_name || null, receiptNumber, total, 'completed', payment_method || 'cash', notes || null]
    );
    const order = orderResult.rows[0];

    for (const item of validatedItems) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price, total_price)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [order.id, item.product_id, item.product_name, item.quantity, item.unit_price, item.total_price]
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

router.get('/orders', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const { page, limit, offset } = getPagination(req, 20, 100);
    const countResult = await pool.query('SELECT COUNT(*) as total FROM orders WHERE store_id = $1', [storeId]);
    const total = parseInt(countResult.rows[0].total);

    const result = await pool.query(
      `SELECT o.*,
        (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) as item_count
       FROM orders o
       WHERE o.store_id=$1
       ORDER BY o.created_at DESC
       LIMIT $2 OFFSET $3`,
      [storeId, limit, offset]
    );

    res.json({
      data: result.rows,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) }
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load orders' });
  }
});

router.get('/orders/:id', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

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

router.post('/orders', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, validate(schemas.createOrder), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const storeId = req.storeContext.store_id;

    const items = req.validatedBody.items;
    if (!Array.isArray(items) || items.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Items required' });
    }

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

    const discount = parseFloat(req.validatedBody.discount) || 0;
    const tax = parseFloat(req.validatedBody.tax) || 0;
    
    const frontendSubtotal = parseFloat(req.validatedBody.subtotal);
    const frontendTotal = parseFloat(req.validatedBody.total);
    const finalSubtotal = (!isNaN(frontendSubtotal) && frontendSubtotal > 0) ? frontendSubtotal : subtotal;
    const computedTotal = Math.max(0, finalSubtotal - discount + tax);
    const finalTotal = (!isNaN(frontendTotal) && frontendTotal > 0) ? frontendTotal : computedTotal;
    const receiptNumber = generateReceiptNumber();

    // Get cashier name for receipt (survives account deletion)
    const cashierResult = await client.query(
      'SELECT full_name FROM users WHERE id = $1',
      [req.user.userId]
    );
    const cashierName = cashierResult.rows[0]?.full_name || 'Unknown';

    const orderResult = await client.query(
      `INSERT INTO orders (store_id, cashier_id, cashier_name, customer_name, customer_phone, subtotal, discount, tax, total, status, payment_method, receipt_number, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
       RETURNING *`,
      [
        storeId,
        req.user.userId,
        cashierName,
        req.validatedBody.customer_name || null,
        req.validatedBody.customer_phone || null,
        finalSubtotal,
        discount,
        tax,
        finalTotal,
        'completed',
        req.validatedBody.payment_method || 'cash',
        receiptNumber,
        req.validatedBody.notes || null,
      ]
    );
    const orderId = orderResult.rows[0].id;

    for (const item of items) {
      const productId = item.product_id;
      const qty = parseInt(item.quantity);
      const unitPrice = parseFloat(item.unit_price) || 0;
      const lineTotal = parseFloat(item.total_price) || (unitPrice * qty);

      await client.query(
        `INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price, total_price, barcode)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [orderId, productId, item.product_name || null, qty, unitPrice, lineTotal, item.barcode || null]
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

// ==================== LOW STOCK ====================
router.get('/my-store/low-stock', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const result = await pool.query(
      `SELECT id, name, quantity, barcode, price FROM products
       WHERE store_id = $1 AND quantity <= COALESCE(low_stock_threshold, 5) AND quantity >= 0
       ORDER BY quantity ASC, name`,
      [storeId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

// ==================== RECEIPT SETTINGS ====================
router.get('/my-store/receipt-settings', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const result = await pool.query(
      'SELECT * FROM receipt_settings WHERE store_id = $1',
      [storeId]
    );
    if (result.rows.length > 0) return res.json(result.rows[0]);

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

router.put('/my-store/receipt-settings', authenticateToken, requireRealUser, attachStoreContext, requireStoreAccess, validate(schemas.receiptSettings), async (req, res) => {
  try {
    const storeId = req.storeContext.store_id;

    const existing = await pool.query('SELECT id FROM receipt_settings WHERE store_id = $1', [storeId]);
    const hasRecord = existing.rows.length > 0;

    const { footer_message, show_logo, show_barcode, currency_symbol } = req.validatedBody;

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
        [footer_message !== undefined ? sanitizeString(footer_message, 255) : null, show_logo, show_barcode, currency_symbol !== undefined ? sanitizeString(currency_symbol, 10) : null, storeId]
      );
    } else {
      result = await pool.query(
        `INSERT INTO receipt_settings (store_id, footer_message, show_logo, show_barcode, currency_symbol)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [storeId, footer_message ? sanitizeString(footer_message, 255) : 'Thank you for your purchase!', show_logo ?? true, show_barcode ?? true, currency_symbol ? sanitizeString(currency_symbol, 10) : 'SYP']
      );
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed' });
  }
});

module.exports = router;