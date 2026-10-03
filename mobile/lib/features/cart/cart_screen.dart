import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// "Bag" tab: line items with quantity steppers, coupon field and the
/// running totals that feed checkout.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _couponController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).ensureCart());
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The bag tab stays alive across a logout: flush the coupon the previous
    // user typed along with the rest of the store.
    ref.listen(storeProvider.select((s) => s.auth.isAuthenticated), (previous, next) {
      if (previous == true && next == false) _couponController.clear();
    });

    final cartRes = ref.watch(storeProvider.select((s) => s.cart.cart));
    final busy = ref.watch(storeProvider.select((s) => s.cart.busy));
    final cart = cartRes.value;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 16,
        title: const Text('My Bag'),
        actions: [
          if (cart != null && cart.items.isNotEmpty)
            TextButton(
              onPressed: busy ? null : _confirmClear,
              child: const Text('Clear', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: _body(context, cartRes, busy),
      bottomNavigationBar: cart == null || cart.items.isEmpty
          ? null
          : _SummaryBar(cart: cart, busy: busy),
    );
  }

  Widget _body(BuildContext context, Resource<Cart>? cartRes, bool busy) {
    if (cartRes == null || cartRes.showSkeleton) {
      return const ListSkeleton(rows: 3, height: 96);
    }
    if (cartRes.isError && !cartRes.hasValue) {
      return ErrorRetry(message: cartRes.error, onRetry: () => ref.read(storeProvider.notifier).refreshCart());
    }

    final Cart? cart = cartRes.value;
    if (cart == null) {
      return const ListSkeleton(rows: 3, height: 96);
    }
    if (cart.items.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Your bag is empty',
        subtitle: 'Explore our fragrances and add something you love.',
        actionLabel: 'Start shopping',
        onAction: () => context.go('/shop'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(storeProvider.notifier).refreshCart(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final line in cart.items)
            _CartLineTile(
              line: line,
              busy: busy,
              onQty: (qty) => ref.read(storeProvider.notifier).setLineQuantity(line.id, qty),
              onOpen: () => context.push('/product/${line.handle}'),
            ),
          _CouponField(
            controller: _couponController,
            applied: cart.couponCode,
            busy: busy,
            onApply: () async {
              final code = _couponController.text.trim();
              if (code.isEmpty) return;
              final ok = await ref.read(storeProvider.notifier).applyCoupon(code);
              if (ok && mounted) _couponController.clear();
            },
            onRemove: () => ref.read(storeProvider.notifier).removeCoupon(),
          ),
          _Totals(cart: cart),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final store = ref.read(storeProvider.notifier);
    final lines = ref.read(storeProvider).cart.cart.value?.items ?? const <CartLine>[];
    for (final line in lines) {
      await store.setLineQuantity(line.id, 0);
    }
  }
}

// ────────────────────────────────── line tile ────────────────────────────────

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.busy,
    required this.onQty,
    required this.onOpen,
  });

  final CartLine line;
  final bool busy;
  final ValueChanged<int> onQty;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(10),
            child: CachedImage(line.imageUrl, width: 78, height: 92, radius: 10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                  if (line.variantTitle != null && line.variantTitle != 'Default Title') ...[
                    const SizedBox(height: 2),
                    Text(line.variantTitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PriceText(line.lineTotal, fontSize: 14.5),
                            if (line.quantity > 1)
                              Text(
                                '${line.quantity} × ${MoneyFormat.rupees(line.unitPrice)}',
                                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                              ),
                          ],
                        ),
                      ),
                      QtyStepper(
                        value: line.quantity,
                        compact: true,
                        busy: busy,
                        onChanged: onQty,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────── coupon ───────────────────────────────────

class _CouponField extends StatelessWidget {
  const _CouponField({
    required this.controller,
    required this.applied,
    required this.busy,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final String? applied;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Coupon code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          if (applied != null && applied!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(applied!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    onPressed: busy ? null : onRemove,
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'WELCOME10, FLAT100, FREESHIP'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: busy ? null : onApply,
                    style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────── totals ───────────────────────────────────

class _Totals extends StatelessWidget {
  const _Totals({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final totals = cart.totals;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _row('Subtotal', MoneyFormat.rupees(totals.subtotal)),
          if (totals.discount > 0) _row('Discount', '- ${MoneyFormat.rupees(totals.discount)}', color: AppColors.success),
          _row(
            'Shipping',
            totals.shipping == 0 ? 'FREE' : MoneyFormat.rupees(totals.shipping),
            color: totals.shipping == 0 ? AppColors.success : null,
          ),
          const Divider(height: 20),
          _row('Total', MoneyFormat.rupees(totals.total), bold: true),
          if (totals.savings > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'You save ${MoneyFormat.rupees(totals.savings)} on this order',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 15 : 13.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: bold ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 17 : 13.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: color ?? (bold ? AppColors.ink : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────── summary bar ────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.cart, required this.busy});

  final Cart cart;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text(
                    MoneyFormat.rupees(cart.totals.total),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 172,
              child: FilledButton(
                onPressed: busy ? null : () => context.push('/checkout'),
                child: const Text('Checkout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
