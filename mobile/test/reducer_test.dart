import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/state/actions.dart';
import 'package:blabliblu/state/app_state.dart';
import 'package:blabliblu/state/reducers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rootReducer', () {
    test('untouched slices keep their instance (no rebuild churn)', () {
      const before = AppState();
      final after = rootReducer(before, const SearchQueryChanged('oud'));

      expect(identical(before.catalog, after.catalog), isTrue);
      expect(identical(before.cart, after.cart), isTrue);
      expect(identical(before.orders, after.orders), isTrue);
      expect(after.ui.searchQuery, 'oud');
    });

    test('bootstrap restores the persisted session and cart id', () {
      final state = rootReducer(
        const AppState(),
        const BootstrapCompleted(restoredToken: 'tok', restoredCartId: 'cart-1'),
      );

      expect(state.bootstrapped, isTrue);
      expect(state.auth.token, 'tok');
      expect(state.cart.cartId, 'cart-1');
      expect(state.auth.isAuthenticated, isTrue);
    });

    test('signing out clears the session but keeps the cart id', () {
      var state = rootReducer(
        const AppState(),
        const BootstrapCompleted(restoredToken: 'tok', restoredCartId: 'cart-1'),
      );
      state = rootReducer(state, const AuthSignedOut());

      expect(state.auth.token, isNull);
      expect(state.auth.isAuthenticated, isFalse);
      expect(state.cart.cartId, 'cart-1');
    });

    test('cart slices round-trip through CartLoadSucceeded', () {
      const cart = Cart(id: 'c1', itemCount: 3, subtotal: 198500, totals: CartTotals(total: 198500));
      final state = rootReducer(const AppState(), const CartLoadSucceeded(cart));

      expect(state.cart.itemCount, 3);
      expect(state.cart.isEmpty, isFalse);
      expect(state.cart.cart.value?.id, 'c1');
    });

    test('an order leaves lastPlaced for the confirmation screen', () {
      const order = Order(
        id: 'o1',
        orderNumber: 'BBL-20260928-1001',
        status: 'placed',
        address: ShippingAddress(line1: '1 Main Road', city: 'Pune', state: 'MH', pincode: '411001'),
        total: 69500,
      );
      final state = rootReducer(const AppState(), const OrderPlaced(order));

      expect(state.orders.lastPlaced?.orderNumber, 'BBL-20260928-1001');
    });

    test('listing cache is keyed by query and stores appended pages', () {
      const key = '::oud::featured';
      const pageOne = ProductPage(items: [], total: 40, page: 1, totalPages: 2);
      final state = rootReducer(const AppState(), const ListingLoadSucceeded(key, pageOne));

      expect(state.catalog.listings[key]?.value?.total, 40);
      expect(state.catalog.listings[key]?.isSuccess, isTrue);
    });

    test('toast slot is set and cleared', () {
      var state = rootReducer(const AppState(), const ToastShown('Added', error: false));
      expect(state.ui.toast, 'Added');
      expect(state.ui.toastIsError, isFalse);

      state = rootReducer(state, const ToastCleared());
      expect(state.ui.toast, isNull);
    });
  });
}
