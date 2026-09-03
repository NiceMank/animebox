import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../features/anime/data/repositories/anime_repository.dart';
import '../features/anime/data/repositories/local_anime_repository.dart';
import '../features/anime/data/repositories/mock_anime_repository.dart';
import '../features/library/services/library_service.dart';
import '../features/local/data/local_database.dart';
import '../features/media/services/download_manager.dart';
import '../features/media/services/media_service.dart';
import '../features/media/services/storage_checker.dart';
import '../features/notifications/services/notification_center.dart';
import '../features/notifications/services/notification_service.dart';
import '../features/notifications/services/notification_service_factory.dart';
import '../features/notifications/services/notification_settings.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/services/app_settings.dart';
import '../features/settings/services/settings_dependencies.dart';
import '../features/sync/models/sync_frequency.dart';
import '../features/sync/services/auto_sync_scheduler.dart';
import '../features/sync/services/auto_sync_scheduler_factory.dart';
import '../features/telegram/data/gateway/tdlib_gateway.dart';
import '../features/telegram/data/services/episode_grouping_service.dart';
import '../features/telegram/data/services/local_telegram_service.dart';
import '../features/telegram/data/services/mock_telegram_service.dart';
import '../features/telegram/data/services/telegram_service.dart';
import '../features/telegram/data/services/telegram_session_manager.dart';
import '../navigation/home_shell.dart';
import 'router.dart';

/// Racine de l'application : thème global, services et routes.
///
/// Architecture TELEGRAM 100 % LOCALE (aucun backend AnimeBox — la session
/// de l'utilisateur ne quitte jamais l'appareil). Sélection du service
/// (aucun secret codé en dur) :
/// - `ANIMEBOX_TELEGRAM_API_ID` + `ANIMEBOX_TELEGRAM_API_HASH` fournis
///   (--dart-define, identifiants d'application my.telegram.org) →
///   **client MTProto réel** : Telegram directement via TDLib, authentification
///   du compte de l'utilisateur (numéro → code → 2FA), session chiffrée
///   conservée localement, base SQLite et analyse 100 % locales ;
/// - sinon → démonstration mockée, clairement indiquée à l'écran
///   (aucun réseau, aucune session réelle prétendue).
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
    this.database,
    this.mediaService,
    this.notificationService,
    this.notificationSettings,
    this.autoSyncScheduler,
    this.appSettings,
  });

  /// Source de données injectée depuis `main()`.
  final AnimeRepository? repository;
  final TelegramService? telegramService;
  final EpisodeGroupingService? groupingService;
  final LibraryService? libraryService;

  /// Base locale partagée (mode local réel).
  final LocalDatabase? database;

  /// Couche média injectable pour les tests.
  final MediaService? mediaService;

  /// Notifications injectables pour les tests (prompt 9).
  final NotificationService? notificationService;

  /// Réglages de notification/synchronisation injectables (tests).
  final NotificationSettings? notificationSettings;

  /// Planificateur d'arrière-plan injectable (tests).
  final AutoSyncScheduler? autoSyncScheduler;

  /// Préférences centrales injectables (prompt 12 — tests).
  final AppSettings? appSettings;

  /// Identifiants d'application Telegram (my.telegram.org) — valeurs de
  /// compilation uniquement, jamais dans le dépôt, les écrans ou les logs.
  static int get telegramApiId =>
      int.tryParse(const String.fromEnvironment('ANIMEBOX_TELEGRAM_API_ID')) ?? 0;

  static String get telegramApiHash => const String.fromEnvironment('ANIMEBOX_TELEGRAM_API_HASH');

  /// Client Telegram réel (MTProto) activé quand les identifiants
  /// d'application sont présents à la compilation. AUCUN mode serveur
  /// n'existe : sans identifiants, seule la démonstration mockée tourne.
  static bool get useLocalTelegram =>
      telegramApiId > 0 && telegramApiHash.isNotEmpty;

  @override
  State<AnimeBoxApp> createState() => _AnimeBoxAppState();
}

class _AnimeBoxAppState extends State<AnimeBoxApp> with WidgetsBindingObserver {
  late final AnimeRepository _repository = widget.repository ?? MockAnimeRepository();

