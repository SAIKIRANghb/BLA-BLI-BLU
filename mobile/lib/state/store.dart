/// The single store: owns [AppState], exposes `dispatch`, and hosts the async
/// *thunks* that talk to the API and dispatch the resulting actions.
///
///  dispatch(action)  -> reducer -> new AppState -> Riverpod notifies watchers
///  thunks            -> side effects (I/O) only; they never mutate state
///                       directly, they only dispatch.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/network/api_client.dart';
import 'actions.dart';
import 'app_state.dart';
import 'reducers.dart';

/// The one API instance the whole app uses (seed or live, per [kUseLocalSeed]).
final apiProvider = Provider<AppApi>((ref) => createApi());

/// Redux-style store. `Notifier` gives us a `state` setter that notifies.
class Store extends Notifier<AppState> {
  Store();

  /// Injected in tests / overrides; production builds use [apiProvider].
  AppApi get api => ref.read(apiProvider);

  @override
  AppState build() {
    // Fire and forget: restore the persisted session + cart, then hydrate.
    Future.microtask(bootstrap);
    return const AppState();
  }

  // ── dispatch ──────────────────────────────────────────────────────────────

  /// The only mutation entry point. Pure reducer runs synchronously.
  void dispatch(AppAction action) => state = rootReducer(state, action);

  // ── persistence ───────────────────────────────────────────────────────────

