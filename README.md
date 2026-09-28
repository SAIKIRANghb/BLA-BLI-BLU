# Bla Bli Blu — commerce app

A full-stack recreation of [blabliblulife.com](https://blabliblulife.com/) as a
Flutter mobile/web app plus a Node.js + PostgreSQL API.

```
REPO/
├── backend/   Node.js (ESM + JSDoc) API — DDD layering, PostgreSQL
├── mobile/    Flutter app — Riverpod + go_router, redux-like store
└── _scratch/  local tooling (Flutter SDK, scraped source data) — gitignored
```

---

## Backend (`backend/`)

Node.js 18+, Express, PostgreSQL. Plain ES modules with JSDoc types — no TS build.

**Domain-Driven Design layout** (`src/`):

| Layer | What lives there |
|---|---|
| `domain/` | Entities (`Product`, `Cart`, `Order`, `User`), aggregate roots, value objects (`Money` in integer paise, `Email`, `Address`), `Result`, domain events |
| `application/` | Use-case services (catalog, checkout, auth, tracking…), event handlers |
| `infrastructure/` | PostgreSQL repositories, unit of work, JWT/bcrypt adapters, event bus |
| `interfaces/` | HTTP controllers/routes, validators (Zod), middleware |
| `modules/` | Feature modules wiring their routes + services |

Principles: dependency direction points inward (interfaces → application →
domain), repositories behind interfaces, explicit UnitOfWork per request,
cross-cutting concerns (auth, validation, errors) at the edge.

### Setup

```bash
cd backend
cp .env.example .env          # then edit DB_* and JWT_SECRET
npm install
npm run db:setup              # migrate + seed (69 products, 13 collections,
                              # 228 reviews, 122 notes, 9 FAQs, 9 CMS pages)
npm start                     # http://localhost:4000/api
```

`REPOSITORY_DRIVER=memory` runs the whole API from the seed file with no
database (useful for quick demos).

### Verify

```bash
npm run smoke                 # 40 end-to-end checks against a running server
npm test                      # 48 domain unit tests (node --test)
```

### API notes

- Envelope: success `{ "success": true, "data": ..., "meta": ... }`,
  failure `{ "success": false, "error": { code, message, details } }`.
- Prices are **integer paise** everywhere (`49900` = ₹499.00).
- Auth: `POST /api/auth/register|login` → `{ accessToken, refreshToken }`,
  then `Authorization: Bearer <token>`.
- Admin: header `x-api-key` (dev value `blabliblu-admin`) advances order status.
- Coupons: `WELCOME10` (10%), `FLAT100` (₹100), `FREESHIP`.
- Track an order with order number + email/phone: `POST /api/orders/track`.
- Invalid input → `422 VALIDATION_ERROR` with per-field `details`;
  unknown routes/products → `404 NOT_FOUND`.

---

## Mobile (`mobile/`)

Flutter app (Dart 3) — **Riverpod** for DI/async state and a **redux-like**
store: a single immutable `AppState`, a sealed `AppAction` union, a pure
`rootReducer`, and a `Store extends Notifier<AppState>` that the UI reads via
`store.select(...)` (subscribers rebuild only on the slices they select).

Routing: **go_router**, ShellRoute with a persistent bottom nav
(Home / Shop / Search / Bag) plus full-screen routes for auth, checkout,
orders, tracking, FAQ, profile and CMS pages.

### Screens

Home (hero carousel, claims, collection strips, bestsellers) · Shop with
filter/sort · Collection listing · Search with recent searches ·
Product detail (gallery, variants, notes, reviews) · Cart with coupons ·
Address book + checkout (COD/UPI) · Orders, order detail, live tracking ·
Sign in / sign up / profile · FAQ · CMS pages.

### Data source switch

`lib/core/config/app_config.dart`:

```dart
const bool kUseLocalSeed = true;   // false → hit kApiHost instead
```

`true` (default) serves everything from `assets/seed/seed.json`
(regenerate with `npm run seed:mobile` in `backend/`), so the app runs with
no backend at all. `false` talks to the API (`kApiHost`, Android emulator
alias `10.0.2.2:4000`).

Images: `CachedImage` (`lib/shared/widgets/cached_image.dart`) — in-house
session LRU + memory cache with pulse placeholder and fade-in, no plugin
dependencies (works on every target without native assets).

### Run / verify

```bash
cd mobile
flutter pub get
flutter run                   # device/emulator
flutter analyze --no-pub      # 0 issues
flutter test --no-pub         # models, reducer, CachedImage, links/routing,
                              # pagination, hero autoplay, cart badge, layout smoke
flutter build web --release --no-pub
```

`test/layout_smoke_test.dart` walks every route at 390×844 and 653×891 and
fails on any rendering exception (RenderFlex overflow etc.). It is
deliberately golden-free so it passes on any machine.

> **Windows note:** the Flutter SDK used during development lives in
> `_scratch/flutter/` (gitignored). If `flutter` is not on your PATH, invoke
> `_scratch\flutter\bin\flutter.bat` (or install Flutter yourself) and run all
> commands from `mobile/` with `--no-pub` after a one-time `flutter pub get`.

---

## Quick demo

```bash
# terminal 1
cd backend && npm run db:setup && npm start
# terminal 2
cd mobile  && flutter run        # kUseLocalSeed = true → no backend needed
```
