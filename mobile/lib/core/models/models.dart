/// Domain models (DTOs) returned by the API / seed source.
///
/// Every model is immutable, has a `fromJson` factory and a `toJson` so the
/// same objects can be serialized back into the offline seed store.
library;

import 'package:latlong2/latlong.dart';

class MoneyFormat {
  /// `69500` (paise) -> `₹695`
  static String rupees(int paise) {
    final rupees = paise / 100;
    final value = rupees == rupees.roundToDouble() ? rupees.round().toString() : rupees.toStringAsFixed(2);
    final grouped = value.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '₹$grouped';
  }
}

// ───────────────────────────────── Catalog ───────────────────────────────────

class ProductCard {
  const ProductCard({
    required this.id,
    required this.handle,
    required this.title,
    this.imageUrl,
    required this.price,
    this.compareAtPrice,
    this.discountPercent = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.notesSummary = '',
    this.audience = 'Unisex',
    this.badge,
    this.available = true,
  });

  final String id;
  final String handle;
  final String title;
  final String? imageUrl;
  final int price;
  final int? compareAtPrice;
  final int discountPercent;
  final double rating;
  final int ratingCount;
  final String notesSummary;
  final String audience;
  final String? badge;
  final bool available;

  factory ProductCard.fromJson(Map<String, dynamic> json) => ProductCard(
        id: json['id'] as String,
        handle: json['handle'] as String,
        title: json['title'] as String,
        imageUrl: json['imageUrl'] as String?,
        price: (json['price'] as num).toInt(),
        compareAtPrice: (json['compareAtPrice'] as num?)?.toInt(),
        discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
        rating: ((json['rating'] as num?) ?? 0).toDouble(),
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        notesSummary: json['notesSummary'] as String? ?? '',
        audience: json['audience'] as String? ?? 'Unisex',
        badge: json['badge'] as String?,
        available: json['available'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'handle': handle,
        'title': title,
        'imageUrl': imageUrl,
        'price': price,
        'compareAtPrice': compareAtPrice,
        'discountPercent': discountPercent,
        'rating': rating,
        'ratingCount': ratingCount,
        'notesSummary': notesSummary,
        'audience': audience,
        'badge': badge,
        'available': available,
      };
}

class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.title,
    required this.price,
    this.compareAtPrice,
    this.available = true,
  });

  final String id;
  final String title;
  final int price;
  final int? compareAtPrice;
  final bool available;

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Default Title',
        price: (json['price'] as num).toInt(),
        compareAtPrice: (json['compareAtPrice'] as num?)?.toInt(),
        available: json['available'] as bool? ?? true,
      );
}

class ProductNote {
  const ProductNote({required this.type, required this.name, this.iconUrl});

  final String type; // head | heart | base
  final String name;
  final String? iconUrl;

  factory ProductNote.fromJson(Map<String, dynamic> json) => ProductNote(
        type: json['type'] as String,
        name: json['name'] as String,
        iconUrl: json['iconUrl'] as String?,
      );
}

class ProductDetail extends ProductCard {
  const ProductDetail({
    required super.id,
    required super.handle,
    required super.title,
    super.imageUrl,
    required super.price,
    super.compareAtPrice,
    super.discountPercent,
    super.rating,
    super.ratingCount,
    super.notesSummary,
    super.audience,
    super.badge,
    super.available,
    required this.description,
    this.tagline = '',
    this.oilConcentration,
    required this.images,
    required this.variants,
    required this.headNotes,
    required this.heartNotes,
    required this.baseNotes,
    this.collections = const [],
  });

