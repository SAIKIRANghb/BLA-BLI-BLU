import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import 'product_card.dart';

/// Shimmer-ish placeholder used while a [Resource] is on its first load.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 10});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value, 0),
              end: Alignment(1 - 2 * _c.value, 0),
              colors: const [Color(0xFFEDEDED), Color(0xFFF7F7F7), Color(0xFFEDEDED)],
            ),
          ),
        ),
      );
}

/// Skeleton grid matching [ProductCardTile]'s proportions.
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          const padding = 16.0;
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final tileWidth = (width - padding * 2 - gap) / 2;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: ProductCardTile.heightFor(tileWidth),
            ),
            itemCount: count,
            itemBuilder: (_, __) => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SkeletonBox(radius: 14)),
                SizedBox(height: 8),
                SkeletonBox(width: 130, height: 12),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 12),
              ],
            ),
          );
        },
      );
}

/// Line-style skeleton for lists (orders, reviews, addresses).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 5, this.height = 76});

  final int rows;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SkeletonBox(width: double.infinity, height: height),
            ),
        ],
      );
}

/// Full-width banner skeleton used by the home hero.
class BannerSkeleton extends StatelessWidget {
  const BannerSkeleton({super.key, this.height = 220});

  final double height;

  @override
  Widget build(BuildContext context) => SkeletonBox(width: double.infinity, height: height, radius: 0);
}

/// Inline error + retry, shared by every list/detail screen.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                message ?? 'Something went wrong',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: AppColors.muted, height: 1.4),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