  static const _kToken = 'bbl.token';
  static const _kCartId = 'bbl.cartId';

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    dispatch(BootstrapCompleted(
      restoredToken: prefs.getString(_kToken),
      restoredCartId: prefs.getString(_kCartId),
    ));
    // Hydrate in parallel; every failure is already surfaced by the thunk.
    await Future.wait([loadHome(), loadCollections(), ensureCart()]);
  }

  Future<void> _persistSession(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  Future<void> _persistCartId(String? cartId) async {
    final prefs = await SharedPreferences.getInstance();
    if (cartId == null) {
      await prefs.remove(_kCartId);
    } else {
      await prefs.setString(_kCartId, cartId);
    }
  }

  // ── error helper ──────────────────────────────────────────────────────────

  String _message(Object error) =>
      error is ApiException ? error.message : 'Something went wrong. Please try again.';

  void _toast(String message, {bool error = false}) => dispatch(ToastShown(message, error: error));

  // ── content / catalogue ───────────────────────────────────────────────────

  Future<void> loadHome() async {
    dispatch(const HomeLoadRequested());
    try {
      dispatch(HomeLoadSucceeded(await api.getHome()));
    } catch (err) {
      dispatch(HomeLoadFailed(_message(err)));
    }
  }

  Future<void> loadCollections() async {
    try {
      dispatch(CollectionsLoadSucceeded(await api.getCollections()));
    } catch (err) {
      dispatch(CollectionsLoadFailed(_message(err)));
    }
  }

  /// Fetch (or serve from cache) one listing query.
  Future<void> loadListing({
    String? collection,
    String? query,
    String sort = 'featured',
    int page = 1,
    int limit = 24,
    bool refresh = false,
    bool append = false,
  }) async {
    final key = listingKey(collection: collection, query: query, sort: sort);
    final cached = state.catalog.listings[key];
    // Cached page 1 is enough unless this call is a refresh *or* an explicit
    // request for the next page - an append must always reach the API even
    // though the slot already holds a successful result.
    if (!refresh && !append && cached?.isSuccess == true) return;

    dispatch(ListingLoadRequested(key, refresh: refresh));
    try {
      final result = await api.getProducts(collection: collection, q: query, sort: sort, page: page, limit: limit);
      dispatch(ListingLoadSucceeded(key, result, append: append));
    } catch (err) {
      dispatch(ListingLoadFailed(key, _message(err)));
    }
  }

  Future<void> loadProduct(String handle) async {
    final cached = state.catalog.details[handle];
    if (cached?.isLoading == true) return;

    dispatch(ProductLoadRequested(handle));
    try {
      final detail = await api.getProduct(handle);
      var reviews = state.catalog.reviews[handle] ?? const <ProductReview>[];
      if (reviews.isEmpty) {
        reviews = await _safeReviews(handle);
      }
      dispatch(ProductLoadSucceeded(handle, detail, reviews: reviews));
    } catch (err) {
      dispatch(ProductLoadFailed(handle, _message(err)));
    }
  }

  Future<List<ProductReview>> _safeReviews(String handle) async {
    try {
      return await api.getReviews(handle);
    } catch (_) {
      return const [];
    }
  }

  Future<void> search(String query) async {
    dispatch(SearchQueryChanged(query));
    await loadListing(query: query, refresh: true);
  }

  Future<void> loadFaqs() async {
    if (state.content.faqs.hasValue) return;
    try {
      dispatch(FaqsLoadSucceeded(await api.getFaqs()));
    } catch (err) {
      dispatch(FaqsLoadFailed(_message(err)));
    }
  }

  Future<void> loadPage(String handle) async {
    if (state.content.pages[handle]?.hasValue == true) return;
    try {
      dispatch(PageLoadSucceeded(await api.getPage(handle)));
    } catch (err) {
      dispatch(PageLoadFailed(handle, _message(err)));
    }
  }

  // ── auth ──────────────────────────────────────────────────────────────────

  Future<bool> register({required String name, required String email, required String password, String? phone}) =>
      _authenticate(() => api.register(name: name, email: email, password: password, phone: phone));

  Future<bool> login({required String email, required String password}) =>
      _authenticate(() => api.login(email: email, password: password));

  Future<bool> _authenticate(Future<AuthSession> Function() run) async {
    dispatch(const AuthRequestStarted());
    try {
      final session = await run();
      dispatch(AuthSucceeded(session));
      await _persistSession(session.accessToken);
      // A signed-in device gets its server-side cart merged into the local one.
      final guestId = state.cart.cartId;
      if (guestId != null) {
        try {
          final merged = await api.mergeCart(cartId: guestId, token: session.accessToken);
          await _adoptCart(merged);
        } catch (_) {
          /* merge is best-effort */
        }
      }
      await refreshCart();
      return true;
    } catch (err) {
      dispatch(AuthFailed(_message(err)));
      return false;
    }
  }

  Future<void> signOut() async {
    dispatch(const AuthSignedOut());
    await _persistSession(null);
    await createFreshCart();
  }

  Future<bool> updateProfile({String? name, String? phone}) async {
    final token = state.auth.token;
    if (token == null) return false;
    try {
      final user = await api.updateProfile(token: token, name: name, phone: phone);
      dispatch(ProfileUpdated(user));
      _toast('Profile updated');
      return true;
    } catch (err) {
      _toast(_message(err), error: true);
      return false;
    }
  }

  // ── cart ──────────────────────────────────────────────────────────────────

  String? get _token => state.auth.token;

  /// Makes sure a cart id exists (guest or signed in) before the first add.
  Future<void> ensureCart() async {
    if (state.cart.cartId != null) {
      await refreshCart();
      return;
    }
    await createFreshCart();
  }

  Future<void> createFreshCart() async {
    try {
      await _adoptCart(await api.createCart(token: _token));
    } catch (err) {
      dispatch(CartLoadFailed(_message(err)));
    }
  }

  Future<void> _adoptCart(Cart cart) async {
    dispatch(CartLoadSucceeded(cart));
    if (state.cart.cartId != cart.id) {
      dispatch(CartIdAssigned(cart.id));
      await _persistCartId(cart.id);
    }
  }

  Future<void> refreshCart() async {
    final id = state.cart.cartId;
    if (id == null) return;
    try {
      dispatch(CartLoadSucceeded(await api.getCart(id, token: _token)));
    } catch (err) {
      dispatch(CartLoadFailed(_message(err)));
    }
  }

  Future<void> addToCart(ProductDetail product, {ProductVariant? variant, int qty = 1}) async {
    dispatch(const CartBusyChanged(true));
    try {
      var id = state.cart.cartId;
      if (id == null) {
        final created = await api.createCart(token: _token);
        id = created.id;
        dispatch(CartIdAssigned(id));
        await _persistCartId(id);
      }
      final updated = await api.addToCart(
        cartId: id,
        productId: product.id,
        variantId: variant?.id ?? (product.variants.isNotEmpty ? product.variants.first.id : null),
        qty: qty,
        token: _token,
      );
      dispatch(CartLoadSucceeded(updated));
      _toast('${product.title} added to bag');
    } catch (err) {
      dispatch(CartLoadFailed(_message(err)));
      _toast(_message(err), error: true);
    } finally {
      dispatch(const CartBusyChanged(false));
    }
  }

  Future<void> setLineQuantity(String lineId, int qty) async {
    final id = state.cart.cartId;
    if (id == null) return;
    dispatch(const CartBusyChanged(true));
    try {
      if (qty <= 0) {
        dispatch(CartLoadSucceeded(await api.removeFromCart(cartId: id, lineId: lineId, token: _token)));
      } else {
        dispatch(CartLoadSucceeded(await api.updateCartLine(cartId: id, lineId: lineId, qty: qty, token: _token)));
      }
    } catch (err) {
      _toast(_message(err), error: true);
      await refreshCart();
    } finally {
      dispatch(const CartBusyChanged(false));
    }
  }

  Future<bool> applyCoupon(String code) async {
    final id = state.cart.cartId;
    if (id == null) return false;
    try {
      dispatch(CartLoadSucceeded(await api.applyCoupon(cartId: id, code: code, token: _token)));
      _toast('Coupon $code applied');
      return true;
    } catch (err) {
      _toast(_message(err), error: true);
      return false;
    }
  }

  Future<void> removeCoupon() async {
    final id = state.cart.cartId;
    if (id == null) return;
    try {
      dispatch(CartLoadSucceeded(await api.applyCoupon(cartId: id, code: null, token: _token)));
    } catch (_) {
      /* nothing to clear */
    }
  }

  // ── checkout / orders ─────────────────────────────────────────────────────

  Future<Order?> placeOrder({
    required ShippingAddress address,
    String? email,
    String? name,
    String paymentMethod = 'cod',
  }) async {
    final id = state.cart.cartId;
    if (id == null || state.cart.cart.value?.items.isEmpty != false) {
      _toast('Your bag is empty', error: true);
      return null;
    }
    dispatch(const CartBusyChanged(true));
    try {
      final order = await api.placeOrder(
        cartId: id,
        address: address,
        email: email,
        name: name,
        paymentMethod: paymentMethod,
        token: _token,
      );
      dispatch(OrderPlaced(order));
      // Start a fresh bag for the next purchase.
      await createFreshCart();
      return order;
    } catch (err) {
      dispatch(CartLoadFailed(_message(err)));
      _toast(_message(err), error: true);
      return null;
    } finally {
      dispatch(const CartBusyChanged(false));
    }
  }

  Future<void> loadOrders() async {
    try {
      dispatch(OrdersLoadSucceeded(await api.getOrders(token: _token)));
    } catch (err) {
      dispatch(OrdersLoadFailed(_message(err)));
    }
  }

  Future<void> loadOrder(String id) async {
    try {
      dispatch(OrderDetailSucceeded(await api.getOrder(id, token: _token)));
    } catch (err) {
      dispatch(OrderDetailFailed(_message(err)));
    }
  }

  Future<bool> trackOrder({required String orderNumber, String? email, String? phone}) async {
    try {
      dispatch(OrderTrackingSucceeded(await api.trackOrder(orderNumber: orderNumber, email: email, phone: phone)));
      return true;
    } catch (err) {
      dispatch(OrderTrackingFailed(_message(err)));
      return false;
    }
  }

  // ── addresses ─────────────────────────────────────────────────────────────

  Future<void> loadAddresses() async {
    final token = _token;
    if (token == null) return;
    try {
      dispatch(AddressesLoadSucceeded(await api.getAddresses(token: token)));
    } catch (err) {
      dispatch(AddressesLoadFailed(_message(err)));
    }
  }

  Future<Address?> saveAddress({Address? existing, required Map<String, dynamic> fields}) async {
    final token = _token;
    if (token == null) {
      _toast('Sign in to save an address', error: true);
      return null;
    }
    try {
      final saved = await api.saveAddress(token: token, id: existing, fields: fields);
      final current = state.orders.addresses.value ?? const <Address>[];
      final next = [saved, ...current.where((a) => a.id != saved.id)];
      dispatch(AddressesLoadSucceeded(next));
      _toast('Address saved');
      return saved;
    } catch (err) {
      _toast(_message(err), error: true);
      return null;
    }
  }

  Future<void> deleteAddress(String id) async {
    final token = _token;
    if (token == null) return;
    try {
      await api.deleteAddress(token: token, id: id);
      final current = state.orders.addresses.value ?? const <Address>[];
      dispatch(AddressesLoadSucceeded(current.where((a) => a.id != id).toList()));
    } catch (err) {
      _toast(_message(err), error: true);
    }
  }

  // ── routing (OSM / OSRM) ───────────────────────────────────────────────────

  /// Road-snaps a dropped pin (Nearest). Return-only thunk: the picker screen
  /// owns the transient result, and a failed snap silently falls back to the
  /// raw coordinate - panning must never spam toasts.
  Future<NearestResult?> snapToRoad(LatLng point) async {
    try {
      return await api.nearest(lat: point.latitude, lng: point.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Serving hub for [destination]: one OSRM Table over every warehouse,
  /// shortest road time wins. Shared by the checkout ETA and the tracking
  /// route so both screens always agree on the origin. `null` = unreachable.
  Future<({int index, double duration, double distance})?> _bestWarehouse(LatLng destination) async {
    final points = <LatLng>[
      for (final w in kWarehouses) LatLng(w.lat, w.lng),
      destination,
    ];
    final last = kWarehouses.length;
    final table = await api.table(
      points,
      sources: [for (var i = 0; i < last; i++) i],
      destinations: [last],
    );
    var best = -1;
    double? bestSeconds;
    for (var i = 0; i < last && i < table.durations.length; i++) {
      final row = table.durations[i];
      final seconds = row.isEmpty ? null : row.first;
      if (seconds != null && (bestSeconds == null || seconds < bestSeconds)) {
        bestSeconds = seconds;
        best = i;
      }
    }
    if (best < 0 || bestSeconds == null) return null;
    final row = best < table.distances.length ? table.distances[best] : const <double?>[];
    return (index: best, duration: bestSeconds, distance: row.isEmpty ? 0.0 : (row.first ?? 0.0));
  }

  /// Checkout ETA: best warehouse -> address pin, as an [EtaEstimate] (Table).
  Future<void> loadEta(LatLng destination) async {
    dispatch(const EtaLoadRequested());
    try {
      final best = await _bestWarehouse(destination);
      if (best == null) {
        dispatch(const EtaLoadFailed('No warehouse can reach that address'));
        return;
      }
      dispatch(EtaLoadSucceeded(EtaEstimate(
        warehouse: kWarehouses[best.index].name,
        distance: best.distance,
        duration: best.duration,
      )));
    } catch (err) {
      dispatch(EtaLoadFailed(_message(err)));
    }
  }

  /// Tracking: serving hub -> address pin road route (Route). Returns the hub
  /// so the map can label its origin marker; the polyline itself lives in
  /// `routing.route`.
  Future<({String name, double lat, double lng})?> loadDeliveryRoute(LatLng destination) async {
    dispatch(const RouteLoadRequested());
    try {
      final best = await _bestWarehouse(destination);
      if (best == null) {
        dispatch(const RouteLoadFailed('No warehouse can reach that address'));
        return null;
      }
      final hub = kWarehouses[best.index];
      dispatch(RouteLoadSucceeded(
        await api.route([LatLng(hub.lat, hub.lng), destination]),
      ));
      return (name: hub.name, lat: hub.lat, lng: hub.lng);
    } catch (err) {
      dispatch(RouteLoadFailed(_message(err)));
      return null;
    }
  }

  /// Tracking: re-snap the rider's GPS trace onto roads (Match). Runs every few
  /// ticks, so failures only update `routing.match` - never a toast.
  Future<void> matchRiderTrace(List<TracePoint> trace) async {
    if (trace.length < 2) return;
    try {
      dispatch(MatchSucceeded(await api.matchTrace(trace)));
    } catch (err) {
      dispatch(MatchFailed(_message(err)));
    }
  }

  /// One tick of the rider simulation along the loaded route.
  void moveRider(LatLng at, double progress) => dispatch(RiderAdvanced(at, progress));

  /// Leaves a clean tracking slice behind when the map screen closes.
  void resetTracking() => dispatch(const TrackingReset());

  // ── tracking (rider GPS + customer trail) ─────────────────────────────────

  /// Customer poll: newest slice of the rider's trail. Return-only - the
  /// screen owns staleness/miss handling, so a failed poll never toasts.
  Future<TrackResult?> loadRiderTrack(String orderId, {int limit = 120}) async {
    try {
      return await api.getOrderTrack(orderId, token: _token, limit: limit);
    } catch (_) {
      return null;
    }
  }

  /// Rider queue: active deliveries with map pins (rider key, no session).
  /// `null` = the read failed (the screen decides how to say so).
  Future<List<DeliveryJob>?> activeDeliveries({int limit = 20}) async {
    try {
      return await api.getActiveDeliveries(limit: limit);
    } catch (_) {
      return null;
    }
  }

  /// One GPS fix from the rider device. Returns an error message, or null on
  /// success - the rider screen surfaces it inline (no toast spam per fix).
  Future<String?> reportRiderFix({
    required String orderId,
    required double lat,
    required double lng,
    double? accuracyM,
    double? speedMps,
    double? headingDeg,
    DateTime? recordedAt,
  }) async {
    try {
      await api.reportRiderPosition(
        orderId: orderId,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        speedMps: speedMps,
        headingDeg: headingDeg,
        recordedAt: recordedAt,
      );
      return null;
    } catch (err) {
      return _message(err);
    }
  }

  /// Periodic ETA + reroute check: one OSRM **Route** call from [from] to
  /// [to] answers both questions at once - remaining travel time (the ETA)
  /// and the road geometry the rider should actually follow now. `null` when
  /// the engine can't reach the pair; callers fall back to the proportional
  /// estimate off the last known route.
  Future<({double duration, double distance, List<LatLng> geometry})?> rerouteFrom(LatLng from, LatLng to) async {
    try {
      final route = await api.route([from, to]);
      if (route.geometry.length < 2) return null;
      return (duration: route.duration, distance: route.distance, geometry: route.geometry);
    } catch (_) {
      return null;
    }
  }

  // ── misc ui ───────────────────────────────────────────────────────────────

  void clearToast() => dispatch(const ToastCleared());

  void selectTab(int index) => dispatch(BottomNavChanged(index));
}

/// Redux store, exposed to the widget tree.
final storeProvider = NotifierProvider<Store, AppState>(Store.new);
