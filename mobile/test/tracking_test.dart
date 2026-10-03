import 'dart:convert';

import 'package:blabliblu/core/config/app_config.dart';
import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/core/network/api_client.dart';
import 'package:blabliblu/core/utils/route_math.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Rider tracking: route math, DTO parsing, and both API implementations of
/// the `/api/tracking/*` contract (seed offline, live against a mock HTTP).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── route math ────────────────────────────────────────────────────────────

  group('route_math', () {
    // A simple L: north 1.1 km, then east ~1.9 km.
    final line = [const LatLng(28.60, 77.20), const LatLng(28.61, 77.20), const LatLng(28.61, 77.22)];

    test('cumulativeDistances starts at 0 and ends at the total', () {
      final cum = cumulativeDistances(line);
      expect(cum, hasLength(3));
      expect(cum.first, 0);
      expect(cum.last, routeDistance(line));
      expect(cum.last, greaterThan(2000)); // ~3 km of road
      expect(cum[1], lessThan(cum[2]));
    });

    test('pointAt hits both endpoints and walks between them', () {
      expect(pointAt(line, 0).latitude, closeTo(line.first.latitude, 1e-9));
      expect(pointAt(line, 0).longitude, closeTo(line.first.longitude, 1e-9));
      expect(pointAt(line, 1).latitude, closeTo(line.last.latitude, 1e-9));
      expect(pointAt(line, 1).longitude, closeTo(line.last.longitude, 1e-9));

      // Half way by distance lands on the corner (first leg is the short one,
      // so 50 % of the total is already into the second leg).
      final mid = pointAt(line, 0.5);
      expect(mid.latitude, closeTo(28.61, 1e-6));
      expect(mid.longitude, greaterThan(77.20));
      expect(mid.longitude, lessThan(77.22));
    });

    test('projectOnRoute snaps a nearby fix with a small off-route error', () {
      final fix = const LatLng(28.605, 77.2001); // 10 m east of the first leg
      final projection = projectOnRoute(line, fix);

      expect(projection.index, 0);
      expect(projection.point.longitude, closeTo(77.20, 1e-9));
      expect(projection.point.latitude, closeTo(28.605, 1e-6));
      expect(projection.offRoute, greaterThan(5));
      expect(projection.offRoute, lessThan(15));
      expect(projection.along, closeTo(kRouteDistance.distance(line.first, const LatLng(28.605, 77.20)), 1));
    });

    test('projectOnRoute reports how far a fix strayed', () {
      // East of both legs: leg 1 projects to its midpoint (~4.9 km away),
      // leg 2 clamps to its endpoint (~3.0 km) - the nearer one wins.
      final fix = const LatLng(28.605, 77.25);
      final projection = projectOnRoute(line, fix);
      expect(projection.index, 1);
      expect(projection.offRoute, closeTo(2981, 25));
      expect(projection.offRoute, greaterThan(2500));
    });

    test('progressAlong runs 0 -> 1 along the line', () {
      expect(progressAlong(line, line.first), closeTo(0, 1e-6));
      expect(progressAlong(line, const LatLng(28.61, 77.20)), closeTo(0.35, 0.05));
      expect(progressAlong(line, line.last), 1.0);
      // Pinned past the end clamps instead of overshooting.
      expect(progressAlong(line, const LatLng(28.61, 77.30)), 1.0);
    });
  });

  // ── DTO parsing ───────────────────────────────────────────────────────────

  group('tracking models', () {
    test('RiderPosition parses the backend fix DTO', () {
      final position = RiderPosition.fromJson(const {
        'id': 'p1',
        'orderId': 'o1',
        'lat': 28.6,
        'lng': 77.2,
        'accuracyM': 7,
        'speedMps': 4.5,
        'headingDeg': 180,
        'recordedAt': '2026-10-02T15:47:00.000Z',
        'receivedAt': '2026-10-02T15:47:01.000Z',
      });
      expect(position.lat, 28.6);
      expect(position.lng, 77.2);
      expect(position.accuracyM, 7);
      expect(position.speedMps, 4.5);
      expect(position.location, const LatLng(28.6, 77.2));
      expect(position.recordedAt, isNotEmpty);
    });

    test('RiderPosition tolerates a queue lastFix without id/orderId', () {
      final position = RiderPosition.fromJson(const {'lat': 1.5, 'lng': 2.5, 'accuracyM': 5, 'recordedAt': 'x'});
      expect(position.id, isEmpty);
      expect(position.orderId, isEmpty);
      expect(position.lat, 1.5);
    });

    test('TrackResult parses the trail; empty trail has no latest', () {
      final track = TrackResult.fromJson(const {
        'orderId': 'o1',
        'orderNumber': 'BBL-20261002-5500',
        'status': 'shipped',
        'latest': {'lat': 28.62, 'lng': 77.21},
        'trail': [
          {'id': 'p1', 'orderId': 'o1', 'lat': 28.60, 'lng': 77.20, 'recordedAt': '2026-10-02T15:47:00.000Z'},
          {'id': 'p2', 'orderId': 'o1', 'lat': 28.61, 'lng': 77.205, 'recordedAt': '2026-10-02T15:47:05.000Z'},
        ],
        'updatedAt': '2026-10-02T15:47:05.000Z',
      });
      expect(track.orderNumber, 'BBL-20261002-5500');
      expect(track.status, 'shipped');
      expect(track.trail, hasLength(2));
      expect(track.latest!.id, 'p2'); // chronological: newest last
      expect(track.updatedAt, isNotEmpty);

      const empty = TrackResult(orderId: 'o1');
      expect(empty.latest, isNull);
    });

    test('DeliveryJob parses a queue item with pin and last fix', () {
      final job = DeliveryJob.fromJson(const {
        'id': 'o1',
        'orderNumber': 'BBL-1',
        'status': 'placed',
        'address': {'name': 'Ada', 'line1': '4 MG Road', 'city': 'Delhi', 'lat': 28.61, 'lng': 77.21},
        'placedAt': '2026-10-02T10:00:00.000Z',
        'lastFix': {'lat': 28.60, 'lng': 77.20, 'accuracyM': 5, 'recordedAt': '2026-10-02T15:47:00.000Z'},
      });
      expect(job.hasPin, isTrue);
      expect(job.address.name, 'Ada');
      expect(job.lastFix!.lat, 28.60);

      final bare = DeliveryJob.fromJson(const {
        'id': 'o2',
        'orderNumber': 'BBL-2',
        'status': 'confirmed',
        'address': {'name': '', 'lat': 1.0, 'lng': 2.0},
        'lastFix': null,
      });
      expect(bare.lastFix, isNull);
      expect(bare.hasPin, isTrue);
    });
  });

  // ── seed implementation (offline contract) ────────────────────────────────

  group('SeedApi tracking', () {
    late SeedApi api;

    setUp(() => api = SeedApi());

    test('unknown order 404s on report and read', () async {
      await expectLater(
        api.reportRiderPosition(orderId: 'nope', lat: 28.6, lng: 77.2),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
      await expectLater(
        api.getOrderTrack('nope'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('queue starts empty (seed has no preset orders)', () async {
      expect(await api.getActiveDeliveries(), isEmpty);
    });

    test('checkout -> report -> trail -> queue round trip', () async {
      final seed = jsonDecode(await rootBundle.loadString(kSeedAsset)) as Map<String, dynamic>;
      final productId = ((seed['details'] as Map).values.first as Map)['id'] as String;

      final cart = await api.createCart();
      await api.addToCart(cartId: cart.id, productId: productId, qty: 1);
      final order = await api.placeOrder(
        cartId: cart.id,
        address: const ShippingAddress(name: 'Ada', line1: '4 MG Road', city: 'Delhi', lat: 28.61, lng: 77.21),
      );

      // Report two fixes, read them back chronologically.
      await api.reportRiderPosition(orderId: order.id, lat: 28.60, lng: 77.20, accuracyM: 9);
      await api.reportRiderPosition(orderId: order.id, lat: 28.605, lng: 77.205, accuracyM: 12);

      final track = await api.getOrderTrack(order.id);
      expect(track.trail, hasLength(2));
      expect(track.latest!.lat, closeTo(28.605, 1e-9));
      expect(track.status, 'placed');

      // The rider queue projects the active, pinned order with its last fix.
      final jobs = await api.getActiveDeliveries();
      expect(jobs, hasLength(1));
      expect(jobs.first.id, order.id);
      expect(jobs.first.lastFix!.accuracyM, 12);
    });
  });

  // ── live implementation (HTTP contract) ───────────────────────────────────

  group('LiveApi tracking', () {
    final fixJson = jsonEncode(const {
      'success': true,
      'data': {
        'id': 'p1',
        'orderId': 'o1',
        'lat': 28.6,
        'lng': 77.2,
        'accuracyM': 9,
        'speedMps': null,
        'headingDeg': null,
        'recordedAt': '2026-01-01T12:00:00.000Z',
        'receivedAt': '2026-01-01T12:00:01.000Z',
      },
    });

    test('report posts the rider key, body and parses the fix', () async {
      http.Request? seen;
      final api = LiveApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(fixJson, 201, headers: {'content-type': 'application/json'});
        }),
      );

      final fix = await api.reportRiderPosition(
        orderId: 'o1',
        lat: 28.6,
        lng: 77.2,
        accuracyM: 9,
        recordedAt: DateTime.utc(2026, 1, 1, 12),
      );

      expect(seen, isNotNull);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/tracking/orders/o1/position');
      expect(seen!.headers['x-rider-key'], kRiderKey);
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['lat'], 28.6);
      expect(body['lng'], 77.2);
      expect(body['accuracyM'], 9);
      expect(body['recordedAt'], '2026-01-01T12:00:00.000Z');
      expect(fix.id, 'p1');
      expect(fix.accuracyM, 9);
    });

    test('read sends the bearer token and the limit query', () async {
      final api = LiveApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/tracking/orders/o1');
          expect(request.url.queryParameters['limit'], '50');
          expect(request.headers['authorization'], 'Bearer tok-1');
          return http.Response(
            jsonEncode(const {
              'success': true,
              'data': {
                'orderId': 'o1',
                'orderNumber': 'BBL-1',
                'status': 'shipped',
                'trail': [
                  {'id': 'p1', 'orderId': 'o1', 'lat': 28.6, 'lng': 77.2},
                ],
                'updatedAt': '2026-01-01T12:00:00.000Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final track = await api.getOrderTrack('o1', token: 'tok-1', limit: 50);
      expect(track.status, 'shipped');
      expect(track.trail, hasLength(1));
    });

    test('queue unwraps data.items and carries the rider key', () async {
      final api = LiveApi(
        client: MockClient((request) async {
          expect(request.url.path, '/api/tracking/deliveries');
          expect(request.url.queryParameters['limit'], '20');
          expect(request.headers['x-rider-key'], kRiderKey);
          return http.Response(
            jsonEncode(const {
              'success': true,
              'data': {
                'items': [
                  {
                    'id': 'o1',
                    'orderNumber': 'BBL-1',
                    'status': 'placed',
                    'address': {'name': 'Ada', 'lat': 28.61, 'lng': 77.21},
                    'placedAt': '2026-10-02T10:00:00.000Z',
                    'lastFix': null,
                  },
                ],
                'total': 1,
                'limit': 20,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final jobs = await api.getActiveDeliveries();
      expect(jobs, hasLength(1));
      expect(jobs.first.orderNumber, 'BBL-1');
      expect(jobs.first.lastFix, isNull);
    });

    test('403 without the rider key surfaces as ApiException', () async {
      final api = LiveApi(
        client: MockClient((request) async => http.Response(
              jsonEncode(const {
                'success': false,
                'error': {'code': 'FORBIDDEN', 'message': 'Rider key required'},
              }),
              403,
              headers: {'content-type': 'application/json'},
            )),
      );

      await expectLater(
        api.getActiveDeliveries(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'FORBIDDEN'),
        ),
      );
    });
  });
}
