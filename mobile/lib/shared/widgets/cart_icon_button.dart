import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../state/store.dart';

/// The live cart count printed as a **bare number** onto an icon.
///
/// Deliberately not Material's `Badge`: the storefront header simply shows the
/// figure riding on the existing glyph - no pill, no coloured dot - so this
/// only draws the digits at the icon's top-right corner and nothing else.
class CountOnIcon extends StatelessWidget {
  const CountOnIcon({super.key, required this.count, required this.child, this.color = AppColors.primary});

  /// Items in the bag; zero (or less) draws the plain icon.
  final int count;

  /// The icon the number sits on.
  final Widget child;

  final Color color;

  String get _label => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -6,
          right: -9,
          child: Text(
            _label,
            textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false),
            style: TextStyle(color: color, fontSize: 10, height: 1, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

/// Shopping-bag action for the top app bar - including the product screen,
/// where the shell's bottom bar is pushed away, so this is the only place the
/// count is visible at the add-to-bag moment.
///
/// Tapping it switches the shell to the Bag tab (the cart is a branch root, so
/// it must be reached with `go`, never `push`).
class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(storeProvider.select((s) => s.cart.itemCount));

    return IconButton(
      tooltip: count > 0 ? 'Bag, $count item${count == 1 ? '' : 's'}' : 'Bag',
      onPressed: () => context.go('/cart'),
      icon: CountOnIcon(count: count, child: const Icon(Icons.shopping_bag_outlined)),
    );
  }
}
