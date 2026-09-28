/// Immutable application state - a tree of slices, each holding [Resource]s.
///
/// `AppState` and every slice are const-constructible value objects; the store
/// swaps the whole tree on each dispatch and Riverpod notifies exactly the
/// widgets that `select` a slice that actually changed.
library;

import 'package:flutter/foundation.dart' show immutable, mapEquals;

import '../core/models/models.dart';
import 'resource.dart';

// ──────────────────────────────────── slices ─────────────────────────────────

@immutable
class CatalogSlice {
  const CatalogSlice({
    this.home = const Resource<HomeData>(),
    this.collections = const Resource<List<CollectionTile>>(),
    this.listings = const {},
    this.details = const {},
    this.reviews = const {},
  });

  final Resource<HomeData> home;
  final Resource<List<CollectionTile>> collections;

  /// Cached listing pages keyed by [listingKey] from `actions.dart`.
  final Map<String, Resource<ProductPage>> listings;

  /// Cached product details keyed by handle.
  final Map<String, Resource<ProductDetail>> details;

  /// Cached review lists keyed by handle.
  final Map<String, List<ProductReview>> reviews;

  CatalogSlice copyWith({
    Resource<HomeData>? home,
    Resource<List<CollectionTile>>? collections,
    Map<String, Resource<ProductPage>>? listings,
    Map<String, Resource<ProductDetail>>? details,
    Map<String, List<ProductReview>>? reviews,
  }) =>
      CatalogSlice(
        home: home ?? this.home,
        collections: collections ?? this.collections,
        listings: listings ?? this.listings,
        details: details ?? this.details,
        reviews: reviews ?? this.reviews,
      );

  @override
  bool operator ==(Object other) =>
      other is CatalogSlice &&
      other.home == home &&
      other.collections == collections &&
      mapEquals(other.listings, listings) &&
      mapEquals(other.details, details) &&
      mapEquals(other.reviews, reviews);

  @override
  int get hashCode => Object.hash(home, collections, Object.hashAll(listings.entries), Object.hashAll(details.entries));
}

@immutable
class ContentSlice {
  const ContentSlice({this.faqs = const Resource<List<FaqGroup>>(), this.pages = const {}});

  final Resource<List<FaqGroup>> faqs;
  final Map<String, Resource<PageContent>> pages;

  ContentSlice copyWith({Resource<List<FaqGroup>>? faqs, Map<String, Resource<PageContent>>? pages}) =>
      ContentSlice(faqs: faqs ?? this.faqs, pages: pages ?? this.pages);

  @override
  bool operator ==(Object other) =>
      other is ContentSlice && other.faqs == faqs && mapEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(faqs, Object.hashAll(pages.entries));
}

@immutable
class AuthSlice {
  const AuthSlice({
    this.request = const Resource<AuthSession>(),
    this.session,
    this.user,
    this.token,
  });

  /// In-flight login/register/register form state.
  final Resource<AuthSession> request;

  /// Persisted session, if signed in.
  final AuthSession? session;
  final AuthUser? user;
  final String? token;

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  bool get isBusy => request.isLoading;

  AuthSlice copyWith({
    Resource<AuthSession>? request,
    AuthSession? session,
    AuthUser? user,
    String? token,
    bool clearSession = false,
  }) =>
      AuthSlice(
        request: request ?? this.request,
        session: clearSession ? null : (session ?? this.session),
        user: clearSession ? null : (user ?? this.user),
        token: clearSession ? null : (token ?? this.token),
      );

  @override
  bool operator ==(Object other) =>
      other is AuthSlice &&
      other.request == request &&
      other.session == session &&
      other.user == user &&
      other.token == token;

  @override
  int get hashCode => Object.hash(request, session, user, token);
}

@immutable
class CartSlice {
  const CartSlice({this.cartId, this.cart = const Resource<Cart>(), this.busy = false});

  final String? cartId;
  final Resource<Cart> cart;
  final bool busy;

  int get itemCount => cart.value?.itemCount ?? 0;
  bool get isEmpty => itemCount == 0;

  CartSlice copyWith({String? cartId, Resource<Cart>? cart, bool? busy, bool clearCartId = false}) => CartSlice(
        cartId: clearCartId ? null : (cartId ?? this.cartId),
        cart: cart ?? this.cart,
        busy: busy ?? this.busy,
      );

