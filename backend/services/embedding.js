//services/embedding.js
const { pool } = require('../config/database');
const path = require('path');
const fs = require('fs');
const { uploadsDir } = require('../config/upload');

let clipProcessor = null;
let clipVisionModel = null;
let pgvectorAvailable = false;
let transformersModule = null;
let clipLoadPromise = null;

async function getTransformers() {
  if (transformersModule) return transformersModule;
  try {
    const mod = await import('@xenova/transformers');
    // Handle both ESM and CJS module structures
    transformersModule = mod.default || mod;
    console.log('Transformers module loaded. Available keys:', Object.keys(transformersModule).slice(0, 10));
    return transformersModule;
  } catch (err) {
    console.error('Failed to import @xenova/transformers:', err.message);
    throw err;
  }
}

async function initEmbeddingTables() {
  try {
    await pool.query('CREATE EXTENSION IF NOT EXISTS vector');
    pgvectorAvailable = true;
    await pool.query(`
      CREATE TABLE IF NOT EXISTS image_embeddings (
        id SERIAL PRIMARY KEY,
        product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
        image_url TEXT NOT NULL,
        embedding vector(512),
        model_name VARCHAR(50) DEFAULT 'Xenova/clip-vit-base-patch16',
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(product_id, image_url)
      )
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_image_embeddings_vector 
      ON image_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
    `);
    console.log('✅ pgvector embedding tables ready');
  } catch (err) {
    console.log('⚠️ pgvector not available, using JSONB fallback for embeddings');
    pgvectorAvailable = false;
    await pool.query(`
      CREATE TABLE IF NOT EXISTS image_embeddings (
        id SERIAL PRIMARY KEY,
        product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
        image_url TEXT NOT NULL,
        embedding_json JSONB,
        model_name VARCHAR(50) DEFAULT 'Xenova/clip-vit-base-patch16',
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(product_id, image_url)
      )
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_image_embeddings_product ON image_embeddings(product_id)
    `);
  }
}

async function loadClipModel() {
  if (clipProcessor && clipVisionModel) return { processor: clipProcessor, model: clipVisionModel };
  if (!clipLoadPromise) {
    clipLoadPromise = (async () => {
      const tf = await getTransformers();
      try {
        const AutoProcessor = tf.AutoProcessor || tf.default.AutoProcessor;
        const CLIPVisionModelWithProjection = tf.CLIPVisionModelWithProjection || tf.default.CLIPVisionModelWithProjection;
        const env = tf.env || tf.default.env || {};

        if (env.allowRemoteModels !== undefined) env.allowRemoteModels = true;
        if (env.localModelPath !== undefined) env.localModelPath = './models/';

        const modelId = 'Xenova/clip-vit-base-patch16';
        clipProcessor = await AutoProcessor.from_pretrained(modelId);
        clipVisionModel = await CLIPVisionModelWithProjection.from_pretrained(modelId, { quantized: true });
        console.log('✅ CLIP vision model loaded (Xenova/clip-vit-base-patch16)');
        return { processor: clipProcessor, model: clipVisionModel };
      } catch (err) {
        console.error('❌ Failed to load CLIP model:', err.message);
        clipLoadPromise = null;
        throw new Error('Image embedding model unavailable: ' + err.message);
      }
    })();
  }
  return clipLoadPromise;
}

function normalizeVector(vec) {
  const norm = Math.sqrt(vec.reduce((sum, v) => sum + v * v, 0));
  if (norm === 0) return vec;
  return vec.map(v => v / norm);
}

async function generateImageEmbedding(imagePath) {
  const { processor, model } = await loadClipModel();
  const tf = await getTransformers();

  const RawImage = tf.RawImage || (tf.default && tf.default.RawImage);
  if (!RawImage) {
    throw new Error('RawImage not available in @xenova/transformers');
  }

  const image = await RawImage.read(imagePath);
  const imageInputs = await processor(image);
  const { image_embeds } = await model(imageInputs);

  let vec;
  if (image_embeds && image_embeds.data) {
    vec = Array.from(image_embeds.data);
  } else {
    throw new Error('Failed to extract image embedding');
  }

  vec = vec.map(v => typeof v === 'number' ? v : parseFloat(v)).filter(v => !isNaN(v));
  if (vec.length === 0) throw new Error('Empty embedding generated');
  if (vec.length !== 512) {
    console.warn(`Embedding dimension is ${vec.length}, expected 512. Truncating/padding.`);
    if (vec.length > 512) vec = vec.slice(0, 512);
    else while (vec.length < 512) vec.push(0);
  }
  return normalizeVector(vec);
}

