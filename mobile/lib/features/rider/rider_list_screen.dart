import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// The rider's queue: active deliveries that carry a map pin.
///
/// Reads `GET /api/tracking/deliveries` through the store (the rider key is
/// baked into the API client), so the list shows what is actually on the
/// road right now - in seed mode that means orders placed in this session,
/// which the empty state spells out.
class RiderListScreen extends ConsumerStatefulWidget {
  const RiderListScreen({super.key});

  @override
  ConsumerState<RiderListScreen> createState() => _RiderListScreenState();
}

class _RiderListScreenState extends ConsumerState<RiderListScreen> {
  late final Store _store;

  /// `null` = still loading / unknown; `[]` = genuinely empty.
  List<DeliveryJob>? _jobs;
  bool _failed = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _store = ref.read(storeProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _refreshing = true);
    final jobs = await _store.activeDeliveries();
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _failed = jobs == null;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 16,
        title: const Text('Rider queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : _load,
          ),
        ],
      ),
      body: _body(jobs),
    );
  }

  Widget _body(List<DeliveryJob>? jobs) {
    if (jobs == null && _failed) {
      return ErrorRetry(message: 'Could not load the rider queue', onRetry: _load);
    }
    if (jobs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (jobs.isEmpty && _refreshing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (jobs.isEmpty) {
      return EmptyState(
        icon: Icons.delivery_dining_outlined,
        title: 'No active deliveries',
        subtitle: kUseLocalSeed
            ? 'Seed mode has no preset orders - check out a bag with a delivery pin and it will appear here.'
            : 'New orders with a delivery pin land here as soon as they are placed. Pull to refresh.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _jobTile(context, jobs[index]),
      ),
    );
  }

  Widget _jobTile(BuildContext context, DeliveryJob job) {
    final address = job.address;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/rider/${job.id}', extra: job),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delivery_dining, size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            job.orderNumber,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(job.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address.name.isNotEmpty ? address.name : address.singleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.hasPin
                          ? 'Drop pin ${address.lat!.toStringAsFixed(4)}, ${address.lng!.toStringAsFixed(4)}'
                          : 'No delivery pin set',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final label = status.isEmpty ? 'active' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.ink),
      ),
    );
  }
}
