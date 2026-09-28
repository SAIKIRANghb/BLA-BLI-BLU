import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';
import 'product_listing.dart';

/// A single collection page: hero header + the shared listing grid.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.handle});

  final String handle;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(storeProvider.notifier);
      store.loadCollections();
      store.loadListing(collection: widget.handle, refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(storeProvider.select((s) => s.catalog.collections));
    final CollectionTile? tile =
        (collections.value ?? const <CollectionTile>[]).cast<CollectionTile?>().firstWhere((c) => c?.handle == widget.handle, orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(tile?.title ?? 'Collection'),
        backgroundColor: AppColors.surface,
        actions: const [CartIconButton()],
      ),
      body: ProductListingView(
        collection: widget.handle,
        header: tile == null ? null : _CollectionHeader(tile: tile),
      ),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.tile});
  final CollectionTile tile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tile.imageUrl != null && tile.imageUrl!.isNotEmpty) ...[
            Hero(
              tag: 'collection-${tile.handle}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: CachedImage(tile.imageUrl, height: 150, width: double.infinity),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (tile.description.isNotEmpty)
            Text(tile.description, style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.5)),
        ],
      ),
    );
  }
}