  final String description;
  final String tagline;
  final String? oilConcentration;
  final List<String> images;
  final List<ProductVariant> variants;
  final List<ProductNote> headNotes;
  final List<ProductNote> heartNotes;
  final List<ProductNote> baseNotes;
  final List<String> collections;

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    final notes = (json['notes'] as Map<String, dynamic>?) ?? const {};
    List<ProductNote> read(String key) =>
        ((notes[key] as List?) ?? const []).map((e) => ProductNote.fromJson(e as Map<String, dynamic>)).toList();
    return ProductDetail(
      id: json['id'] as String,
      handle: json['handle'] as String,
      title: json['title'] as String,
      imageUrl: json['imageUrl'] as String?,
      price: (json['price'] as num).toInt(),
      compareAtPrice: (json['compareAtPrice'] as num?)?.toInt(),
      discountPercent: (json['discountPercent'] as num?)?.toInt() ?? 0,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      notesSummary: json['notesSummary'] as String? ?? '',
      audience: json['audience'] as String? ?? 'Unisex',
      badge: json['badge'] as String?,
      available: json['available'] as bool? ?? true,
      description: json['description'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      oilConcentration: json['oilConcentration'] as String?,
      images: ((json['images'] as List?) ?? const [])
          .map((e) => (e as Map<String, dynamic>)['url'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList(),
      variants: ((json['variants'] as List?) ?? const [])
          .map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
      headNotes: read('head'),
      heartNotes: read('heart'),
      baseNotes: read('base'),
      collections: ((json['collections'] as List?) ?? const []).cast<String>(),
    );
  }
}

class CollectionTile {
  const CollectionTile({
    required this.handle,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.productCount = 0,
  });

  final String handle;
  final String title;
  final String description;
  final String? imageUrl;
  final int productCount;

  factory CollectionTile.fromJson(Map<String, dynamic> json) => CollectionTile(
        handle: json['handle'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      );
}

class ProductReview {
  const ProductReview({
    required this.id,
    required this.author,
    required this.rating,
    this.title = '',
    this.body = '',
    this.createdAt = '',
  });

  final String id;
  final String author;
  final int rating;
  final String title;
  final String body;
  final String createdAt;

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
        id: json['id'] as String,
        author: json['author'] as String,
        rating: (json['rating'] as num).toInt(),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );
}

// ────────────────────────────────── Home ─────────────────────────────────────

class HeroSlide {
  const HeroSlide({required this.desktopUrl, required this.mobileUrl, this.link = '', this.alt = ''});

  final String desktopUrl;
  final String mobileUrl;
  final String link;
  final String alt;

  factory HeroSlide.fromJson(Map<String, dynamic> json) => HeroSlide(
        desktopUrl: json['desktopUrl'] as String? ?? '',
        mobileUrl: json['mobileUrl'] as String? ?? '',
        link: json['link'] as String? ?? '',
        alt: json['alt'] as String? ?? '',
      );
}

class HomeTile {
  const HomeTile({required this.title, required this.imageUrl, this.link = '', this.startingPricePaise, this.badge = '', this.caption});

  final String title;
  final String imageUrl;
  final String link;
  final int? startingPricePaise;
  final String badge;
  final String? caption;

  factory HomeTile.fromJson(Map<String, dynamic> json) => HomeTile(
        title: json['title'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        link: json['link'] as String? ?? '',
        startingPricePaise: (json['startingPricePaise'] as num?)?.toInt(),
        badge: json['badge'] as String? ?? '',
        caption: json['caption'] as String?,
      );
}

class HomeBanner {
  const HomeBanner({required this.imageUrl, this.mobileUrl, this.link = '', this.alt = ''});

  final String imageUrl;
  final String? mobileUrl;
  final String link;
  final String alt;

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
        imageUrl: json['imageUrl'] as String? ?? '',
        mobileUrl: json['mobileUrl'] as String?,
        link: json['link'] as String? ?? '',
        alt: json['alt'] as String? ?? '',
      );
}

class FaqGroup {
  const FaqGroup({required this.category, required this.items});

  final String category;
  final List<FaqItem> items;

  factory FaqGroup.fromJson(Map<String, dynamic> json) => FaqGroup(
        category: json['category'] as String,
        items: ((json['items'] as List?) ?? const [])
            .map((e) => FaqItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FaqItem {
  const FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  factory FaqItem.fromJson(Map<String, dynamic> json) => FaqItem(
        question: json['question'] as String,
        answer: json['answer'] as String,
      );
}

class HomeData {
  const HomeData({
    required this.announcement,
    required this.heroSlides,
    required this.collectionSectionTitle,
    required this.collectionTiles,
    required this.trialTitle,
    required this.trialTagline,
    required this.trialTiles,
    required this.featuredTitle,
    required this.featured,
    required this.newArrivals,
    required this.banners,
    required this.claimsPoints,
    required this.faqTitle,
    required this.faqIntro,
    required this.newsletter,
    required this.brandTagline,
    required this.social,
    required this.footer,
    required this.support,
    required this.scamAlert,
    required this.copyright,
  });

  final String announcement;
  final List<HeroSlide> heroSlides;
  final String collectionSectionTitle;
  final List<HomeTile> collectionTiles;
  final String trialTitle;
  final String trialTagline;
  final List<HomeTile> trialTiles;
  final String featuredTitle;
  final List<ProductCard> featured;
  final List<ProductCard> newArrivals;
  final List<HomeBanner> banners;
  final List<String> claimsPoints;
  final String faqTitle;
  final String faqIntro;
  final Map<String, String> newsletter;
  final String brandTagline;
  final List<Map<String, String>> social;
  final Map<String, List<Map<String, String>>> footer;
  final Map<String, String> support;
  final Map<String, dynamic> scamAlert;
  final String copyright;

  factory HomeData.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) => (json[key] as Map<String, dynamic>?) ?? const {};

    List<HomeTile> tiles(String key) => ((section(key)['tiles'] as List?) ?? const [])
        .map((e) => HomeTile.fromJson(e as Map<String, dynamic>))
        .toList();

    List<Map<String, String>> listOf(dynamic value) => ((value as List?) ?? const [])
        .map((e) => (e as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())))
        .toList();

    Map<String, List<Map<String, String>>> footerOf(dynamic value) =>
        ((value as Map<String, dynamic>?) ?? const {}).map((k, v) => MapEntry(k, listOf(v)));

    return HomeData(
      announcement: json['announcement'] as String? ?? '',
      heroSlides: ((json['heroSlides'] as List?) ?? const [])
          .map((e) => HeroSlide.fromJson(e as Map<String, dynamic>))
          .toList(),
      collectionSectionTitle: section('collectionSection')['title'] as String? ?? 'Our Collection',
      collectionTiles: tiles('collectionSection'),
      trialTitle: section('trialSection')['title'] as String? ?? '',
      trialTagline: section('trialSection')['tagline'] as String? ?? '',
      trialTiles: tiles('trialSection'),
      featuredTitle: json['featuredTitle'] as String? ?? 'Bestsellers',
      featured: ((json['featured'] as List?) ?? const [])
          .map((e) => ProductCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      newArrivals: ((json['newArrivals'] as List?) ?? const [])
          .map((e) => ProductCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      banners: ((json['banners'] as List?) ?? const [])
          .map((e) => HomeBanner.fromJson(e as Map<String, dynamic>))
          .toList(),
      claimsPoints: ((section('claims')['points'] as List?) ?? const []).map((e) => e.toString()).toList(),
      faqTitle: json['faqTitle'] as String? ?? 'Faqs',
      faqIntro: json['faqIntro'] as String? ?? '',
      newsletter: ((section('newsletter') as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
      brandTagline: json['brandTagline'] as String? ?? '',
      social: listOf(json['social']),
      footer: footerOf(json['footer']),
      support: ((json['support'] as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
      scamAlert: (json['scamAlert'] as Map<String, dynamic>?) ?? const {},
      copyright: json['copyright'] as String? ?? '',
    );
  }
}

// ─────────────────────────────────── Cart ────────────────────────────────────

class CartLine {
  const CartLine({
    required this.id,
    required this.productId,
    required this.handle,
    required this.title,
    this.imageUrl,
    this.variantId,
    this.variantTitle,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.available = true,
  });

  final String id;
  final String productId;
  final String handle;
  final String title;
  final String? imageUrl;
  final String? variantId;
  final String? variantTitle;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  final bool available;

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        id: json['id'] as String,
        productId: json['productId'] as String,
        handle: json['handle'] as String,
        title: json['title'] as String,
        imageUrl: json['imageUrl'] as String?,
        variantId: json['variantId'] as String?,
        variantTitle: json['variantTitle'] as String?,
        unitPrice: (json['unitPrice'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        lineTotal: (json['lineTotal'] as num).toInt(),
        available: json['available'] as bool? ?? true,
      );
}

class CartTotals {
  const CartTotals({
    this.subtotal = 0,
    this.discount = 0,
    this.shipping = 0,
    this.total = 0,
    this.couponCode,
    this.freeShipping = false,
    this.savings = 0,
  });

  final int subtotal;
  final int discount;
  final int shipping;
  final int total;
  final String? couponCode;
  final bool freeShipping;
  final int savings;

  factory CartTotals.fromJson(Map<String, dynamic> json) => CartTotals(
        subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
        discount: (json['discount'] as num?)?.toInt() ?? 0,
        shipping: (json['shipping'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        couponCode: json['couponCode'] as String?,
        freeShipping: json['freeShipping'] as bool? ?? false,
        savings: (json['savings'] as num?)?.toInt() ?? 0,
      );
}

class Cart {
  const Cart({
    required this.id,
    this.userId,
    this.items = const [],
    this.itemCount = 0,
    this.subtotal = 0,
    this.couponCode,
    this.totals = const CartTotals(),
  });

  final String id;
  final String? userId;
  final List<CartLine> items;
  final int itemCount;
  final int subtotal;
  final String? couponCode;
  final CartTotals totals;

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        items: ((json['items'] as List?) ?? const [])
            .map((e) => CartLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
        subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
        couponCode: json['couponCode'] as String?,
        totals: CartTotals.fromJson((json['totals'] as Map<String, dynamic>?) ?? const {}),
      );
}

// ────────────────────────────────── Orders ───────────────────────────────────

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productId,
    required this.handle,
    required this.title,
    this.imageUrl,
    this.variantTitle,
    required this.unitPrice,
    required this.quantity,
    required this.total,
  });

  final String id;
  final String productId;
  final String handle;
  final String title;
  final String? imageUrl;
  final String? variantTitle;
  final int unitPrice;
  final int quantity;
  final int total;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String,
        productId: json['productId'] as String? ?? '',
        handle: json['handle'] as String? ?? '',
        title: json['title'] as String,
        imageUrl: json['imageUrl'] as String?,
        variantTitle: json['variantTitle'] as String?,
        unitPrice: (json['unitPrice'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        total: (json['total'] as num).toInt(),
      );
}

class OrderEvent {
  const OrderEvent({required this.status, this.note = '', this.at = ''});

  final String status;
  final String note;
  final String at;

  factory OrderEvent.fromJson(Map<String, dynamic> json) => OrderEvent(
        status: json['status'] as String,
        note: json['note'] as String? ?? '',
        at: (json['at'] ?? json['occurredAt']) as String? ?? '',
      );
}

class ShippingAddress {
  const ShippingAddress({
    this.name = '',
    this.phone = '',
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.label = 'Home',
    this.lat,
    this.lng,
  });

  final String name;
  final String phone;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String label;

  /// Optional map pin (WGS84) - lets the tracking screen draw the destination.
  final double? lat;
  final double? lng;

  bool get hasPin => lat != null && lng != null;

  String get singleLine => [line1, line2, city, state, pincode].where((s) => s.isNotEmpty).join(', ');

  factory ShippingAddress.fromJson(Map<String, dynamic> json) => ShippingAddress(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        line1: json['line1'] as String? ?? '',
        line2: json['line2'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        pincode: json['pincode'] as String? ?? '',
        label: json['label'] as String? ?? 'Home',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'label': label,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };
}

class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.paymentMethod = 'cod',
    this.paymentStatus = 'pending',
    this.subtotal = 0,
    this.discount = 0,
    this.shipping = 0,
    this.total = 0,
    this.couponCode,
    required this.address,
    this.items = const [],
    this.events = const [],
    this.email,
    this.phone,
    this.createdAt = '',
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final int subtotal;
  final int discount;
  final int shipping;
  final int total;
  final String? couponCode;
  final ShippingAddress address;
  final List<OrderItem> items;
  final List<OrderEvent> events;
  final String? email;
  final String? phone;
  final String createdAt;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        orderNumber: json['orderNumber'] as String,
        status: json['status'] as String? ?? 'placed',
        paymentMethod: json['paymentMethod'] as String? ?? 'cod',
        paymentStatus: json['paymentStatus'] as String? ?? 'pending',
        subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
        discount: (json['discount'] as num?)?.toInt() ?? 0,
        shipping: (json['shipping'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        couponCode: json['couponCode'] as String?,
        address: ShippingAddress.fromJson((json['address'] as Map<String, dynamic>?) ?? const {}),
        items: ((json['items'] as List?) ?? const [])
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: ((json['events'] as List?) ?? const [])
            .map((e) => OrderEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderNumber': orderNumber,
        'status': status,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'subtotal': subtotal,
        'discount': discount,
        'shipping': shipping,
        'total': total,
        'couponCode': couponCode,
        'address': address.toJson(),
        'items': items
            .map((i) => {
                  'id': i.id,
                  'productId': i.productId,
                  'handle': i.handle,
                  'title': i.title,
                  'imageUrl': i.imageUrl,
                  'variantTitle': i.variantTitle,
                  'unitPrice': i.unitPrice,
                  'quantity': i.quantity,
                  'total': i.total,
                })
            .toList(),
        'events': events.map((e) => {'status': e.status, 'note': e.note, 'at': e.at}).toList(),
        'email': email,
        'phone': phone,
        'createdAt': createdAt,
      };
}

// ────────────────────────────────── Auth ─────────────────────────────────────

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email, this.phone});

  final String id;
  final String name;
  final String email;
  final String? phone;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'phone': phone};
}

class AuthSession {
  const AuthSession({required this.user, required this.accessToken, this.refreshToken});

  final AuthUser user;
  final String accessToken;
  final String? refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String?,
      );
}

class Address {
  const Address({
    required this.id,
    this.label = 'Home',
    required this.line1,
    this.line2 = '',
    required this.city,
    required this.state,
    required this.pincode,
    required this.phone,
    this.isDefault = false,
    this.lat,
    this.lng,
  });

  final String id;
  final String label;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final bool isDefault;

  /// Optional map pin (WGS84) picked on the address map screen.
  final double? lat;
  final double? lng;

  bool get hasPin => lat != null && lng != null;

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Home',
        line1: json['line1'] as String? ?? '',
        line2: json['line2'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        pincode: json['pincode'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  /// Same address with (or without) a map pin - used after the picker returns.
  Address withPin(double? lat, double? lng) => Address(
        id: id,
        label: label,
        line1: line1,
        line2: line2,
        city: city,
        state: state,
        pincode: pincode,
        phone: phone,
        isDefault: isDefault,
        lat: lat,
        lng: lng,
      );

  ShippingAddress toShipping(String name) => ShippingAddress(
        name: name,
        phone: phone,
        line1: line1,
        line2: line2,
        city: city,
        state: state,
        pincode: pincode,
        label: label,
        lat: lat,
        lng: lng,
      );
}

class PageContent {
  const PageContent({required this.handle, required this.title, required this.body});

  final String handle;
  final String title;
  final String body;

  factory PageContent.fromJson(Map<String, dynamic> json) => PageContent(
        handle: json['handle'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
}

class ProductPage {
  const ProductPage({required this.items, this.total = 0, this.page = 1, this.totalPages = 1});

  final List<ProductCard> items;
  final int total;
  final int page;
  final int totalPages;

  factory ProductPage.fromJson(Map<String, dynamic> json, {List<ProductCard> items = const []}) => ProductPage(
        items: items,
        total: (json['total'] as num?)?.toInt() ?? items.length,
        page: (json['page'] as num?)?.toInt() ?? 1,
        totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      );
}

// ────────────────────────────────── Routing ───────────────────────────────────
// DTOs for the six OSRM services proxied by `/api/routing/*`. Geometry always
// arrives as GeoJSON (`[lng, lat]` pairs) and is flipped to [LatLng] here.

/// One point of a GPS trace fed to OSRM Match.
class TracePoint {
  const TracePoint({required this.location, required this.timestamp, this.accuracy});

  final LatLng location;

  /// Epoch seconds - must be monotonically increasing for Match.
  final int timestamp;

  /// GPS accuracy in metres, forwarded as OSRM `radiuses`.
  final double? accuracy;
}

/// Nearest - the road-snapped version of a dropped pin.
class NearestResult {
  const NearestResult({required this.location, this.name = '', this.snapDistance = 0});

  final LatLng location;

  /// Name of the street/way the point snapped to (may be empty).
  final String name;

  /// Metres between the input point and the snapped location.
  final double snapDistance;

  factory NearestResult.fromJson(Map<String, dynamic> json) {
    final wp = ((json['waypoints'] as List?) ?? const []).firstOrNull;
    final location = ((wp?['location'] as List?) ?? const [0, 0]);
    return NearestResult(
      location: LatLng((location.elementAtOrNull(1) as num? ?? 0).toDouble(), (location.firstOrNull as num? ?? 0).toDouble()),
      name: wp?['name'] as String? ?? '',
      snapDistance: (wp?['distance'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Route - distance/duration plus the road polyline to draw on a map.
class RouteResult {
  const RouteResult({required this.distance, required this.duration, required this.geometry, this.legs = const []});

  /// Total length in metres.
  final double distance;

  /// Total travel time in seconds.
  final double duration;

  final List<LatLng> geometry;

  /// Per-leg breakdown (one leg per input waypoint pair).
  final List<RouteLeg> legs;

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final route = ((json['routes'] as List?) ?? const []).firstOrNull ?? const <String, dynamic>{};
    return RouteResult(
      distance: (route['distance'] as num?)?.toDouble() ?? 0,
      duration: (route['duration'] as num?)?.toDouble() ?? 0,
      geometry: _lineFrom(route['geometry']),
      legs: ((route['legs'] as List?) ?? const [])
          .map((l) => RouteLeg.fromJson((l as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class RouteLeg {
  const RouteLeg({required this.distance, required this.duration, this.summary = ''});

  final double distance;
  final double duration;
  final String summary;

  factory RouteLeg.fromJson(Map<String, dynamic> json) => RouteLeg(
        distance: (json['distance'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        summary: json['summary'] as String? ?? '',
      );
}

/// Table - pairwise travel times between the given points.
class TableResult {
  const TableResult({required this.durations, required this.distances});

  /// `durations[source][destination]` in seconds (`null` = unreachable).
  final List<List<double?>> durations;

  /// `distances[source][destination]` in metres, same indexing.
  final List<List<double?>> distances;

  factory TableResult.fromJson(Map<String, dynamic> json) => TableResult(
        durations: _matrix(json['durations']),
        distances: _matrix(json['distances']),
      );

  /// Best (shortest) duration in seconds across [sourceRow] -> all columns,
  /// or `null` when nothing is reachable.
  double? bestFrom(int sourceRow) {
    if (sourceRow < 0 || sourceRow >= durations.length) return null;
    double? best;
    for (final d in durations[sourceRow]) {
      if (d != null && (best == null || d < best)) best = d;
    }
    return best;
  }
}

/// Match - a GPS trace re-snapped onto the road network.
class MatchResult {
  const MatchResult({required this.distance, required this.duration, required this.geometry, this.confidence = 0});

  final double distance;
  final double duration;
  final List<LatLng> geometry;

  /// 0..1 - OSRM's trace quality score.
  final double confidence;

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final m = ((json['matchings'] as List?) ?? const []).firstOrNull ?? const <String, dynamic>{};
    return MatchResult(
      distance: (m['distance'] as num?)?.toDouble() ?? 0,
      duration: (m['duration'] as num?)?.toDouble() ?? 0,
      geometry: _lineFrom(m['geometry']),
      confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Trip - a set of waypoints reordered into an optimal tour.
class TripResult {
  const TripResult({required this.distance, required this.duration, required this.geometry});

  final double distance;
  final double duration;
  final List<LatLng> geometry;

  factory TripResult.fromJson(Map<String, dynamic> json) {
    final t = ((json['trips'] as List?) ?? const []).firstOrNull ?? const <String, dynamic>{};
    return TripResult(
      distance: (t['distance'] as num?)?.toDouble() ?? 0,
      duration: (t['duration'] as num?)?.toDouble() ?? 0,
      geometry: _lineFrom(t['geometry']),
    );
  }
}

/// Checkout ETA card: nearest warehouse -> address pin.
class EtaEstimate {
  const EtaEstimate({required this.warehouse, required this.distance, required this.duration});

  /// Which fulfilment hub is serving the order.
  final String warehouse;

  /// Road distance in metres.
  final double distance;

  /// Travel time in seconds.
  final double duration;

  String get distanceLabel => distance < 1000 ? '${distance.round()} m' : '${(distance / 1000).toStringAsFixed(1)} km';

  String get durationLabel {
    final minutes = (duration / 60).ceil();
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} hr ${minutes % 60} min';
  }
}

// ────────────────────────────────── Tracking ─────────────────────────────────
// Rider GPS trail + rider queue DTOs for `/api/tracking/*`.

/// One GPS fix reported by a rider device (POST .../position, trail entries).
class RiderPosition {
  const RiderPosition({
    required this.id,
    required this.orderId,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
    this.recordedAt = '',
    this.receivedAt = '',
  });

  final String id;
  final String orderId;
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;

  /// Device clock of the fix (ISO 8601).
  final String recordedAt;

  /// Server clock of arrival (ISO 8601) - the safer staleness reference.
  final String receivedAt;

  LatLng get location => LatLng(lat, lng);

  factory RiderPosition.fromJson(Map<String, dynamic> json) => RiderPosition(
        id: json['id'] as String? ?? '',
        orderId: json['orderId'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
        speedMps: (json['speedMps'] as num?)?.toDouble(),
        headingDeg: (json['headingDeg'] as num?)?.toDouble(),
        recordedAt: json['recordedAt'] as String? ?? '',
        receivedAt: json['receivedAt'] as String? ?? '',
      );
}

/// The customer's read of a live trail: GET /tracking/orders/:id.
class TrackResult {
  const TrackResult({
    required this.orderId,
    this.orderNumber = '',
    this.status = '',
    this.trail = const [],
    this.updatedAt = '',
  });

  final String orderId;
  final String orderNumber;
  final String status;

  /// Chronological (oldest -> newest) newest-slice of fixes.
  final List<RiderPosition> trail;
  final String updatedAt;

  /// Newest fix, or null while the rider hasn't reported yet.
  RiderPosition? get latest => trail.isEmpty ? null : trail.last;

  factory TrackResult.fromJson(Map<String, dynamic> json) => TrackResult(
        orderId: json['orderId'] as String? ?? '',
        orderNumber: json['orderNumber'] as String? ?? '',
        status: json['status'] as String? ?? '',
        trail: _asJsonMapList(json['trail']).map(RiderPosition.fromJson).toList(),
        updatedAt: json['updatedAt'] as String? ?? '',
      );
}

/// One job in the rider queue: GET /tracking/deliveries.
class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.address,
    this.placedAt = '',
    this.lastFix,
  });

  final String id;
  final String orderNumber;
  final String status;
  final ShippingAddress address;
  final String placedAt;

  /// The rider's newest fix for this job, when one exists.
  final RiderPosition? lastFix;

  bool get hasPin => address.hasPin;

  factory DeliveryJob.fromJson(Map<String, dynamic> json) => DeliveryJob(
        id: json['id'] as String? ?? '',
        orderNumber: json['orderNumber'] as String? ?? '',
        status: json['status'] as String? ?? '',
        address: ShippingAddress.fromJson((json['address'] as Map<String, dynamic>?) ?? const {}),
        placedAt: json['placedAt'] as String? ?? '',
        lastFix: json['lastFix'] is Map
            ? RiderPosition.fromJson((json['lastFix'] as Map).cast<String, dynamic>())
            : null,
      );
}

List<Map<String, dynamic>> _asJsonMapList(dynamic value) =>
    ((value as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

// GeoJSON `[lng, lat]` pairs -> [LatLng].
List<LatLng> _lineFrom(dynamic geometry) {
  final coords = ((geometry as Map?)?['coordinates'] as List?) ?? const [];
  return [
    for (final c in coords)
      LatLng(
        ((c as List).elementAtOrNull(1) as num? ?? 0).toDouble(),
        (c.firstOrNull as num? ?? 0).toDouble(),
      ),
  ];
}

List<List<double?>> _matrix(dynamic value) => [
      for (final row in ((value as List?) ?? const []))
        [for (final cell in ((row as List?) ?? const [])) (cell as num?)?.toDouble()],
    ];
