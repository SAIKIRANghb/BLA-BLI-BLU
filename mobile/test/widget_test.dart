import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/features/home/home_screen.dart';
import 'package:blabliblu/shared/widgets/widgets.dart';
import 'package:blabliblu/state/actions.dart';
import 'package:blabliblu/state/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seed_app.dart';

void main() {
  group('shared widgets', () {
    testWidgets('EmptyState shows its message and fires the CTA', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your bag is empty',
              subtitle: 'Nothing here yet.',
              actionLabel: 'Start shopping',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Your bag is empty'), findsOneWidget);
      await tester.tap(find.text('Start shopping'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('QtyStepper never goes below its minimum', (tester) async {
      var value = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => QtyStepper(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );

      // The minus button is disabled at the floor, so this must be a no-op.
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(value, 1);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(value, 2);
    });
  });

  testWidgets('app boots into the storefront shell', (tester) async {
    // Seed mode (`kUseLocalSeed`) + an empty session = no backend required.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(seedApp());

    // Let bootstrap (prefs restore + seed hydration) land before asserting.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('BLA BLI BLU'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('the cart count rides on both the Bag tab and the header cart', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(seedApp());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Empty bag: no number yet on either surface, but the header action is there.
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('3')), findsNothing);
    expect(find.descendant(of: find.byType(HomeScreen), matching: find.text('3')), findsNothing);
    expect(find.descendant(of: find.byType(HomeScreen), matching: find.byIcon(Icons.shopping_bag_outlined)), findsOneWidget);

    // A cart landing in the store repaints both counts without a rebuild hack.
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));
    container.read(storeProvider.notifier).dispatch(
          const CartLoadSucceeded(Cart(id: 'c1', itemCount: 3, subtotal: 69500, totals: CartTotals(total: 69500))),
        );
    await tester.pump();

    // 1. the Bag tab in the bottom bar carries the bare number on its icon...
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.byType(CountOnIcon)), findsWidgets);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('3')), findsWidgets);
    // 2. ...and so does the cart action in the top app bar.
    expect(find.descendant(of: find.byType(HomeScreen), matching: find.text('3')), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
