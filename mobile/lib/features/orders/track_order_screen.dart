import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';
import 'order_status.dart';

/// Guest order tracking: order number + the email/phone on the order.
class TrackOrderScreen extends ConsumerStatefulWidget {
  const TrackOrderScreen({super.key, this.initialOrderNumber});

  /// Pre-filled when launched from an existing order's "Track" button.
  final String? initialOrderNumber;

  @override
  ConsumerState<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends ConsumerState<TrackOrderScreen> {
  late final TextEditingController _number = TextEditingController(text: widget.initialOrderNumber ?? '');
  final _contact = TextEditingController();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderNumber != null && widget.initialOrderNumber!.isNotEmpty) {
      _submitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final value = _contact.text.trim();
    final isEmail = value.contains('@');
    await ref.read(storeProvider.notifier).trackOrder(
          orderNumber: _number.text.trim(),
          email: isEmail ? value : null,
          phone: isEmail ? null : value,
        );
    if (mounted) setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(storeProvider.select((s) => s.orders.tracking));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Track your order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order number', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _number,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. BBL-20250624-1001'),
                ),
                const SizedBox(height: 14),
                const Text('Email or phone on the order', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _contact,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'you@example.com or 98xxxxxxxx'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Track order'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (tracking.showSkeleton)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (tracking.isError && !tracking.hasValue)
            ErrorRetry(message: tracking.error, onRetry: _search)
          else if (tracking.isSuccess && tracking.hasValue)
            _TrackingCard(order: tracking.value!)
          else if (tracking.isError || _submitted)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Order not found',
              subtitle: 'Check the order number and the contact details you entered.',
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                'Enter your order number from the confirmation email along with the email or phone used at checkout.',
                style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(order.orderNumber, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
              StatusChip(status: order.status, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(MoneyFormat.rupees(order.total), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 16),
          OrderTimeline(order: order),
          const Divider(height: 26),
          Text(
            [
              order.address.line1,
              if (order.address.line2.isNotEmpty) order.address.line2,
              order.address.city,
              order.address.state,
              order.address.pincode,
            ].where((s) => s.isNotEmpty).join(', '),
            style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/order/${order.id}'),
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: const Text('View full order'),
          ),
        ],
      ),
    );
  }
}
