import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/app_config.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// Full-screen map that lets the user drop the delivery pin.
///
/// A fixed crosshair sits in the middle of the view; panning moves the map
/// underneath it. Every time the camera settles the centre is run through
/// OSRM **Nearest** (debounced) so the bottom card can name the street the
/// pin landed on. "Use this location" pops the chosen [LatLng] back to the
/// caller (`/addresses/pick` -> address dialog / checkout).
class AddressPickerScreen extends ConsumerStatefulWidget {
  const AddressPickerScreen({super.key, this.initialPin});

  /// Pin to centre on when opened (an existing address pin), else the
  /// Connaught Place fallback inside [OsmMap].
  final LatLng? initialPin;

  @override
  ConsumerState<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends ConsumerState<AddressPickerScreen> {
  late final LatLng _startPin = widget.initialPin ?? const LatLng(kMapDefaultLat, kMapDefaultLng);

  /// Current crosshair position - the value handed back on confirm.
  late LatLng _center = _startPin;

  /// Street name from the last successful Nearest snap.
  /// `null` = still locating, `''` = no usable name at this spot.
  String? _street;

  Timer? _debounce;
  int _snapSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _snap() async {
    if (!mounted) return;
    final seq = ++_snapSeq;
    final at = _center;
    final result = await ref.read(storeProvider.notifier).snapToRoad(at);
    if (!mounted || seq != _snapSeq) return;
    setState(() => _street = result?.name ?? '');
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _snap);
  }

  String get _streetLabel {
    final street = _street;
    if (street == null) return 'Finding street name...';
    // The offline seed reports a placeholder for every point; only show a
    // name that actually identifies a road.
    if (street.isEmpty || street == 'Unnamed road') return 'Dropped pin';
    return street;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Pick delivery location')),
      body: Stack(
        children: [
          OsmMap(
            center: _startPin,
            zoom: widget.initialPin == null ? 13 : 15,
            onPositionChanged: _onMove,
          ),
          // Fixed crosshair - the pin tip marks the exact centre.
          Center(
            child: IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: const Icon(Icons.location_on, size: 46, color: AppColors.primary),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.sell_outlined, size: 14, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _streetLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _center),
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text('Use this location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
