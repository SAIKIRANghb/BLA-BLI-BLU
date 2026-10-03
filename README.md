# Bla Bli Blu — commerce app

A full-stack recreation of [blabliblulife.com](https://blabliblulife.com/) as a
Flutter mobile/web app plus a Node.js + PostgreSQL API.

```
REPO/
├── backend/   Node.js (ESM + JSDoc) API — DDD layering, PostgreSQL
├── infra/     OSRM routing stack (New Delhi OSM extract + WSL/Docker scripts)
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
npm run smoke                 # 72 end-to-end checks against a running server
                              # (needs OSRM up for the routing cases)
npm test                      # 101 domain unit tests (node --test)
```

### API notes

- Envelope: success `{ "success": true, "data": ..., "meta": ... }`,
  failure `{ "success": false, "error": { code, message, details } }`.
- Prices are **integer paise** everywhere (`49900` = ₹499.00).
- Auth: `POST /api/auth/register|login` → `{ accessToken, refreshToken }`,
  then `Authorization: Bearer <token>`.
- Admin: header `x-api-key` (dev value `blabliblu-admin`) advances order status.
- Rider: header `x-rider-key` (dev value `blabliblu-rider`, env `RIDER_KEY`)
  posts GPS fixes and reads the delivery queue (see "Rider GPS tracking").
- Coupons: `WELCOME10` (10%), `FLAT100` (₹100), `FREESHIP`.
- Track an order with order number + email/phone: `POST /api/orders/track`.
- Invalid input → `422 VALIDATION_ERROR` with per-field `details`;
  unknown routes/products → `404 NOT_FOUND`.
- Routing: six OSRM services under `/api/routing/` (see below).

---

## Maps & routing (OSM + OSRM)

OpenStreetMap data is routed by [OSRM](https://github.com/Project-OSRM/osrm-backend)
serving all six engine services through the API:

| Endpoint | OSRM service | Used by the app for |
|---|---|---|
| `GET /api/routing/nearest` | Nearest | snapping the address-picker pin to a road |
| `GET /api/routing/route` | Route | checkout ETA + live-map route polyline |
| `GET /api/routing/table` | Table | multi-point ETA matrix |
| `GET /api/routing/match` | Match | map-matching the rider's GPS trace |
| `GET /api/routing/trip` | Trip | multi-stop trip planning (API-level) |
| `GET /api/routing/tile/:z/:x/:y` | Tile | vector tiles (API-level, z ≥ 12) |

Conventions: coordinates are `lat,lng` in the app and converted to OSRM's
`lng,lat` at the gateway; the profile whitelist is `driving`; responses default
to `geometries=geojson` + `overview=full`; transport failures map to
`503 ROUTING_UNAVAILABLE` / `504 ROUTING_TIMEOUT`; validation failures to the
usual `422 VALIDATION_ERROR` envelope.

### OSRM setup (WSL2 + Docker)

```bash
infra/osrm/setup.sh     # once: downloads the BBBike New Delhi extract,
                        # partitions (MLD) and builds the driving profile
infra/osrm/start.sh     # docker run --restart unless-stopped → :5000
infra/osrm/stop.sh
```

The API talks to it via `OSRM_URL` (default `http://127.0.0.1:5000`),
`OSRM_PROFILE=driving`, `OSRM_TIMEOUT_MS=8000`. The raw/processed data lives in
`infra/osrm/data/` (gitignored). With OSRM down the app still works — routing
endpoints return `503` and the Flutter screens fall back gracefully.

---

## Rider GPS tracking

Real rider positions end to end: the rider screen (or any device) posts GPS
fixes, the backend keeps a bounded trail per order, and the customer's live
map polls it. Migration `db/migrations/003_rider_positions.sql` creates
`rider_positions` (FK `order_id` cascade, index `order_id + recorded_at DESC`,
7-day prune on insert).

| Endpoint | Auth | Purpose |
|---|---|---|
| `POST /api/tracking/orders/:id/position` | `x-rider-key` | append one fix (201; `404` unknown order, `409` terminal order) |
| `GET /api/tracking/orders/:id` | `Bearer` + ownership | customer trail: `{ orderNumber, status, latest, trail[], updatedAt }` |
| `GET /api/tracking/deliveries` | `x-rider-key` | rider queue: active orders that carry a map pin |

- Fix body: `{ lat, lng, accuracyM?, speedMps?, headingDeg?, recordedAt? }`;
  domain limits are `accuracyM ≤ 1000`, `speedMps ≤ 80`, and a device clock at
  most `300s` ahead of the server.
- Trail reads clamp `limit` to `2..500` (default 120) and return the newest
  slice in chronological order; ownership mirrors `GET /api/orders/:id`
  (account owner or guest email) — anonymous `401`, wrong user `403`.
- The rider key is `security.riderKey` / `RIDER_KEY` (default
  `blabliblu-rider`) and ships as `kRiderKey` in the app's `app_config.dart`.
- The admin `x-api-key` is also accepted on the rider endpoints for curl.

### Live map behaviour (online/prod)

`DeliveryMapScreen` polls the trail every 2 s and, at least every 16 s (or
whenever the rider strays > 50 m off the drawn line), re-asks OSRM **Route**
from the rider's current fix to the delivery pin. One call answers both open
questions: the fresh geometry (the polyline follows the rider's actual path)
and the remaining duration (the ETA card ticks it down between checks).
Progress is a monotone distance model — a reroute can only move it forward.
A trail older than 15 s shows "Last seen Ns ago"; 5 consecutive failed polls
flip the card to "Connection trouble". The rider screen does the same
periodic reroute from its own position.

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
Address book + checkout (COD/UPI) with map pin & live ETA · address picker
(map pin → manual form) · orders, order detail + live delivery map ·
Sign in / sign up / profile · FAQ · CMS pages ·
rider queue (`/rider`) + rider console (`/rider/:id`).

Maps: **flutter_map** (OpenStreetMap tiles, `kOsmUserAgent` set) backs four
screens — the address picker (`/addresses/pick`, snaps the pin via
`/routing/nearest`), the checkout ETA card (`/routing/route` → "Delivers in
~N min"), the live delivery map (`/order/:id/live`), and the rider console
(route + live position).

### Rider console

`Account → Rider queue → /rider` lists the backend's active deliveries
(`GET /api/tracking/deliveries`); opening one (`/rider/:id`) shows the route
map, destination and a live ETA, and offers two ways to feed the customer
map:

- **Use device GPS** — a `geolocator` stream throttled to 1 fix/second,
  posted straight to `POST /api/tracking/orders/:id/position`.
- **Demo ride** — walks the loaded OSRM route in `kDemoRideSeconds` (45 s),
  posting one jittered fix per second (±0.00005°, accuracy 10–25 m). Runs in
  seed mode too, so the whole pipeline can be demoed offline.

Either engine re-checks the ETA through OSRM **Route** every 10 fixes and
swaps the polyline in when the rider leaves the drawn line.

### Live delivery map

Two engines behind one screen, picked by `kUseLocalSeed`:

- **seed / offline** — the original 350 ms ticker walks the rider along the
  planned hub → pin geometry (simulation, engine unchanged).
- **live / online** — polls `GET /api/tracking/orders/:id` every 2 s and
  projects the real fixes onto the drawn route for a monotone progress;
  periodic/off-route OSRM **Route** reroutes update the polyline and ETA
  (details in the backend section above).

Both engines paint the marker through `RiderGlider`
(`lib/shared/widgets/rider_glider.dart`): each incoming fix *glides* over the
interval it arrived on — following the drawn polyline when the fix sits on it,
a straight line otherwise — so the marker moves continuously instead of
hopping every tick/poll, and only its own `MarkerLayer` rebuilds per frame
(the progress bar eases to each new value the same way). Fixes more than
250 m apart are treated as GPS corrections and jump rather than fly; the
simulated walks opt out of that guard since their step size scales with
route length.

### Data source switch

`lib/core/config/app_config.dart`:

```dart
const bool kUseLocalSeed = false;  // true → serve everything from the seed asset
const String kApiHost = 'http://localhost:4000';
```

`false` (current default) talks to the API (`kApiHost`, Android emulator
alias `10.0.2.2:4000`). `true` serves everything from
`assets/seed/seed.json` (regenerate with `npm run seed:mobile` in
`backend/`), so the app runs with no backend at all — including the ticker
simulation and the rider demo ride.

Images: `CachedImage` (`lib/shared/widgets/cached_image.dart`) — in-house
session LRU + memory cache with pulse placeholder and fade-in, no plugin
dependencies (works on every target without native assets).

### Run / verify

```bash
cd mobile
flutter pub get
flutter run                   # device/emulator
flutter analyze --no-pub      # 0 issues
flutter test --no-pub         # 69 tests: models, reducer, CachedImage,
                              # links/routing, pagination, hero autoplay,
                              # cart count (bar + bag tab + add-to-bag),
                              # routing/geo + ETA & rider-trace logic,
                              # rider tracking (route math, DTOs, seed+live
                              # API contracts), rider marker glider,
                              # layout smoke
flutter build web --release --no-pub
```

Widget tests pump `test/seed_app.dart` (`seedApp()`), which overrides
`apiProvider` with `SeedApi` — the suite never opens a socket whatever
`kUseLocalSeed` says.

`test/layout_smoke_test.dart` walks every route at 390×844 and 653×891 and
fails on any rendering exception (RenderFlex overflow etc.). It is
deliberately golden-free so it passes on any machine.

> **Windows note:** the Flutter SDK used during development lives in
> `_scratch/flutter/` (gitignored). If `flutter` is not on your PATH, invoke
> `_scratch\flutter\bin\flutter.bat` (or install Flutter yourself) and run all
> commands from `mobile/` with `--no-pub` after a one-time `flutter pub get`.
>
> **Paths must not contain spaces.** This repo lives under
> `...\CLIENT PROJECT\...`, and running `flutter run`/`build` from the real
> path fails in the native-assets step with
> `'C:\Users\...\CLIENT' is not recognized as an internal or external command`
> — Windows `cmd.exe` quote-stripping when hooks (e.g. `objective_c`'s
> `hook/build.dart`) are spawned. Use a directory junction so both the SDK and
> the project resolve to a space-free path (created once, at the repo root):
>
> ```bat
> mklink /J C:\blabliblu "%CD%"
> cd /d C:\blabliblu\mobile
> C:\blabliblu\_scratch\flutter\bin\flutter.bat run -d chrome
> ```
>
> Pointing PATH at `C:\blabliblu\_scratch\flutter\bin` makes the bare `flutter`
> command work too. Never edit files under the SDK or pub cache to work around
> this — the junction is the supported fix.

---

## Quick demo

```bash
# terminal 1
cd backend && npm run db:setup && npm start
# terminal 2
cd mobile  && flutter run        # kUseLocalSeed = false → needs terminal 1
```

Follow a delivery live (both sessions signed in as the same account):

1. Place an order through checkout with a map pin (Okhla/CP area).
2. Open `Account → Rider queue →` the order → **Demo ride**.
3. Open the order detail → live map: it polls the posted fixes, follows the
   rider and re-asks OSRM for the route + ETA as the ride progresses.
