import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';

/// The single OpenStreetMap view every screen shares.
///
/// Wraps flutter_map so the tile source, OSM user agent, attribution and
/// fallback centre live in one place (see [kOsmTileUrl] and friends). Callers
/// pass a [controller] when they need camera control, plus overlay
/// [polylines] / [markers] / [layers] to decorate the scene; everything else
/// uses the defaults.
class OsmMap extends StatelessWidget {
  const OsmMap({
    super.key,
    this.controller,
    this.center,
    this.zoom = 13,
    this.onTap,
    this.onPositionChanged,
    this.polylines = const [],
    this.markers = const [],
    this.layers = const [],
  });

  /// Optional camera handle - screens that fit bounds or move the view.
  final MapController? controller;

  /// First camera position; falls back to the Connaught Place default.
  final LatLng? center;

  /// First camera zoom.
  final double zoom;

  /// Tap on the map, forwarded straight to flutter_map.
  final TapCallback? onTap;

  /// Camera moved (by gesture or programmatically), forwarded to flutter_map.
  final PositionCallback? onPositionChanged;

  /// Road polylines drawn above the tiles (routes, matched traces).
  final List<Polyline> polylines;

  /// Markers drawn above the tiles (pin, hubs, rider).
  final List<Marker> markers;

  /// Extra map layers stacked above [markers].
  ///
  /// A layer can wrap a [Listenable] so only it rebuilds when the listener
  /// fires - the rider marker glides through here without disturbing the
  /// tiles or polylines underneath.
  final List<Widget> layers;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center ?? const LatLng(kMapDefaultLat, kMapDefaultLng),
        initialZoom: zoom,
        onTap: onTap,
        onPositionChanged: onPositionChanged,
      ),
      children: [
        TileLayer(urlTemplate: kOsmTileUrl, userAgentPackageName: kOsmUserAgent),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        ...layers,
        // `kOsmAttribution` already carries the © sign.
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(kOsmAttribution, prependCopyright: false),
          ],
        ),
      ],
    );
  }
}