  late final EpisodeGroupingService _groupingService = widget.groupingService ?? EpisodeGroupingService();
  late final LibraryService _libraryService =
      widget.libraryService ?? LibraryService(repository: _repository, groupingService: _groupingService);

  late final TelegramService _telegramService = widget.telegramService ?? _buildTelegramService();

  late final DownloadManager _downloadManager = DownloadManager(
    gateway: _telegramService.mediaGateway,
    database: widget.database,
    storageChecker: createStorageChecker(),
    resolveBaseDirectory: _resolveMediaBaseDirectory,
  );

  late final MediaService _mediaService = widget.mediaService ??
      MediaService(
        repository: _repository,
        downloadManager: _downloadManager,
        gateway: _telegramService.mediaGateway,
      );

  // -----------------------------------------------------------------------
  // Notifications + synchronisation automatique (prompt 9)
  // -----------------------------------------------------------------------

  /// Clé de navigation racine : le centre de notifications ouvre le bon
  /// écran au clic (règle 7 — Anime → Saison → Épisode).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final NotificationService _notificationService =
      widget.notificationService ?? createPlatformNotificationService();

  late final NotificationSettings _notificationSettings =
      widget.notificationSettings ?? NotificationSettings(database: widget.database);

  late final AutoSyncScheduler _autoSyncScheduler =
      widget.autoSyncScheduler ?? createPlatformAutoSyncScheduler();

  /// Préférences centrales persistantes (prompt 12 §25/§26).
  late final AppSettings _appSettings = widget.appSettings ?? AppSettings(database: widget.database);

  /// Dépendances de la section Paramètres (composition des vraies briques).
  late final SettingsDependencies _settingsDependencies = SettingsDependencies(
    appSettings: _appSettings,
    notificationSettings: _notificationSettings,
    repository: _repository,
    telegramService: _telegramService,
    mediaService: _mediaService,
    storageChecker: createStorageChecker(),
    database: widget.database,
  );

  late final NotificationCenter _notificationCenter = NotificationCenter(
    notifications: _notificationService,
    settings: _notificationSettings,
    database: widget.database,
  );

  Future<String?> _resolveMediaBaseDirectory() async {
    final LocalDatabase? db = widget.database;
    if (db == null) return null;
    try {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } catch (_) {
      return null;
    }
  }


