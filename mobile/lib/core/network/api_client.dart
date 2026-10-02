/// The application's ONLY API file.
///
/// Structure requested by the client:
///  * private, reusable HTTP verbs  -> [_get], [_post], [_put], [_patch], [_delete]
///  * public API methods            -> one per endpoint, built on those verbs
///
/// Two implementations of [AppApi]:
///  * [LiveApi] - real HTTP against the Node.js/PostgreSQL backend
///  * [SeedApi] - serves `assets/seed/seed.json` (and an in-memory store for
///                mutations) when [kUseLocalSeed] is `true`
///
/// The rest of the app only ever sees [AppApi], so the flag in
/// `app_config.dart` is the single switch between test mode and live mode.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/models.dart';

// ────────────────────────────────── Contract ─────────────────────────────────

abstract class AppApi {
  // content / catalog
  Future<HomeData> getHome();
  Future<List<CollectionTile>> getCollections();
  Future<ProductPage> getProducts({String? collection, String? q, String sort, int page, int limit});
  Future<ProductDetail> getProduct(String handle);
  Future<List<ProductReview>> getReviews(String handle, {int page, int limit});
  Future<List<FaqGroup>> getFaqs();
  Future<PageContent> getPage(String handle);

  // auth
  Future<AuthSession> register({required String name, required String email, required String password, String? phone});
  Future<AuthSession> login({required String email, required String password});
  Future<AuthUser> me(String token);
  Future<AuthUser> updateProfile({required String token, String? name, String? phone});

  // cart
  Future<Cart> createCart({String? token});
  Future<Cart> getCart(String cartId, {String? token});
  Future<Cart> addToCart({required String cartId, required String productId, String? variantId, int qty = 1, String? token});
  Future<Cart> updateCartLine({required String cartId, required String lineId, required int qty, String? token});
  Future<Cart> removeFromCart({required String cartId, required String lineId, String? token});
  Future<Cart> applyCoupon({required String cartId, String? code, String? token});
  Future<Cart> mergeCart({required String cartId, required String token});

  // orders
  Future<Order> placeOrder({
    required String cartId,
    required ShippingAddress address,
    String? email,
    String? name,
    String paymentMethod = 'cod',
    String? token,
  });
  Future<List<Order>> getOrders({String? token, int page = 1, int limit = 20});
  Future<Order> getOrder(String id, {String? token});
  Future<Order> trackOrder({required String orderNumber, String? email, String? phone});

  // addresses
  Future<List<Address>> getAddresses({required String token});
  Future<Address> saveAddress({required String token, Address? id, Map<String, dynamic>? fields});
  Future<void> deleteAddress({required String token, required String id});

  // routing (OSRM: nearest, route, table, match, trip, tile)
  Future<NearestResult> nearest({required double lat, required double lng, int number = 1});
  Future<RouteResult> route(List<LatLng> points, {String overview = 'full', bool geometriesGeojson = true});
  Future<TableResult> table(List<LatLng> points, {List<int>? sources, List<int>? destinations});
  Future<MatchResult> matchTrace(List<TracePoint> points);
  Future<TripResult> trip(List<LatLng> points, {bool roundtrip = true, String source = 'any', String destination = 'any'});
  Future<Uint8List> vectorTile(int z, int x, int y);
}

/// Raised for any transport / protocol failure. [statusCode] is 0 for offline.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode = 0, this.code});

  final String message;
  final int statusCode;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

// ─────────────────────────────── Shared helpers ──────────────────────────────

class _Envelope {
  const _Envelope(this.data, this.meta);
  final dynamic data;
  final Map<String, dynamic> meta;
}

