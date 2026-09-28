import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// Saved address book: list, add/edit form, delete.
class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});

  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).loadAddresses());
  }

  @override
  Widget build(BuildContext context) {
    final addressesRes = ref.watch(storeProvider.select((s) => s.orders.addresses));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Saved addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add address'),
      ),
      body: _body(addressesRes),
    );
  }

  Widget _body(Resource<List<Address>> res) {
    if (res.showSkeleton) return const ListSkeleton(rows: 3, height: 110);
    if (res.isError && !res.hasValue) {
      return ErrorRetry(message: res.error, onRetry: () => ref.read(storeProvider.notifier).loadAddresses());
    }

    final addresses = res.value ?? const <Address>[];
    if (addresses.isEmpty) {
      return EmptyState(
        icon: Icons.location_on_outlined,
        title: 'No saved addresses',
        subtitle: 'Add a delivery address once and it will be ready at every checkout.',
        actionLabel: 'Add address',
        onAction: () => _openEditor(null),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      itemCount: addresses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _AddressCard(
        address: addresses[i],
        onEdit: () => _openEditor(addresses[i]),
        onDelete: () => _confirmDelete(addresses[i]),
      ),
    );
  }

  Future<void> _openEditor(Address? existing) async {
    final saved = await showDialog<Address?>(
      context: context,
      builder: (_) => _AddressDialog(existing: existing),
    );
    if (saved == null) return;
    await ref.read(storeProvider.notifier).saveAddress(
          existing: existing,
          fields: {
            'label': saved.label,
            'line1': saved.line1,
            'line2': saved.line2,
            'city': saved.city,
            'state': saved.state,
            'pincode': saved.pincode,
            'phone': saved.phone,
          },
        );
  }

  Future<void> _confirmDelete(Address address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text('${address.line1}, ${address.city} will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(storeProvider.notifier).deleteAddress(address.id);
  }
}

// ─────────────────────────────────── card ────────────────────────────────────

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onEdit, required this.onDelete});

  final Address address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(address.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              if (address.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(4)),
                  child: const Text('DEFAULT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ],
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.primary),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [address.line1, if (address.line2.isNotEmpty) address.line2].join(', '),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 3),
          Text(
            '${address.city}, ${address.state} - ${address.pincode}',
            style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 3),
          Text('Ph ${address.phone}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      ),
    );
  }
}

// ────────────────────────────────── dialog ───────────────────────────────────

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({this.existing});
  final Address? existing;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label = TextEditingController(text: widget.existing?.label ?? 'Home');
  late final TextEditingController _line1 = TextEditingController(text: widget.existing?.line1 ?? '');
  late final TextEditingController _line2 = TextEditingController(text: widget.existing?.line2 ?? '');
  late final TextEditingController _city = TextEditingController(text: widget.existing?.city ?? '');
  late final TextEditingController _state = TextEditingController(text: widget.existing?.state ?? '');
  late final TextEditingController _pincode = TextEditingController(text: widget.existing?.pincode ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.existing?.phone ?? '');

  @override
  void dispose() {
    for (final c in [_label, _line1, _line2, _city, _state, _pincode, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add address' : 'Edit address'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Label (Home, Office...)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _line1,
                  decoration: const InputDecoration(labelText: 'Address line 1'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _line2,
                  decoration: const InputDecoration(labelText: 'Address line 2 (optional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _city,
                        decoration: const InputDecoration(labelText: 'City'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _state,
                        decoration: const InputDecoration(labelText: 'State'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _pincode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN code'),
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : '6 digits',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length >= 10 ? null : 'Enter a valid phone number';
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      Address(
        id: widget.existing?.id ?? '',
        label: _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
        line1: _line1.text.trim(),
        line2: _line2.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        pincode: _pincode.text.trim(),
        phone: _phone.text.trim(),
        isDefault: widget.existing?.isDefault ?? false,
      ),
    );
  }
}
