//routes//search.js
const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');

const { upload } = require('../config/upload');
const { authenticateToken, optionalAuth, requireRealUser } = require('../middleware/auth');
const { loadClipModel, generateImageEmbedding, findSimilarProductsByImage } = require('../services/embedding');
const { pool } = require('../config/database');
const fs = require('fs');

// ==================== IMAGE SIMILARITY SEARCH ====================
const imageSearchLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => res.status(429).json({ error: 'Too many image searches. Please wait a minute.' }),
});

router.post('/search/image-similarity', imageSearchLimiter, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No image uploaded' });

    try {
      await loadClipModel();
    } catch (modelErr) {
      console.error('Model load error:', modelErr.message);
      return res.status(503).json({
        error: 'Image search is currently unavailable. Model not loaded.',
        detail: modelErr.message
      });
    }

    const filePath = req.file.path;
    const embedding = await generateImageEmbedding(filePath);

    const similar = await findSimilarProductsByImage(embedding, 50, 0.80);

    if (similar.length === 0) {
      return res.json({
        results: [],
        message: 'No visually similar products found',
        reason: 'no_matches'
      });
    }

    const productIds = similar.map(s => s.product_id);
    const placeholders = productIds.map((_, i) => '$' + (i + 1)).join(',');
    const productsResult = await pool.query(
      `SELECT p.*, s.name as shop_name, s.city, s.country, s.lat, s.lng, s.id as store_id
       FROM products p
       JOIN stores s ON p.store_id = s.id
       WHERE p.id IN (${placeholders}) AND p.quantity > 0`,
      productIds
    );

    const productMap = new Map(productsResult.rows.map(p => [p.id, p]));

    // Build results with similarity scores - NO DEDUPLICATION, show ALL matching products
    let results = similar
      .map(s => {
        const product = productMap.get(s.product_id);
        if (!product) return null;
        return {
          ...product,
          similarity_score: Math.round(s.similarity * 1000) / 1000,
          matched_image_url: s.image_url,
        };
      })
      .filter(Boolean);

    // Sort by similarity (highest first) - keep ALL results
    results.sort((a, b) => b.similarity_score - a.similarity_score);

    // Limit to top 50 results (increased from 20)
    results = results.slice(0, 50);

    if (results.length === 0) {
      return res.json({
        results: [],
        message: 'Similar products found but currently unavailable',
        reason: 'out_of_stock'
      });
    }

    res.json({ results });
  } catch (err) {
    console.error('Image similarity search error:', err);
    res.status(500).json({ error: err.message || 'Image search failed' });
  } finally {
    if (req.file?.path) {
      fs.unlink(req.file.path, (unlinkErr) => {
        if (unlinkErr) console.error('Failed to delete temp image:', unlinkErr.message);
      });
    }
  }
});

module.exports = router;
