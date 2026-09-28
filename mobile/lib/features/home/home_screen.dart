import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/links.dart';
import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/store.dart';

/// Storefront landing page: ticker, hero carousel, claims, collection tiles,
/// trial packs, bestsellers, new arrivals, banners and the FAQ teaser.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _heroController = PageController(viewportFraction: 0.92);
  int _heroPage = 0;

  /// Advances the hero banner on its own, like the storefront's autoplaying
  /// slider. The timer is zone-driven, so widget tests only see it fire when
  /// they pump past [_heroInterval], and [dispose] cancels it outright.
  Timer? _heroTimer;
  static const _heroInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storeProvider.notifier).loadHome();
      ref.read(storeProvider.notifier).loadCollections();
    });
    _heroTimer = Timer.periodic(_heroInterval, (_) => _advanceHero());
  }

  /// Next slide, wrapping back to the first one at the end of the list.
  void _advanceHero() {
    if (!mounted || !_heroController.hasClients) return;
    final slides = ref.read(storeProvider).catalog.home.value?.heroSlides ?? const <HeroSlide>[];
    if (slides.length < 2) return;
    if (_heroPage >= slides.length - 1) {
      _heroController.jumpToPage(0);
    } else {
      _heroController.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(storeProvider.select((s) => s.catalog.home));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => ref.read(storeProvider.notifier).loadHome(),
        child: CustomScrollView(
          slivers: [
            const _HomeAppBar(),
            if (home.showSkeleton) ...const [
              SliverToBoxAdapter(child: BannerSkeleton(height: 230)),
              SliverToBoxAdapter(child: ProductGridSkeleton(count: 4)),
            ] else if (home.isError && !home.hasValue)
              SliverFillRemaining(
                child: ErrorRetry(message: home.error, onRetry: () => ref.read(storeProvider.notifier).loadHome()),
              )
            else if (home.value != null)
              ..._sections(context, home.value!),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, HomeData data) {
    return [
      SliverToBoxAdapter(child: _AnnouncementBar(text: data.announcement)),
      if (data.heroSlides.isNotEmpty) SliverToBoxAdapter(child: _HeroCarousel(slides: data.heroSlides, controller: _heroController, page: _heroPage, onChanged: (i) => setState(() => _heroPage = i))),
      if (data.claimsPoints.isNotEmpty) SliverToBoxAdapter(child: _ClaimsRow(points: data.claimsPoints)),
      if (data.collectionTiles.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionHeader(title: data.collectionSectionTitle, actionLabel: 'See all', onAction: () => context.go('/shop'))),
        SliverToBoxAdapter(child: _CollectionStrip(tiles: data.collectionTiles)),
      ],
      if (data.trialTiles.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionHeader(title: data.trialTitle, subtitle: data.trialTagline)),
        SliverToBoxAdapter(child: _CollectionStrip(tiles: data.trialTiles)),
      ],
      if (data.featured.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionHeader(title: data.featuredTitle)),
        SliverToBoxAdapter(child: _ProductStrip(products: data.featured)),
      ],
      if (data.newArrivals.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionHeader(title: 'New Arrivals')),
        SliverToBoxAdapter(child: _ProductStrip(products: data.newArrivals)),
      ],
      for (final banner in data.banners)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openLink(context, banner.link),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedImage(banner.imageUrl, height: 160, width: double.infinity),
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(child: _SectionHeader(title: data.faqTitle, actionLabel: 'All FAQs', onAction: () => context.push('/faq'))),
      SliverToBoxAdapter(child: _HomeFaqTeaser(data: data)),
      SliverToBoxAdapter(child: _SectionHeader(title: 'Shop by category', actionLabel: 'See all', onAction: () => context.go('/shop'))),
      SliverToBoxAdapter(
        child: _CollectionStrip(
          tiles: (ref.read(storeProvider).catalog.collections.value ?? const <CollectionTile>[])
              .map((c) => HomeTile(title: c.title, imageUrl: c.imageUrl ?? '', link: '/collection/${c.handle}'))
              .toList(),
        ),
      ),
      SliverToBoxAdapter(child: _FooterLinks(data: data)),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      const SliverToBoxAdapter(child: _SignInCta()),
    ];
  }

  void _openLink(BuildContext context, String link) => openShopLink(context, link);
}

