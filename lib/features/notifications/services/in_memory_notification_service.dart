import 'notification_service.dart';

/// Service de notification EN MÉMOIRE — utilisé par les tests et par le
/// mode démonstration sur les plateformes sans greffon de notifications.
///
/// Toutes les notifications « affichées » sont enregistrées dans
/// [shown] (la dernière version d'un même identifiant remplace la
/// précédente, comme Android), ce qui permet de vérifier très précisément
/// le comportement du centre de notifications.
class InMemoryNotificationService implements NotificationService {
  InMemoryNotificationService({this.permissionGranted = true});

  /// Permission simulée (modifiable par les tests).
  bool permissionGranted;

  /// Notifications actuellement affichées, par identifiant.
  final Map<int, ShownNotification> shown = <int, ShownNotification>{};

  /// Historique complet des affichages (ordre chronologique).
  final List<ShownNotification> history = <ShownNotification>[];

  /// Identifiants supprimés (ordre chronologique).
  final List<int> cancelled = <int>[];

  void Function(NotificationTap tap)? _handler;
  NotificationTap? _launchTap;

  /// Simule l'ouverture de l'application depuis une notification.
  void simulateLaunchTap(NotificationTap tap) => _launchTap = tap;

  /// Simule un clic utilisateur.
  void simulateTap(NotificationTap tap) => _handler?.call(tap);

  /// Dernière notification affichée pour un identifiant.
  ShownNotification? lastShown(int id) => shown[id];

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> show(ShownNotification notification) async {
    shown[notification.id] = notification;
    history.add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    shown.remove(id);
    cancelled.add(id);
  }

  @override
  void setOnTap(void Function(NotificationTap tap) handler) => _handler = handler;

  @override
  Future<NotificationTap?> consumeLaunchTap() async {
    final NotificationTap? tap = _launchTap;
    _launchTap = null;
    return tap;
  }
}
