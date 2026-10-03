/// Pure reducers: `AppState x AppAction -> AppState`.
///
/// No I/O, no `async`, no captured state - every function takes the current
/// tree and returns a new tree, touching only the slice the action belongs to.
/// Slices that are not mentioned keep their *same instance*, so
/// `select`-ing an untouched slice never rebuilds a widget.
library;

import '../core/models/models.dart';
import 'actions.dart';
import 'app_state.dart';
import 'resource.dart';

/// Root reducer - a switch over the sealed action type.
AppState rootReducer(AppState state, AppAction action) {
  return switch (action) {
    BootstrapCompleted(:final restoredToken, :final restoredCartId) => state.copyWith(
        bootstrapped: true,
        auth: state.auth.copyWith(token: restoredToken),
        cart: state.cart.copyWith(cartId: restoredCartId),
      ),

    // ── home ──────────────────────────────────────────────────────────────
    HomeLoadRequested() => state.copyWith(
        catalog: state.catalog.copyWith(home: state.catalog.home.toLoading()),
      ),
    HomeLoadSucceeded(:final data) => state.copyWith(
        catalog: state.catalog.copyWith(home: Resource<HomeData>.seeded(data)),
      ),
    HomeLoadFailed(:final message) => state.copyWith(
        catalog: state.catalog.copyWith(home: state.catalog.home.toError(message)),
      ),

    // ── collections ───────────────────────────────────────────────────────
    CollectionsLoadSucceeded(:final items) => state.copyWith(
        catalog: state.catalog.copyWith(collections: Resource<List<CollectionTile>>.seeded(items)),
      ),
    CollectionsLoadFailed(:final message) => state.copyWith(
        catalog: state.catalog.copyWith(collections: state.catalog.collections.toError(message)),
      ),

    // ── listings ──────────────────────────────────────────────────────────
    ListingLoadRequested(:final key, :final refresh) => state.copyWith(
        catalog: state.catalog.copyWith(
          listings: {
            ...state.catalog.listings,
            key: refresh
                ? const Resource<ProductPage>().toLoading()
                : (state.catalog.listings[key] ?? const Resource<ProductPage>()).toLoading(),
          },
        ),
      ),
    ListingLoadSucceeded(:final key, :final page, :final append) => state.copyWith(
        catalog: state.catalog.copyWith(
          listings: {...state.catalog.listings, key: _mergeListing(state.catalog.listings[key], page, append)},
        ),
      ),
    ListingLoadFailed(:final key, :final message) => state.copyWith(
        catalog: state.catalog.copyWith(
          listings: {
            ...state.catalog.listings,
            key: (state.catalog.listings[key] ?? const Resource<ProductPage>()).toError(message),
          },
        ),
      ),
    ListingCacheCleared() => state.copyWith(catalog: state.catalog.copyWith(listings: const {})),

    // ── product detail ────────────────────────────────────────────────────
    ProductLoadRequested(:final handle) => state.copyWith(
        catalog: state.catalog.copyWith(
          details: {
            ...state.catalog.details,
            handle: (state.catalog.details[handle] ?? const Resource<ProductDetail>()).toLoading(),
          },
        ),
      ),
    ProductLoadSucceeded(:final handle, :final detail, :final reviews) => state.copyWith(
        catalog: state.catalog.copyWith(
          details: {...state.catalog.details, handle: Resource<ProductDetail>.seeded(detail)},
          reviews: {...state.catalog.reviews, handle: reviews},
        ),
      ),
    ProductLoadFailed(:final handle, :final message) => state.copyWith(
        catalog: state.catalog.copyWith(
          details: {
            ...state.catalog.details,
            handle: (state.catalog.details[handle] ?? const Resource<ProductDetail>()).toError(message),
          },
        ),
      ),
    ProductReviewsLoaded(:final handle, :final reviews) => state.copyWith(
        catalog: state.catalog.copyWith(reviews: {...state.catalog.reviews, handle: reviews}),
      ),

    // ── content ───────────────────────────────────────────────────────────
    FaqsLoadSucceeded(:final groups) => state.copyWith(
        content: state.content.copyWith(faqs: Resource<List<FaqGroup>>.seeded(groups)),
      ),
    FaqsLoadFailed(:final message) => state.copyWith(
        content: state.content.copyWith(faqs: state.content.faqs.toError(message)),
      ),
    PageLoadSucceeded(:final page) => state.copyWith(
        content: state.content.copyWith(pages: {...state.content.pages, page.handle: Resource<PageContent>.seeded(page)}),
      ),
    PageLoadFailed(:final handle, :final message) => state.copyWith(
        content: state.content.copyWith(pages: {...state.content.pages, handle: Resource<PageContent>().toError(message)}),
      ),

    // ── auth ──────────────────────────────────────────────────────────────
    AuthRequestStarted() => state.copyWith(
        auth: state.auth.copyWith(request: const Resource<AuthSession>().toLoading()),
      ),
    AuthSucceeded(:final session) => state.copyWith(
        auth: state.auth.copyWith(
          request: Resource<AuthSession>.seeded(session),
          session: session,
          user: session.user,
          token: session.accessToken,
        ),
      ),
    AuthFailed(:final message) => state.copyWith(
        auth: state.auth.copyWith(request: state.auth.request.toError(message)),
      ),
    // Sign-out wipes the whole tree: catalogue, content, auth, cart, orders,
    // routing and UI all go back to their pristine value. `bootstrapped` is
    // carried over (the persisted session was already restored once; a flush
    // is not a cold start), and the store re-loads the public shell after
    // dispatching this - see `Store.signOut`.
    StateFlushed() => AppState(bootstrapped: state.bootstrapped),
    ProfileUpdated(:final user) => state.copyWith(
        auth: state.auth.copyWith(user: user, session: state.auth.session == null ? null : _withUser(state.auth.session!, user)),
      ),

    // ── cart ──────────────────────────────────────────────────────────────
    CartLoadSucceeded(:final cart) => state.copyWith(
        cart: state.cart.copyWith(cart: Resource<Cart>.seeded(cart), busy: false),
      ),
    CartLoadFailed(:final message) => state.copyWith(
        cart: state.cart.copyWith(cart: state.cart.cart.toError(message), busy: false),
      ),
    CartBusyChanged(:final busy) => state.copyWith(cart: state.cart.copyWith(busy: busy)),
    CartIdAssigned(:final cartId) => state.copyWith(cart: state.cart.copyWith(cartId: cartId)),

    // ── orders ────────────────────────────────────────────────────────────
    OrdersLoadSucceeded(:final orders) => state.copyWith(
        orders: state.orders.copyWith(list: Resource<List<Order>>.seeded(orders)),
      ),
    OrdersLoadFailed(:final message) => state.copyWith(
        orders: state.orders.copyWith(list: state.orders.list.toError(message)),
      ),
    OrderDetailSucceeded(:final order) => state.copyWith(
        orders: state.orders.copyWith(detail: Resource<Order>.seeded(order)),
      ),
    OrderDetailFailed(:final message) => state.copyWith(
        orders: state.orders.copyWith(detail: state.orders.detail.toError(message)),
      ),
    OrderTrackingSucceeded(:final order) => state.copyWith(
        orders: state.orders.copyWith(tracking: Resource<Order>.seeded(order)),
      ),
    OrderTrackingFailed(:final message) => state.copyWith(
        orders: state.orders.copyWith(tracking: state.orders.tracking.toError(message)),
      ),
    OrderPlaced(:final order) => state.copyWith(
        orders: state.orders.copyWith(
          lastPlaced: order,
          detail: Resource<Order>.seeded(order),
          list: Resource<List<Order>>.seeded([order, ...state.orders.list.value ?? const <Order>[]]),
        ),
        // checkout empties the server cart; mirror it locally right away
        cart: const CartSlice(),
        catalog: state.catalog.copyWith(listings: const {}),
      ),
    AddressesLoadSucceeded(:final addresses) => state.copyWith(
        orders: state.orders.copyWith(addresses: Resource<List<Address>>.seeded(addresses)),
      ),
    AddressesLoadFailed(:final message) => state.copyWith(
        orders: state.orders.copyWith(addresses: state.orders.addresses.toError(message)),
      ),

    // ── routing (OSRM) ─────────────────────────────────────────────────────
    EtaLoadRequested() => state.copyWith(
        routing: state.routing.copyWith(eta: const Resource<EtaEstimate>().toLoading()),
      ),
    EtaLoadSucceeded(:final estimate) => state.copyWith(
        routing: state.routing.copyWith(eta: Resource<EtaEstimate>.seeded(estimate)),
      ),
    EtaLoadFailed(:final message) => state.copyWith(
        routing: state.routing.copyWith(eta: state.routing.eta.toError(message)),
      ),
    RouteLoadRequested() => state.copyWith(
        routing: state.routing.copyWith(
          route: const Resource<RouteResult>().toLoading(),
          match: const Resource<MatchResult>(),
          clearRider: true,
          progress: 0.0,
        ),
      ),
    RouteLoadSucceeded(:final result) => state.copyWith(
        routing: state.routing.copyWith(route: Resource<RouteResult>.seeded(result)),
      ),
    RouteLoadFailed(:final message) => state.copyWith(
        routing: state.routing.copyWith(route: state.routing.route.toError(message)),
      ),
    MatchSucceeded(:final result) => state.copyWith(
        routing: state.routing.copyWith(match: Resource<MatchResult>.seeded(result)),
      ),
    MatchFailed(:final message) => state.copyWith(
        routing: state.routing.copyWith(match: state.routing.match.toError(message)),
      ),
    RiderAdvanced(:final at, :final progress) => state.copyWith(
        routing: state.routing.copyWith(rider: at, progress: progress),
      ),
    TrackingReset() => state.copyWith(
        routing: state.routing.copyWith(
          route: const Resource<RouteResult>(),
          match: const Resource<MatchResult>(),
          clearRider: true,
          progress: 0.0,
        ),
      ),

    // ── UI ────────────────────────────────────────────────────────────────
    SearchQueryChanged(:final query) => state.copyWith(ui: state.ui.copyWith(searchQuery: query)),
    ToastShown(:final message, :final error) =>
      state.copyWith(ui: state.ui.copyWith(toast: message, toastIsError: error)),
    ToastCleared() => state.copyWith(ui: state.ui.copyWith(clearToast: true)),
    BottomNavChanged(:final index) => state.copyWith(ui: state.ui.copyWith(navIndex: index)),
  };
}

/// Appends freshly fetched pages to the ones already cached for that query.
///
/// The slot is keyed per query (never per page), so this is where the grid's
/// infinite scroll actually accumulates: page 2 lands *after* page 1 instead
/// of replacing it, and items already shown are dropped again if the server
/// shifts its sort window between requests.
Resource<ProductPage> _mergeListing(Resource<ProductPage>? previous, ProductPage next, bool append) {
  if (!append || previous?.value == null) return Resource<ProductPage>.seeded(next);
  final current = previous!.value!.items;
  final known = current.map((p) => p.handle).toSet();
  final merged = ProductPage(
    items: [...current, ...next.items.where((p) => !known.contains(p.handle))],
    total: next.total,
    page: next.page,
    totalPages: next.totalPages,
  );
  return Resource<ProductPage>.seeded(merged);
}

AuthSession _withUser(AuthSession session, AuthUser user) =>
    AuthSession(user: user, accessToken: session.accessToken, refreshToken: session.refreshToken);
