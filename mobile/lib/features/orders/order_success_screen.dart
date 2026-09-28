import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../state/store.dart';

/// Post-checkout confirmation: ticks the confirmation animation, echoes the
/// order number and offers the two next steps (view / keep shopping).
class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storeProvider);
    final Order? placed = state.orders.lastPlaced?.id == orderId ? state.orders.lastPlaced : state.orders.detail.value;
    final Order? order = placed?.id == orderId ? placed : null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              const _Tick(),
              const SizedBox(height: 26),
              const Text(
                'Thank you for your order!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6),
              ),
              const SizedBox(height: 10),
              Text(
                order == null
                    ? 'Your order has been placed successfully. We have emailed you a confirmation.'
                    : 'Order ${order.orderNumber} is confirmed. We will notify you at every step until it arrives.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, color: AppColors.muted, height: 1.55),
              ),
              if (order != null) ...[
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: [
                      _row('Order number', order.orderNumber),
                      const SizedBox(height: 6),
                      _row('Payment', order.paymentMethod == 'cod' ? 'Cash on delivery' : order.paymentMethod.toUpperCase()),
                      const SizedBox(height: 6),
                      _row('Total paid', MoneyFormat.rupees(order.total)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (order != null)
                FilledButton(
                  onPressed: () => context.go('/order/$orderId'),
                  child: const Text('View order details'),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Continue shopping'),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
          Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ],
      );
}

class _Tick extends StatefulWidget {
  const _Tick();

  @override
  State<_Tick> createState() => _TickState();
}

class _TickState extends State<_Tick> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 58, color: AppColors.success),
      ),
    );
  }
}