  TelegramService _buildTelegramService() {
    // Le client MTProto réel exige la base locale partagée (ouverte par main()).
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

  /// Luminosité de la plateforme (mode « Système ») — suivie en direct.
  Brightness _platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Restauration des téléchargements persistés (reprise après
    // redémarrage — règle 13).
    // ignore: discarded_futures
    _downloadManager.restorePersisted();
    _wireNotifications();
  }

  /// Branche le système de notifications (prompt 9) :
  /// - résumés de synchronisation RÉELS → notifications nouveaux épisodes ;
  /// - événements RÉELS du téléchargeur → progression / fin / échec ;
  /// - clics → navigation vers le bon épisode / lecture / reprise ;
  /// - fréquence de synchronisation automatique restaurée (WorkManager).
  void _wireNotifications() {
    _downloadManager.onEvent = _notificationCenter.handleDownloadEvent;
    _telegramService.onSyncCompleted = _notificationCenter.handleSyncSummary;
    _notificationSettings.attachScheduler(_autoSyncScheduler);

    _notificationCenter.onOpenEpisode = (String animeId, String seasonId, String episodeId) {
      final NavigatorState? navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator
        ..pushNamed(AppRoutes.animeDetails, arguments: AnimeIdArgs(animeId))
        ..pushNamed(
          AppRoutes.episodeQuality,
          arguments: EpisodeRouteArgs(animeId: animeId, episodeId: episodeId),
        );
    };
    _notificationCenter.onPlayDownload = (String animeId, String episodeId) {
      final NavigatorState? navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushNamed(
        AppRoutes.player,
        arguments: EpisodeRouteArgs(animeId: animeId, episodeId: episodeId),
      );
    };
    _notificationCenter.onResumeDownload = _downloadManager.resume;

    // ignore: discarded_futures
    _initializeNotificationSystem();
  }

  Future<void> _initializeNotificationSystem() async {
    await _notificationService.initialize();
    _notificationService.setOnTap(
      (NotificationTap tap) => _notificationCenter.handleNotificationTap(tap.actionId, tap.payload),
    );

    // Restauration des réglages + fréquence d'arrière-plan (Android
    // conserve la tâche planifiée, on la ré-arme simplement) — la
    // contrainte Wi-Fi persistée (prompt 12 §10) est ré-appliquée aussi.
    await _notificationSettings.load();
    await _appSettings.ensureLoaded();
    try {
      final SyncFrequency frequency = _notificationSettings.syncFrequency;
      if (frequency != SyncFrequency.disabled) {
        await _autoSyncScheduler.initialize();
        await _autoSyncScheduler.applyFrequency(frequency, wifiOnly: _appSettings.syncWifiOnly);
      }
    } catch (_) {
      // Planificateur indisponible : la synchronisation manuelle reste.
    }

    // L'application a-t-elle été ouverte DEPUIS une notification ?
    final NotificationTap? launchTap = await _notificationService.consumeLaunchTap();
    if (launchTap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationCenter.handleNotificationTap(launchTap.actionId, launchTap.payload);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Le système (Android) bascule sombre ↔ clair pendant que l'appli
  /// tourne : en mode « Système », l'interface suit immédiatement (§6).
  @override
  void didChangePlatformBrightness() {
    setState(() {
      _platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  /// Luminosité effective selon le réglage « Thème » persisté.
  Brightness get _effectiveBrightness => switch (_appSettings.theme) {
        AppThemeMode.dark => Brightness.dark,
        AppThemeMode.light => Brightness.light,
        AppThemeMode.system => _platformBrightness,
      };

  ThemeMode get _materialThemeMode => switch (_appSettings.theme) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    // Le changement de thème (réglage ou système) reconstruit tout
    // l'arbre : la palette active est basculée AVANT la construction.
    return ListenableBuilder(
      listenable: _appSettings,
      builder: (BuildContext context, Widget? child) {
        final Brightness brightness = _effectiveBrightness;
        AppColors.apply(brightness);
        _applySystemUiStyle(brightness);
        return MaterialApp(
          title: 'AnimeBox',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _materialThemeMode,
          navigatorKey: _navigatorKey,
          home: _buildHome(),
          onGenerateRoute: AppRouter.onGenerateRoute(
            _repository,
            _telegramService,
            _mediaService,
            _notificationSettings,
            _notificationService,
            _settingsDependencies,
          ),
        );
      },
    );
  }

  /// Barres système cohérentes avec le thème courant (icônes lisibles et
  /// barre de navigation dans la surface active).
  void _applySystemUiStyle(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: AppColors.bottomBar,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
  }

  /// Écran racine : onboarding au PREMIER lancement uniquement
  /// (prompt 13 §4 — préférence persistante) sinon l'application normale.
  Widget _buildHome() {
    return FutureBuilder<void>(
      future: _appSettings.ensureLoaded(),
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Écran d'attente minimal — aucune donnée fictive affichée.
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Center(
              child: Text('AnimeBox', style: Theme.of(context).textTheme.displaySmall),
            ),
          );
        }
        if (!_appSettings.onboardingCompleted) {
          return OnboardingScreen(
            onStart: () => _finishOnboarding(launchTelegramFlow: true),
            onSkip: () => _finishOnboarding(launchTelegramFlow: false),
          );
        }
        return _homeShell();
      },
    );
  }

  Widget _homeShell() => HomeShell(
        repository: _repository,
        telegramService: _telegramService,
        groupingService: _groupingService,
        libraryService: _libraryService,
        mediaService: _mediaService,
        database: widget.database,
      );

  /// Fin de l'onboarding (prompt 13 §5) : la préférence est persistée,
  /// l'application s'ouvre, puis le VRAI parcours Telegram existant est
  /// lancé — sauf si un compte est déjà configuré (logique respectée).
  Future<void> _finishOnboarding({required bool launchTelegramFlow}) async {
    await _appSettings.completeOnboarding();
    if (!mounted) return;
    setState(() {});
    final bool connected = _telegramService.authState == TelegramAuthState.connected;
    if (launchTelegramFlow && !connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigatorKey.currentState?.pushNamed(AppRoutes.telegramConnect);
      });
    }
  }
}
