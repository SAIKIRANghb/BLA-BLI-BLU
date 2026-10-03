import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/actions.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// Sort options exposed by the storefront.
const kSortOptions = <(String, String)>[
  ('featured', 'Featured'),
  ('best_selling', 'Best selling'),
  ('newest', 'Newest'),
  ('price_asc', 'Price: low to high'),
  ('price_desc', 'Price: high to low'),
  ('rating', 'Top rated'),
  ('title_asc', 'Name: A-Z'),
  ('title_desc', 'Name: Z-A'),
];

/// Reusable paginated grid used by the collection, search and "shop all" tabs.
///
/// Reads from (and writes into) the `catalog.listings` cache via the store's
/// `loadListing` thunk - the screen itself stays declarative.
class ProductListingView extends ConsumerStatefulWidget {
  const ProductListingView({
    super.key,
    this.collection,
    this.query,
    this.header,
    this.pageSize = 24,
  });

  final String? collection;
  final String? query;
  final Widget? header;
  final int pageSize;

  @override
  ConsumerState<ProductListingView> createState() => _ProductListingViewState();
}

class _ProductListingViewState extends ConsumerState<ProductListingView> {
  String _sort = 'featured';
  int _page = 1;
  final _scroll = ScrollController();
  bool _loadingMore = false;

  /// Set once this grid's cache slot has actually existed, so a store flush
  /// (sign-out resets the whole catalogue) reads as "our slot vanished" rather
  /// than the normal first build. The tab shell keeps this view alive across a
  /// logout, so `initState` never runs again and the grid would otherwise sit
  /// on an eternal skeleton - nothing else ever refetches it.
  bool _hadSlot = false;

  @override
  void initState() {
    super.initState();
    _sort = 'featured';
    _page = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ProductListingView old) {
    super.didUpdateWidget(old);
    if (old.collection != widget.collection || old.query != widget.query) {
      _page = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(refresh: true));
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  String get _key => listingKey(collection: widget.collection, query: widget.query, sort: _sort);

  Future<void> _load({bool refresh = false, bool append = false}) {
    return ref.read(storeProvider.notifier).loadListing(
          collection: widget.collection,
          query: widget.query,
          sort: _sort,
          page: _page,
          limit: widget.pageSize,
          refresh: refresh,
          append: append,
        );
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;

    final resource = ref.read(storeProvider).catalog.listings[_key];
    final page = resource?.value;
    if (page == null || page.page >= page.totalPages) return;

    // The cached slot - not a local counter - is the source of truth for what
    // comes next, so a failed fetch is retried instead of skipping a page.
    _page = page.page + 1;
    _loadingMore = true;
    _load(append: true).whenComplete(() {
      _loadingMore = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final resource = ref.watch(storeProvider.select((s) => s.catalog.listings[_key]));
    _healFlushedSlot(resource);

    return Column(
      children: [
        _SortBar(
          value: _sort,
          total: resource?.value?.total,
          onChanged: (sort) {
            setState(() {
              _sort = sort;
              _page = 1;
            });
            _load(refresh: true);
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () {
              _page = 1;
              return _load(refresh: true);
            },
            child: _body(resource),
          ),
        ),
      ],
    );
  }

  /// Recovers this grid after a store flush wiped its cache slot.
  ///
  /// Never mutates during build: the reload is scheduled for the next frame
  /// and re-reads the slot first, because a public catalogue response that was
  /// already in flight when the flush landed may have refilled it - then there
  /// is nothing left to heal.
  void _healFlushedSlot(Resource<ProductPage>? resource) {
    if (resource != null) {
      _hadSlot = true;
      return;
    }
    if (!_hadSlot) return;
    _hadSlot = false;
    _page = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(storeProvider).catalog.listings[_key] != null) return;
      _load(refresh: true);
    });
  }

  Widget _body(Resource<ProductPage>? resource) {
    if (resource == null || resource.showSkeleton) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            if (widget.header != null) widget.header!,
            const ProductGridSkeleton(count: 6),
          ],
        ),
      );
    }
    if (resource.isError && !resource.hasValue) {
      return ErrorRetry(message: resource.error, onRetry: () => _load(refresh: true));
    }

    final ProductPage? maybePage = resource.value;
    if (maybePage == null) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: ProductGridSkeleton(count: 6),
      );
    }
    final ProductPage page = maybePage;
    if (page.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.header != null) widget.header!,
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nothing here yet',
            subtitle: 'Try a different search or browse another collection.',
          ),
        ],
      );
    }

    // Tile height is derived from the tile width so the card's text block
    // always fits: image (width / imageAspectRatio) + ProductCardTile.textExtent.
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const gap = 12.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final tileWidth = (width - horizontalPadding * 2 - gap) / 2;

        return CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (widget.header != null) SliverToBoxAdapter(child: widget.header!),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: ProductCardTile.heightFor(tileWidth),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => ProductCardTile(product: page.items[i]),
                  childCount: page.items.length,
                ),
              ),
            ),
            if (page.page < page.totalPages)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.value, required this.onChanged, this.total});

  final String value;
  final int? total;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (total != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('$total products', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Sort',
            padding: EdgeInsets.zero,
            onSelected: onChanged,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.sort_rounded, size: 18),
                  const SizedBox(width: 5),
                  Text(
                    kSortOptions.firstWhere((o) => o.$1 == value).$2,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, size: 20),
                ],
              ),
            ),
            itemBuilder: (_) => [
              for (final (key, label) in kSortOptions)
                PopupMenuItem(
                  value: key,
                  child: Row(
                    children: [
                      if (key == value)
                        const Icon(Icons.check_rounded, size: 16, color: AppColors.primary)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(label, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
