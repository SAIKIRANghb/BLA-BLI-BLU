import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// Checkout: delivery address -> payment method -> order summary -> place.
///
/// The route is auth-guarded by the router, so a token is always present
/// here and the saved-address book can be loaded.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  // New-address form fields (used when no saved address is picked).
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _email = TextEditingController();

  String? _addressId;
  String _payment = 'cod';
  bool _savingAddress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(storeProvider.notifier);
      store.loadAddresses();
      store.refreshCart();
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _line1, _line2, _city, _state, _pincode, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Address? _selected(List<Address> addresses) =>
      addresses.cast<Address?>().firstWhere((a) => a?.id == _addressId, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(storeProvider.select((s) => s.cart.cart.value));
    final busy = ref.watch(storeProvider.select((s) => s.cart.busy));
    final addressesRes = ref.watch(storeProvider.select((s) => s.orders.addresses));
    final user = ref.watch(storeProvider.select((s) => s.auth.user));

    if (_name.text.isEmpty && user != null) _name.text = user.name;
    if (_email.text.isEmpty && user != null) _email.text = user.email;

    final addresses = addressesRes.value ?? const <Address>[];
    if (_addressId == null && addresses.isNotEmpty) {
      _addressId = (addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first)).id;
    }
    final selected = _selected(addresses);

    if (cart == null || cart.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Checkout')),
        body: EmptyState(
          icon: Icons.shopping_bag_outlined,
          title: 'Nothing to check out',
          subtitle: 'Your bag is empty.',
          actionLabel: 'Back to shop',
          onAction: () => context.go('/shop'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Checkout')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _SectionCard(
              title: 'Deliver to',
              trailing: addresses.isEmpty ? null : TextButton(onPressed: () => setState(() => _addressId = null), child: const Text('New address')),
              child: addresses.isEmpty || _addressId == null
                  ? _addressForm()
                  : _AddressPicker(
                      addresses: addresses,
                      selected: selected,
                      onSelect: (id) => setState(() => _addressId = id),
                      onEdit: () => context.push('/addresses'),
                    ),
            ),
            _SectionCard(
              title: 'Payment method',
              child: Column(
                children: [
                  _PayOption(
                    value: 'cod',
                    group: _payment,
                    title: 'Cash on Delivery',
                    subtitle: 'Pay when your order arrives',
                    icon: Icons.payments_outlined,
                    onChanged: (v) => setState(() => _payment = v),
                  ),
                  const SizedBox(height: 8),
                  _PayOption(
                    value: 'upi',
                    group: _payment,
                    title: 'UPI / Online payment',
                    subtitle: 'GPay, PhonePe, cards & net banking',
                    icon: Icons.account_balance_wallet_outlined,
                    onChanged: (v) => setState(() => _payment = v),
                  ),
                ],
              ),
            ),
            _SectionCard(
              title: 'Order summary',
              child: Column(
                children: [
                  for (final line in cart.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedImage(line.imageUrl, width: 44, height: 52),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                Text('Qty ${line.quantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          Text(MoneyFormat.rupees(line.lineTotal), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  _row('Subtotal', MoneyFormat.rupees(cart.totals.subtotal)),
                  if (cart.totals.discount > 0)
                    _row('Discount (${cart.totals.couponCode ?? ''})', '- ${MoneyFormat.rupees(cart.totals.discount)}', color: AppColors.success),
                  _row('Shipping', cart.totals.shipping == 0 ? 'FREE' : MoneyFormat.rupees(cart.totals.shipping)),
                  const Divider(height: 20),
                  _row('Total payable', MoneyFormat.rupees(cart.totals.total), bold: true),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton(
          onPressed: busy ? null : () => _place(cart, selected),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : Text('Place order · ${MoneyFormat.rupees(cart.totals.total)}'),
        ),
      ),
    );
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _place(Cart cart, Address? address) async {
    final store = ref.read(storeProvider.notifier);

    // Collect / persist the address first when the inline form is in use.
    ShippingAddress shipping;
    if (address != null) {
      shipping = address.toShipping(_name.text.trim().isEmpty ? 'Customer' : _name.text.trim());
    } else {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      setState(() => _savingAddress = true);
      final saved = await store.saveAddress(fields: {
        'label': 'Home',
        'line1': _line1.text.trim(),
        'line2': _line2.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'phone': _phone.text.trim(),
      });
      setState(() => _savingAddress = false);
      if (saved == null) return;
      _addressId = saved.id;
      shipping = saved.toShipping(_name.text.trim());
    }

    final order = await store.placeOrder(
      address: shipping,
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      name: shipping.name,
      paymentMethod: _payment,
    );

    if (order == null) return;
    if (!mounted) return;
    context.go('/order-success/${order.id}');
  }

  // ── pieces ───────────────────────────────────────────────────────────────

  Widget _addressForm() {
    return Column(
      children: [
        _field(_name, 'Full name', icon: Icons.person_outline_rounded),
        _field(_phone, 'Phone number', icon: Icons.phone_outlined, keyboard: TextInputType.phone, validator: (v) {
          final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
          if (digits.length < 10) return 'Enter a valid phone number';
          return null;
        }),
        _field(_email, 'Email (for order updates)', icon: Icons.mail_outline_rounded, keyboard: TextInputType.emailAddress),
        _field(_line1, 'Address line 1', icon: Icons.home_outlined, validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        _field(_line2, 'Address line 2 (optional)', icon: Icons.apartment_outlined),
        Row(
          children: [
            Expanded(child: _field(_city, 'City', validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null)),
            const SizedBox(width: 10),
            Expanded(child: _field(_state, 'State', validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null)),
          ],
        ),
        _field(_pincode, 'PIN code', keyboard: TextInputType.number, validator: (v) {
          if (!RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())) return '6 digits';
          return null;
        }),
        if (_savingAddress)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData icon = Icons.edit_outlined,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          validator: validator,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19)),
        ),
      );

  Widget _row(String label, String value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: bold ? AppColors.ink : AppColors.muted)),
            ),
            Text(value, style: TextStyle(fontSize: bold ? 17 : 13.5, fontWeight: FontWeight.w900, color: color ?? AppColors.ink)),
          ],
        ),
      );
}

// ───────────────────────────────── sub widgets ───────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AddressPicker extends StatelessWidget {
  const _AddressPicker({
    required this.addresses,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final List<Address> addresses;
  final Address? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final address in addresses)
          InkWell(
            onTap: () => onSelect(address.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected?.id == address.id ? AppColors.primary.withValues(alpha: 0.05) : AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected?.id == address.id ? AppColors.primary : AppColors.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected?.id == address.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18,
                    color: selected?.id == address.id ? AppColors.primary : AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(address.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                            if (address.isDefault) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(4)),
                                child: const Text('DEFAULT', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [address.line1, address.line2, address.city, address.state, address.pincode].where((s) => s.isNotEmpty).join(', '),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                        ),
                        Text('Ph ${address.phone}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Manage addresses',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    onPressed: onEdit,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.value,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  final String value;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value == group;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.05) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.primary : AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: active ? AppColors.primary : AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(
              active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: active ? AppColors.primary : AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
