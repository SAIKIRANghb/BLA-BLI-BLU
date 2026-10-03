import 'package:blabliblu/app/links.dart';
import 'package:blabliblu/features/product/product_screen.dart';
import 'package:blabliblu/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seed_app.dart';

/// The bag has to be reachable exactly where it is used.
///
/// `/product/:handle` is a full-screen route, so it pushes the shell (and its
/// bottom bar) away - which left the add-to-bag moment with no cart anywhere
/// on screen. The product top bar therefore carries the cart action, and the
/// count prints onto it as a bare number the instant the item lands.
void main() {
  testWidgets('the product top bar carries the cart and its live count', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(seedApp());
    await _settle(tester);

    final context = tester.element(find.byType(NavigationBar));
    openShopLink(context, '/products/love-drunk-best-unisex-perfume');
    await _settle(tester);
    expect(find.byType(ProductScreen), findsOneWidget);

    // The bottom bar is gone on this route - the top bar is the only surface.
    expect(find.byType(NavigationBar), findsNothing);

    final cartAction = find.descendant(of: find.byType(ProductScreen), matching: find.byType(CartIconButton));
    expect(cartAction, findsOneWidget);

    // Empty bag: the icon is there, the number is not.
    expect(find.descendant(of: cartAction, matching: find.text('1')), findsNothing);

    // Add to bag (the pinned bottom sheet) -> the count rides onto that icon.
    await tester.tap(find.textContaining('Add to bag'));
    await _settle(tester);

    expect(find.descendant(of: cartAction, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: cartAction, matching: find.byType(CountOnIcon)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Same bounded settle as the other suites: the seed file is real async IO and
/// skeletons/carousels animate forever.
Future<void> _settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
