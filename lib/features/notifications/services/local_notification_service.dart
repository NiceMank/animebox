import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

/// Service de notification RÉEL, adossé au greffon
/// `flutter_local_notifications` (solution Flutter/Android stable —
/// règle 1).
///
/// - canaux Android créés explicitement (règle 3) ;
/// - permission Android 13+ demandée au moment opportun par l'interface
///   (règle 2) puis déléguée à [requestPermission] ;
/// - même identifiant = mise à jour en place (regroupement des qualités,
///   progression des téléchargements) ;
/// - tout reste local : aucune donnée n'est envoyée à un serveur (règle 29).
class LocalNotificationService implements NotificationService {
  LocalNotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  void Function(NotificationTap tap)? _handler;

  /// Icône de notification — ressource vectorielle personnalisée
  /// (`res/drawable/ic_notification.xml`), jamais d'emoji (règle 28).
  static const String _icon = 'ic_notification';

  static const AndroidNotificationChannel _episodesChannel = AndroidNotificationChannel(
    'animebox_new_episodes',
    'Nouveaux épisodes',
    description: 'Alerte quand un nouvel épisode est détecté dans vos sources Telegram.',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _episodesSilentChannel = AndroidNotificationChannel(
    'animebox_new_episodes_silent',
    'Nouveaux épisodes (silencieux)',
    description: 'Mêmes alertes, sans son ni vibration (mode silencieux, heures silencieuses).',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  static const AndroidNotificationChannel _downloadsChannel = AndroidNotificationChannel(
    'animebox_downloads',
    'Téléchargements',
    description: 'Progression et fin des téléchargements de vidéos.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onResponse,
      );
      // Canaux Android (créés une fois — règle 3).
      final AndroidFlutterLocalNotificationsPlugin? android = _android;
      await android?.createNotificationChannel(_episodesChannel);
      await android?.createNotificationChannel(_episodesSilentChannel);
      await android?.createNotificationChannel(_downloadsChannel);
      _initialized = true;
      return true;
    } catch (_) {
      // Le greffon est indisponible (plateforme inattendue) : l'application
      // doit continuer sans notifications plutôt que planter.
      return false;
    }
  }

  void _onResponse(NotificationResponse response) {
    _handler?.call(NotificationTap(
      actionId: response.actionId?.isEmpty == true ? null : response.actionId,
      payload: response.payload,
    ));
  }

  @override
  Future<bool> isPermissionGranted() async {
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _detailsFor(ShownNotification notification) {
    final (String id, String name, String? description, Importance importance, bool sound, bool vibration) =
        switch (notification.channel) {
      AppNotificationChannel.newEpisodes => (
          _episodesChannel.id,
          _episodesChannel.name,
          _episodesChannel.description,
          Importance.high,
          true,
          true,
        ),
      AppNotificationChannel.newEpisodesSilent => (
          _episodesSilentChannel.id,
          _episodesSilentChannel.name,
          _episodesSilentChannel.description,
          Importance.low,
          false,
          false,
        ),
      AppNotificationChannel.downloads => (
          _downloadsChannel.id,
          _downloadsChannel.name,
          _downloadsChannel.description,
          Importance.low,
          false,
          false,
        ),
    };

    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        channelDescription: description,
        importance: importance,
        priority: notification.channel == AppNotificationChannel.newEpisodes
            ? Priority.high
            : Priority.low,
        playSound: sound,
        enableVibration: vibration,
        icon: _icon,
        ongoing: notification.ongoing,
        autoCancel: !notification.ongoing,
        onlyAlertOnce: notification.onlyAlertOnce,
        showProgress: notification.progress != null || notification.indeterminate,
        maxProgress: notification.progressMax ?? 0,
        progress: notification.progress ?? 0,
        indeterminate: notification.indeterminate,
        styleInformation: BigTextStyleInformation(notification.body),
        actions: <AndroidNotificationAction>[
          for (final NotificationActionButton action in notification.actions)
            AndroidNotificationAction(action.id, action.label, showsUserInterface: true),
        ],
      ),
    );
  }

  @override
  Future<void> show(ShownNotification notification) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        notification.id,
        notification.title,
        notification.body,
        _detailsFor(notification),
        payload: notification.payload,
      );
    } catch (_) {
      // Une notification qui échoue ne doit jamais casser le flux
      // (synchronisation, téléchargement).
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  @override
  void setOnTap(void Function(NotificationTap tap) handler) => _handler = handler;

  @override
  Future<NotificationTap?> consumeLaunchTap() async {
    if (!_initialized) return null;
    try {
      final NotificationAppLaunchDetails? details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final NotificationResponse? response = details!.notificationResponse;
        return NotificationTap(
          actionId: response?.actionId?.isEmpty == true ? null : response?.actionId,
          payload: response?.payload,
        );
      }
    } catch (_) {}
    return null;
  }
}
