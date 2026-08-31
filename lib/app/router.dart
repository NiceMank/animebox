import 'package:flutter/material.dart';

import '../features/anime/data/repositories/anime_repository.dart';
import '../features/details/anime_details_screen.dart';
import '../features/episodes/episode_list_screen.dart';
import '../features/player/player_screen.dart';
import '../features/quality/quality_select_screen.dart';

/// Routes nommées de l'application.
abstract final class AppRoutes {
  AppRoutes._();

  /// Fiche d'un animé — argument : [AnimeIdArgs].
  static const String animeDetails = '/anime/details';

  /// Liste des épisodes — argument : [EpisodeListArgs].
  static const String animeEpisodes = '/anime/episodes';

  /// Choix qualité / langue d'un épisode — argument : [EpisodeRouteArgs].
  static const String episodeQuality = '/episode/quality';

  /// Lecteur vidéo — argument : [EpisodeRouteArgs].
  static const String player = '/player';
}

/// Arguments d'une route animé simple.
class AnimeIdArgs {
  const AnimeIdArgs(this.animeId);
  final String animeId;
}

/// Arguments de la liste d'épisodes (saison présélectionnée optionnelle).
class EpisodeListArgs {
  const EpisodeListArgs(this.animeId, {this.seasonId});
  final String animeId;
  final String? seasonId;
}

/// Arguments des routes épisode (qualité / lecteur).
class EpisodeRouteArgs {
  const EpisodeRouteArgs({required this.animeId, required this.episodeId});
  final String animeId;
  final String episodeId;
}

/// Construction centralisée des routes.
abstract final class AppRouter {
  AppRouter._();

  static RouteFactory onGenerateRoute(AnimeRepository repository) {
    return (RouteSettings settings) {
      switch (settings.name) {
        case AppRoutes.animeDetails:
          final AnimeIdArgs args = settings.arguments as AnimeIdArgs;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => AnimeDetailsScreen(repository: repository, animeId: args.animeId),
          );
        case AppRoutes.animeEpisodes:
          final EpisodeListArgs args = settings.arguments as EpisodeListArgs;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => EpisodeListScreen(repository: repository, animeId: args.animeId, initialSeasonId: args.seasonId),
          );
        case AppRoutes.episodeQuality:
          final EpisodeRouteArgs args = settings.arguments as EpisodeRouteArgs;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => QualitySelectScreen(repository: repository, animeId: args.animeId, episodeId: args.episodeId),
          );
        case AppRoutes.player:
          final EpisodeRouteArgs args = settings.arguments as EpisodeRouteArgs;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => PlayerScreen(repository: repository, animeId: args.animeId, episodeId: args.episodeId),
          );
        default:
          return null;
      }
    };
  }
}
