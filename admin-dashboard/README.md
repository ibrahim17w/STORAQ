# STORAQ — Admin Dashboard

Completely isolated admin panel. Connects to the same PostgreSQL database, runs on a different port.

## Structure

```
admin-dashboard/
├── server.js          ← entire backend (single file)
├── public/
│   └── index.html     ← entire frontend (CSS + JS inline, single file)
├── .env               ← your config
└── package.json
```

## Quick Start

```bash
cd admin-dashboard
npm install
cp .env.example .env   # then edit with your values
npm start
```

Open `http://localhost:4400`

## Make yourself admin

```sql
UPDATE users SET is_admin = TRUE WHERE email = 'you@example.com';
```

## .env variables

| Variable | Description |
|----------|-------------|
| DATABASE_URL | Same PostgreSQL connection string as main API |
| ADMIN_JWT_SECRET | Random secret (DIFFERENT from main API) |
| PORT | Default 4400 |
| PG_SSL | Set `true` if DB requires SSL |