List<Map<String, dynamic>> _asJsonList(dynamic value) =>
    ((value as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

// ───────────────────────────────── Live API ──────────────────────────────────

class LiveApi implements AppApi {
  LiveApi({http.Client? client, String baseUrl = kApiBaseUrl}) : _client = client ?? http.Client(), _baseUrl = baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  // ── private reusable verbs ────────────────────────────────────────────────

  Future<_Envelope> _get(String path, {Map<String, String>? query, String? token}) =>
      _send('GET', path, query: query, token: token);

  Future<_Envelope> _post(String path, {Object? body, String? token}) =>
      _send('POST', path, body: body, token: token);

  Future<_Envelope> _put(String path, {Object? body, String? token}) =>
      _send('PUT', path, body: body, token: token);

  Future<_Envelope> _patch(String path, {Object? body, String? token}) =>
      _send('PATCH', path, body: body, token: token);

  Future<_Envelope> _delete(String path, {String? token}) => _send('DELETE', path, token: token);

  /// Binary variant of [_get] - vector tiles are MVT bytes, not JSON.
  Future<Uint8List> _getBytes(String path) async {
    final request = http.Request('GET', Uri.parse('$_baseUrl$path'));
    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('Request timed out. Check your connection.', statusCode: 0);
    } catch (err) {
      throw ApiException('Could not reach the server', statusCode: 0, code: err.toString());
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException('Tile request failed', statusCode: streamed.statusCode, code: 'ROUTING_ERROR');
    }
    final bytes = <int>[];
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  Future<_Envelope> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? token,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query == null ? null : _clean(query));
    final headers = <String, String>{
      'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };

    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..body = body == null ? '' : jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('Request timed out. Check your connection.', statusCode: 0);
    } on SocketExceptionLike {
      rethrow;
    } catch (err) {
      throw ApiException('Could not reach the server', statusCode: 0, code: err.toString());
    }
    return _decode(response);
  }

  Map<String, String> _clean(Map<String, String> query) =>
      Map<String, String>.fromEntries(query.entries.where((e) => e.value.isNotEmpty));

  _Envelope _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    final map = body is Map<String, dynamic> ? body : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _Envelope(map['data'], ((map['meta'] as Map?) ?? const {}).cast<String, dynamic>());
    }
    final error = (map['error'] as Map?) ?? const {};
    throw ApiException(
      error['message'] as String? ?? 'Something went wrong',
      statusCode: response.statusCode,
      code: error['code'] as String?,
    );
  }

  // ── public API surface ────────────────────────────────────────────────────

  @override
  Future<HomeData> getHome() async => HomeData.fromJson((await _get('/home')).data as Map<String, dynamic>);

  @override
  Future<List<CollectionTile>> getCollections() async =>
      _asJsonList((await _get('/collections')).data).map(CollectionTile.fromJson).toList();

  @override
  Future<ProductPage> getProducts({String? collection, String? q, String sort = 'featured', int page = 1, int limit = 24}) async {
    final envelope = await _get('/products', query: {
      if (collection != null && collection.isNotEmpty) 'collection': collection,
      if (q != null && q.isNotEmpty) 'q': q,
      'sort': sort,
      'page': '$page',
      'limit': '$limit',
    });
    final items = _asJsonList(envelope.data).map(ProductCard.fromJson).toList();
    return ProductPage.fromJson(envelope.meta, items: items);
  }

  @override
  Future<ProductDetail> getProduct(String handle) async =>
      ProductDetail.fromJson(((await _get('/products/$handle')).data as Map)['product'] as Map<String, dynamic>);

  @override
  Future<List<ProductReview>> getReviews(String handle, {int page = 1, int limit = 10}) async =>
      _asJsonList((await _get('/products/$handle/reviews', query: {'page': '$page', 'limit': '$limit'})).data)
          .map(ProductReview.fromJson)
          .toList();

  @override
  Future<List<FaqGroup>> getFaqs() async =>
      _asJsonList((await _get('/faqs')).data).map(FaqGroup.fromJson).toList();

  @override
  Future<PageContent> getPage(String handle) async =>
      PageContent.fromJson((await _get('/pages/$handle')).data as Map<String, dynamic>);

  @override
  Future<AuthSession> register({required String name, required String email, required String password, String? phone}) async =>
      AuthSession.fromJson((await _post('/auth/register', body: {'name': name, 'email': email, 'password': password, if (phone != null) 'phone': phone})).data as Map<String, dynamic>);

  @override
  Future<AuthSession> login({required String email, required String password}) async =>
      AuthSession.fromJson((await _post('/auth/login', body: {'email': email, 'password': password})).data as Map<String, dynamic>);

  @override
  Future<AuthUser> me(String token) async =>
      AuthUser.fromJson((await _get('/auth/me', token: token)).data as Map<String, dynamic>);

  @override
  Future<AuthUser> updateProfile({required String token, String? name, String? phone}) async =>
      AuthUser.fromJson((await _put('/auth/me', token: token, body: {if (name != null) 'name': name, if (phone != null) 'phone': phone})).data as Map<String, dynamic>);

  @override
  Future<Cart> createCart({String? token}) async =>
      Cart.fromJson((await _post('/carts', token: token)).data as Map<String, dynamic>);

  @override
  Future<Cart> getCart(String cartId, {String? token}) async =>
      Cart.fromJson((await _get('/carts/$cartId', token: token)).data as Map<String, dynamic>);

  @override
  Future<Cart> addToCart({required String cartId, required String productId, String? variantId, int qty = 1, String? token}) async =>
      Cart.fromJson((await _post('/carts/$cartId/items', token: token, body: {'productId': productId, if (variantId != null) 'variantId': variantId, 'qty': qty})).data as Map<String, dynamic>);

  @override
  Future<Cart> updateCartLine({required String cartId, required String lineId, required int qty, String? token}) async =>
      Cart.fromJson((await _patch('/carts/$cartId/items/$lineId', token: token, body: {'qty': qty})).data as Map<String, dynamic>);

  @override
  Future<Cart> removeFromCart({required String cartId, required String lineId, String? token}) async =>
      Cart.fromJson((await _delete('/carts/$cartId/items/$lineId', token: token)).data as Map<String, dynamic>);

  @override
  Future<Cart> applyCoupon({required String cartId, String? code, String? token}) async =>
      Cart.fromJson((await _post('/carts/$cartId/coupon', token: token, body: {'code': code})).data as Map<String, dynamic>);

  @override
  Future<Cart> mergeCart({required String cartId, required String token}) async =>
      Cart.fromJson((await _post('/carts/merge', token: token, body: {'cartId': cartId})).data as Map<String, dynamic>);

  @override
  Future<Order> placeOrder({
    required String cartId,
    required ShippingAddress address,
    String? email,
    String? name,
    String paymentMethod = 'cod',
    String? token,
  }) async {
    final data = await _post('/orders', token: token, body: {
      'cartId': cartId,
      'paymentMethod': paymentMethod,
      if (email != null) 'email': email,
      if (name != null) 'name': name,
      'address': address.toJson(),
    });
    return Order.fromJson(data.data as Map<String, dynamic>);
  }

  @override
  Future<List<Order>> getOrders({String? token, int page = 1, int limit = 20}) async =>
      _asJsonList((await _get('/orders', token: token, query: {'page': '$page', 'limit': '$limit'})).data)
          .map(Order.fromJson)
          .toList();

  @override
  Future<Order> getOrder(String id, {String? token}) async =>
      Order.fromJson((await _get('/orders/$id', token: token)).data as Map<String, dynamic>);

  @override
  Future<Order> trackOrder({required String orderNumber, String? email, String? phone}) async =>
      Order.fromJson((await _get('/orders/track', query: {
        'orderNumber': orderNumber,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }))
          .data as Map<String, dynamic>);

  @override
  Future<List<Address>> getAddresses({required String token}) async =>
      _asJsonList((await _get('/addresses', token: token)).data).map(Address.fromJson).toList();

  @override
  Future<Address> saveAddress({required String token, Address? id, Map<String, dynamic>? fields}) async {
    final payload = <String, dynamic>{};
    if (fields != null) payload.addAll(fields);
    if (id != null) payload['id'] = id.id;
    return Address.fromJson((await _post('/addresses', token: token, body: payload)).data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteAddress({required String token, required String id}) => _delete('/addresses/$id', token: token);

  // ── routing (six OSRM services behind /api/routing) ─────────────────────

  /// `lat,lng;lat,lng;...` - the app's convention, semicolon-separated.
  static String _points(List<LatLng> points) => points.map((p) => '${p.latitude},${p.longitude}').join(';');

  @override
  Future<NearestResult> nearest({required double lat, required double lng, int number = 1}) async => NearestResult.fromJson(
        ((await _get('/routing/nearest', query: {'point': '$lat,$lng', 'number': '$number'})).data as Map).cast<String, dynamic>(),
      );

  @override
  Future<RouteResult> route(List<LatLng> points, {String overview = 'full', bool geometriesGeojson = true}) async =>
      RouteResult.fromJson(
        ((await _get('/routing/route', query: {
          'points': _points(points),
          'overview': overview,
          'geometries': geometriesGeojson ? 'geojson' : 'polyline',
        }))
            .data as Map)
            .cast<String, dynamic>(),
      );

  @override
  Future<TableResult> table(List<LatLng> points, {List<int>? sources, List<int>? destinations}) async => TableResult.fromJson(
        ((await _get('/routing/table', query: {
          'points': _points(points),
          if (sources != null) 'sources': sources.join(','),
          if (destinations != null) 'destinations': destinations.join(','),
          'annotations': 'duration,distance',
        }))
            .data as Map)
            .cast<String, dynamic>(),
      );

  @override
  Future<MatchResult> matchTrace(List<TracePoint> points) async => MatchResult.fromJson(
        ((await _get('/routing/match', query: {
          'points': _points([for (final p in points) p.location]),
          'timestamps': points.map((p) => '${p.timestamp}').join(','),
          if (points.every((p) => p.accuracy != null)) 'radiuses': points.map((p) => '${p.accuracy!.round()}').join(','),
          'overview': 'full',
        }))
            .data as Map)
            .cast<String, dynamic>(),
      );

  @override
  Future<TripResult> trip(
    List<LatLng> points, {
    bool roundtrip = true,
    String source = 'any',
    String destination = 'any',
  }) async =>
      TripResult.fromJson(
        ((await _get('/routing/trip', query: {
          'points': _points(points),
          'roundtrip': '$roundtrip',
          'source': source,
          'destination': destination,
          'overview': 'full',
        }))
            .data as Map)
            .cast<String, dynamic>(),
      );

  @override
  Future<Uint8List> vectorTile(int z, int x, int y) => _getBytes('/routing/tile/$z/$x/$y');

  void dispose() => _client.close();
}

/// Local alias so the offline path can reuse the same error vocabulary.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
}

