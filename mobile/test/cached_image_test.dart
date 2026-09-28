import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blabliblu/shared/widgets/cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Exercises the in-house [CachedImage] that replaced `cached_network_image`.
///
/// Every request runs through a [MockClient] injected with [http.runWithClient],
/// so the real download -> cache -> decode -> fallback path is covered without
/// touching the network (and without the native-assets hook that
/// `cached_network_image` drags in).
void main() {
  late Uint8List png;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // A real 4x4 PNG from the engine encoder, so the decode path is genuine.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFFD8232A),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    png = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });

  /// The placeholder runs an endless pulse animation, so `pumpAndSettle`
  /// would never return - pump a bounded number of frames instead. Real
  /// delays are interleaved because image decoding happens on the engine's
  /// event loop, which only turns while `runAsync` is active.
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int iterations = 40,
  }) async {
    for (var i = 0; i < iterations; i++) {
      if (condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return condition();
  }

  /// True once a frame has actually decoded into the raster pipeline.
  bool decoded(WidgetTester tester) => tester
      .widgetList<RawImage>(find.byType(RawImage))
      .any((raw) => raw.image != null);

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('downloads, decodes and renders the catalogue image', (tester) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
    });

    await tester.runAsync(() async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          host(const CachedImage('https://cdn.test/a.png', width: 80, height: 80)),
        );

        final rendered = await pumpUntil(tester, () => decoded(tester));
        expect(
          rendered,
          isTrue,
          reason: 'the image never decoded - fallback=${find.byKey(_fallbackKey).evaluate().length} '
              'placeholder=${find.byKey(_placeholderKey).evaluate().length} '
              'image=${find.byType(Image).evaluate().length} '
              'rawImage=${find.byType(RawImage).evaluate().length} '
              'requests=$requests bytes=${png.length}',
        );
        expect(find.byKey(_fallbackKey), findsNothing);
      }, () => client);
    });

    expect(requests, 1);
  });

  testWidgets('a rejected link degrades to the brand tile', (tester) async {
    final client = MockClient((_) async => http.Response('gone', 404));

    await tester.runAsync(() async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          host(const CachedImage('https://cdn.test/missing.png', width: 80, height: 80)),
        );

        final fellBack =
            await pumpUntil(tester, () => find.byKey(_fallbackKey).evaluate().isNotEmpty);
        expect(fellBack, isTrue, reason: 'a 404 must degrade, never throw');
        expect(find.byKey(_placeholderKey), findsNothing);
        expect(find.byType(RawImage), findsNothing);
      }, () => client);
    });
  });

  testWidgets('two cards sharing a URL trigger exactly one download', (tester) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
    });

    await tester.runAsync(() async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          host(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CachedImage('https://cdn.test/shared.png', width: 40, height: 40),
                CachedImage('https://cdn.test/shared.png', width: 40, height: 40),
              ],
            ),
          ),
        );
        await pumpUntil(tester, () => decoded(tester));
      }, () => client);
    });

    expect(requests, 1, reason: 'concurrent requests for one URL must be coalesced');
  });

  testWidgets('a missing url renders the fallback without any request', (tester) async {
    await tester.pumpWidget(host(const CachedImage('', width: 40, height: 40)));
    await tester.pump();

    expect(find.byKey(_fallbackKey), findsOneWidget);
    expect(find.byKey(_placeholderKey), findsNothing);
    expect(find.byType(RawImage), findsNothing);
  });
}

const _fallbackKey = ValueKey('cached-image-fallback');
const _placeholderKey = ValueKey('cached-image-placeholder');
