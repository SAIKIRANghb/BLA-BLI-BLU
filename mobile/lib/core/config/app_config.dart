/// Global application configuration.
///
/// [kUseLocalSeed] is the single switch for local testing:
///  * `true`  -> every API call is served from `assets/seed/seed.json`
///               (offline UI testing, widget tests, screenshots - no backend).
///               The seed implementation still exposes the exact same public
///               API surface, so nothing else in the app changes.
///  * `false` -> real HTTP calls against [kApiBaseUrl].
library;

import 'package:flutter/material.dart';

/// ── TEST SWITCH ─────────────────────────────────────────────────────────────
/// Keep `true` while testing the UI without a running backend.
/// Set to `false` to talk to the Node.js/PostgreSQL API.
const bool kUseLocalSeed = true;

/// ── API endpoint ────────────────────────────────────────────────────────────
/// * Android emulator -> `10.0.2.2` is the host machine loopback
/// * iOS simulator     -> `localhost` / `127.0.0.1`
/// * Physical device   -> your machine's LAN IP, e.g. `192.168.1.10:4000`
const String kApiHost = 'http://10.0.2.2:4000';
const String kApiBaseUrl = '$kApiHost/api';

/// Seed asset used when [kUseLocalSeed] is enabled.
const String kSeedAsset = 'assets/seed/seed.json';

/// ── MAP / ROUTING ───────────────────────────────────────────────────────────
/// OpenStreetMap raster tiles. `flutter_map` needs a user-agent package name
/// that identifies the app per OSM tile usage policy.
const String kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String kOsmUserAgent = 'com.blabliblu.app';
const String kOsmAttribution = '© OpenStreetMap contributors';

/// Fallback map centre while no pin exists yet (Connaught Place, New Delhi).
const double kMapDefaultLat = 28.6139;
const double kMapDefaultLng = 77.2090;

/// Fulfilment hubs the delivery estimate chooses from (Delhi NCR first).
const List<({String name, double lat, double lng})> kWarehouses = [
  (name: 'Okhla Phase 2 Hub', lat: 28.5355, lng: 77.2710),
  (name: 'Rohini Hub', lat: 28.7495, lng: 77.0565),
];

/// Brand palette (matches blabliblulife.com).
abstract final class AppColors {
  static const primary = Color(0xFFD8232A);
  static const primaryDark = Color(0xFF9E1219);
  static const ink = Color(0xFF141414);
  static const muted = Color(0xFF6B6B6B);
  static const line = Color(0xFFE6E6E6);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF7F7F7);
  static const success = Color(0xFF1E8E3E);
  static const star = Color(0xFFF5A623);
}
