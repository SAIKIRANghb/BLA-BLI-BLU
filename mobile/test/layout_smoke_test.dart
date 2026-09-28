import 'package:blabliblu/app/router.dart';
import 'package:blabliblu/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layout smoke sweep: walks every screen of the app on a phone-sized and a
/// foldable-sized viewport and fails if the framework recorded any rendering
/// exception (RenderFlex overflow, unbounded text, failed assertion, ...).
///
/// Deliberately golden-free: PNG goldens depend on the machine's fonts and
/// rendering backend, so they would fail on any other computer. Overflow
/// detection needs no goldens at all.
void main() {
  final screens = <String, String>{
    '/': 'home',
    '/shop': 'shop',
    '/search': 'search',
    '/cart': 'cart',
    '/checkout': 'checkout',
    '/account': 'account',
    '/collection/new-arrivals': 'collection',
    '/product/love-drunk-best-unisex-perfume': 'product',
    '/faq': 'faq',
    '/page/about-us': 'page',
    '/sign-in': 'sign-in',
    '/sign-up': 'sign-up',
    '/track': 'track',
    '/orders': 'orders',
    '/order/TST-1001': 'order-detail',
    '/addresses': 'addresses',
    '/route-that-does-not-exist': 'not-found',
  };

  for (final size in const [Size(390, 844), Size(653, 891)]) {
    testWidgets('no layout defects at ${size.width}x${size.height}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: BlablibluApp()));
      await _settle(tester);
      expectNoErrors(tester, 'boot');

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final router = container.read(routerProvider);

      for (final entry in screens.entries) {
        router.go(entry.key);
        await _settle(tester);
        expectNoErrors(tester, entry.value);
      }
    });
  }
}

/// Bounded settle loop - skeletons, pulse placeholders and carousels animate
/// forever, so `pumpAndSettle` would never return.
///
/// Each frame is preceded by a real `runAsync` delay: the seed file and the
/// image bytes are real async IO, which only completes while the actual event
/// loop turns (fake-async `pump` alone would leave every screen on its
/// skeleton forever).
Future<void> _settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Drains every exception recorded since the last drain (not only the first)
/// and fails the test if there was any.
void expectNoErrors(WidgetTester tester, String where) {
  final errors = <Object>[];
  Object? next;
  while ((next = tester.takeException()) != null) {
    errors.add(next!);
  }
  expect(
    errors,
    isEmpty,
    reason: 'rendering defects on "$where":\n'
        '${errors.map((e) => '  - $e').join('\n')}',
  );
}
