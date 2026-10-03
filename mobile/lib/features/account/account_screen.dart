import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/links.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// "Account" tab: profile header, quick links (orders, addresses, track,
/// FAQ), static content pages and sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(storeProvider.notifier);
      store.loadHome();
      store.loadOrders();
      store.loadAddresses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(storeProvider.select((s) => s.auth.isAuthenticated));
    final user = ref.watch(storeProvider.select((s) => s.auth.user));
    final orderCount = ref.watch(storeProvider.select((s) => s.orders.list.value?.length ?? 0));
    final home = ref.watch(storeProvider.select((s) => s.catalog.home.value));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 16,
        title: const Text('Account'),
        actions: [
          const CartIconButton(),
          IconButton(
            tooltip: 'FAQ',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => context.push('/faq'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: Text(
                    signedIn ? _initials(user?.name ?? 'You') : 'B',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signedIn ? (user?.name ?? 'Welcome back') : 'Welcome to Bla Bli Blu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        signedIn ? (user?.email ?? '') : 'Sign in to track orders and check out faster',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (!signedIn)
                  FilledButton(
                    onPressed: () => context.push('/sign-in'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size(84, 40),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Sign in'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _Group(
            children: [
              _Tile(
                icon: Icons.receipt_long_outlined,
                title: 'My orders',
                subtitle: signedIn ? '$orderCount placed' : 'Sign in to view',
                trailing: Icons.chevron_right_rounded,
                onTap: () => context.push('/orders'),
              ),
              _Tile(
                icon: Icons.location_on_outlined,
                title: 'Saved addresses',
                subtitle: 'Manage delivery locations',
                trailing: Icons.chevron_right_rounded,
                onTap: () => context.push('/addresses'),
              ),
              _Tile(
                icon: Icons.local_shipping_outlined,
                title: 'Track an order',
                subtitle: 'Guest tracking with order number',
                trailing: Icons.chevron_right_rounded,
                onTap: () => context.push('/track'),
              ),
              _Tile(
                icon: Icons.delivery_dining_outlined,
                title: 'Rider queue',
                subtitle: 'Send live GPS for active deliveries',
                trailing: Icons.chevron_right_rounded,
                onTap: () => context.push('/rider'),
              ),
              _Tile(
                icon: Icons.help_outline_rounded,
                title: 'FAQs & support',
                subtitle: 'Shipping, returns and product care',
                trailing: Icons.chevron_right_rounded,
                onTap: () => context.push('/faq'),
              ),
            ],
          ),

          if (signedIn) ...[
            const SizedBox(height: 16),
            _Group(
              children: [
                _Tile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit profile',
                  subtitle: 'Name and phone number',
                  trailing: Icons.chevron_right_rounded,
                  onTap: () => _editProfile(context),
                ),
                _Tile(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  destructive: true,
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),
          ],

          if (home != null && home.footer.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('INFORMATION', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.muted)),
            ),
            const SizedBox(height: 8),
            _Group(
              children: [
                for (final entry in home.footer.entries.take(4))
                  for (final link in entry.value)
                    if ((link['link'] ?? '').startsWith('/pages/'))
                      _Tile(
                        icon: Icons.description_outlined,
                        title: link['title'] ?? entry.key,
                        trailing: Icons.chevron_right_rounded,
                        compact: true,
                        onTap: () => openShopLink(context, link['link']),
                      ),
                _Tile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  trailing: Icons.chevron_right_rounded,
                  compact: true,
                  onTap: () => context.push('/page/privacy-policy'),
                ),
              ],
            ),
          ],

          if (kUseLocalSeed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Center(
                child: Text(
                  'Seed mode ON · data served from assets/seed/seed.json',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This clears the app completely on this device: your session, bag, orders and everything else stored here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = ref.read(storeProvider.notifier);
    // Leave the protected tab *before* the auth flips. Once `signOut` clears
    // the session the router refresh bounces `/account` to the root-level
    // `/sign-in` route, and a second navigation back to `/` landing in the
    // same frame makes the shell's GlobalKey exist twice ("Duplicate GlobalKey"
    // assertion). Navigate first, then flush: the refresh then evaluates
    // against `/`, which is public, and stays put.
    if (context.mounted) context.go('/');
    await store.signOut();
  }

  Future<void> _editProfile(BuildContext context) async {
    final store = ref.read(storeProvider.notifier);
    final user = ref.read(storeProvider).auth.user;
    final name = TextEditingController(text: user?.name ?? '');
    final phone = TextEditingController(text: user?.phone ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(90, 42)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await store.updateProfile(name: name.text.trim(), phone: phone.text.trim());
    }
    name.dispose();
    phone.dispose();
  }
}

// ────────────────────────────────── pieces ───────────────────────────────────

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.destructive = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailing;
  final VoidCallback onTap;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.primary : AppColors.ink;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 9 : 13),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          children: [
            Icon(icon, size: compact ? 18 : 21, color: destructive ? AppColors.primary : AppColors.muted),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: compact ? 13.5 : 14.5, fontWeight: FontWeight.w700, color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (trailing != null) Icon(trailing, size: 20, color: AppColors.muted.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
