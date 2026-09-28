import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../state/store.dart';

/// Bridges the store's `ui.toast` slot to a SnackBar.
///
/// Mounted once around the router; the toast is cleared after display so the
/// same message never re-fires on rebuild.
class ToastListener extends ConsumerStatefulWidget {
  const ToastListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ToastListener> createState() => _ToastListenerState();
}

class _ToastListenerState extends ConsumerState<ToastListener> {
  String? _lastShown;

  @override
  Widget build(BuildContext context) {
    final toast = ref.watch(storeProvider.select((s) => s.ui.toast));
    final isError = ref.watch(storeProvider.select((s) => s.ui.toastIsError));

    if (toast != null && toast != _lastShown) {
      _lastShown = toast;
      // Defer until after this frame so we never ScaffoldMessenger during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(toast, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
              backgroundColor: isError ? AppColors.primaryDark : AppColors.ink,
              duration: const Duration(seconds: 2),
            ),
          );
        ref.read(storeProvider.notifier).clearToast();
      });
    } else if (toast == null) {
      _lastShown = null;
    }

    return widget.child;
  }
}
