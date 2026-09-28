import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';
import 'product_listing.dart';

/// "Shop" tab - collection tiles on top, the full catalogue grid below.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(storeProvider.select((s) => s.catalog.collections));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          const CartIconButton(),
          IconButton(
            tooltip: 'Track order',
            icon: const Icon(Icons.location_on_outlined),
            onPressed: () => context.push('/track'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (collections.showSkeleton)
            const SizedBox(height: 96, child: SkeletonBox(radius: 0))
          else if (collections.hasValue)
            _CollectionRail(tiles: collections.value ?? const []),
          Expanded(
            child: ProductListingView(
              collection: null,
              header: const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('All products', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionRail extends StatelessWidget {
  const _CollectionRail({required this.tiles});
  final List<CollectionTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final tile = tiles[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/collection/${tile.handle}'),
            child: SizedBox(
              width: 96,
              child: Column(
                children: [
                  Expanded(
                    child: Hero(
                      tag: 'collection-${tile.handle}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedImage(tile.imageUrl, width: 96, height: double.infinity),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tile.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