  @override
  bool operator ==(Object other) =>
      other is CartSlice && other.cartId == cartId && other.cart == cart && other.busy == busy;

  @override
  int get hashCode => Object.hash(cartId, cart, busy);
}

@immutable
class OrderSlice {
  const OrderSlice({
    this.list = const Resource<List<Order>>(),
    this.detail = const Resource<Order>(),
    this.tracking = const Resource<Order>(),
    this.addresses = const Resource<List<Address>>(),
    this.lastPlaced,
  });

  final Resource<List<Order>> list;
  final Resource<Order> detail;
  final Resource<Order> tracking;
  final Resource<List<Address>> addresses;

  /// Order just submitted - used by the confirmation screen.
  final Order? lastPlaced;

  OrderSlice copyWith({
    Resource<List<Order>>? list,
    Resource<Order>? detail,
    Resource<Order>? tracking,
    Resource<List<Address>>? addresses,
    Order? lastPlaced,
    bool clearLastPlaced = false,
  }) =>
      OrderSlice(
        list: list ?? this.list,
        detail: detail ?? this.detail,
        tracking: tracking ?? this.tracking,
        addresses: addresses ?? this.addresses,
        lastPlaced: clearLastPlaced ? null : (lastPlaced ?? this.lastPlaced),
      );

  @override
  bool operator ==(Object other) =>
      other is OrderSlice &&
      other.list == list &&
      other.detail == detail &&
      other.tracking == tracking &&
      other.addresses == addresses &&
      other.lastPlaced == lastPlaced;

  @override
  int get hashCode => Object.hash(list, detail, tracking, addresses, lastPlaced);
}

@immutable
class UiSlice {
  const UiSlice({this.navIndex = 0, this.toast, this.toastIsError = false, this.searchQuery = ''});

  final int navIndex;
  final String? toast;
  final bool toastIsError;
  final String searchQuery;

  UiSlice copyWith({
    int? navIndex,
    String? toast,
    bool? toastIsError,
    String? searchQuery,
    bool clearToast = false,
  }) =>
      UiSlice(
        navIndex: navIndex ?? this.navIndex,
        toast: clearToast ? null : (toast ?? this.toast),
        toastIsError: toastIsError ?? this.toastIsError,
        searchQuery: searchQuery ?? this.searchQuery,
      );

  @override
  bool operator ==(Object other) =>
      other is UiSlice &&
      other.navIndex == navIndex &&
      other.toast == toast &&
      other.toastIsError == toastIsError &&
      other.searchQuery == searchQuery;

  @override
  int get hashCode => Object.hash(navIndex, toast, toastIsError, searchQuery);
}

// ────────────────────────────────── AppState ─────────────────────────────────

@immutable
class AppState {
  const AppState({
    this.catalog = const CatalogSlice(),
    this.content = const ContentSlice(),
    this.auth = const AuthSlice(),
    this.cart = const CartSlice(),
    this.orders = const OrderSlice(),
    this.ui = const UiSlice(),
    this.bootstrapped = false,
  });

  final CatalogSlice catalog;
  final ContentSlice content;
  final AuthSlice auth;
  final CartSlice cart;
  final OrderSlice orders;
  final UiSlice ui;

  /// True once persisted token/cart id have been restored from storage.
  final bool bootstrapped;

  AppState copyWith({
    CatalogSlice? catalog,
    ContentSlice? content,
    AuthSlice? auth,
    CartSlice? cart,
    OrderSlice? orders,
    UiSlice? ui,
    bool? bootstrapped,
  }) =>
      AppState(
        catalog: catalog ?? this.catalog,
        content: content ?? this.content,
        auth: auth ?? this.auth,
        cart: cart ?? this.cart,
        orders: orders ?? this.orders,
        ui: ui ?? this.ui,
        bootstrapped: bootstrapped ?? this.bootstrapped,
      );

  @override
  bool operator ==(Object other) =>
      other is AppState &&
      other.catalog == catalog &&
      other.content == content &&
      other.auth == auth &&
      other.cart == cart &&
      other.orders == orders &&
      other.ui == ui &&
      other.bootstrapped == bootstrapped;

  @override
  int get hashCode => Object.hash(catalog, content, auth, cart, orders, ui, bootstrapped);

  @override
  String toString() => 'AppState(bootstrapped: $bootstrapped, nav: ${ui.navIndex}, items: ${cart.itemCount})';
}
