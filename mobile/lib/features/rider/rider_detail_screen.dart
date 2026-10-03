import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/utils/route_math.dart' as rm;
import '../../shared/widgets/widgets.dart';
import '../../state/actions.dart';
import '../../state/app_state.dart';
import '../../state/store.dart';

/// Rider console for one delivery: destination, route map, live ETA and the
/// two ways to feed the tracking pipeline.
///
///  * **Device GPS** - [geolocator] stream, throttled to 1 fix/second,
///    posted through `POST /api/tracking/orders/:id/position` (rider key).
///  * **Demo ride** - walks the loaded OSRM route for [kDemoRideSeconds]
///    posting a jittered fix every second, so the customer map can be seen
///    end-to-end without leaving the desk (works in seed mode too).
///
/// Either way the screen re-asks OSRM **Route** every 10 fixes (or when the
/// rider leaves the drawn line), so the ETA card and the polyline keep
/// tracking where the rider actually is - not where the plan said.
class RiderDetailScreen extends ConsumerStatefulWidget {
  const RiderDetailScreen({super.key, required this.orderId, this.job});

  final String orderId;

  /// Passed through the route's `extra`; deep links resolve it from the queue.
  final DeliveryJob? job;

  @override
  ConsumerState<RiderDetailScreen> createState() => _RiderDetailScreenState();
}

class _RiderDetailScreenState extends ConsumerState<RiderDetailScreen> {
  /// Re-check ETA/geometry every N posted fixes (~10 s at 1 fix/s).
  static const int _etaEveryNFixes = 10;

  final MapController _map = MapController();
  final Random _rng = Random();

  /// Store handle captured while mounted - `ref` is unusable in [dispose].
  late final Store _store;

  DeliveryJob? _job;
  bool _loading = true;
  String? _error;
  ({String name, double lat, double lng})? _hub;
  bool _fitted = false;

  /// Ride engine state.
  bool _riding = false;
  String _mode = ''; // 'gps' | 'demo'
  Timer? _fixTimer;
  StreamSubscription<Position>? _gps;
  DateTime? _startedAt;
  DateTime? _lastPost;
  int _posted = 0;
  int _fixCount = 0;
  String? _postError;

  /// Last OSRM-backed estimate to the drop pin (ticked by periodic reroutes).
  double? _etaSec;
  double? _etaDist;

