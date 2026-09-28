import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/store.dart';

/// Shopping-bag action for the top app bar.
///
/// Mirrors the storefront header cart: the icon itself carries the live item
/// count as a pill badge, and tapping it switches the shell to the Bag tab
/// (the cart is a branch root, so it must be reached with `go`, never `push`).
class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(storeProvider.select((s) => s.cart.itemCount));

    return IconButton(
      tooltip: count > 0 ? 'Bag, $count item${count == 1 ? '' : 's'}' : 'Bag',
      onPressed: () => context.go('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}
