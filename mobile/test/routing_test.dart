import 'package:blabliblu/core/config/app_config.dart';
import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/core/network/api_client.dart';
import 'package:blabliblu/state/actions.dart';
import 'package:blabliblu/state/app_state.dart';
import 'package:blabliblu/state/reducers.dart';
import 'package:blabliblu/state/store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Routing contracts: the six OSRM services as the app consumes them (the
/// seed implementation exposes the exact surface [LiveApi] proxies from the
/// backend), the routing reducer's fresh-loading semantics, and the checkout
/// ETA thunk's hub selection.
///
/// Deliberately widget-free - map rendering is covered by the layout sweep;
/// this file pins the data underneath it.

const _cp = LatLng(kMapDefaultLat, kMapDefaultLng); // Connaught Place
const _hauz = LatLng(28.5494, 77.2001); // Hauz Khas
const _gate = LatLng(28.6129, 77.2295); // India Gate

/// Runs [body] on the real event loop - the seed asset is async IO that a
/// fake-async `pump` alone would never complete.
Future<T> _async<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

void main() {
  group('six OSRM services (seed)', () {
    testWidgets('Nearest drops the pin exactly where it was', (tester) async {
      final AppApi api = SeedApi();
      final result = await _async(tester, () => api.nearest(lat: _cp.latitude, lng: _cp.longitude));

      expect(result.location.latitude, closeTo(_cp.latitude, 1e-9));
      expect(result.location.longitude, closeTo(_cp.longitude, 1e-9));
      expect(result.snapDistance, 0);
      expect(result.name, 'Unnamed road');
    });

    testWidgets('Route reports distance, duration and both endpoints', (tester) async {
      final AppApi api = SeedApi();
      final result = await _async(tester, () => api.route([_cp, _hauz]));

      expect(result.distance, greaterThan(0));
      expect(result.duration, greaterThan(0));
      expect(result.geometry, hasLength(2));
      expect(result.geometry.first, _cp);
      expect(result.geometry.last, _hauz);
    });

    testWidgets('Table honours the requested source/destination split', (tester) async {
      final AppApi api = SeedApi();
      final result = await _async(
        tester,
        () => api.table([_cp, _hauz, _gate], sources: [0, 1], destinations: [2]),
      );

      expect(result.durations, hasLength(2)); // one row per source
      expect(result.durations[0], hasLength(1)); // one cell per destination
      expect(result.durations[1], hasLength(1));
      expect(result.distances, hasLength(2));
      expect(result.distances[0], hasLength(1));
      expect(result.durations[0][0], greaterThan(0));
      expect(result.distances[0][0], greaterThan(0));
      // Only one destination: the best hop out of row 0 is that very cell.
      expect(result.bestFrom(0), result.durations[0][0]);
    });

    testWidgets('Match hands the trace back as snapped geometry', (tester) async {
      const trace = [
        TracePoint(location: LatLng(28.6139, 77.2090), timestamp: 1700000000, accuracy: 30),
        TracePoint(location: LatLng(28.6144, 77.2095), timestamp: 1700000050, accuracy: 30),
        TracePoint(location: LatLng(28.6149, 77.2100), timestamp: 1700000100, accuracy: 30),
      ];
      final AppApi api = SeedApi();
      final result = await _async(tester, () => api.matchTrace(trace));

      expect(result.geometry, hasLength(trace.length));
      for (var i = 0; i < trace.length; i++) {
        expect(result.geometry[i], trace[i].location);
      }
      expect(result.confidence, 1);
      expect(result.distance, greaterThan(0));
    });

    testWidgets('Trip closes the tour: first point == last point', (tester) async {
      final AppApi api = SeedApi();
      final result = await _async(tester, () => api.trip([_cp, _hauz, _gate]));

      expect(result.geometry.first, result.geometry.last);
      expect(result.geometry, hasLength(4)); // 3 stops + return leg
      expect(result.distance, greaterThan(0));
      expect(result.duration, greaterThan(0));
    });

    testWidgets('Tile refuses politely: 501 NOT_SUPPORTED', (tester) async {
      final AppApi api = SeedApi();
      await tester.runAsync(() async {
        await expectLater(
          api.vectorTile(12, 3270, 2045),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 501)
                .having((e) => e.code, 'code', 'NOT_SUPPORTED'),
          ),
        );
      });
    });
  });

  group('routing reducer', () {
    /// State with every routing slot populated, to prove resets stay scoped.
    AppState loaded() {
      var state = const AppState();
      state = rootReducer(
        state,
        const RouteLoadSucceeded(RouteResult(
          distance: 1200,
          duration: 140,
          geometry: [LatLng(28.5355, 77.2710), LatLng(28.6139, 77.2090)],
        )),
      );
      state = rootReducer(
        state,
        const MatchSucceeded(MatchResult(distance: 900, duration: 100, geometry: [LatLng(28.6, 77.2)], confidence: 1)),
      );
      state = rootReducer(state, const RiderAdvanced(LatLng(28.6, 77.21), 0.42));
      state = rootReducer(
        state,
        const EtaLoadSucceeded(EtaEstimate(warehouse: 'Okhla Phase 2 Hub', distance: 13700, duration: 1650)),
      );
      return state;
    }

    test('RouteLoadRequested wipes the previous tracking run', () {
      final next = rootReducer(loaded(), const RouteLoadRequested());

      expect(next.routing.route.isLoading, isTrue);
      expect(next.routing.route.value, isNull); // fresh slot, not stale data
      expect(next.routing.match.hasValue, isFalse);
      expect(next.routing.rider, isNull);
      expect(next.routing.progress, 0.0);
      // The checkout estimate is a different concern - untouched.
      expect(next.routing.eta.hasValue, isTrue);
    });

    test('EtaLoadRequested starts a fresh estimate', () {
      final next = rootReducer(loaded(), const EtaLoadRequested());

      expect(next.routing.eta.isLoading, isTrue);
      expect(next.routing.eta.value, isNull);
      // Tracking is a different concern - untouched.
      expect(next.routing.route.hasValue, isTrue);
      expect(next.routing.rider, isNotNull);
    });

    test('TrackingReset leaves a clean slice behind', () {
      final next = rootReducer(loaded(), const TrackingReset());

      expect(next.routing.route.hasValue, isFalse);
      expect(next.routing.match.hasValue, isFalse);
      expect(next.routing.rider, isNull);
      expect(next.routing.progress, 0.0);
      expect(next.routing.eta.hasValue, isTrue); // checkout estimate survives
    });
  });

  group('store thunk', () {
    testWidgets('loadEta serves Connaught Place from the Okhla hub', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [apiProvider.overrideWithValue(SeedApi())],
      );
      addTearDown(container.dispose);

      final store = container.read(storeProvider.notifier);
      await _async(tester, () => store.loadEta(_cp));

      final eta = container.read(storeProvider.select((s) => s.routing.eta));
      expect(eta.hasValue, isTrue, reason: 'eta failed: ${eta.error}');
      // ~13.7 km road-adjusted from CP vs ~27 km from Rohini.
      expect(eta.value!.warehouse, 'Okhla Phase 2 Hub');
      expect(eta.value!.distance, greaterThan(0));
      expect(eta.value!.duration, greaterThan(0));
      expect(eta.value!.distanceLabel, endsWith('km'));
      expect(eta.value!.durationLabel, isNotEmpty);
    });
  });
}
