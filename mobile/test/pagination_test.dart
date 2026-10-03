import 'package:blabliblu/core/models/models.dart';
import 'package:blabliblu/core/network/api_client.dart';
import 'package:blabliblu/state/actions.dart';
import 'package:blabliblu/state/resource.dart';
import 'package:blabliblu/state/store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for grid pagination.
///
/// The listing slot used to be keyed *per page*, so fetching page 2 replaced
/// page 1 in the watched slot: scrolling made products disappear instead of
/// appending. The slot is now keyed per query and pages accumulate into it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every fetched page accumulates into one query slot', () async {
    SharedPreferences.setMockInitialValues({});
    // Production boots live; the test container reads the same apiProvider,
    // so pin it to the offline seed.
    final container = ProviderContainer(overrides: [apiProvider.overrideWithValue(SeedApi())]);
    addTearDown(container.dispose);
    final store = container.read(storeProvider.notifier);
    final key = listingKey();
    Resource<ProductPage>? slot() => container.read(storeProvider).catalog.listings[key];

    await store.loadListing(limit: 24, refresh: true);
    final first = slot()?.value;
    expect(first, isNotNull, reason: 'page 1 must land in the slot');
    expect(first!.page, 1);
    expect(first.items.length, 24);
    expect(first.totalPages, greaterThan(1), reason: 'the seed catalogue spans several pages');

    // The scroll handler asks for page 2 with `append: true`.
    await store.loadListing(limit: 24, page: 2, append: true);
    final merged = slot()?.value;
    expect(merged, isNotNull);
    expect(merged!.page, 2);
    expect(merged.total, first.total, reason: 'the reported total is unchanged');
    expect(merged.items.length, 48, reason: 'page 2 appends instead of replacing page 1');

    final handles = merged.items.map((p) => p.handle).toList();
    expect(handles.toSet().length, handles.length, reason: 'no duplicated tiles across pages');
    expect(handles.take(24).toList(), first.items.map((p) => p.handle).toList(), reason: 'page 1 keeps its order at the top');

    // A plain re-request of a warm slot short-circuits - no reload churn.
    final warm = slot();
    await store.loadListing(limit: 24);
    expect(identical(warm, slot()), isTrue, reason: 'a cached query is not refetched');

    // A refresh (pull-to-refresh / sort change) starts the accumulation over.
    await store.loadListing(limit: 24, refresh: true);
    final reset = slot()?.value;
    expect(reset!.page, 1);
    expect(reset.items.length, 24, reason: 'refresh drops the appended pages');
  });
}
