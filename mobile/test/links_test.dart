import 'package:blabliblu/app/links.dart';
import 'package:blabliblu/app/router.dart';
import 'package:blabliblu/features/auth/sign_in_screen.dart';
import 'package:blabliblu/features/home/home_screen.dart';
import 'package:blabliblu/features/product/product_screen.dart';
import 'package:blabliblu/features/shop/collection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seed_app.dart';

/// Regression coverage for the scraped-content links: the storefront speaks
/// Shopify's plural vocabulary (`/collections/x`, `/products/x`) which used to
/// leave every home section ("Our Collection", "Game Changer", banners,
/// footer) dead on tap.
void main() {
  group('resolveShopLink', () {
    test('translates storefront links onto app routes', () {
      expect(resolveShopLink('/collections/perfume'), '/collection/perfume');
      expect(resolveShopLink('/products/habibi'), '/product/habibi');
      expect(resolveShopLink('/pages/about-us'), '/page/about-us');
      expect(resolveShopLink('/collections/perfume?sort=new#top'), '/collection/perfume');
      expect(resolveShopLink('https://blabliblulife.com/collections/body-wash'), '/collection/body-wash');
      expect(resolveShopLink('/collections/'), '/shop');
      expect(resolveShopLink('/collections'), '/shop');
    });

    test('passes routes that are already singular through untouched', () {
      expect(resolveShopLink('/collection/new-arrivals'), '/collection/new-arrivals');
      expect(resolveShopLink('/product/habibi'), '/product/habibi');
      expect(resolveShopLink('/page/contact'), '/page/contact');
      expect(resolveShopLink('/faq'), '/faq');
      expect(resolveShopLink('/'), '/');
    });

    test('refuses links that have no in-app destination', () {
      expect(resolveShopLink(null), isNull);
      expect(resolveShopLink(''), isNull);
      expect(resolveShopLink('   '), isNull);
      expect(resolveShopLink('#reviews'), isNull);
      expect(resolveShopLink('https://instagram.com/blabliblu'), isNull);
      expect(resolveShopLink('mailto:support@blabliblulife.com'), isNull);
      expect(resolveShopLink('/pages'), isNull);
    });

    test('a web deep link survives the cold start', () {
      expect(coldStartLocation(true, '/shop'), '/shop');
      expect(coldStartLocation(true, '/collection/perfume'), '/collection/perfume');
      expect(coldStartLocation(true, '/cart?promo=WELCOME10'), '/cart?promo=WELCOME10');
      expect(coldStartLocation(true, ''), '/');
      expect(coldStartLocation(true, 'shop'), '/');
      // Native launches have no fragment and always boot on home.
      expect(coldStartLocation(false, '/shop'), '/');
    });
  });

  testWidgets('a scraped /collections tile opens its collection screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(seedApp());
    await _settle(tester);

    final context = tester.element(find.byType(NavigationBar));
    openShopLink(context, '/collections/perfume');
    await _settle(tester);

    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ...and the back button now has something underneath it to pop to.
    goBack(context);
    await _settle(tester);
    expect(find.byType(CollectionScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scraped /products tile opens the product screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(seedApp());
    await _settle(tester);

    final context = tester.element(find.byType(NavigationBar));
    openShopLink(context, '/products/love-drunk-best-unisex-perfume');
    await _settle(tester);

    expect(find.byType(ProductScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sign-in back arrow escapes a redirected screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(seedApp());
    await _settle(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBar)));

    // Exactly what the auth guard produces when the Account tab is tapped
    // while signed out: a bare `go` to /sign-in with an empty stack.
    container.read(routerProvider).go('/sign-in?next=%2Faccount');
    await _settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await _settle(tester);

    // The arrow used to call pop() into nothing and strand the user here.
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Same bounded settle as the layout sweep - skeletons and carousels animate
/// forever, and the seed file is real async IO that needs the event loop.
Future<void> _settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
