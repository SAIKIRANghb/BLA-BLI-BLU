import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import 'cached_image.dart';
import 'price_text.dart';
import 'rating_stars.dart';

/// Grid/list card: image, badge, title, notes, rating, price.
class ProductCardTile extends StatelessWidget {
  const ProductCardTile({super.key, required this.product, this.onTap});

  final ProductCard product;
  final VoidCallback? onTap;

  static const double imageAspectRatio = 0.86;

  /// Vertical room the block under the image needs: title (2 lines), notes,
  /// rating, price and its padding. Grids and horizontal strips size their
  /// tiles with [heightFor] so a card never has to clip away its own price.
  static const double textExtent = 136;

  /// Total height of a card that is [width] wide.
  static double heightFor(double width) => width / imageAspectRatio + textExtent;

  void _open(BuildContext context) {
    if (onTap != null) {
      onTap!();
    } else {
      context.push('/product/${product.handle}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: imageAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedImage(product.imageUrl),
                  if (product.badge != null && product.badge!.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Badge(label: product.badge!),
                    ),
                  if (!product.available)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.72),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(6)),
                          child: const Text('SOLD OUT',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    if (product.notesSummary.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        product.notesSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                    const Spacer(),
                    if (product.rating > 0) ...[
                      RatingStars(rating: product.rating, count: product.ratingCount, size: 13),
                      const SizedBox(height: 4),
                    ],
                    PriceText.fromProduct(product, fontSize: 14.5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(5)),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      );
}
