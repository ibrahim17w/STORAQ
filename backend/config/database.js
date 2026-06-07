//config/database.js
const { Pool } = require('pg');
require('dotenv').config();

// Pool sizing — defaults aimed at a single Node process on a small (~512MB
// to 1GB RAM) host with a managed Postgres that exposes ~60-100 connections
// (Render/Supabase/Neon free tiers all fit). Override via env in production:
//   PG_POOL_MAX                 - max concurrent connections per Node process
//   PG_IDLE_TIMEOUT_MS          - close idle clients after N ms (frees DB slots)
//   PG_CONNECTION_TIMEOUT_MS    - fail fast on DB outage rather than hang
//   PG_STATEMENT_TIMEOUT_MS     - server-side cap on any single query
//
// Why this matters: the pg driver default is 10. Under load that means the
// 11th concurrent DB-bound request queues until one of the first 10 returns
// — which on a slow query stacks the whole API. Bumping to 20 typically
// triples throughput on read-heavy workloads. Going higher than ~25 per
// Node process tends to be wasted because Postgres can only run N CPU-bound
// queries in parallel anyway.
const PG_POOL_MAX = parseInt(process.env.PG_POOL_MAX || '20', 10);
const PG_IDLE_TIMEOUT_MS = parseInt(process.env.PG_IDLE_TIMEOUT_MS || '30000', 10);
const PG_CONNECTION_TIMEOUT_MS = parseInt(process.env.PG_CONNECTION_TIMEOUT_MS || '5000', 10);
const PG_STATEMENT_TIMEOUT_MS = parseInt(process.env.PG_STATEMENT_TIMEOUT_MS || '15000', 10);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: PG_POOL_MAX,
  idleTimeoutMillis: PG_IDLE_TIMEOUT_MS,
  connectionTimeoutMillis: PG_CONNECTION_TIMEOUT_MS,
  // server-side timeout: a runaway query is killed by Postgres after this
  // many ms even if the Node side hangs, so a slow query can't permanently
  // hold a pool slot.
  statement_timeout: PG_STATEMENT_TIMEOUT_MS,
});

// An idle client emitting an error (e.g. server-side terminated connection)
// would otherwise crash the Node process with an uncaught exception. Log and
// let the pool transparently replace the client on next checkout.
pool.on('error', (err) => {
  console.error('[pg] idle client error:', err.message);
});

module.exports = { pool };
