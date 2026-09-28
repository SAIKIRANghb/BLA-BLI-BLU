import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// Product detail: gallery, pricing, variant picker, the note pyramid
/// (head / heart / base), description and customer reviews.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.handle});

  final String handle;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  final _gallery = PageController(viewportFraction: 0.92);
  int _imageIndex = 0;
  int _qty = 1;
  String? _variantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storeProvider.notifier).loadProduct(widget.handle);
    });
  }

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  void _resetFor(ProductDetail detail) {
    if (_variantId != null && detail.variants.every((v) => v.id != _variantId)) {
      _variantId = null;
    }
    if (_variantId == null && detail.variants.isNotEmpty) {
      _variantId = detail.variants.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailRes = ref.watch(storeProvider.select((s) => s.catalog.details[widget.handle]));
    final reviews = ref.watch(storeProvider.select((s) => s.catalog.reviews[widget.handle] ?? const <ProductReview>[]));
    final busy = ref.watch(storeProvider.select((s) => s.cart.busy));

    final detail = detailRes?.value;
    if (detail == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(backgroundColor: AppColors.surface),
        body: detailRes == null || detailRes.showSkeleton
            ? const SingleChildScrollView(child: _DetailSkeleton())
            : ErrorRetry(
                message: detailRes.error,
                onRetry: () => ref.read(storeProvider.notifier).loadProduct(widget.handle),
              ),
      );
    }
    _resetFor(detail);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          _GalleryAppBar(
            images: detail.images.isEmpty ? <String?>[detail.imageUrl] : detail.images.cast<String?>(),
            index: _imageIndex,
            onShare: () {},
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Gallery(
                  images: detail.images.isEmpty ? <String?>[detail.imageUrl] : detail.images.cast<String?>(),
                  controller: _gallery,
                  index: _imageIndex,
                  onChanged: (i) => setState(() => _imageIndex = i),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detail.badge != null && detail.badge!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(5)),
                          child: Text(
                            detail.badge!.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(detail.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.4)),
                      if (detail.tagline.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(detail.tagline, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.8)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          RatingStars(rating: detail.rating, count: detail.ratingCount, size: 15),
                          const Spacer(),
                          Text(detail.audience, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PriceText.fromProduct(detail, fontSize: 22),
                      if (detail.oilConcentration != null && detail.oilConcentration!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.opacity_rounded, size: 15, color: AppColors.muted),
                            const SizedBox(width: 6),
                            Text(detail.oilConcentration!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          ],
                        ),
                      ],
                      if (detail.notesSummary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(detail.notesSummary, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
                      ],
                    ],
                  ),
                ),
                if (detail.variants.length > 1) _Variants(
                  variants: detail.variants,
                  selected: _variantId,
                  onChanged: (id) => setState(() => _variantId = id),
                ),
                if (detail.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Text(detail.description, style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.ink)),
                  ),
                if (detail.headNotes.isNotEmpty || detail.heartNotes.isNotEmpty || detail.baseNotes.isNotEmpty)
                  _NotePyramid(head: detail.headNotes, heart: detail.heartNotes, base: detail.baseNotes),
                _ReviewsSection(reviews: reviews),
                const SizedBox(height: 12),
                const _ShareBar(),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: _AddToBagBar(
        qty: _qty,
        busy: busy,
        product: detail,
        variantId: _variantId,
        onQty: (q) => setState(() => _qty = q),
      ),
    );
  }
}

// ─────────────────────────────────── gallery ─────────────────────────────────

class _GalleryAppBar extends StatelessWidget {
  const _GalleryAppBar({required this.images, required this.index, required this.onShare});

