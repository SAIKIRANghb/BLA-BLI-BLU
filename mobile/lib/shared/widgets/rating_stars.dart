import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// Compact star row + numeric rating (e.g. `4.8 (1148)`).
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.count, this.size = 14, this.showCount = true});

  final double rating;
  final int? count;
  final double size;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i - 0.25 ? Icons.star_rounded : (rating >= i - 0.75 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: AppColors.star,
          ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            showCount && count != null ? '${rating.toStringAsFixed(1)} ($count)' : rating.toStringAsFixed(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: size * 0.85, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
