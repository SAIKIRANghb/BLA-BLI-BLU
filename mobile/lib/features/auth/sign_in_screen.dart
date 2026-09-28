import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/links.dart';
import '../../core/config/app_config.dart';
import '../../state/store.dart';

/// Email + password sign-in. Honours the `?next=` parameter so the router's
/// auth guard can bounce the user straight back to where they were headed.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await ref.read(storeProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );
    if (!ok || !mounted) return;
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    context.go(next == null || next.isEmpty ? '/' : next);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(storeProvider.select((s) => s.auth.isBusy));
    final error = ref.watch(storeProvider.select((s) => s.auth.request.error));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, leading: BackButton(onPressed: () => goBack(context))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to track orders, save addresses and check out faster.',
                  style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded, size: 19)),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? 'Password must be at least 6 characters' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(error, style: const TextStyle(fontSize: 13, color: AppColors.primaryDark, height: 1.4)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    const Text('New to Bla Bli Blu?', style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
                    TextButton(
                      onPressed: () => context.push('/sign-up'),
                      child: const Text('Create an account', style: TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Testing without a backend? Enable the seed flag in app_config.dart.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