  @override
  void initState() {
    super.initState();
    _store = ref.read(storeProvider.notifier);
    _job = widget.job;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void dispose() {
    _fixTimer?.cancel();
    _gps?.cancel();
    _map.dispose();
    // Mirror DeliveryMapScreen: never mutate the store synchronously in
    // dispose - clear the shared tracking slice next tick.
    Future(() => _store.resetTracking());
    super.dispose();
  }

  // ── setup ─────────────────────────────────────────────────────────────────

  /// Adopt the pushed job (or fetch the queue on a deep link), then load the
  /// hub -> pin route that both the map and the demo walk need.
  Future<void> _resolve() async {
    var job = _job;
    if (job == null) {
      final jobs = await _store.activeDeliveries();
      if (!mounted) return;
      job = jobs?.where((j) => j.id == widget.orderId).firstOrNull;
    }
    if (!mounted) return;
    if (job == null) {
      setState(() {
        _loading = false;
        _error = 'Delivery not found - it may have been completed already.';
      });
      return;
    }
    if (!job.hasPin) {
      setState(() {
        _loading = false;
        _error = 'This address has no delivery pin, so there is no route to ride.';
      });
      return;
    }
    setState(() {
      _job = job;
      _loading = false;
    });

    final hub = await _store.loadDeliveryRoute(LatLng(job.address.lat!, job.address.lng!));
    if (!mounted) return;
    final route = ref.read(storeProvider).routing.route.value;
    setState(() {
      _hub = hub;
      _etaSec = route?.duration;
      _etaDist = route?.distance;
    });
    _fitRoute();
  }

  /// Frame hub + route once, as soon as the geometry arrives.
  void _fitRoute() {
    final route = ref.read(storeProvider).routing.route.value;
    final hub = _hub;
    if (route == null || hub == null || route.geometry.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fitted) return;
      _fitted = true;
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([LatLng(hub.lat, hub.lng), ...route.geometry]),
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ));
    });
  }

  // ── ride engines ──────────────────────────────────────────────────────────

  Future<void> _toggleGps() async {
    if (_riding && _mode == 'gps') {
      _stop();
      return;
    }
    if (_riding) _stop(); // switching engines: stop the demo first

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _postError = 'Location permission denied - enable it in your browser/app settings.');
      return;
    }

    setState(() {
      _riding = true;
      _mode = 'gps';
      _posted = 0;
      _fixCount = 0;
      _postError = null;
      _startedAt = DateTime.now();
    });

    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen(
      (position) {
        if (!_riding || _mode != 'gps') return;
        final now = DateTime.now();
        if (_lastPost != null && now.difference(_lastPost!) < const Duration(seconds: 1)) return;
        _lastPost = now;
        final fix = LatLng(position.latitude, position.longitude);
        _store.moveRider(fix, _progressAt(fix));
        _submit(
          fix,
          accuracy: position.accuracy.isFinite ? position.accuracy : null,
          speed: position.speed.isFinite ? position.speed : null,
          heading: position.heading.isFinite ? position.heading : null,
        );
      },
      onError: (Object error) {
        if (mounted) setState(() => _postError = 'GPS: $error');
      },
    );
  }

  void _startDemo() {
    if (_riding && _mode == 'demo') {
      _stop();
      return;
    }
    if (_riding) _stop(); // switching engines: stop GPS first

    final route = ref.read(storeProvider).routing.route.value;
    if (route == null || route.geometry.length < 2) {
      setState(() => _postError = 'Route not ready yet - one moment.');
      return;
    }
    final geometry = List<LatLng>.of(route.geometry);

    setState(() {
      _riding = true;
      _mode = 'demo';
      _posted = 0;
      _fixCount = 0;
      _postError = null;
      _startedAt = DateTime.now();
    });
    _fixTimer = Timer.periodic(const Duration(seconds: 1), (_) => _demoTick(geometry));
    _demoTick(geometry); // first fix lands at t = 0, hub departure
  }

  void _demoTick(List<LatLng> geometry) {
    if (!mounted || !_riding || _mode != 'demo') {
      _stop();
      return;
    }
    final started = _startedAt;
    if (started == null) return;
    final elapsed = DateTime.now().difference(started).inMilliseconds / 1000.0;
    final t = (elapsed / kDemoRideSeconds).clamp(0.0, 1.0);

    // True position along the road, then GPS-style noise around it.
    final at = rm.pointAt(geometry, t);
    final fix = LatLng(at.latitude + _jitter(), at.longitude + _jitter());
    _store.moveRider(fix, t);
    _submit(fix, accuracy: 10 + _rng.nextDouble() * 15);

    if (t >= 1) _stop(arrived: true);
  }

  double _jitter() => (_rng.nextDouble() - 0.5) * 0.0001; // +-0.00005 deg

  /// Progress off the current geometry (GPS mode); demo mode passes t itself.
  double _progressAt(LatLng fix) {
    final geometry = ref.read(storeProvider).routing.route.value?.geometry ?? const <LatLng>[];
    return geometry.length >= 2 ? rm.progressAlong(geometry, fix) : 0;
  }

  void _stop({bool arrived = false}) {
    _fixTimer?.cancel();
    _fixTimer = null;
    _gps?.cancel();
    _gps = null;
    if (!mounted) return;
    setState(() {
      _riding = false;
      _mode = '';
      if (arrived) _postError = null;
    });
    if (arrived) _toast('Demo ride complete - delivered');
  }

  Future<void> _toast(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  // ── reporting ─────────────────────────────────────────────────────────────

  Future<void> _submit(LatLng fix, {double? accuracy, double? speed, double? heading}) async {
    final job = _job;
    if (job == null) return;
    final error = await _store.reportRiderFix(
      orderId: job.id,
      lat: fix.latitude,
      lng: fix.longitude,
      accuracyM: accuracy,
      speedMps: speed,
      headingDeg: heading,
      recordedAt: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      if (error == null) {
        _posted++;
        _postError = null;
      } else {
        // Terminal orders (delivered/cancelled) or a backend hiccup: show it.
        _postError = error;
      }
    });
    if (error == null) await _maybeRefreshEta(fix, job);
  }

  /// Periodic ETA + reroute check: one OSRM Route call from the rider's
  /// current fix to the pin, every [_etaEveryNFixes] posted fixes. If the
  /// rider has left the drawn line the new geometry is swapped in too, so
  /// this screen (and the customer map) show the route they are really on.
  Future<void> _maybeRefreshEta(LatLng fix, DeliveryJob job) async {
    _fixCount++;
    if (_fixCount % _etaEveryNFixes != 0 && _etaSec != null) return;

    final reroute = await _store.rerouteFrom(fix, LatLng(job.address.lat!, job.address.lng!));
    if (reroute == null || !mounted) return;

    setState(() {
      _etaSec = reroute.duration;
      _etaDist = reroute.distance;
    });

    final geometry = ref.read(storeProvider).routing.route.value?.geometry ?? const <LatLng>[];
    if (geometry.length >= 2 && rm.projectOnRoute(geometry, fix).offRoute > kRerouteOffRouteMetres) {
      _store.dispatch(RouteLoadSucceeded(RouteResult(
        distance: reroute.distance,
        duration: reroute.duration,
        geometry: reroute.geometry,
      )));
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.surface, titleSpacing: 16, title: const Text('Ride')),
        body: ErrorRetry(message: error, onRetry: _resolve),
      );
    }

    final routing = ref.watch(storeProvider.select((s) => s.routing));
    final job = _job!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 16,
        title: Text(job.orderNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          _infoCard(job, routing),
          Expanded(child: _mapArea(routing)),
          _controls(job),
        ],
      ),
    );
  }

  Widget _infoCard(DeliveryJob job, RoutingSlice routing) {
    final address = job.address;
    final etaSec = _etaSec;
    final etaLabel = etaSec == null
        ? 'ETA calculating...'
        : 'ETA ~${etaSec < 60 ? 1 : (etaSec / 60).ceil()} min';
    final distLabel = _etaDist == null ? '' : _meters(_etaDist!);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  address.name.isNotEmpty ? address.name : 'Drop pin',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${job.status} · $etaLabel${distLabel.isEmpty ? '' : ' · $distLabel'}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            address.singleLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _mapArea(RoutingSlice routing) {
    final job = _job!;
    final pin = LatLng(job.address.lat!, job.address.lng!);
    final route = routing.route;
    final rider = routing.rider;

    if (route.isError && !route.hasValue) {
      return ErrorRetry(message: route.error, onRetry: _resolve);
    }

    return OsmMap(
      controller: _map,
      center: pin,
      zoom: 13,
      polylines: [
        if (route.value != null && route.value!.geometry.length > 1) ...[
          Polyline(points: route.value!.geometry, strokeWidth: 9, color: Colors.white),
          Polyline(points: route.value!.geometry, strokeWidth: 5, color: AppColors.ink),
        ],
      ],
      markers: [
        if (_hub != null) _marker(LatLng(_hub!.lat, _hub!.lng), Icons.warehouse_outlined, AppColors.ink),
        _marker(pin, Icons.location_on, AppColors.primary),
        if (rider != null) _marker(rider, Icons.delivery_dining, AppColors.primary, filled: true),
      ],
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color, {bool filled = false}) => Marker(
        point: point,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: filled ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Icon(icon, size: 20, color: filled ? Colors.white : color),
        ),
      );

  Widget _controls(DeliveryJob job) {
    final riding = _riding;
    final isGps = _mode == 'gps';
    final isDemo = _mode == 'demo';
    final postError = _postError;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleGps,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: Icon(isGps ? Icons.stop_circle_outlined : Icons.my_location_rounded, size: 19),
                  label: Text(isGps ? 'Stop GPS' : 'Use device GPS'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _startDemo,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: Icon(isDemo ? Icons.stop_circle_outlined : Icons.route_outlined, size: 19),
                  label: Text(isDemo ? 'Stop demo' : 'Demo ride'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            riding
                ? '${isGps ? 'Device GPS' : 'Demo ride'} on · $_posted fix${_posted == 1 ? '' : 'es'} sent'
                : 'Send fixes so the customer map can follow you live.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (postError != null) ...[
            const SizedBox(height: 4),
            Text(postError, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ] else if (kUseLocalSeed && riding) ...[
            const SizedBox(height: 4),
            const Text(
              'Seed mode: fixes stay on this device.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  String _meters(double meters) =>
      meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
}
