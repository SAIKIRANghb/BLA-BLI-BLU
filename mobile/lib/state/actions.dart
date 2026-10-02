/// Sealed action hierarchy - the only way application state may change.
///
/// Redux vocabulary: an *action* is an immutable description of "what happened",
/// a *reducer* (see `reducers.dart`) is a pure `AppState x Action -> AppState`
/// function, and the *store* (`store.dart`) is the single mutable owner that
/// dispatches actions coming from async thunks.
///
/// Nothing in this file performs I/O - it is data only, so reducers stay
/// deterministic and trivially unit-testable.
library;

import 'package:latlong2/latlong.dart';

import '../core/models/models.dart';

sealed class AppAction {
  const AppAction();
}

// ─────────────────────────────────── bootstrap ───────────────────────────────

class BootstrapCompleted extends AppAction {
  const BootstrapCompleted({this.restoredToken, this.restoredCartId});
  final String? restoredToken;
  final String? restoredCartId;
}

// ───────────────────────────────────── home ──────────────────────────────────

class HomeLoadRequested extends AppAction {
  const HomeLoadRequested();
}

class HomeLoadSucceeded extends AppAction {
  const HomeLoadSucceeded(this.data);
  final HomeData data;
}

class HomeLoadFailed extends AppAction {
  const HomeLoadFailed(this.message);
  final String message;
}

// ───────────────────────────────── collections ───────────────────────────────

class CollectionsLoadSucceeded extends AppAction {
  const CollectionsLoadSucceeded(this.items);
  final List<CollectionTile> items;
}

class CollectionsLoadFailed extends AppAction {
  const CollectionsLoadFailed(this.message);
  final String message;
}

// ──────────────────────── product listings (grid pages) ──────────────────────

/// Key that identifies one listing *query* (collection + search + sort).
///
/// The page number is deliberately **not** part of the key: a grid keeps one
/// slot per query and appends fetched pages into it, so scrolling deep never
/// swaps page 1 out from under the user. The slot itself records which page it
/// has reached (see `ProductPage.page`).
String listingKey({String? collection, String? query, String sort = 'featured'}) =>
    [collection ?? '', query ?? '', sort].join('::');

class ListingLoadRequested extends AppAction {
  const ListingLoadRequested(this.key, {this.refresh = false});
  final String key;
  final bool refresh;
}

class ListingLoadSucceeded extends AppAction {
  const ListingLoadSucceeded(this.key, this.page, {this.append = false});
  final String key;
  final ProductPage page;
  final bool append;
}

class ListingLoadFailed extends AppAction {
  const ListingLoadFailed(this.key, this.message);
  final String key;
  final String message;
}

/// Discards cached listing pages (called after checkout empties the cart is
/// *not* needed, but a new session is - kept explicit so cache growth is bounded).
class ListingCacheCleared extends AppAction {
  const ListingCacheCleared();
}

// ────────────────────────────── product details ──────────────────────────────

class ProductLoadRequested extends AppAction {
  const ProductLoadRequested(this.handle);
  final String handle;
}

class ProductLoadSucceeded extends AppAction {
  const ProductLoadSucceeded(this.handle, this.detail, {this.reviews = const []});
  final String handle;
  final ProductDetail detail;
  final List<ProductReview> reviews;
}

class ProductLoadFailed extends AppAction {
  const ProductLoadFailed(this.handle, this.message);
  final String handle;
  final String message;
}

class ProductReviewsLoaded extends AppAction {
  const ProductReviewsLoaded(this.handle, this.reviews);
  final String handle;
  final List<ProductReview> reviews;
}

// ──────────────────────────────────── search ─────────────────────────────────

class SearchQueryChanged extends AppAction {
  const SearchQueryChanged(this.query);
  final String query;
}

// ──────────────────────────────────── content ────────────────────────────────

class FaqsLoadSucceeded extends AppAction {
  const FaqsLoadSucceeded(this.groups);
  final List<FaqGroup> groups;
}

class FaqsLoadFailed extends AppAction {
  const FaqsLoadFailed(this.message);
  final String message;
}

