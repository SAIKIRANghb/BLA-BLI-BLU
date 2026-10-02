import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';
import 'order_status.dart';

/// Full order detail: status timeline, items, address, payment and totals.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).loadOrder(widget.orderId));
  }

  @override
  Widget build(BuildContext context) {
    // Watch the slice so the screen rebuilds as the fetch progresses.
    final raw = ref.watch(storeProvider.select((s) => s.orders.detail));
    final Resource<Order> resource = (raw.hasValue && raw.value!.id != widget.orderId)
        ? (raw.isLoading ? const Resource<Order>() : Resource<Order>(status: raw.status))
        : raw;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Order details'),
        actions: [
          IconButton(
            tooltip: 'Track',
            icon: const Icon(Icons.location_on_outlined),
            onPressed: () => context.push('/track'),
          ),
        ],
      ),
      body: _body(resource),
    );
  }

  Widget _body(Resource<Order> resource) {
    if (resource.showSkeleton || (!resource.hasValue && !resource.isError)) {
      return const SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              SkeletonBox(width: double.infinity, height: 90),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 220),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 160),
            ],
          ),
        ),
      );
    }
    if (resource.isError && !resource.hasValue) {
      return ErrorRetry(message: resource.error, onRetry: () => ref.read(storeProvider.notifier).loadOrder(widget.orderId));
    }

    final Order order = resource.value!;

    return RefreshIndicator(
      onRefresh: () => ref.read(storeProvider.notifier).loadOrder(widget.orderId),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.orderNumber, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
                          const SizedBox(height: 3),
                          Text(_date(order.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    StatusChip(status: order.status),
                  ],
                ),
                const Divider(height: 26),
                OrderTimeline(order: order),
              ],
            ),
          ),
          _card(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final item in order.items) _ItemRow(item: item),
            ],
          ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(order.address.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  [order.address.line1, order.address.line2, order.address.city, order.address.state, order.address.pincode]
                      .where((s) => s.isNotEmpty)
                      .join(', '),
                  style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
                ),
                if (order.address.phone.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Ph ${order.address.phone}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
                if (order.address.hasPin) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/order/${order.id}/live'),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Live delivery map'),
                  ),
                ],
              ],
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Payment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900))),
                    StatusChip(status: order.paymentStatus == 'paid' ? 'delivered' : 'placed', dense: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${order.paymentMethod.toUpperCase()} · ${order.paymentStatus == 'paid' ? 'Paid' : 'Due on delivery'}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const Divider(height: 24),
                _row('Subtotal', MoneyFormat.rupees(order.subtotal)),
                if (order.discount > 0)
                  _row('Discount (${order.couponCode ?? ''})', '- ${MoneyFormat.rupees(order.discount)}', color: AppColors.success),
                _row('Shipping', order.shipping == 0 ? 'FREE' : MoneyFormat.rupees(order.shipping)),
                const Divider(height: 20),
                _row('Total', MoneyFormat.rupees(order.total), bold: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/faq'),
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: const Text('Need help with this order?'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: child,
      );

  Widget _row(String label, String value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: bold ? AppColors.ink : AppColors.muted))),
            Text(value, style: TextStyle(fontSize: bold ? 17 : 13.5, fontWeight: FontWeight.w900, color: color ?? AppColors.ink)),
          ],
        ),
      );

  String _date(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Placed on ${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedImage(item.imageUrl, width: 52, height: 60),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3)),
                if (item.variantTitle != null && item.variantTitle != 'Default Title')
                  Text(item.variantTitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 4),
                Text('Qty ${item.quantity} · ${MoneyFormat.rupees(item.unitPrice)} each', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Text(MoneyFormat.rupees(item.total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
