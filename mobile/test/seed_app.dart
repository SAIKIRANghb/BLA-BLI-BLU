import 'package:blabliblu/core/network/api_client.dart';
import 'package:blabliblu/main.dart';
import 'package:blabliblu/state/store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pumps the app wired to the offline [SeedApi], whatever `kUseLocalSeed`
/// says in `app_config.dart`.
///
/// Production boots live (`kUseLocalSeed = false`), but widget tests must
/// never open a socket: overriding [apiProvider] keeps every screen on the
/// bundled seed data and the suite backend-free.
ProviderScope seedApp() => ProviderScope(
      overrides: [apiProvider.overrideWithValue(SeedApi())],
      child: const BlablibluApp(),
    );
