import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/anime/data/repositories/anime_repository.dart';
import '../features/anime/data/repositories/api_anime_repository.dart';
import '../features/anime/data/repositories/catalog_repository.dart';
import '../features/anime/data/repositories/mock_anime_repository.dart';
import '../features/library/services/library_service.dart';
import '../features/telegram/data/services/api_telegram_service.dart';
import '../features/telegram/data/services/episode_grouping_service.dart';
import '../features/telegram/data/services/mock_telegram_service.dart';
import '../features/telegram/data/services/secure_session_service.dart';
import '../features/telegram/data/services/telegram_service.dart';
import '../features/telegram/data/services/telegram_session_service.dart';
import '../navigation/home_shell.dart';
import 'router.dart';

/// Racine de l'application : thème global, services et routes.
///
/// Sélection des services :
/// - si `ANIMEBOX_API_URL` est fournie au lancement (`--dart-define`),
///   l'application utilise [ApiTelegramService] ET [ApiAnimeRepository]
///   (backend réel : catalogue + métadonnées + recherche serveur) ;
/// - sinon, [MockTelegramService] + [MockAnimeRepository] (démonstration
///   locale, sans réseau).
///
/// Les secrets Telegram ne vivent QUE côté backend : l'application ne
/// contient aucun API_ID / API_HASH / session en clair.
class AnimeBoxApp extends StatefulWidget {
  const AnimeBoxApp({
    super.key,
    this.repository,
    this.telegramService,
    this.groupingService,
    this.libraryService,
    this.sessionService,
  });

  /// Source de données injectée depuis `main()`.
  final AnimeRepository? repository;
  final TelegramService? telegramService;
  final EpisodeGroupingService? groupingService;
  final LibraryService? libraryService;

  /// Stockage sécurisé de session (injectable pour les tests).
  final TelegramSessionService? sessionService;

  /// URL du backend, lue à la compilation (aucun secret).
  static String get apiBaseUrl => const String.fromEnvironment('ANIMEBOX_API_URL');

  static bool get useBackendApi => apiBaseUrl.isNotEmpty;

  @override
  State<AnimeBoxApp> createState() => _AnimeBoxAppState();
}

class _AnimeBoxAppState extends State<AnimeBoxApp> {
  late final TelegramSessionService _sessionService = widget.sessionService ??
      // Session stockée dans le stockage sécurisé de la plateforme
      // (Keystore Android) ; en mémoire sur le web (démo).
      (kIsWeb ? InMemorySessionService() : SecureSessionService());

  late final AnimeRepository _repository = widget.repository ??
      (AnimeBoxApp.useBackendApi
          ? ApiAnimeRepository(baseUrl: AnimeBoxApp.apiBaseUrl, session: _sessionService)
          : MockAnimeRepository());

  late final EpisodeGroupingService _groupingService = widget.groupingService ?? EpisodeGroupingService();
  late final LibraryService _libraryService =
      widget.libraryService ?? LibraryService(repository: _repository, groupingService: _groupingService);

  late final TelegramService _telegramService = widget.telegramService ?? _buildTelegramService();

  TelegramService _buildTelegramService() {
    if (AnimeBoxApp.useBackendApi) {
      return ApiTelegramService(baseUrl: AnimeBoxApp.apiBaseUrl, session: _sessionService);
    }
    return MockTelegramService();
  }

  @override
  void initState() {
    super.initState();
    // Chargement initial du catalogue (non bloquant) : les écrans affichent
    // d'abord les données connues, puis se mettent à jour via le Listenable.
    if (_repository case final CatalogRepository catalog) {
      // ignore: discarded_futures
      catalog.refreshCatalog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimeBox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeShell(
        repository: _repository,
        telegramService: _telegramService,
        groupingService: _groupingService,
        libraryService: _libraryService,
      ),
      onGenerateRoute: AppRouter.onGenerateRoute(_repository, _telegramService),
    );
  }
}
