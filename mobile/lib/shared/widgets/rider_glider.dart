import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/route_math.dart' as rm;

/// Smooths the rider marker between discrete GPS fixes.
///
/// Fixes arrive on a cadence (350 ms seed ticker, 2 s track poll, 1 s rider
/// post) and painting them raw makes the marker hop from point to point. The
/// glider interpolates from wherever the marker currently is to the newest
/// fix over the *interval itself*, so the next fix restarts the glide exactly
/// as this one lands - constant, continuous motion instead of hops.
///
/// Where the walk happens:
///  * both the drawn position and the new fix sit on the drawn route ->
///    the marker follows the polyline (a corner stays a corner, it never
///    cuts across the block);
///  * otherwise (or with no geometry) -> a straight line between the two;
///  * a fix past [snapBeyond] metres (250 by default) is a data correction,
///    not travel - the marker jumps rather than flying across town.
///    Simulated walks (the seed ticker, the demo ride) pass
///    [double.infinity]: their fixes are generated *on* the route, so every
///    step is travel and gliding must never be interrupted - their per-fix
///    gaps grow with route length and would trip any fixed limit.
///
/// It is a [ValueListenable] on purpose: only the marker layer listens, so
/// a frame costs one `MarkerLayer` rebuild, not the whole map under it.
class RiderGlider extends ChangeNotifier implements ValueListenable<LatLng?> {
  RiderGlider({required TickerProvider vsync})
      : _controller = AnimationController(vsync: vsync, duration: const Duration(seconds: 1)) {
    _controller.addListener(_frame);
  }

  /// Fixes further apart than this are treated as a correction: snap.
  /// Simulated walks override it with [double.infinity] (see [moveTo]).
  static const double jumpMetres = 250;

  /// Road-walking stays on while both ends project within this many metres
  /// of the drawn line; beyond it the honest interpolation is a straight line.
  static const double onRouteMetres = 30;

  final AnimationController _controller;

  /// Currently drawn position - `null` until the first fix.
  LatLng? _value;

  /// The newest fix handed in (dedupe key + straight-line destination).
  LatLng? _target;

  /// Straight-line snapshot for the running glide (road snapshots live in
  /// [_geom]/[_cum]/`_fromAlong`/`_toAlong` instead).
  LatLng? _from;
  List<LatLng>? _geom;
  List<double>? _cum;
  double _fromAlong = 0;
  double _toAlong = 0;

  /// The marker's current position - what the map should draw right now.
  @override
  LatLng? get value => _value;

  /// Jump straight to [at] with no transition.
  ///
  /// Used for the first fix, a reset, and corrections past [jumpMetres].
  void snap(LatLng? at) {
    _controller.stop();
    _target = at;
    _from = null;
    _geom = null;
    _cum = null;
    _set(at); // equality-gated: resting in place notifies nothing
  }

  /// Glide to [to], arriving in [within] - the cadence fixes arrive on.
  ///
  /// Fixes more than [snapBeyond] metres apart are a data correction and
  /// jump (simulated walks pass [double.infinity]: their steps scale with
  /// route length, so no fixed limit fits them).
  ///
  /// [geometry] is the route currently drawn: when both ends sit on it the
  /// walk follows the road (and reuses a cumulative-distance cache for the
  /// whole glide instead of recomputing per frame).
  void moveTo(LatLng to,
      {required Duration within, List<LatLng>? geometry, double snapBeyond = jumpMetres}) {
    final from = _value;
    if (from == null) {
      snap(to);
      return;
    }
    if (to == _target) return; // same fix re-delivered (slow poll, retry)

    if (rm.kRouteDistance.distance(from, to) > snapBeyond) {
      snap(to);
      return;
    }

    var onRoad = false;
    if (geometry != null && geometry.length >= 2) {
      final cum = rm.cumulativeDistances(geometry);
      if (cum.last > 0) {
        final a = rm.projectOnRoute(geometry, from);
        final b = rm.projectOnRoute(geometry, to);
        if (a.offRoute <= onRouteMetres && b.offRoute <= onRouteMetres) {
          _geom = geometry;
          _cum = cum;
          _fromAlong = a.along;
          _toAlong = b.along;
          _from = null;
          onRoad = true;
        }
      }
    }
    if (!onRoad) {
      _geom = null;
      _cum = null;
      _from = from;
    }

    _target = to;
    // Linear by design: constant speed reads as real travel, and the glide
    // lands exactly when the next fix is due.
    _controller.duration = within;
    _controller.forward(from: 0);
  }

  /// One animation frame: interpolate (road distance or straight line) and
  /// publish. Equality-gated so a resting marker notifies nothing.
  void _frame() {
    final t = _controller.value;
    final geom = _geom;
    final cum = _cum;
    if (geom != null && cum != null) {
      _set(rm.sampleAtDistance(geom, cum, _fromAlong + (_toAlong - _fromAlong) * t));
    } else {
      final from = _from;
      final to = _target;
      if (from != null && to != null) {
        _set(LatLng(
          from.latitude + (to.latitude - from.latitude) * t,
          from.longitude + (to.longitude - from.longitude) * t,
        ));
      }
    }
    // Land and retire in the same frame: at t == 1 the controller's own
    // completion check can still be waiting for the *next* tick (its isDone
    // is exclusive), which would leave a phantom scheduled frame behind the
    // marker. Value is already the exact target here, so nothing is cut off.
    if (t >= 1.0) _controller.stop(canceled: false);
  }

  void _set(LatLng? at) {
    if (at == _value) return;
    _value = at;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_frame)
      ..dispose();
    super.dispose();
  }
}
