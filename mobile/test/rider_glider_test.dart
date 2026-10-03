import 'package:blabliblu/shared/widgets/rider_glider.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// The glider's contract: fixes arrive on a cadence and the marker must read
/// as continuous travel - never hops, never flies, and when a corner is on
/// the drawn road it goes *around* the corner, not across the block.
///
/// Fix gaps in these tests stay under [RiderGlider.jumpMetres] (250 m), the
/// window real GPS fixes fall in; simulated walks are covered separately.

/// Minimal ticker provider for pump-driven tests.
class _TestVsync implements TickerProvider {
  const _TestVsync();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

RiderGlider _glider() {
  final glider = RiderGlider(vsync: const _TestVsync());
  addTearDown(glider.dispose);
  return glider;
}

void main() {
  testWidgets('first fix snaps in, later fixes glide half-way on time', (tester) async {
    final glider = _glider();
    const start = LatLng(28.6000, 77.20);

    expect(glider.value, isNull); // nothing until the rider reports
    glider.moveTo(const LatLng(28.6010, 77.20),
        within: const Duration(seconds: 2), geometry: const [start, LatLng(28.6010, 77.20)]);
    expect(glider.value, const LatLng(28.6010, 77.20), reason: 'first fix appears in place, no fly-in');

    glider.moveTo(const LatLng(28.6020, 77.20),
        within: const Duration(seconds: 2), geometry: const [start, LatLng(28.6020, 77.20)]);
    await tester.pump(); // ticker's first frame
    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.latitude, closeTo(28.6015, 0.0002), reason: 'half way after half the time');

    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.latitude, closeTo(28.6020, 1e-9), reason: 'lands exactly on the fix');
  });

  testWidgets('walks the road around a corner instead of cutting the diagonal', (tester) async {
    final glider = _glider();
    // A small L (88 m north, then 156 m east) - total ~245 m of road, but
    // start-to-end is only ~180 m as the crow flies, inside the jump limit.
    const line = [LatLng(28.6000, 77.2000), LatLng(28.6008, 77.2000), LatLng(28.6008, 77.2016)];

    glider.snap(line.first);
    glider.moveTo(line.last, within: const Duration(seconds: 4), geometry: line);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // half the ride

    final mid = glider.value!;
    // Half the road distance is past the corner: dead on the east leg,
    // where a straight-line glide would still be cutting the diagonal
    // (that one would sit at latitude 28.6004).
    expect(mid.latitude, closeTo(28.6008, 1e-6));
    expect(mid.longitude, greaterThan(77.2000));
    expect(mid.longitude, lessThan(77.2016));

    await tester.pump(const Duration(seconds: 2));
    expect(glider.value, line.last);
  });

  testWidgets('falls back to a straight line when there is no route', (tester) async {
    final glider = _glider();

    glider.snap(const LatLng(28.60, 77.20));
    glider.moveTo(const LatLng(28.60, 77.2020), within: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.2010, 1e-9));

    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.2020, 1e-9));
  });

  testWidgets('a far fix is a correction: the marker jumps, never flies', (tester) async {
    final glider = _glider();
    const far = LatLng(28.70, 77.20); // ~11 km north

    glider.snap(const LatLng(28.60, 77.20));
    glider.moveTo(far, within: const Duration(seconds: 2));
    expect(glider.value, far, reason: 'past jumpMetres it teleports');

    await tester.pump(const Duration(seconds: 1)); // nothing happens in between
    expect(glider.value, far);
  });

  testWidgets('simulated walks glide past the jump limit when told to', (tester) async {
    final glider = _glider();
    const to = LatLng(28.65, 77.20); // ~5.5 km - a demo-ride step on a long route

    glider.snap(const LatLng(28.60, 77.20));
    glider.moveTo(to, within: const Duration(seconds: 1), snapBeyond: double.infinity);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(glider.value!.latitude, closeTo(28.625, 0.001), reason: 'glides, does not teleport');

    await tester.pump(const Duration(milliseconds: 500));
    expect(glider.value!.latitude, closeTo(28.65, 1e-9));
  });

  testWidgets('a new fix mid-glide re-aims from the current position', (tester) async {
    final glider = _glider();

    glider.snap(const LatLng(28.60, 77.20));
    glider.moveTo(const LatLng(28.60, 77.2020), within: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.2010, 1e-9)); // half way

    // The next fix lands short of the old target: re-aim from where the
    // marker *is*, with a fresh full interval (the every-poll live path).
    glider.moveTo(const LatLng(28.60, 77.2015), within: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.20125, 1e-9), reason: 'from the current spot, not the old target');

    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.2015, 1e-9));
  });

  testWidgets('a re-delivered fix continues the glide instead of restarting', (tester) async {
    final glider = _glider();
    const to = LatLng(28.60, 77.2015);

    glider.snap(const LatLng(28.60, 77.20));
    glider.moveTo(to, within: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(glider.value!.longitude, closeTo(77.20075, 1e-9)); // half way

    glider.moveTo(to, within: const Duration(seconds: 2)); // same latest fix
    await tester.pump(const Duration(seconds: 1));
    // Restarted would read 77.20075 + quarter of the gap; continued lands.
    expect(glider.value!.longitude, closeTo(77.2015, 1e-9));
  });

  testWidgets('snap resets the run without notifying a resting marker', (tester) async {
    final glider = _glider();
    var frames = 0;
    glider.addListener(() => frames++);

    glider.snap(const LatLng(28.60, 77.20));
    expect(frames, 1);
    glider.snap(const LatLng(28.60, 77.20)); // same point, nothing to redraw
    expect(frames, 1);

    glider.snap(null);
    expect(glider.value, isNull);
    expect(frames, 2);
  });
}
