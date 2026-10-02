import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_state.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// Live courier tracking on OpenStreetMap.
///
/// [_load] pulls the order, picks the serving hub and loads the warehouse ->
/// pin road route (OSRM Route via the store). A 350 ms ticker then walks the
/// rider along that geometry, dispatching `RiderAdvanced` every tick and a
/// jittered GPS trace through OSRM **Match** every fourth tick - so the map
/// route, the snapped trace and the bottom card all rebuild straight from
/// `state.routing`.
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

  /// (Re)fetch the order, then the hub -> pin route, then start the ticker.
  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _trace.clear();
      _tick = 0;
      _fitted = false;
      _hub = null;
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
      _startTicker();
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
    final minutes = (route.duration * (1 - progress) / 60).ceil();
    final eta = progress >= 1
        ? 'Arrived'
        : 'Arriving in ~${minutes < 1 ? 1 : minutes} min';
    final status = progress >= 1
        ? 'Delivered'
        : (routing.rider == null ? 'Rider at the hub' : 'Rider on the way');
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
                Text(_meters(route.distance), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
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