async function saveEmbedding(productId, imageUrl, embedding) {
  if (!embedding || embedding.length === 0) return;
  if (pgvectorAvailable) {
    const vectorStr = `[${embedding.join(',')}]`;
    await pool.query(
      `INSERT INTO image_embeddings (product_id, image_url, embedding)
       VALUES ($1, $2, $3::vector)
       ON CONFLICT (product_id, image_url) DO UPDATE SET
         embedding = EXCLUDED.embedding,
         model_name = 'Xenova/clip-vit-base-patch16',
         created_at = NOW()`,
      [productId, imageUrl, vectorStr]
    );
  } else {
    await pool.query(
      `INSERT INTO image_embeddings (product_id, image_url, embedding_json)
       VALUES ($1, $2, $3)
       ON CONFLICT (product_id, image_url) DO UPDATE SET
         embedding_json = EXCLUDED.embedding_json,
         model_name = 'Xenova/clip-vit-base-patch16',
         created_at = NOW()`,
      [productId, imageUrl, JSON.stringify(embedding)]
    );
  }
}

async function deleteEmbeddingsForProduct(productId) {
  await pool.query('DELETE FROM image_embeddings WHERE product_id = $1', [productId]);
}

function cosineSimilarity(a, b) {
  if (!Array.isArray(a)) a = JSON.parse(JSON.stringify(a));
  if (!Array.isArray(b)) b = JSON.parse(JSON.stringify(b));
  let dot = 0, normA = 0, normB = 0;
  const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

async function findSimilarProductsByImage(embedding, limit = 20, minSimilarity = 0.80) {
  let rows = [];

  if (pgvectorAvailable) {
    const vectorStr = `[${embedding.join(',')}]`;
    const result = await pool.query(
      `SELECT 
         ie.product_id,
         ie.image_url,
         1 - (ie.embedding <=> $1::vector) AS similarity
       FROM image_embeddings ie
       WHERE 1 - (ie.embedding <=> $1::vector) >= $2
       ORDER BY similarity DESC
       LIMIT $3`,
      [vectorStr, minSimilarity, limit * 3] // fetch extra to allow for dedup
    );
    rows = result.rows;
  } else {
    const result = await pool.query(
      `SELECT product_id, image_url, embedding_json 
       FROM image_embeddings 
       LIMIT 2000`
    );
    rows = result.rows.map(row => ({
      product_id: row.product_id,
      image_url: row.image_url,
      similarity: cosineSimilarity(embedding, row.embedding_json)
    })).filter(r => r.similarity >= minSimilarity);
    rows.sort((a, b) => b.similarity - a.similarity);
    rows = rows.slice(0, limit * 3);
  }

  // Return all matching image embeddings, sorted by similarity
  return rows
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, limit);
}

async function processProductEmbeddings(productId, imageUrls) {
  try {
    await deleteEmbeddingsForProduct(productId);
    for (const url of imageUrls) {
      if (!url) continue;
      const filename = path.basename(url);
      const filePath = path.join(uploadsDir, filename);

      if (!fs.existsSync(filePath)) {
        console.log('Image file not found for embedding:', filePath);
        continue;
      }
      const embedding = await generateImageEmbedding(filePath);
      await saveEmbedding(productId, url, embedding);
    }
    console.log(`✅ Embeddings generated for product ${productId}`);
  } catch (err) {
    console.error(`❌ Embedding generation failed for product ${productId}:`, err.message);
  }
}

module.exports = {
  getTransformers,
  initEmbeddingTables,
  loadClipModel,
  normalizeVector,
  generateImageEmbedding,
  saveEmbedding,
  deleteEmbeddingsForProduct,
  cosineSimilarity,
  findSimilarProductsByImage,
  processProductEmbeddings
};