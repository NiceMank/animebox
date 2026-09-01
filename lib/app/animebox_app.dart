import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/anime/data/repositories/anime_repository.dart';
import '../features/anime/data/repositories/catalog_repository.dart';
import '../features/anime/data/repositories/local_anime_repository.dart';
import '../features/anime/data/repositories/mock_anime_repository.dart';
import '../features/library/services/library_service.dart';
import '../features/local/data/local_database.dart';
import '../features/telegram/data/gateway/tdlib_gateway.dart';
import '../features/telegram/data/services/api_telegram_service.dart';
import '../features/telegram/data/services/episode_grouping_service.dart';
import '../features/telegram/data/services/local_telegram_service.dart';
import '../features/telegram/data/services/mock_telegram_service.dart';
import '../features/telegram/data/services/secure_session_service.dart';
import '../features/telegram/data/services/telegram_service.dart';
import '../features/telegram/data/services/telegram_session_manager.dart';
import '../features/telegram/data/services/telegram_session_service.dart';
import '../navigation/home_shell.dart';
import 'router.dart';

/// Racine de l'application : thème global, services et routes.
///
/// Sélection des services (aucun secret codé en dur) :
/// - `ANIMEBOX_API_URL` fourni → mode backend hérité (étapes 1–6) ;
/// - `ANIMEBOX_TELEGRAM_API_ID` + `ANIMEBOX_TELEGRAM_API_HASH` fournis
///   (--dart-define, identifiants d'application my.telegram.org) →
///   **mode local réel** : Telegram directement via TDLib, base SQLite
///   locale, analyse locale ;
/// - sinon → démonstration mockée (aucun réseau).
///
/// Par défaut, le dépôt est LOCAL (base SQLite, catalogue enrichi par la
/// synchronisation) ; `main()` peut injecter n'importe quelle variante.
class AnimeBoxApp extends StatefulWidget {
  const AnimeBoxApp({
    super.key,
    this.repository,
    this.telegramService,
    this.groupingService,
    this.libraryService,
    this.sessionService,
    this.database,
  });

  /// Source de données injectée depuis `main()`.
  final AnimeRepository? repository;
  final TelegramService? telegramService;
  final EpisodeGroupingService? groupingService;
  final LibraryService? libraryService;

  /// Stockage sécurisé de session (injectable pour les tests).
  final TelegramSessionService? sessionService;

  /// Base locale partagée (mode local réel).
  final LocalDatabase? database;

  /// URL du backend, lue à la compilation (aucun secret).
  static String get apiBaseUrl => const String.fromEnvironment('ANIMEBOX_API_URL');

  static bool get useBackendApi => apiBaseUrl.isNotEmpty;

  /// Identifiants d'application Telegram (my.telegram.org) — valeurs de
  /// compilation uniquement, jamais dans le dépôt, les écrans ou les logs.
  static int get telegramApiId =>
      int.tryParse(const String.fromEnvironment('ANIMEBOX_TELEGRAM_API_ID')) ?? 0;

  static String get telegramApiHash => const String.fromEnvironment('ANIMEBOX_TELEGRAM_API_HASH');

  /// Mode local réel activé quand les identifiants de compilation sont
  /// présents (et qu'on n'est pas en mode backend).
  static bool get useLocalTelegram =>
      !useBackendApi && telegramApiId > 0 && telegramApiHash.isNotEmpty;

  @override
  State<AnimeBoxApp> createState() => _AnimeBoxAppState();
}

class _AnimeBoxAppState extends State<AnimeBoxApp> {
  late final TelegramSessionService _sessionService = widget.sessionService ??
      (kIsWeb ? InMemorySessionService() : SecureSessionService());

  late final AnimeRepository _repository = widget.repository ?? MockAnimeRepository();

  late final EpisodeGroupingService _groupingService = widget.groupingService ?? EpisodeGroupingService();
  late final LibraryService _libraryService =
      widget.libraryService ?? LibraryService(repository: _repository, groupingService: _groupingService);

  late final TelegramService _telegramService = widget.telegramService ?? _buildTelegramService();

  TelegramService _buildTelegramService() {
    if (AnimeBoxApp.useBackendApi) {
      return ApiTelegramService(baseUrl: AnimeBoxApp.apiBaseUrl, session: _sessionService);
    }
    // Le mode local réel exige la base locale partagée (ouverte par main()).
    if (AnimeBoxApp.useLocalTelegram && widget.database != null) {
      final TelegramSessionManager sessionManager =
          TelegramSessionManager(store: PlatformSecureStore());
      return LocalTelegramService(
        gateway: TdlibTelegramGateway(
          apiId: AnimeBoxApp.telegramApiId,
          apiHash: AnimeBoxApp.telegramApiHash,
        ),
        sessionManager: sessionManager,
        database: widget.database!,
        onCatalogChanged: () {
          final AnimeRepository repository = _repository;
          if (repository is LocalAnimeRepository) {
            // ignore: discarded_futures
            repository.reloadFromDatabase();
          }
        },
      );
    }
    return MockTelegramService();
  }

  @override
  void initState() {
    super.initState();
    // Chargement initial du catalogue (non bloquant) en mode backend.
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
