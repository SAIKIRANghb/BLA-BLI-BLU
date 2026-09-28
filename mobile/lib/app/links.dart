/// Resolves storefront links onto this app's routes.
///
/// The catalogue content (home sections, banners, footer, CMS pages) is
/// scraped from blabliblulife.com, so it speaks **Shopify's plural**
/// vocabulary - `/collections/perfume`, `/products/habibi`, `/pages/about-us`
/// - while this app's router is singular - `/collection/perfume`,
/// `/product/habibi`, `/page/about-us`. Without this mapping every scraped
/// tile ("Our Collection", "Game Changer Trial Set", banners, footer links)
/// silently does nothing when tapped.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Route roots owned by the bottom navigation - reaching them must *switch*
/// the active tab (`go`) instead of pushing a second instance on the stack.
const _tabRoots = {'/', '/shop', '/search', '/cart', '/account'};

/// The in-app route for [link], or `null` when it has no destination here
/// (external host, anchor, empty).
String? resolveShopLink(String? link) {
  var value = (link ?? '').trim();
  if (value.isEmpty || value.startsWith('#')) return null;

  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    // Absolute URL: only follow the storefront's own hosts, and keep the path.
    final host = parsed.host.toLowerCase();
    final ownHost = host.contains('blabliblulife') ||
        host.contains('myshopify') ||
        host.isEmpty;
    if (!ownHost) return null;
    value = parsed.path;
  }

  // Drop query string and fragment: route parameters live in the path only.
  value = value.split(RegExp(r'[?#]')).first;

  if (!value.startsWith('/')) return null;
  final segments = value.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return '/';

  final head = segments.first;
  if (segments.length == 1) {
    // Bare index links: the storefront's product/collection index is this
    // app's Shop tab, while a stray singular root has no screen of its own.
    if (head == 'collections' || head == 'collection' || head == 'products' || head == 'product') return '/shop';
    if (head == 'pages') return null;
  }
  if (head == 'collections') {
    segments[0] = 'collection';
  } else if (head == 'products') {
    segments[0] = 'product';
  } else if (head == 'pages') {
    segments[0] = 'page';
  } else if (head == 'search' || head == 'cart' || head == 'account' || head == 'checkout') {
    return '/$head';
  }
  return '/${segments.join('/')}';
}

/// Opens [link]: tab roots switch branch, everything else is pushed so the
/// back button returns to where the user came from. No-op when unresolvable.
void openShopLink(BuildContext context, String? link) {
  final route = resolveShopLink(link);
  if (route == null) return;
  if (_tabRoots.contains(route)) {
    context.go(route);
  } else {
    context.push(route);
  }
}

/// Back navigation that also survives a *redirected* screen.
///
/// The auth guard reaches `/sign-in` with a bare `go` (tapping the Account
/// tab while signed out rewrites the location), so there is nothing underneath
/// to pop and a bare `context.pop()` leaves the arrow dead. In that case fall
/// back to the Home tab instead of trapping the user.
void goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}
