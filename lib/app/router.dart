import 'package:flutter/material.dart';

import '../features/anime/data/repositories/anime_repository.dart';
import '../features/details/anime_details_screen.dart';

/// Routes nommées de l'application.
abstract final class AppRoutes {
  AppRoutes._();

  /// Fiche d'un animé — argument attendu : l'identifiant (`String`) de l'animé.
  static const String animeDetails = '/anime/details';
}

/// Construction centralisée des routes.
abstract final class AppRouter {
  AppRouter._();

  static RouteFactory onGenerateRoute(AnimeRepository repository) {
    return (RouteSettings settings) {
      switch (settings.name) {
        case AppRoutes.animeDetails:
          final String animeId = settings.arguments as String;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => AnimeDetailsScreen(repository: repository, animeId: animeId),
          );
        default:
          return null;
      }
    };
  }
}
