import 'package:flutter/material.dart';

import '../../anime/data/models/anime.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/carousel_indicator.dart';
import 'hero_card.dart';

/// Carousel de mise en avant de l'accueil (glissable, avec indicateur).
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.repository});

  final AnimeRepository repository;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  static const double _height = 430;

  int _index = 0;

  List<Anime> get _items => widget.repository.latestReleases.take(4).toList();

  void _open(Anime anime) {
    Navigator.of(context).pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(anime.id));
  }

  @override
  Widget build(BuildContext context) {
    final List<Anime> items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: _height,
          child: PageView.builder(
            itemCount: items.length,
            onPageChanged: (int index) => setState(() => _index = index),
            itemBuilder: (BuildContext context, int index) {
              final Anime anime = items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.22), blurRadius: 34, offset: const Offset(0, 14))],
                  ),
                  child: HeroCard(anime: anime, onOpen: () => _open(anime)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        CarouselIndicator(count: items.length, index: _index),
      ],
    );
  }
}
