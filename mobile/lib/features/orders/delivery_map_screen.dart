import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/utils/route_math.dart' as rm;
import '../../shared/widgets/widgets.dart';
import '../../state/actions.dart';
import '../../state/app_state.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// Live courier tracking on OpenStreetMap.
///
/// Two engines behind one screen, picked by [kUseLocalSeed]:
///
///  * **seed / offline** - [_load] pulls the order, picks the serving hub and
///    loads the warehouse -> pin road route (OSRM Route via the store), then a
///    350 ms ticker walks the rider along that geometry, dispatching
///    `RiderAdvanced` every tick and a jittered GPS trace through OSRM
///    **Match** every fourth tick.
///  * **live / prod** - no simulation: the screen *polls*
///    `GET /api/tracking/orders/:id` every [kTrackPollInterval], projects the
///    rider's real fixes onto the current geometry for a monotone progress,
///    and periodically re-asks OSRM **Route** (every [kRerouteEveryNPolls]th
///    poll, or sooner when the rider strays [kRerouteOffRouteMetres] off the
///    line) so the polyline *and* the ETA follow the rider's actual path.
class DeliveryMapScreen extends ConsumerStatefulWidget {
  const DeliveryMapScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends ConsumerState<DeliveryMapScreen> {
  /// Unrounded haversine - only used for interpolation proportions along the
  /// route, where Vincenty's iteration cost buys nothing.
  static const Distance _dist = DistanceHaversine(roundResult: false);

  final MapController _map = MapController();
  final Random _rng = Random();

  /// Store handle captured while mounted - `ref` is unusable in [dispose].
  late final Store _store;

  Timer? _timer;
  int _tick = 0;
  bool _fitted = false;
  ({String name, double lat, double lng})? _hub;

  /// Jittered GPS fixes fed to Match (5 simulated seconds apart).
  final List<TracePoint> _trace = [];
  int _baseTs = 0;

  /// Cumulative road distances behind [_pointAt], cached per geometry.
  List<LatLng> _geom = const [];
  List<double> _cum = const [];

  // ── live mode (kUseLocalSeed == false) ────────────────────────────────────
  /// Poll counter (drives the Match/reroute cadences) + consecutive misses.
  int _poll = 0;
  int _misses = 0;
  bool _pollBusy = false;

  /// When the server received the newest fix (staleness display).
  DateTime? _lastSeen;

  /// Distance model behind the progress bar: [_baseline] metres still to go
  /// when tracking started, [_remaining] metres estimated now. Progress is
  /// monotone - a reroute may only move it forward.
  double _baseline = 0;
  double _remaining = 0;
  double _liveProgress = 0;

  /// OSRM-backed remaining seconds + when they were measured (the card ticks
  /// them down between reroutes instead of guessing off the planned route).
  double? _etaSeconds;
  DateTime? _etaAt;

  /// Rider hasn't reported a fix yet / the poll loop is failing repeatedly.
  bool _noFix = true;
  bool _trouble = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(storeProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    // Route swaps unmount us mid-build, and mutating the store synchronously
    // inside dispose is exactly what Riverpod forbids - clear next tick.
    Future(() => _store.resetTracking());
    super.dispose();
  }

  /// (Re)fetch the order, then the hub -> pin route, then start the engine:
  /// ticker in seed mode, GPS polling everywhere else.
  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _trace.clear();
      _tick = 0;
      _fitted = false;
      _hub = null;
      _poll = 0;
      _misses = 0;
      _lastSeen = null;
      _baseline = 0;
      _remaining = 0;
      _liveProgress = 0;
      _etaSeconds = null;
      _etaAt = null;
      _noFix = true;
      _trouble = false;
    });
    final store = _store;
    await store.loadOrder(widget.orderId);
    if (!mounted) return;
    final order = ref.read(storeProvider).orders.detail.value;
    final address = order?.id == widget.orderId ? order!.address : null;
    // No pin (or order failed): the order resource drives the empty/error UI.
    if (address == null || !address.hasPin) return;
    final hub = await store.loadDeliveryRoute(LatLng(address.lat!, address.lng!));
    if (!mounted) return;
    setState(() => _hub = hub);
    if (hub != null) {
      _fitRoute();
      // Full planned distance: the yardstick progress is measured against.
      _baseline = ref.read(storeProvider).routing.route.value?.distance ?? 0;
      if (kUseLocalSeed) {
        _startTicker();
      } else {
        _startPolling();
      }
    }
  }

  /// Frame the whole route (hub + geometry) once, as soon as it arrives.
  void _fitRoute() {
    final route = ref.read(storeProvider).routing.route.value;
    if (route == null || _hub == null || route.geometry.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fitted) return;
      _fitted = true;
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([LatLng(_hub!.lat, _hub!.lng), ...route.geometry]),
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ));
    });
  }

  void _startTicker() {
    _timer?.cancel();
    _baseTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _timer = Timer.periodic(const Duration(milliseconds: 350), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) {
      _timer?.cancel();
      return;
    }
    final route = ref.read(storeProvider).routing.route.value;
    if (route == null || route.geometry.length < 2) {
      _timer?.cancel();
      return;
    }
    _tick++;
    final t = (_tick * 0.02).clamp(0.0, 1.0);
    final at = _pointAt(route.geometry, t);
    final store = _store;
    store.moveRider(at, t);

    // GPS-style fix: +-0.0001 deg around the true position, fed to Match.
    _trace.add(TracePoint(
      location: LatLng(at.latitude + _jitter(), at.longitude + _jitter()),
      timestamp: _baseTs + _tick * 5,
      accuracy: 30,
    ));
    if (_trace.length >= 6 && _tick % 4 == 0) {
      store.matchRiderTrace(List<TracePoint>.of(_trace));
    }
    if (t >= 1) _timer?.cancel();
  }

  double _jitter() => (_rng.nextDouble() - 0.5) * 0.0002;

  // ── live mode: poll the rider's real GPS trail ────────────────────────────

  void _startPolling() {
    _timer?.cancel();
    _poll = 0;
    _onPoll(); // first read immediately, then every kTrackPollInterval
    _timer = Timer.periodic(kTrackPollInterval, (_) => _onPoll());
  }

  /// One poll: newest trail -> progress (projected on the current geometry),
  /// Match every 4th read, and a fresh OSRM Route (geometry + ETA) every
  /// [kRerouteEveryNPolls]th read or as soon as the rider leaves the line.
  Future<void> _onPoll() async {
    if (!mounted) {
      _timer?.cancel();
      return;
    }
    if (_pollBusy) return; // a slow read must not stack on the next tick
    _pollBusy = true;
    _poll++;
    try {
      final track = await _store.loadRiderTrack(widget.orderId);
      if (!mounted) return;

      if (track == null) {
        _misses++;
        if (_misses >= kTrackMissesBeforeTrouble && !_trouble) {
          setState(() => _trouble = true);
        }
        return;
      }
      _misses = 0;

      final fix = track.latest;
      if (fix == null) {
        // Rider accepted the job but hasn't reported yet: keep the plan.
        if (!_noFix) setState(() => _noFix = true);
        return;
      }

      // 1) where is the fix on the route we are currently drawing?
      final geometry = ref.read(storeProvider).routing.route.value?.geometry ?? const <LatLng>[];
      var remaining = _remaining;
      var offRoute = 0.0;
      if (geometry.length >= 2) {
        final projection = rm.projectOnRoute(geometry, fix.location);
        remaining = (rm.routeDistance(geometry) - projection.along).clamp(0.0, double.infinity);
        offRoute = projection.offRoute;
      }

      // 2) monotone progress + rider marker from the real position.
      _applyProgress(fix.location, remaining, status: track.status);
      setState(() {
        _noFix = false;
        _trouble = false;
        _lastSeen = _parseTime(fix.receivedAt) ?? _parseTime(fix.recordedAt) ?? DateTime.now();
        _remaining = remaining;
      });

      // 3) snap the raw trail to roads (OSRM Match), every 4th read.
      if (_poll % 4 == 0 && track.trail.length >= 2) {
        _store.matchRiderTrace(_traceFromTrail(track.trail));
      }

      // 4) fresh geometry + ETA from OSRM Route: periodic, off-route, or first.
      final due = _etaSeconds == null ||
          _poll % kRerouteEveryNPolls == 0 ||
          offRoute > kRerouteOffRouteMetres;
      final pin = _pinFromOrder();
      if (due && pin != null) {
        final reroute = await _store.rerouteFrom(fix.location, pin);
        if (reroute != null && mounted) {
          if (reroute.distance > _baseline) _baseline = reroute.distance; // started beyond the hub
          _etaSeconds = reroute.duration;
          _etaAt = DateTime.now();
          setState(() => _remaining = reroute.distance);
          _applyProgress(fix.location, reroute.distance, status: track.status);
          // Swap the drawn line for the rider's actual path (no loading
          // flicker: only the success action, a failed reroute keeps the old).
          _store.dispatch(RouteLoadSucceeded(RouteResult(
            distance: reroute.distance,
            duration: reroute.duration,
            geometry: reroute.geometry,
          )));
        }
      }

      if (track.status == 'delivered' || track.status == 'cancelled') _timer?.cancel();
    } finally {
      _pollBusy = false;
    }
  }

  /// Distance model -> monotone 0..1 progress, pushed to the store.
  void _applyProgress(LatLng at, double remaining, {required String status}) {
    if (status == 'delivered' || status == 'cancelled') {
      _liveProgress = 1;
    } else if (_baseline > 0) {
      final raw = (1 - remaining / _baseline).clamp(0.0, 1.0);
      if (raw > _liveProgress) _liveProgress = raw; // never rides backwards
    }
    _store.moveRider(at, _liveProgress);
  }

  /// Trail -> Match input: last 12 fixes, timestamps forced ascending.
  List<TracePoint> _traceFromTrail(List<RiderPosition> trail) {
    final points = <TracePoint>[];
    var lastTs = 0;
    for (final p in trail.length > 12 ? trail.sublist(trail.length - 12) : trail) {
      final at = _parseTime(p.recordedAt);
      var ts = at == null ? 0 : at.millisecondsSinceEpoch ~/ 1000;
      if (ts <= lastTs) ts = lastTs + 1; // OSRM Match needs strict increase
      lastTs = ts;
      points.add(TracePoint(location: p.location, timestamp: ts, accuracy: p.accuracyM ?? 30));
    }
    return points;
  }

  LatLng? _pinFromOrder() {
    final order = ref.read(storeProvider).orders.detail.value;
    final address = order?.id == widget.orderId ? order!.address : null;
    if (address == null || !address.hasPin) return null;
    return LatLng(address.lat!, address.lng!);
  }

  DateTime? _parseTime(String iso) => iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();

  /// OSRM-backed remaining seconds, ticking down between reroute checks.
  /// `null` = seed mode / first reroute still pending (card falls back to
  /// the planned route's proportional estimate).
  double? get _liveEta {
    final seconds = _etaSeconds;
    final at = _etaAt;
    if (seconds == null || at == null) return null;
    final left = seconds - DateTime.now().difference(at).inSeconds;
    return left < 0 ? 0 : left;
  }

  /// 'Last seen Ns ago' once the trail went quiet past [kTrackStaleAfter].
  String? get _staleLabel {
    if (kUseLocalSeed || _noFix) return null;
    final seen = _lastSeen;
    if (seen == null) return null;
    final age = DateTime.now().difference(seen);
    if (age < kTrackStaleAfter) return null;
    final seconds = age.inSeconds;
    return seconds < 60 ? 'Last seen ${seconds}s ago' : 'Last seen ${seconds ~/ 60}m ago';
  }

  /// Point at fraction [t] (0..1) of the route, by cumulative road distance.
  LatLng _pointAt(List<LatLng> geom, double t) {
    if (!identical(_geom, geom)) {
      _geom = geom;
      _cum = [0.0];
      for (var i = 1; i < geom.length; i++) {
        _cum.add(_cum.last + _dist.distance(geom[i - 1], geom[i]));
      }
    }
    final total = _cum.last;
    if (total <= 0) return geom.first;
    final target = total * t.clamp(0.0, 1.0);
    var i = 1;
    while (i < _cum.length - 1 && _cum[i] < target) {
      i++;
    }
    final span = _cum[i] - _cum[i - 1];
    final f = span <= 0 ? 0.0 : ((target - _cum[i - 1]) / span).clamp(0.0, 1.0);
    final a = geom[i - 1];
    final b = geom[i];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(storeProvider.select((s) => s.orders.detail));
    // Same guard as OrderDetailScreen: keep showing the requested order while
    // a different one still occupies the slot.
    final Resource<Order> order = (detail.hasValue && detail.value!.id != widget.orderId)
        ? (detail.isLoading ? const Resource<Order>() : Resource<Order>(status: detail.status, error: detail.error))
        : detail;
    final routing = ref.watch(storeProvider.select((s) => s.routing));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Live delivery')),
      body: _body(order, routing),
    );
  }

  Widget _body(Resource<Order> order, RoutingSlice routing) {
    if (order.showSkeleton || (!order.hasValue && !order.isError)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (order.isError && !order.hasValue) {
      return ErrorRetry(message: order.error, onRetry: _load);
    }

    final address = order.value!.address;
    if (!address.hasPin) {
      return const EmptyState(
        icon: Icons.location_off_outlined,
        title: 'No delivery pin set',
        subtitle: 'Add a map pin to this address to follow the rider live.',
      );
    }

    final center = LatLng(address.lat!, address.lng!);
    final route = routing.route.value;
    final match = routing.match.value;
    final rider = routing.rider;

    return Stack(
      children: [
        OsmMap(
          controller: _map,
          center: center,
          zoom: 12,
          polylines: [
            if (route != null && route.geometry.length > 1) ...[
              Polyline(points: route.geometry, strokeWidth: 9, color: Colors.white),
              Polyline(points: route.geometry, strokeWidth: 5, color: AppColors.primary),
            ],
            if (match != null && match.geometry.length > 1)
              Polyline(points: match.geometry, strokeWidth: 5, color: AppColors.success),
          ],
          markers: [
            if (_hub != null) _pin(LatLng(_hub!.lat, _hub!.lng), Icons.warehouse_outlined, AppColors.ink),
            _pin(center, Icons.location_on, AppColors.primary),
            if (rider != null) _pin(rider, Icons.delivery_dining, AppColors.primary, filled: true),
          ],
        ),
        Positioned(left: 16, right: 16, bottom: 18, child: _card(routing)),
      ],
    );
  }

  /// Map marker: white circle (or solid) with a coloured glyph.
  Marker _pin(LatLng point, IconData icon, Color color, {bool filled = false}) => Marker(
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

  Widget _card(RoutingSlice routing) {
    final route = routing.route;
    final Widget content;
    if (route.isError && !route.hasValue) {
      content = ErrorRetry(message: route.error, onRetry: _load);
    } else if (!route.hasValue) {
      content = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(minHeight: 4, color: AppColors.primary),
          SizedBox(height: 12),
          Text('Finding the fastest route...', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      );
    } else {
      content = _progress(routing, route.value!);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: content,
    );
  }

  Widget _progress(RoutingSlice routing, RouteResult route) {
    final progress = routing.progress.clamp(0.0, 1.0);
    // Live mode prefers the OSRM-backed remaining time (ticked down since the
    // last reroute); seed mode keeps the planned-route proportional estimate.
    final liveEta = _liveEta;
    final seconds = liveEta ?? route.duration * (1 - progress);
    final minutes = (seconds / 60).ceil();
    final eta = progress >= 1
        ? 'Arrived'
        : 'Arriving in ~${minutes < 1 ? 1 : minutes} min';
    final status = progress >= 1
        ? 'Delivered'
        : (!kUseLocalSeed && _noFix)
            ? 'Waiting for the rider to start'
            : (routing.rider == null ? 'Rider at the hub' : 'Rider on the way');
    final stale = _staleLabel;
    final remainingLabel = _remaining > 0 ? _remaining : route.distance;
    final match = routing.match;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warehouse_outlined, size: 19, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_hub?.name ?? 'Warehouse', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 1),
                  Text(eta, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${(progress * 100).round()}%', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                Text(_meters(remainingLabel), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: AppColors.primary,
            backgroundColor: AppColors.line,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.local_shipping_outlined, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(status, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            if (stale != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '· $stale',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ] else if (_trouble) ...[
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  '· Connection trouble, retrying',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
            const Spacer(),
            if (match.hasValue)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gps_fixed, size: 13, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'GPS ${(match.value!.confidence * 100).round()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String _meters(double meters) =>
      meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';
}
