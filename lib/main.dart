import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/animebox_app.dart';
import 'core/theme/app_colors.dart';
import 'features/anime/data/repositories/local_anime_repository.dart';
import 'features/local/data/local_database.dart';

/// Point d'entrée.
///
/// Architecture 100 % locale : la base SQLite de l'appareil (sources,
/// catalogue, progression, favoris) est ouverte au démarrage puis partagée
/// entre le dépôt du catalogue et le service Telegram local (TDLib).
/// Aucun serveur distant n'est requis.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barres système transparentes, dans l'esprit sombre de l'application.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bottomBar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Base locale : en cas d'indisponibilité (plateforme sans SQLite),
  // le dépôt fonctionne en mémoire — l'application ne plante jamais.
  final LocalDatabase? database = await LocalDatabase.open();

  runApp(AnimeBoxApp(
    repository: LocalAnimeRepository(database: database),
    database: database,
  ));
}
