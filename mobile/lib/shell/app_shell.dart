import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../state/store.dart';

/// Bottom-navigation shell hosting the five primary tabs.
///
/// The cart tab shows a live badge fed straight from the store's cart slice.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = <_Destination>[
    _Destination('Home', Icons.home_outlined, Icons.home_rounded),
    _Destination('Shop', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _Destination('Search', Icons.search_outlined, Icons.search_rounded),
    _Destination('Bag', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
    _Destination('Account', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  void _go(int index) {
    // Tabs are branch roots: `goBranch` swaps the stack instead of pushing.
    // Re-tapping the active tab pops it back to that branch's root screen.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = ref.watch(storeProvider.select((s) => s.cart.itemCount));

    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          height: 62,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.10),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (var i = 0; i < destinations.length; i++)
              NavigationDestination(
                // The Bag tab wears the live cart count as a pill badge (the
                // label stays a constant "Bag" so it never jitters).
                icon: Badge(
                  isLabelVisible: i == 3 && badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  child: Icon(destinations[i].icon, color: _color(i, shell.currentIndex)),
                ),
                selectedIcon: Badge(
                  isLabelVisible: i == 3 && badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  child: Icon(destinations[i].selectedIcon, color: _color(i, shell.currentIndex)),
                ),
                label: destinations[i].label,
              ),
          ],
        ),
      ),
    );
  }

  static Color _color(int index, int current) =>
      index == current ? AppColors.primary : AppColors.muted;
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
