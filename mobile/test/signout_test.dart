import 'dart:async';

import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/core/network/api_client.dart';
import 'package:blabliblu/state/app_state.dart';
import 'package:blabliblu/state/resource.dart';
import 'package:blabliblu/state/store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SeedApi] whose order list can be held open, to prove a reply that was
/// already in flight when sign-out flushed the store never lands.
class _GatedOrdersApi extends SeedApi {
  Completer<void>? gateOrders;

  @override
  Future<List<Order>> getOrders({String? token, int page = 1, int limit = 20}) async {
    final gate = gateOrders;
    if (gate != null) await gate.future;
    return super.getOrders(token: token, page: page, limit: limit);
  }
}

/// [SeedApi] that cannot create a cart - sign-out must still wipe storage.
class _OfflineCartApi extends SeedApi {
  @override
  Future<Cart> createCart({String? token}) async => throw ApiException('offline', statusCode: 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Lets bootstrap's microtask + its awaited storage/seed reads finish.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('sign-out flushes every slice, wipes storage and drops late replies', () async {
    SharedPreferences.setMockInitialValues({'bbl.token': 'tok', 'bbl.cartId': 'cart-1'});
    final api = _GatedOrdersApi();
    final container = ProviderContainer(overrides: [apiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);

    final store = container.read(storeProvider.notifier);
    await settle();
    AppState state() => container.read(storeProvider);

    // A session as bootstrap left it: restored token + cart id.
    expect(state().auth.token, 'tok');
    expect(state().cart.cartId, 'cart-1');

    // Private state the session has loaded.
    await store.loadAddresses();
    await store.loadOrders();
    expect(state().orders.addresses.isSuccess, isTrue);
    expect(state().orders.list.isSuccess, isTrue);

    // Hold the *next* order read open, as a slow network would.
    api.gateOrders = Completer<void>();
    final inFlight = store.loadOrders();

    await store.signOut();

    api.gateOrders!.complete();
    await inFlight;
    api.gateOrders = null;

    // Nothing the old session loaded survives - in memory...
    expect(state().auth.token, isNull);
    expect(state().auth.isAuthenticated, isFalse);
    expect(state().orders.list.value, isNull, reason: 'a reply from before the flush must be dropped');
    expect(state().orders.list.status, LoadStatus.idle);
    expect(state().orders.addresses.value, isNull);
    expect(state().cart.cartId, isNot('cart-1'));
    expect(state().cart.cart.value?.id, state().cart.cartId, reason: 'a brand-new guest bag replaced the old one');
    expect(state().bootstrapped, isTrue);

    // ...and on disk.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bbl.token'), isNull);
    expect(prefs.getString('bbl.cartId'), state().cart.cartId);

    // The public shell refills itself, so no kept-alive tab is left on an
    // empty slot nothing will ever fetch.
    expect(state().catalog.home.hasValue, isTrue);
    expect(state().catalog.collections.hasValue, isTrue);
    expect(state().catalog.listings, isEmpty);
  });

  test('a failed fresh-cart creation still leaves storage wiped', () async {
    SharedPreferences.setMockInitialValues({'bbl.token': 'tok', 'bbl.cartId': 'cart-1'});
    final container = ProviderContainer(overrides: [apiProvider.overrideWithValue(_OfflineCartApi())]);
    addTearDown(container.dispose);

    final store = container.read(storeProvider.notifier);
    await settle();

    await store.signOut();

    expect(container.read(storeProvider).cart.cartId, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bbl.token'), isNull);
    expect(prefs.getString('bbl.cartId'), isNull, reason: 'the old bag id must never be re-persisted');
  });
}
