import 'package:blabliblu/features/home/home_screen.dart';
import 'package:blabliblu/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for the hero autoplay.
///
/// The carousel used to be static - the `PageController` never advanced on
/// its own, so the banner only moved when the user swiped it. The store now
/// owns a 4-second periodic timer that walks the slides (and wraps at the
/// end), cancelled together with the screen.
void main() {
  testWidgets('the hero carousel advances on its own', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: BlablibluApp()));
    await _settle(tester);

    final pageView = tester.widget<PageView>(
      find.descendant(of: find.byType(HomeScreen), matching: find.byType(PageView)).first,
    );
    final controller = pageView.controller!;
    expect(controller.page, 0);
    expect(pageView.childrenDelegate.estimatedChildCount, greaterThan(1), reason: 'autoplay needs more than one slide');

    // Cross the 4s timer boundary - the periodic callback schedules nextPage.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 430));
    expect(controller.page, 1, reason: 'the banner moved on without a swipe');

    // ...and it keeps going instead of stalling on slide 2.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 430));
    expect(controller.page, 2);

    expect(tester.takeException(), isNull);
  });
}

/// Same bounded settle as the layout sweep: the seed file and the slide
/// images are real async IO, which needs the actual event loop to turn.
Future<void> _settle(WidgetTester tester, {int iterations = 25}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