class PageLoadSucceeded extends AppAction {
  const PageLoadSucceeded(this.page);
  final PageContent page;
}

class PageLoadFailed extends AppAction {
  const PageLoadFailed(this.handle, this.message);
  final String handle;
  final String message;
}

// ───────────────────────────────────── auth ──────────────────────────────────

class AuthRequestStarted extends AppAction {
  const AuthRequestStarted();
}

class AuthSucceeded extends AppAction {
  const AuthSucceeded(this.session);
  final AuthSession session;
}

class AuthFailed extends AppAction {
  const AuthFailed(this.message);
  final String message;
}

class AuthSignedOut extends AppAction {
  const AuthSignedOut();
}

class ProfileUpdated extends AppAction {
  const ProfileUpdated(this.user);
  final AuthUser user;
}

// ───────────────────────────────────── cart ──────────────────────────────────

class CartLoadSucceeded extends AppAction {
  const CartLoadSucceeded(this.cart);
  final Cart cart;
}

class CartLoadFailed extends AppAction {
  const CartLoadFailed(this.message);
  final String message;
}

class CartBusyChanged extends AppAction {
  const CartBusyChanged(this.busy);
  final bool busy;
}

/// Sets the active cart id (after create/merge) without touching the payload.
class CartIdAssigned extends AppAction {
  const CartIdAssigned(this.cartId);
  final String cartId;
}

// ──────────────────────────────────── orders ─────────────────────────────────

class OrdersLoadSucceeded extends AppAction {
  const OrdersLoadSucceeded(this.orders);
  final List<Order> orders;
}

class OrdersLoadFailed extends AppAction {
  const OrdersLoadFailed(this.message);
  final String message;
}

class OrderDetailSucceeded extends AppAction {
  const OrderDetailSucceeded(this.order);
  final Order order;
}

class OrderDetailFailed extends AppAction {
  const OrderDetailFailed(this.message);
  final String message;
}

class OrderTrackingSucceeded extends AppAction {
  const OrderTrackingSucceeded(this.order);
  final Order order;
}

class OrderTrackingFailed extends AppAction {
  const OrderTrackingFailed(this.message);
  final String message;
}

class OrderPlaced extends AppAction {
  const OrderPlaced(this.order);
  final Order order;
}

class AddressesLoadSucceeded extends AppAction {
  const AddressesLoadSucceeded(this.addresses);
  final List<Address> addresses;
}

class AddressesLoadFailed extends AppAction {
  const AddressesLoadFailed(this.message);
  final String message;
}

// ──────────────────────────────────── routing ─────────────────────────────────

class EtaLoadRequested extends AppAction {
  const EtaLoadRequested();
}

class EtaLoadSucceeded extends AppAction {
  const EtaLoadSucceeded(this.estimate);
  final EtaEstimate estimate;
}

class EtaLoadFailed extends AppAction {
  const EtaLoadFailed(this.message);
  final String message;
}

class RouteLoadRequested extends AppAction {
  const RouteLoadRequested();
}

class RouteLoadSucceeded extends AppAction {
  const RouteLoadSucceeded(this.result);
  final RouteResult result;
}

class RouteLoadFailed extends AppAction {
  const RouteLoadFailed(this.message);
  final String message;
}

class MatchSucceeded extends AppAction {
  const MatchSucceeded(this.result);
  final MatchResult result;
}

class MatchFailed extends AppAction {
  const MatchFailed(this.message);
  final String message;
}

/// One tick of the rider simulation along the loaded route.
class RiderAdvanced extends AppAction {
  const RiderAdvanced(this.at, this.progress);
  final LatLng at;
  final double progress;
}

/// Clears route/match/rider when the tracking screen goes away.
class TrackingReset extends AppAction {
  const TrackingReset();
}

// ───────────────────────────────────── UI ────────────────────────────────────

class ToastShown extends AppAction {
  const ToastShown(this.message, {this.error = false});
  final String message;
  final bool error;
}

class ToastCleared extends AppAction {
  const ToastCleared();
}

class BottomNavChanged extends AppAction {
  const BottomNavChanged(this.index);
  final int index;
}