// ───────────────────────────────── Seed API ──────────────────────────────────

/// Serves the bundled seed asset - no network, no backend.
///
/// Reads are served from `assets/seed/seed.json`; cart/auth/order mutations are
/// kept in memory so UI flows (add to cart -> checkout -> tracking) work end to
/// end while testing without a server.
class SeedApi implements AppApi {
  Map<String, dynamic>? _seed;
  final Map<String, Cart> _carts = {};
  final Map<String, Order> _orders = {};
  final Map<String, List<Address>> _addresses = {};
  final Map<String, AuthUser> _users = {};
  int _orderCounter = 1001;
  int _seq = 0;

  Future<Map<String, dynamic>> _load() async {
    if (_seed != null) return _seed!;
    final raw = await rootBundle.loadString(kSeedAsset);
    _seed = jsonDecode(raw) as Map<String, dynamic>;
    return _seed!;
  }

  String _uuid() {
    _seq += 1;
    return 'seed-${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }

  Future<Map<String, dynamic>> _ensureLoaded() => _load();

  // ── private reusable "verbs" for the seed source ──────────────────────────

  Future<T> _read<T>(T Function(Map<String, dynamic> seed) builder) async {
    final seed = await _ensureLoaded();
    return builder(seed);
  }

  Future<T> _write<T>(T Function() mutation) async {
    await _ensureLoaded();
    return mutation();
  }

  // ── reads ─────────────────────────────────────────────────────────────────

  @override
  Future<HomeData> getHome() => _read((seed) {
        final home = Map<String, dynamic>.from(seed['home'] as Map);
        return HomeData.fromJson(home);
      });

  @override
  Future<List<CollectionTile>> getCollections() =>
      _read((seed) => _asJsonList(seed['collections']).map(CollectionTile.fromJson).toList());

  @override
  Future<ProductPage> getProducts({String? collection, String? q, String sort = 'featured', int page = 1, int limit = 24}) =>
      _read((seed) {
        var items = _asJsonList(seed['products']).map(ProductCard.fromJson).toList();
        if (collection != null && collection.isNotEmpty) {
          final handles = ((seed['collectionProducts'] as Map?) ?? const {})[collection];
          final allowed = ((handles as List?) ?? const []).cast<String>().toSet();
          items = items.where((p) => allowed.contains(p.handle)).toList();
        }
        if (q != null && q.trim().isNotEmpty) {
          final needle = q.trim().toLowerCase();
          items = items
              .where((p) =>
                  p.title.toLowerCase().contains(needle) ||
                  p.notesSummary.toLowerCase().contains(needle) ||
                  p.audience.toLowerCase().contains(needle))
              .toList();
        }
        items = _sort(items, sort);
        final start = (page - 1) * limit;
        final slice = start >= items.length ? <ProductCard>[] : items.sublist(start, (start + limit).clamp(0, items.length));
        return ProductPage(
          items: slice,
          total: items.length,
          page: page,
          totalPages: (items.length / limit).ceil().clamp(1, 999),
        );
      });

  List<ProductCard> _sort(List<ProductCard> items, String sort) {
    final copy = [...items];
    switch (sort) {
      case 'price_asc':
        copy.sort((a, b) => a.price.compareTo(b.price));
      case 'price_desc':
        copy.sort((a, b) => b.price.compareTo(a.price));
      case 'rating':
        copy.sort((a, b) => b.rating.compareTo(a.rating));
      case 'newest':
        return copy.reversed.toList();
      case 'title_asc':
        copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'title_desc':
        copy.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case 'best_selling':
        copy.sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
      default:
        break;
    }
    return copy;
  }

  @override
  Future<ProductDetail> getProduct(String handle) => _read((seed) {
        final detail = (seed['details'] as Map? ?? const {})[handle];
        if (detail == null) throw ApiException('Product not found', statusCode: 404, code: 'NOT_FOUND');
        return ProductDetail.fromJson(detail as Map<String, dynamic>);
      });

  @override
  Future<List<ProductReview>> getReviews(String handle, {int page = 1, int limit = 10}) => _read((seed) {
        final list = _asJsonList((seed['reviews'] as Map? ?? const {})[handle]);
        final start = (page - 1) * limit;
        final slice = start >= list.length ? <Map<String, dynamic>>[] : list.sublist(start, (start + limit).clamp(0, list.length));
        return slice.map(ProductReview.fromJson).toList();
      });

  @override
  Future<List<FaqGroup>> getFaqs() => _read((seed) => _asJsonList(seed['faqs']).map(FaqGroup.fromJson).toList());

  @override
  Future<PageContent> getPage(String handle) => _read((seed) {
        var page = (seed['pages'] as Map? ?? const {})[handle];
        // Tolerate a seed that stored the raw API envelope instead of `.data`.
        if (page is Map && page['data'] is Map) page = page['data'];
        if (page == null) throw ApiException('Page not found', statusCode: 404, code: 'NOT_FOUND');
        final json = Map<String, dynamic>.from(page as Map);
        json['handle'] ??= handle;
        return PageContent.fromJson(json);
      });

  // ── auth ──────────────────────────────────────────────────────────────────

  @override
  Future<AuthSession> register({required String name, required String email, required String password, String? phone}) =>
      _write(() {
        if (password.length < 8) throw ApiException('Password must be at least 8 characters', statusCode: 422);
        final user = AuthUser(id: _uuid(), name: name, email: email, phone: phone);
        _users[user.id] = user;
        return AuthSession(user: user, accessToken: 'seed-token-${user.id}');
      });

  @override
  Future<AuthSession> login({required String email, required String password}) => _write(() {
        final existing = _users.values.where((u) => u.email.toLowerCase() == email.toLowerCase()).toList();
        if (existing.isNotEmpty) {
          return AuthSession(user: existing.first, accessToken: 'seed-token-${existing.first.id}');
        }
        final user = AuthUser(id: _uuid(), name: email.split('@').first, email: email);
        _users[user.id] = user;
        return AuthSession(user: user, accessToken: 'seed-token-${user.id}');
      });

  @override
  Future<AuthUser> me(String token) async {
    final id = token.replaceFirst('seed-token-', '');
    final user = _users[id];
    if (user == null) throw ApiException('Unauthorized', statusCode: 401, code: 'UNAUTHORIZED');
    return user;
  }

  @override
  Future<AuthUser> updateProfile({required String token, String? name, String? phone}) => _write(() {
        final id = token.replaceFirst('seed-token-', '');
        final user = _users[id];
        if (user == null) throw ApiException('Unauthorized', statusCode: 401);
        final updated = AuthUser(id: user.id, name: name ?? user.name, email: user.email, phone: phone ?? user.phone);
        _users[id] = updated;
        return updated;
      });

  // ── cart ──────────────────────────────────────────────────────────────────

  @override
  Future<Cart> createCart({String? token}) => _write(() {
        final cart = Cart(id: _uuid(), items: const [], totals: const CartTotals());
        _carts[cart.id] = _withTotals(cart);
        return _carts[cart.id]!;
      });

  @override
  Future<Cart> getCart(String cartId, {String? token}) => _write(() {
        final cart = _carts[cartId];
        if (cart == null) return Cart(id: cartId, items: const []);
        return _withTotals(cart);
      });

  @override
  Future<Cart> addToCart({required String cartId, required String productId, String? variantId, int qty = 1, String? token}) =>
      _write(() {
        final cart = _carts[cartId] ?? Cart(id: cartId, items: const []);
        final detail = _productById(productId);
        final existing = [...cart.items];
        final index = existing.indexWhere((l) => l.productId == productId);
        if (index >= 0) {
          final line = existing[index];
          final merged = (line.quantity + qty).clamp(1, 10);
          existing[index] = CartLine(
            id: line.id,
            productId: line.productId,
            handle: line.handle,
            title: line.title,
            imageUrl: line.imageUrl,
            variantId: line.variantId,
            variantTitle: line.variantTitle,
            unitPrice: line.unitPrice,
            quantity: merged,
            lineTotal: line.unitPrice * merged,
          );
        } else {
          existing.add(CartLine(
            id: _uuid(),
            productId: productId,
            handle: detail?.handle ?? '',
            title: detail?.title ?? 'Item',
            imageUrl: detail?.imageUrl,
            variantId: variantId,
            unitPrice: detail?.price ?? 0,
            quantity: qty.clamp(1, 10),
            lineTotal: (detail?.price ?? 0) * qty,
          ));
        }
        final next = Cart(
          id: cart.id,
          userId: cart.userId,
          items: existing,
          itemCount: existing.fold(0, (sum, l) => sum + l.quantity),
          subtotal: existing.fold(0, (sum, l) => sum + l.lineTotal),
          couponCode: cart.couponCode,
        );
        _carts[cartId] = _withTotals(next);
        return _carts[cartId]!;
      });

  @override
  Future<Cart> updateCartLine({required String cartId, required String lineId, required int qty, String? token}) =>
      _write(() {
        final cart = _carts[cartId];
        if (cart == null) throw ApiException('Cart not found', statusCode: 404);
        final items = cart.items
            .map((l) => l.id == lineId
                ? CartLine(
                    id: l.id,
                    productId: l.productId,
                    handle: l.handle,
                    title: l.title,
                    imageUrl: l.imageUrl,
                    variantId: l.variantId,
                    variantTitle: l.variantTitle,
                    unitPrice: l.unitPrice,
                    quantity: qty,
                    lineTotal: l.unitPrice * qty,
                  )
                : l)
            .toList();
        if (qty <= 0) items.removeWhere((l) => l.id == lineId);
        return _carts[cartId] = _withTotals(Cart(
          id: cart.id,
          userId: cart.userId,
          items: items,
          itemCount: items.fold(0, (sum, l) => sum + l.quantity),
          subtotal: items.fold(0, (sum, l) => sum + l.lineTotal),
          couponCode: cart.couponCode,
        ));
      });

  @override
  Future<Cart> removeFromCart({required String cartId, required String lineId, String? token}) => _write(() {
        final cart = _carts[cartId];
        if (cart == null) throw ApiException('Cart not found', statusCode: 404);
        final items = cart.items.where((l) => l.id != lineId).toList();
        return _carts[cartId] = _withTotals(Cart(
          id: cart.id,
          userId: cart.userId,
          items: items,
          itemCount: items.fold(0, (sum, l) => sum + l.quantity),
          subtotal: items.fold(0, (sum, l) => sum + l.lineTotal),
          couponCode: cart.couponCode,
        ));
      });

  @override
  Future<Cart> applyCoupon({required String cartId, String? code, String? token}) => _write(() {
        final cart = _carts[cartId];
        if (cart == null) throw ApiException('Cart not found', statusCode: 404);
        final normalized = (code ?? '').trim().toUpperCase();
        if (normalized.isNotEmpty && !_validCoupons().containsKey(normalized)) {
          throw ApiException('Invalid or expired coupon code', statusCode: 422, code: 'VALIDATION_ERROR');
        }
        return _carts[cartId] = _withTotals(Cart(
          id: cart.id,
          userId: cart.userId,
          items: cart.items,
          itemCount: cart.itemCount,
          subtotal: cart.subtotal,
          couponCode: normalized.isEmpty ? null : normalized,
        ));
      });

  @override
  Future<Cart> mergeCart({required String cartId, required String token}) async {
    final guest = await getCart(cartId, token: token);
    final id = token.replaceFirst('seed-token-', '');
    final existing = _carts.values.where((c) => c.userId == id).toList();
    final target = existing.isNotEmpty ? existing.first : Cart(id: _uuid(), userId: id, items: const []);
    final mergedItems = [...target.items];
    for (final line in guest.items) {
      final index = mergedItems.indexWhere((l) => l.productId == line.productId);
      if (index >= 0) {
        final current = mergedItems[index];
        final qty = (current.quantity + line.quantity).clamp(1, 10);
        mergedItems[index] = CartLine(
          id: current.id,
          productId: current.productId,
          handle: current.handle,
          title: current.title,
          imageUrl: current.imageUrl,
          unitPrice: current.unitPrice,
          quantity: qty,
          lineTotal: current.unitPrice * qty,
        );
      } else {
        mergedItems.add(line);
      }
    }
    final next = Cart(
      id: target.id,
      userId: id,
      items: mergedItems,
      itemCount: mergedItems.fold(0, (sum, l) => sum + l.quantity),
      subtotal: mergedItems.fold(0, (sum, l) => sum + l.lineTotal),
      couponCode: target.couponCode,
    );
    _carts[next.id] = _withTotals(next);
    _carts.remove(cartId);
    return _carts[next.id]!;
  }

  Map<String, Map<String, dynamic>> _validCoupons() => {
        'WELCOME10': {'type': 'percent', 'value': 10, 'min': 49900, 'max': 20000},
        'FLAT100': {'type': 'flat', 'value': 10000, 'min': 99900, 'max': null},
        'FREESHIP': {'type': 'free_shipping', 'value': 0, 'min': 0, 'max': null},
      };

  /// Mirrors the backend `StandardPricingStrategy` (free shipping above ₹399).
  Cart _withTotals(Cart cart) {
    final subtotal = cart.subtotal;
    int discount = 0;
    bool freeShipping = subtotal >= 39900;
    final coupon = cart.couponCode == null ? null : _validCoupons()[cart.couponCode!];

    if (coupon != null && subtotal >= ((coupon['min'] as num?) ?? 0).toInt()) {
      if (coupon['type'] == 'percent') {
        discount = (subtotal * ((coupon['value'] as num).toInt()) / 100).round();
        final rawMax = coupon['max'];
        final int? max = rawMax is num ? rawMax.toInt() : null;
        if (max != null && discount > max) discount = max;
      } else if (coupon['type'] == 'flat') {
        discount = ((coupon['value'] as num).toInt()).clamp(0, subtotal);
      } else if (coupon['type'] == 'free_shipping') {
        freeShipping = true;
      }
    }

    final shipping = subtotal == 0 ? 0 : (freeShipping ? 0 : 4900);
    final total = (subtotal - discount) + shipping;
    return Cart(
      id: cart.id,
      userId: cart.userId,
      items: cart.items,
      itemCount: cart.itemCount,
      subtotal: subtotal,
      couponCode: discount > 0 || freeShipping ? cart.couponCode : cart.couponCode,
      totals: CartTotals(
        subtotal: subtotal,
        discount: discount,
        shipping: shipping,
        total: total,
        couponCode: cart.couponCode,
        freeShipping: freeShipping,
        savings: discount + (freeShipping && subtotal < 39900 && subtotal > 0 ? 4900 : 0),
      ),
    );
  }

  ProductDetail? _productById(String id) {
    final details = (_seed!['details'] as Map?) ?? const {};
    for (final raw in details.values) {
      final map = (raw as Map).cast<String, dynamic>();
      if (map['id'] == id) return ProductDetail.fromJson(map);
    }
    return null;
  }

  // ── orders ────────────────────────────────────────────────────────────────

  @override
  Future<Order> placeOrder({
    required String cartId,
    required ShippingAddress address,
    String? email,
    String? name,
    String paymentMethod = 'cod',
    String? token,
  }) =>
      _write(() {
        final cart = _carts[cartId];
        if (cart == null || cart.items.isEmpty) throw ApiException('Your cart is empty', statusCode: 422);
        final now = DateTime.now();
        final order = Order(
          id: _uuid(),
          orderNumber: 'BBL-${now.year}${_two(now.month)}${_two(now.day)}-${1000 + _orderCounter++}',
          status: 'placed',
          paymentMethod: paymentMethod,
          paymentStatus: paymentMethod == 'cod' ? 'pending' : 'paid',
          subtotal: cart.totals.subtotal,
          discount: cart.totals.discount,
          shipping: cart.totals.shipping,
          total: cart.totals.total,
          couponCode: cart.couponCode,
          address: address,
          items: cart.items
              .map((l) => OrderItem(
                    id: l.id,
                    productId: l.productId,
                    handle: l.handle,
                    title: l.title,
                    imageUrl: l.imageUrl,
                    variantTitle: l.variantTitle,
                    unitPrice: l.unitPrice,
                    quantity: l.quantity,
                    total: l.lineTotal,
                  ))
              .toList(),
          events: [OrderEvent(status: 'placed', note: 'Order placed successfully', at: now.toIso8601String())],
          email: email,
          phone: address.phone,
          createdAt: now.toIso8601String(),
        );
        _orders[order.id] = order;
        _carts[cartId] = _withTotals(Cart(id: cart.id, userId: cart.userId, items: const [], couponCode: null));
        return order;
      });

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Future<List<Order>> getOrders({String? token, int page = 1, int limit = 20}) async =>
      _orders.values.toList().reversed.toList();

  @override
  Future<Order> getOrder(String id, {String? token}) async {
    final order = _orders[id];
    if (order == null) throw ApiException('Order not found', statusCode: 404);
    return order;
  }

  @override
  Future<Order> trackOrder({required String orderNumber, String? email, String? phone}) async {
    final match = _orders.values.where((o) => o.orderNumber.toLowerCase() == orderNumber.trim().toLowerCase()).toList();
    if (match.isEmpty) throw ApiException('No order found with that order number', statusCode: 404);
    final order = match.first;
    final ok = (email != null && email.isNotEmpty && order.email == email) ||
        (phone != null && phone.isNotEmpty && order.phone == phone);
    if (!ok) throw ApiException('Order number does not match the email/phone on the order', statusCode: 403);
    return order;
  }

  // ── addresses ─────────────────────────────────────────────────────────────

  @override
  Future<List<Address>> getAddresses({required String token}) async {
    final id = token.replaceFirst('seed-token-', '');
    return _addresses[id] ?? const [];
  }

  @override
  Future<Address> saveAddress({required String token, Address? id, Map<String, dynamic>? fields}) => _write(() {
        final userId = token.replaceFirst('seed-token-', '');
        final list = [...(_addresses[userId] ?? <Address>[])];
        final payload = fields ?? const <String, dynamic>{};
        final address = Address(
          id: id?.id ?? _uuid(),
          label: (payload['label'] as String?) ?? id?.label ?? 'Home',
          line1: (payload['line1'] as String?) ?? id?.line1 ?? '',
          line2: (payload['line2'] as String?) ?? id?.line2 ?? '',
          city: (payload['city'] as String?) ?? id?.city ?? '',
          state: (payload['state'] as String?) ?? id?.state ?? '',
          pincode: (payload['pincode'] as String?) ?? id?.pincode ?? '',
          phone: (payload['phone'] as String?) ?? id?.phone ?? '',
          isDefault: (payload['isDefault'] as bool?) ?? list.isEmpty,
          // Map pin: an omitted/null pair keeps the previously pinned spot.
          lat: (payload['lat'] as num?)?.toDouble() ?? id?.lat,
          lng: (payload['lng'] as num?)?.toDouble() ?? id?.lng,
        );
        list.removeWhere((a) => a.id == address.id);
        list.insert(0, address);
        _addresses[userId] = list;
        return address;
      });

  @override
  Future<void> deleteAddress({required String token, required String id}) => _write(() {
        final userId = token.replaceFirst('seed-token-', '');
        final list = [...(_addresses[userId] ?? <Address>[])]..removeWhere((a) => a.id == id);
        _addresses[userId] = list;
      });

  // ── routing (offline estimates - no engine, no tiles) ───────────────────
  //
  // The seed keeps map screens useful without the OSRM container: haversine
  // straight-line distance scaled by a road factor, an average city pace for
  // time, identity snapping for Nearest/Match, and a greedy nearest-neighbour
  // tour for Trip. Vector tiles have no offline equivalent -> 501.

  static const double _roadFactor = 1.3; // straight line -> road detour ratio
  static const double _citySpeed = 8.3; // ~30 km/h average city pace (m/s)

  /// Metres between two points (haversine on a spherical earth).
  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    const d2r = math.pi / 180;
    final dLat = (b.latitude - a.latitude) * d2r;
    final dLng = (b.longitude - a.longitude) * d2r;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * d2r) * math.cos(b.latitude * d2r) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  double _roadMetres(LatLng a, LatLng b) => _haversine(a, b) * _roadFactor;
  double _seconds(double metres) => metres / _citySpeed;

