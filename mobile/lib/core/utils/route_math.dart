/// Geometry helpers shared by the customer map and the rider screens.
///
/// Everything here works on a bare polyline + cumulative road distances:
///  * [pointAt]         - interpolation at fraction t (the ticker's walk)
///  * [projectOnRoute]  - nearest point *along* the polyline (rider fix ->
///                        route progress + off-route distance)
///  * [progressAlong]   - 0..1 fraction of the polyline consumed at a fix
///
/// Distances are haversine (unrounded) - sub-metre error at city scale, and
/// no Vincenty iteration per vertex.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Unrounded haversine - shared by every helper below.
const Distance kRouteDistance = DistanceHaversine(roundResult: false);

/// Cumulative road distance (m) at each vertex: `[0, d01, d01+d02, ...]`.
List<double> cumulativeDistances(List<LatLng> geometry) {
  final cum = <double>[0.0];
  for (var i = 1; i < geometry.length; i++) {
    cum.add(cum.last + kRouteDistance.distance(geometry[i - 1], geometry[i]));
  }
  return cum;
}

/// Total length of the polyline in metres (0 for fewer than 2 points).
double routeDistance(List<LatLng> geometry) =>
    geometry.length < 2 ? 0 : cumulativeDistances(geometry).last;

/// Point at fraction `t` (clamped 0..1) of the polyline, by road distance.
LatLng pointAt(List<LatLng> geometry, double t) {
  if (geometry.isEmpty) throw ArgumentError('geometry must not be empty');
  if (geometry.length == 1) return geometry.first;
  final cum = cumulativeDistances(geometry);
  final total = cum.last;
  if (total <= 0) return geometry.first;
  final target = total * t.clamp(0.0, 1.0);
  var i = 1;
  while (i < cum.length - 1 && cum[i] < target) {
    i++;
  }
  final span = cum[i] - cum[i - 1];
  final f = span <= 0 ? 0.0 : ((target - cum[i - 1]) / span).clamp(0.0, 1.0);
  final a = geometry[i - 1];
  final b = geometry[i];
  return LatLng(
    a.latitude + (b.latitude - a.latitude) * f,
    a.longitude + (b.longitude - a.longitude) * f,
  );
}

/// Where a fix lands on the polyline: the nearest point *along* it.
///
///  * `point`    - the snapped position (what the map should draw)
///  * `along`    - road distance from the polyline start to the fix
///  * `offRoute` - how far the fix strayed from the polyline (metres)
///  * `index`    - segment index the projection landed in
class RouteProjection {
  const RouteProjection({
    required this.point,
    required this.along,
    required this.offRoute,
    required this.index,
  });

  final LatLng point;
  final double along;
  final double offRoute;
  final int index;
}

/// Project a GPS fix onto the polyline (nearest segment, clamped to it).
///
/// The fix is projected in a local planar metres frame around each segment
/// (equirectangular) - exact enough at city scale, no iteration needed.
RouteProjection projectOnRoute(List<LatLng> geometry, LatLng fix) {
  if (geometry.length == 1) {
    return RouteProjection(
      point: geometry.first,
      along: 0,
      offRoute: kRouteDistance.distance(geometry.first, fix),
      index: 0,
    );
  }
  const double metresPerDegLat = 110540.0;
  final cum = cumulativeDistances(geometry);
  var bestOff = double.infinity;
  var bestAlong = 0.0;
  var bestPoint = geometry.first;
  var bestIndex = 0;

  for (var i = 1; i < geometry.length; i++) {
    final a = geometry[i - 1];
    final b = geometry[i];
    final segLen = cum[i] - cum[i - 1];
    // Local metres frame with `a` at the origin (x east, y north).
    final cosLat = math.cos(a.latitude * math.pi / 180).clamp(0.01, 1.0);
    final bx = (b.longitude - a.longitude) * metresPerDegLat * cosLat;
    final by = (b.latitude - a.latitude) * metresPerDegLat;
    final px = (fix.longitude - a.longitude) * metresPerDegLat * cosLat;
    final py = (fix.latitude - a.latitude) * metresPerDegLat;

    var t = 0.0;
    final denom = bx * bx + by * by;
    if (segLen > 0 && denom > 0) {
      t = ((px * bx + py * by) / denom).clamp(0.0, 1.0);
    }
    final snapped = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    final off = kRouteDistance.distance(snapped, fix);
    if (off < bestOff) {
      bestOff = off;
      bestAlong = cum[i - 1] + segLen * t;
      bestPoint = snapped;
      bestIndex = i - 1;
    }
  }
  return RouteProjection(point: bestPoint, along: bestAlong, offRoute: bestOff, index: bestIndex);
}

/// 0..1 fraction of the polyline consumed at [fix] (0 = at the start,
/// 1 = at/past the end).
double progressAlong(List<LatLng> geometry, LatLng fix) {
  final total = routeDistance(geometry);
  if (total <= 0) return 0;
  return (projectOnRoute(geometry, fix).along / total).clamp(0.0, 1.0);
}
