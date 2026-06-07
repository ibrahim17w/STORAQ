# STORAQ

STORAQ is a Flutter marketplace and store POS app backed by a Node.js/PostgreSQL API. It supports product discovery, store inventory, checkout, receipts, offline SQLite sync, subscriptions, maps, barcode scanning, admin moderation, and multilingual UI.

## Repository Layout

- `lib/` - Flutter client screens, services, widgets, localization, and offline storage.
- `backend/` - Express API, PostgreSQL schema initialization, auth, marketplace, orders, subscriptions, analytics, and search.
- `admin-dashboard/` - Separate Express admin dashboard for moderation, promo codes, and subscription verification.
- `assets/` - Flutter assets such as fonts.

## Requirements

- Flutter SDK compatible with the Dart SDK in `pubspec.yaml`
- Node.js 20 or newer
- PostgreSQL
- Optional: Cloudflare Turnstile keys, SMTP/Resend email credentials, pgvector support for image embeddings

## Flutter App

Install dependencies and run the app:

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

If `API_BASE_URL` is not provided, debug builds use the local backend and release builds fall back to the configured production API in `ApiService`.

Useful checks:

```sh
flutter analyze
flutter test
```

## Backend API

Create `backend/.env` with the required production values:

```env
DATABASE_URL=postgres://user:password@localhost:5432/storaq
JWT_SECRET=replace-me
ALLOWED_ORIGINS=http://localhost:3000
NODE_ENV=development
```

Then run:

```sh
cd backend
npm install
npm run dev
```

Useful checks:

```sh
npm test
```

## Admin Dashboard

Create `admin-dashboard/.env`:

```env
DATABASE_URL=postgres://user:password@localhost:5432/storaq
ADMIN_JWT_SECRET=replace-me
NODE_ENV=development
```

Then run:

```sh
cd admin-dashboard
npm install
npm run dev
```

## Production Readiness Notes

- Use strong, unique `JWT_SECRET` and `ADMIN_JWT_SECRET` values.
- Set `NODE_ENV=production` in deployed services.
- Configure `TURNSTILE_SECRET_KEY` and `TURNSTILE_SITE_KEY` before enabling public registration.
- Keep uploaded media policy explicit. Product images are currently served from `/uploads`.
- Replace startup schema changes with versioned migrations before high-risk production deployments.
- Run `flutter analyze`, `flutter test`, and backend tests in CI before merging.

## Current Quality Gates

The repository includes a CI workflow for:

- Flutter dependency install, static analysis, and tests
- Backend dependency install and Node test runner
- Admin dashboard dependency install smoke check