  List<LatLng> _straight(List<LatLng> points) => List<LatLng>.unmodifiable(points);

  @override
  Future<NearestResult> nearest({required double lat, required double lng, int number = 1}) async {
    // Identity snap: the seed has no road graph to project onto, so the pin
    // stays where it was dropped (OSRM's `number` fan-out has no local use).
    return NearestResult(location: LatLng(lat, lng), name: 'Unnamed road', snapDistance: 0);
  }

  @override
  Future<RouteResult> route(List<LatLng> points, {String overview = 'full', bool geometriesGeojson = true}) async {
    if (points.length < 2) throw const ApiException('Expected at least 2 points', statusCode: 400, code: 'INVALID_COORDINATES');
    double metres = 0;
    for (var i = 1; i < points.length; i++) {
      metres += _roadMetres(points[i - 1], points[i]);
    }
    return RouteResult(distance: metres, duration: _seconds(metres), geometry: _straight(points), legs: const []);
  }

  @override
  Future<TableResult> table(List<LatLng> points, {List<int>? sources, List<int>? destinations}) async {
    final src = sources ?? [for (var i = 0; i < points.length; i++) i];
    final dst = destinations ?? [for (var i = 0; i < points.length; i++) i];
    final durations = <List<double?>>[
      for (final s in src) [for (final d in dst) s == d ? 0 : _seconds(_roadMetres(points[s], points[d]))],
    ];
    final distances = <List<double?>>[
      for (final s in src) [for (final d in dst) s == d ? 0 : _roadMetres(points[s], points[d])],
    ];
    return TableResult(durations: durations, distances: distances);
  }

