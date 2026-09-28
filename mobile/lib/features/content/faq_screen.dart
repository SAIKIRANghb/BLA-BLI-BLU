import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// All FAQs grouped by category with a local filter field.
class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  final _filter = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).loadFaqs());
    _filter.addListener(() => setState(() => _query = _filter.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faqsRes = ref.watch(storeProvider.select((s) => s.content.faqs));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('FAQs'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                hintText: 'Search a question...',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(child: _body(faqsRes)),
        ],
      ),
    );
  }

  Widget _body(Resource<List<FaqGroup>> res) {
    if (res.showSkeleton) return const ListSkeleton(rows: 6, height: 54);
    if (res.isError && !res.hasValue) {
      return ErrorRetry(message: res.error, onRetry: () => ref.read(storeProvider.notifier).loadFaqs());
    }

    final groups = res.value ?? const <FaqGroup>[];
    if (groups.isEmpty) {
      return const EmptyState(icon: Icons.help_outline_rounded, title: 'No FAQs yet', subtitle: 'Check back soon.');
    }

    // Apply the local filter across every group.
    final filtered = <FaqGroup>[
      for (final group in groups)
        if (_query.isEmpty)
          group
        else
          FaqGroup(
            category: group.category,
            items: group.items
                .where((i) => i.question.toLowerCase().contains(_query) || i.answer.toLowerCase().contains(_query))
                .toList(),
          ),
    ].where((g) => g.items.isNotEmpty).toList();

    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching question',
        subtitle: 'Try different words, or contact our support team.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        for (final group in filtered) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(
              group.category.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: AppColors.primary),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  for (final item in group.items)
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      title: Text(item.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(item.answer, style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.6)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
