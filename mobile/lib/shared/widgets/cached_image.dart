import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

/// Network image with a graceful placeholder/error fallback (the catalogue is
/// all Shopify CDN URLs; a broken link must never blow up a card).
///
/// Deliberately free of `cached_network_image`: that package drags in
/// `path_provider` -> `path_provider_foundation` -> `objective_c`, whose
/// native-assets build hook cannot be spawned by `cmd.exe` when the Flutter
/// SDK lives in a path containing spaces (hooks_runner <= 1.5 runs every hook
/// through a shell). This widget keeps the behaviour that matters instead:
/// one download per URL per session, an LRU byte budget, a pulse placeholder
/// and a 180ms fade-in.
class CachedImage extends StatefulWidget {
  const CachedImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.radius = 0,
    this.alignment = Alignment.center,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;
  final Alignment alignment;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  /// Request for the current [CachedImage.url]; `null` when the URL is
  /// unusable (missing, empty or not http/https).
  Future<MemoryImage?>? _request;

  @override
  void initState() {
    super.initState();
    _request = _start();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _request = _start();
  }

  Future<MemoryImage?>? _start() {
    final link = widget.url ?? '';
    if (link.startsWith('http://') || link.startsWith('https://')) {
      return _ImageStore.instance.obtain(link);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: _body(),
    );
    return SizedBox(width: widget.width, height: widget.height, child: child);
  }

  Widget _body() {
    final request = _request;
    if (request == null) return const _Fallback();
    return FutureBuilder<MemoryImage?>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Placeholder();
        }
        if (snapshot.hasError || snapshot.data == null) return const _Fallback();
        return Image(
          image: snapshot.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
          gaplessPlayback: true,
          frameBuilder: _fadeIn,
          errorBuilder: (_, __, ___) => const _Fallback(),
        );
      },
    );
  }

  /// Pulse while the first frame decodes, then cross-fade it in - the exact
  /// feel of the `fadeInDuration` we used before.
  Widget _fadeIn(BuildContext context, Widget child, int? frame, bool wasSyncLoaded) {
    if (wasSyncLoaded) return child;
    if (frame == null) return const _Placeholder();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

/// Session-wide, URL-keyed LRU for downloaded catalogue imagery. Plays the
/// part of `flutter_cache_manager`'s disk cache without the native hooks:
/// bytes are retained in memory for the lifetime of the app (or until the
/// budget is exceeded), and concurrent requests for one URL share a single
/// download.
class _ImageStore {
  _ImageStore._();

  static final _ImageStore instance = _ImageStore._();

  /// Retain at most 120 images / 48 MB, dropping the least recently used
  /// entries first.
  static const int _maxEntries = 120;
  static const int _maxBytes = 48 * 1024 * 1024;
  static const Duration _timeout = Duration(seconds: 20);

  final LinkedHashMap<String, _BufferedImage> _entries =
      LinkedHashMap<String, _BufferedImage>();
  final Map<String, Future<MemoryImage?>> _inFlight =
      <String, Future<MemoryImage?>>{};
  int _bufferedBytes = 0;

  /// Returns the image for [url], downloading it at most once per session.
  Future<MemoryImage?> obtain(String url) {
    final cached = _entries.remove(url);
    if (cached != null) {
      _entries[url] = cached; // re-insert last: it is now the most used
      return SynchronousFuture<MemoryImage>(cached.image);
    }

    final pending = _inFlight[url];
    if (pending != null) return pending;

    final request = _download(url);
    _inFlight[url] = request;
    request.whenComplete(() {
      if (identical(_inFlight[url], request)) _inFlight.remove(url);
    });
    return request;
  }

  Future<MemoryImage?> _download(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final image = MemoryImage(response.bodyBytes);
      _remember(url, image, response.bodyBytes.lengthInBytes);
      return image;
    } catch (_) {
      // A flaky network or a dead CDN link must degrade to the fallback
      // tile, never surface as an exception in a product card.
      return null;
    }
  }

  void _remember(String url, MemoryImage image, int bytes) {
    _entries.remove(url);
    _entries[url] = _BufferedImage(image, bytes);
    _bufferedBytes += bytes;
    while (_entries.length > _maxEntries ||
        (_bufferedBytes > _maxBytes && _entries.length > 1)) {
      final eldestKey = _entries.keys.first;
      final eldest = _entries.remove(eldestKey);
      if (eldest == null) break;
      _bufferedBytes -= eldest.bytes;
    }
  }
}

class _BufferedImage {
  const _BufferedImage(this.image, this.bytes);

  final MemoryImage image;
  final int bytes;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  /// Keyed so tests can tell "still loading" from "gave up".
  static const stateKey = ValueKey('cached-image-placeholder');

  @override
  Widget build(BuildContext context) => const ColoredBox(
        key: stateKey,
        color: Color(0xFFF0F0F0),
        child: Center(child: _PlaceholderPulse()),
      );
}

class _PlaceholderPulse extends StatefulWidget {
  const _PlaceholderPulse();
  @override
  State<_PlaceholderPulse> createState() => _PlaceholderPulseState();
}

class _PlaceholderPulseState extends State<_PlaceholderPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.25, end: 0.7).animate(_c),
        child: const Icon(Icons.local_mall_outlined, color: AppColors.muted, size: 26),
      );
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  /// Keyed so tests can assert a dead link degrades instead of throwing.
  static const stateKey = ValueKey('cached-image-fallback');

  @override
  Widget build(BuildContext context) => const ColoredBox(
        key: stateKey,
        color: Color(0xFFF0F0F0),
        child: Center(child: Icon(Icons.local_mall_outlined, color: AppColors.muted, size: 26)),
      );
}
