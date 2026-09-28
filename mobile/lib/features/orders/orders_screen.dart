import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';
import 'order_status.dart';

/// "My Orders" list with status chips, thumbnails and a track shortcut.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).loadOrders());
  }

  @override
  Widget build(BuildContext context) {
    final ordersRes = ref.watch(storeProvider.select((s) => s.orders.list));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('My Orders'),
        actions: [
          IconButton(
            tooltip: 'Track an order',
            icon: const Icon(Icons.location_on_outlined),
            onPressed: () => context.push('/track'),
          ),
        ],
      ),
      body: _body(ordersRes),
    );
  }

  Widget _body(Resource<List<Order>> res) {
    if (res.showSkeleton) return const ListSkeleton(rows: 4, height: 108);
    if (res.isError && !res.hasValue) {
      return ErrorRetry(message: res.error, onRetry: () => ref.read(storeProvider.notifier).loadOrders());
    }

    final orders = res.value ?? const <Order>[];
    if (orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No orders yet',
        subtitle: 'When you place an order it will show up here with live tracking.',
        actionLabel: 'Start shopping',
        onAction: () => context.go('/shop'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(storeProvider.notifier).loadOrders(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: orders.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Text('${orders.length} order${orders.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            );
          }
          return _OrderCard(order: orders[i - 1], onTap: () => context.push('/order/${orders[i - 1].id}'));
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.orderNumber, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
                ),
                StatusChip(status: order.status, dense: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(_placedOn(order.createdAt), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final item in order.items.take(4)) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedImage(item.imageUrl, width: 46, height: 54),
                  ),
                  const SizedBox(width: 6),
                ],
                if (order.items.length > 4)
                  Container(
                    width: 46,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                    child: Text('+${order.items.length - 4}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.muted)),
                  ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(MoneyFormat.rupees(order.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                    Text('${order.items.length} item${order.items.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), textStyle: const TextStyle(fontSize: 13)),
                    child: const Text('View details'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push('/track', extra: order.orderNumber),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), textStyle: const TextStyle(fontSize: 13)),
                    child: const Text('Track'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _placedOn(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return 'Order';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Placed on ${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }
}
