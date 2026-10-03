/// go_router wiring: one [StatefulShellRoute] for the 5-tab shell, plus
/// full-screen routes pushed on top of it (product, checkout, orders, auth...).
///
/// `refreshListenable` is bridged from the store so redirects (sign-in guard,
/// cart count) react to state changes without a global navigator key hack.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../core/models/models.dart';
import '../features/account/account_screen.dart';
import '../features/account/address_picker_screen.dart';
import '../features/account/addresses_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/content/faq_screen.dart';
import '../features/content/page_screen.dart';
import '../features/home/home_screen.dart';
import '../features/orders/delivery_map_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/order_success_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/orders/track_order_screen.dart';
import '../features/product/product_screen.dart';
import '../features/rider/rider_detail_screen.dart';
import '../features/rider/rider_list_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shop/collection_screen.dart';
import '../features/shop/shop_screen.dart';
import '../shell/app_shell.dart';
import '../state/app_state.dart';
import '../state/store.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Listens to the store and tells go_router to re-evaluate redirects.
///
/// Only meaningful changes trigger a refresh (auth flips, cart count, tab) so
/// a barrage of catalogue updates does not churn the router.
class _StoreRouterRefresh extends ChangeNotifier {
  _StoreRouterRefresh(Ref ref) {
    _subscription = ref.listen<AppState>(
      storeProvider,
      (previous, next) {
        if (previous?.auth.isAuthenticated != next.auth.isAuthenticated ||
            previous?.cart.itemCount != next.cart.itemCount ||
            previous?.ui.navIndex != next.ui.navIndex) {
          notifyListeners();
        }
      },
    );
  }

  late final ProviderSubscription<AppState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _StoreRouterRefresh(ref);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: coldStartLocation(kIsWeb, Uri.base.fragment),
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/shop', builder: (context, state) => const ShopScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/account', builder: (context, state) => const AccountScreen()),
            ],
          ),
        ],
      ),

      // ── full-screen routes ────────────────────────────────────────────────
      GoRoute(
        path: '/collection/:handle',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => CollectionScreen(handle: state.pathParameters['handle']!),
      ),
      GoRoute(
        path: '/product/:handle',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ProductScreen(handle: state.pathParameters['handle']!),
      ),
      GoRoute(
        path: '/checkout',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/order-success/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => OrderSuccessScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/orders',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/order/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
        routes: [
          // Live tracking map; public like its parent so shared links work.
          GoRoute(
            path: 'live',
            parentNavigatorKey: _rootKey,
            builder: (context, state) => DeliveryMapScreen(orderId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/track',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => TrackOrderScreen(initialOrderNumber: state.extra as String?),
      ),
      GoRoute(
        path: '/rider',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const RiderListScreen(),
        routes: [
          // One delivery: route map + device GPS / demo ride fix sender.
          GoRoute(
            path: ':id',
            parentNavigatorKey: _rootKey,
            builder: (context, state) => RiderDetailScreen(
              orderId: state.pathParameters['id']!,
              job: state.extra as DeliveryJob?,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/addresses',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const AddressesScreen(),
        routes: [
          // Pushed above the address dialog so the picker can return a pin.
          GoRoute(
            path: 'pick',
            parentNavigatorKey: _rootKey,
            builder: (context, state) => AddressPickerScreen(initialPin: state.extra as LatLng?),
          ),
        ],
      ),
      GoRoute(
        path: '/faq',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/page/:handle',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => PageScreen(handle: state.pathParameters['handle']!),
      ),
      GoRoute(
        path: '/sign-in',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SignInScreen(),
        routes: [
          GoRoute(
            path: 'sign-up',
            parentNavigatorKey: _rootKey,
            builder: (context, state) => const SignUpScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/sign-up',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SignUpScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That page does not exist.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Back to home')),
          ],
        ),
      ),
    ),
    redirect: (context, state) => _redirect(ref, state),
  );

  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});

/// Auth guard + cross-tab redirects. Returning `null` = "no redirect".
String? _redirect(Ref ref, GoRouterState state) {
  final app = ref.read(storeProvider);
  final location = state.matchedLocation;
  final signedIn = app.auth.isAuthenticated;

  const protected = ['/checkout', '/orders', '/addresses', '/account', '/rider'];
  final needsAuth = protected.any((p) => location == p || location.startsWith('$p/'));

  if (needsAuth && !signedIn) {
    // Preserve where the user was headed so we can bounce back after sign-in.
    return '/sign-in?next=${Uri.encodeComponent(location)}';
  }
  if (signedIn && (location == '/sign-in' || location == '/sign-up')) {
    return state.uri.queryParameters['next'] ?? '/';
  }
  return null;
}

/// Location the router boots at.
///
/// On the web a cold start carries the deep link in the address-bar fragment
/// (`/#/shop`), but go_router's platform default parses that hash as an empty
/// path and silently collapses it to `/` - a shared link would always land on
/// home. Read the fragment straight from [Uri.base] instead. Native launches
/// have no fragment, so they keep booting at `/`.
String coldStartLocation(bool isWeb, String fragment) {
  if (!isWeb) return '/';
  return fragment.startsWith('/') ? fragment : '/';
}