// ─────────────────────────────────── pieces ──────────────────────────────────

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('BLA BLI BLU', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
              child: const Text('INDIA', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ],
        ),
      ),
      actions: [
        const CartIconButton(),
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => context.go('/search'),
        ),
        IconButton(
          tooltip: 'Track order',
          icon: const Icon(Icons.location_on_outlined),
          onPressed: () => context.push('/track'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _AnnouncementBar extends StatelessWidget {
  const _AnnouncementBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    );
  }
}

class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({
    required this.slides,
    required this.controller,
    required this.page,
    required this.onChanged,
  });

  final List<HeroSlide> slides;
  final PageController controller;
  final int page;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 230,
          child: PageView.builder(
            controller: controller,
            itemCount: slides.length,
            onPageChanged: onChanged,
            itemBuilder: (context, i) {
              final slide = slides[i];
              final url = slide.mobileUrl.isNotEmpty ? slide.mobileUrl : slide.desktopUrl;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => openShopLink(context, slide.link),
                  child: CachedImage(url, height: 230, width: double.infinity, radius: 0),
                ),
              );
            },
          ),
        ),
        if (slides.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == page ? AppColors.primary : AppColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ClaimsRow extends StatelessWidget {
  const _ClaimsRow({required this.points});
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        children: [
          for (final point in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 17, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(point, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.actionLabel, this.onAction});

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _CollectionStrip extends StatelessWidget {
  const _CollectionStrip({required this.tiles});
  final List<HomeTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final tile = tiles[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openShopLink(context, tile.link),
            child: SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedImage(tile.imageUrl, width: 132, height: double.infinity),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(tile.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  if (tile.caption != null && tile.caption!.isNotEmpty)
                    Text(tile.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductStrip extends StatelessWidget {
  const _ProductStrip({required this.products});
  final List<ProductCard> products;

  static const double _cardWidth = 178;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ProductCardTile.heightFor(_cardWidth),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(width: _cardWidth, child: ProductCardTile(product: products[i])),
      ),
    );
  }
}

class _HomeFaqTeaser extends ConsumerWidget {
  const _HomeFaqTeaser({required this.data});
  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faqs = ref.watch(storeProvider.select((s) => s.content.faqs));
    ref.read(storeProvider.notifier).loadFaqs();

    final groups = faqs.value ?? const <FaqGroup>[];
    if (groups.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (data.faqIntro.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(data.faqIntro, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
              ),
            ),
          for (final group in groups.take(1))
            for (final item in group.items.take(4))
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 14),
                  title: Text(item.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(item.answer, style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.55)),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => context.push('/faq'), child: const Text('View all FAQs')),
          ),
        ],
      ),
    );
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks({required this.data});
  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final columns = data.footer.entries.take(3).toList();
    if (columns.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.brandTagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(data.brandTagline, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.4)),
            ),
          for (final column in columns) ...[
            Text(column.key.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final link in column.value.take(6))
                  InkWell(
                    onTap: () => _open(context, link['link'] ?? ''),
                    child: Text(link['title'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (data.copyright.isNotEmpty)
            Text(data.copyright, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
      ),
    );
  }

  void _open(BuildContext context, String link) => openShopLink(context, link);
}

class _SignInCta extends ConsumerWidget {
  const _SignInCta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(storeProvider.select((s) => s.auth.isAuthenticated));
    if (signedIn) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: () => context.push('/sign-in'),
        icon: const Icon(Icons.person_outline_rounded, size: 18),
        label: const Text('Sign in for faster checkout'),
      ),
    );
  }
}
