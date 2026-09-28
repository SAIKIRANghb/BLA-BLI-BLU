import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'shared/widgets/toast_listener.dart';

/// Application entry point.
///
/// Wiring, top to bottom:
///   ProviderScope  - Riverpod container; the Redux-style [Store] lives here
///   MaterialApp.router - Material 3 theme + go_router routes
///   ToastListener  - bridges the store's `ui.toast` slot to a SnackBar
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: BlablibluApp()));
}

class BlablibluApp extends ConsumerWidget {
  const BlablibluApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The provider has no watched dependencies, so its value (and therefore
    // the whole route table) is created exactly once for the app's lifetime.
    final router = ref.watch(routerProvider);

    return ToastListener(
      child: MaterialApp.router(
        title: 'Bla Bli Blu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }
}