  @override
  Future<MatchResult> matchTrace(List<TracePoint> points) async {
    if (points.length < 2) {
      throw const ApiException('Expected at least 2 trace points', statusCode: 400, code: 'INVALID_COORDINATES');
    }
    // Identity match: hand the raw trace back as the "snapped" geometry.
    double metres = 0;
    for (var i = 1; i < points.length; i++) {
      metres += _roadMetres(points[i - 1].location, points[i].location);
    }
    return MatchResult(
      distance: metres,
      duration: _seconds(metres),
      geometry: _straight([for (final p in points) p.location]),
      confidence: 1,
    );
  }

  @override
  Future<TripResult> trip(
    List<LatLng> points, {
    bool roundtrip = true,
    String source = 'any',
    String destination = 'any',
  }) async {
    if (points.length < 2) throw const ApiException('Expected at least 2 points', statusCode: 400, code: 'INVALID_COORDINATES');

    // Greedy nearest-neighbour ordering (2-opt quality, tiny code). The seed
    // tour always departs the first point, whatever `source` asks for.
    final unvisited = [for (var i = 1; i < points.length; i++) i];
    var last = 0;
    final order = <int>[last];
    while (unvisited.isNotEmpty) {
      var best = unvisited.first;
      var bestD = double.infinity;
      for (final i in unvisited) {
        final d = _haversine(points[last], points[i]);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      unvisited.remove(best);
      order.add(best);
      last = best;
    }
    // Open trip: force the endpoint when the caller pinned it.
    if (!roundtrip && destination == 'last' && order.last != points.length - 1) {
      final forced = points.length - 1;
      order.remove(forced);
      order.add(forced);
    }
    if (roundtrip) order.add(order.first);

    final path = [for (final i in order) points[i]];
    double metres = 0;
    for (var i = 1; i < path.length; i++) {
      metres += _roadMetres(path[i - 1], path[i]);
    }
    return TripResult(distance: metres, duration: _seconds(metres), geometry: _straight(path));
  }

  @override
  Future<Uint8List> vectorTile(int z, int x, int y) async =>
      throw ApiException('Vector tiles are unavailable in seed mode', statusCode: 501, code: 'NOT_SUPPORTED');
}

// ────────────────────────────────── Factory ──────────────────────────────────

/// Single entry point used by the store. Flipping [kUseLocalSeed] in
/// `app_config.dart` swaps the implementation everywhere.
AppApi createApi() => kUseLocalSeed ? SeedApi() : LiveApi();
