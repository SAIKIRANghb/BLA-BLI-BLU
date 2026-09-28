import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/resource.dart';
import '../../state/store.dart';

/// Static content viewer (about, policies, contact...).
///
/// Body text arrives as plain paragraphs separated by blank lines, so it is
/// rendered directly - no webview needed.
class PageScreen extends ConsumerStatefulWidget {
  const PageScreen({super.key, required this.handle});

  final String handle;

  @override
  ConsumerState<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends ConsumerState<PageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(storeProvider.notifier).loadPage(widget.handle));
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(storeProvider.select((s) => s.content.pages[widget.handle]));

    // The slot is keyed per handle, but guard against a value from another page.
    final Resource<PageContent> resource =
        (raw != null && raw.hasValue && raw.value!.handle.isNotEmpty && raw.value!.handle != widget.handle)
            ? Resource<PageContent>(status: raw.status)
            : (raw ?? const Resource<PageContent>());

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, title: Text(_title(resource))),
      body: _body(resource),
    );
  }

  String _title(Resource<PageContent> resource) {
    final title = resource.value?.title ?? '';
    if (title.isNotEmpty) return title;
    return widget.handle.replaceAll('-', ' ').replaceAllMapped(RegExp(r'\b[a-z]'), (m) => m[0]!.toUpperCase());
  }

  Widget _body(Resource<PageContent> resource) {
    if (resource.showSkeleton || !resource.hasValue) {
      if (resource.isError && !resource.hasValue) {
        return ErrorRetry(message: resource.error, onRetry: () => ref.read(storeProvider.notifier).loadPage(widget.handle));
      }
      return const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 200, height: 24),
            SizedBox(height: 18),
            SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: 9),
            SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: 9),
            SkeletonBox(width: 280, height: 14),
            SizedBox(height: 9),
            SkeletonBox(width: double.infinity, height: 14),
          ],
        ),
      );
    }

    final paragraphs = resource.value!.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return RefreshIndicator(
      onRefresh: () async => ref.read(storeProvider.notifier).loadPage(widget.handle),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final paragraph in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                paragraph.replaceAll(RegExp(r'\n'), ' '),
                style: const TextStyle(fontSize: 14.5, height: 1.7, color: AppColors.ink),
              ),
            ),
        ],
      ),
    );
  }
}
