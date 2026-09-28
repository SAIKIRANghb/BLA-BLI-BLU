import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';

/// Price with a struck-through compare-at price + discount pill, exactly like
/// the storefront cards. Amounts arrive in paise (integer money).
class PriceText extends StatelessWidget {
  const PriceText(
    this.price, {
    super.key,
    this.compareAtPrice,
    this.discountPercent = 0,
    this.fontSize = 15,
    this.showDiscount = true,
  });

  final int price;
  final int? compareAtPrice;
  final int discountPercent;
  final double fontSize;
  final bool showDiscount;

  /// Builds a [PriceText] straight from a catalogue card.
  static PriceText fromProduct(ProductCard product, {Key? key, double fontSize = 15}) => PriceText(
        product.price,
        key: key,
        compareAtPrice: product.compareAtPrice,
        discountPercent: product.discountPercent,
        fontSize: fontSize,
      );

  bool get _hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          MoneyFormat.rupees(price),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: AppColors.ink),
        ),
        if (_hasDiscount)
          Text(
            MoneyFormat.rupees(compareAtPrice!),
            style: TextStyle(
              fontSize: fontSize * 0.85,
              color: AppColors.muted,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.muted,
            ),
          ),
        if (showDiscount && _hasDiscount && discountPercent > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$discountPercent% OFF',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success, letterSpacing: 0.3),
            ),
          ),
      ],
    );
  }
}