  final List<String?> images;
  final int index;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.pop(),
      ),
      title: images.length > 1
          ? Text('${index + 1} / ${images.length}', style: const TextStyle(fontSize: 14, color: AppColors.muted))
          : null,
      actions: [
        IconButton(icon: const Icon(Icons.ios_share_rounded, size: 20), onPressed: onShare),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.images, required this.controller, required this.index, required this.onChanged});

  final List<String?> images;
  final PageController controller;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 360,
          child: PageView.builder(
            controller: controller,
            itemCount: images.length,
            onPageChanged: onChanged,
            itemBuilder: (_, i) => CachedImage(images[i], height: 360, width: double.infinity),
          ),
        ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == index ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.primary : AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────── variants ─────────────────────────────────

class _Variants extends StatelessWidget {
  const _Variants({required this.variants, required this.selected, required this.onChanged});

  final List<ProductVariant> variants;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Size', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variant in variants)
                ChoiceChip(
                  label: Text(variant.title),
                  selected: variant.id == selected,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(variant.id),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: variant.id == selected ? Colors.white : AppColors.ink,
                  ),
                  selectedColor: AppColors.ink,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────── note pyramid ─────────────────────────────────

class _NotePyramid extends StatelessWidget {
  const _NotePyramid({required this.head, required this.heart, required this.base});

  final List<ProductNote> head;
  final List<ProductNote> heart;
  final List<ProductNote> base;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fragrance notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                _NoteRow(label: 'HEAD', color: AppColors.success, notes: head),
                if (head.isNotEmpty && (heart.isNotEmpty || base.isNotEmpty)) const Divider(height: 22),
                _NoteRow(label: 'HEART', color: AppColors.star, notes: heart),
                if (heart.isNotEmpty && base.isNotEmpty) const Divider(height: 22),
                _NoteRow(label: 'BASE', color: AppColors.primary, notes: base),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.label, required this.color, required this.notes});

  final String label;
  final Color color;
  final List<ProductNote> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.8)),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final note in notes)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.line)),
                  child: Text(note.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────── reviews ──────────────────────────────────

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews});

  final List<ProductReview> reviews;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
              Text('${reviews.length}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          if (reviews.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
              child: const Text('No reviews yet for this fragrance.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
            )
          else
            for (final review in reviews) _ReviewTile(review: review),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RatingStars(rating: review.rating.toDouble(), showCount: false, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(review.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              if (review.createdAt.isNotEmpty)
                Text(_date(review.createdAt), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
          if (review.title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ],
          if (review.body.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(review.body, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
          ],
        ],
      ),
    );
  }

  String _date(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }
}

// ────────────────────────────────── share bar ────────────────────────────────

class _ShareBar extends StatelessWidget {
  const _ShareBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () => context.push('/faq'),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('Questions about this fragrance?'),
      ),
    );
  }
}

// ─────────────────────────────── bottom bar ──────────────────────────────────

class _AddToBagBar extends ConsumerWidget {
  const _AddToBagBar({
    required this.qty,
    required this.busy,
    required this.product,
    required this.variantId,
    required this.onQty,
  });

  final int qty;
  final bool busy;
  final ProductDetail product;
  final String? variantId;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = product.variants.cast<ProductVariant?>().firstWhere((v) => v?.id == variantId, orElse: () => null);
    final unitPrice = variant?.price ?? product.price;
    final ProductVariant? fallback = product.variants.isNotEmpty ? product.variants.first : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            QtyStepper(value: qty, onChanged: onQty, busy: busy),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy || !product.available
                    ? null
                    : () => ref.read(storeProvider.notifier).addToCart(product, variant: variant ?? fallback, qty: qty),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text(
                        product.available ? 'Add to bag · ${MoneyFormat.rupees(unitPrice * qty)}' : 'Sold out',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────── skeleton ──────────────────────────────────

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: double.infinity, height: 360, radius: 0),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 220, height: 24),
              SizedBox(height: 10),
              SkeletonBox(width: 140, height: 16),
              SizedBox(height: 14),
              SkeletonBox(width: 190, height: 22),
              SizedBox(height: 20),
              SkeletonBox(width: double.infinity, height: 16),
              SizedBox(height: 8),
              SkeletonBox(width: double.infinity, height: 16),
              SizedBox(height: 8),
              SkeletonBox(width: 240, height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
