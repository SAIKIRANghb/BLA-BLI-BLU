import 'package:flutter/material.dart';

import '../../state/resource.dart';
import 'skeletons.dart';

/// Renders a [Resource] with the three states every remote slot needs:
/// skeleton (first load), stale-value refresh (subtle overlay) and error retry.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.resource,
    required this.builder,
    this.onRetry,
    this.loading,
    this.staleBuilder,
  });

  final Resource<T> resource;
  final Widget Function(BuildContext context, T value) builder;
  final VoidCallback? onRetry;

  /// Custom first-load placeholder (defaults to a generic spinner box).
  final Widget Function(BuildContext context)? loading;

  /// When a refresh fails but stale data exists we keep showing it with this
  /// slim banner; `null` hides the banner entirely.
  final Widget Function(BuildContext context, String error)? staleBuilder;

  @override
  Widget build(BuildContext context) {
    if (resource.showSkeleton) {
      return loading?.call(context) ?? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (resource.isError && !resource.hasValue) {
      return ErrorRetry(message: resource.error, onRetry: onRetry);
    }
    if (!resource.hasValue) {
      return loading?.call(context) ?? const Center(child: CircularProgressIndicator());
    }

    if (resource.isError) {
      final error = resource.error ?? 'Something went wrong';
      final banner = staleBuilder?.call(context, error) ?? _StaleBanner(message: error, onRetry: onRetry);
      return Column(
        children: [
          banner,
          Expanded(child: builder(context, resource.value as T)),
        ],
      );
    }
    return builder(context, resource.value as T);
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFF4E5),
        child: InkWell(
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB26A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A4A00)),
                  ),
                ),
                if (onRetry != null)
                  const Text('Retry', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFB26A00))),
              ],
            ),
          ),
        ),
      );
}
