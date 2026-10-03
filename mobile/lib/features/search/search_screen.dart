import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

import '../shop/product_listing.dart';

/// "Search" tab - debounced query field + the shared listing grid.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  static const _suggestions = ['oud', 'perfume gift set', 'body wash', 'unisex', 'trial pack', 'men', 'women', 'car perfume'];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    // This tab survives a logout (the shell keeps its branches alive), so drop
    // the previous user's query and its results along with the state flush.
    ref.listen(storeProvider.select((s) => s.auth.isAuthenticated), (previous, next) {
      if (previous == true && next == false) {
        _debounce?.cancel();
        _controller.clear();
        if (mounted) setState(() => _query = '');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 16,
        actions: const [CartIconButton()],
        title: TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search fragrances, notes, collections...',
            hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.muted),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      body: _query.isEmpty ? _Suggestions(onPick: _pick) : ProductListingView(query: _query),
    );
  }

  void _pick(String value) {
    _controller.text = value;
    setState(() => _query = value);
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Popular searches', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final term in _SearchScreenState._suggestions)
              ActionChip(
                label: Text(term),
                avatar: const Icon(Icons.trending_up_rounded, size: 15),
                onPressed: () => onPick(term),
              ),
          ],
        ),
        const SizedBox(height: 26),
        const Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 17, color: AppColors.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Search by note (oud, vanilla), mood, or product name.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
