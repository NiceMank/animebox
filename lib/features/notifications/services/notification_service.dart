/// Contrat du service de notification locale (prompt 9, règle 1).
///
/// Deux implémentations :
/// - [LocalNotificationService] : notifications Android réelles via le
///   greffon `flutter_local_notifications` ;
/// - [InMemoryNotificationService] : enregistrement en mémoire (tests,
///   plateformes sans greffon — la logique métier reste testable et le
///   mode démonstration ne plante jamais).
library;

/// Canaux Android proposés (règle 3 — sans multiplier inutilement) :
/// - [newEpisodes] : nouveau contenu détecté (son/vibration système) ;
/// - [newEpisodesSilent] : même information, discrète (mode silencieux,
///   heures silencieuses — règles 19 et 20) ;
/// - [downloads] : progression et fin des téléchargements.
enum AppNotificationChannel { newEpisodes, newEpisodesSilent, downloads }

/// Bouton d'action d'une notification Android.
class NotificationActionButton {
  const NotificationActionButton({required this.id, required this.label});

  final String id;
  final String label;
}

/// Une notification à afficher — données réelles uniquement.
class ShownNotification {
  const ShownNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    this.payload,
    this.actions = const <NotificationActionButton>[],
    this.ongoing = false,
    this.indeterminate = false,
    this.progress,
    this.progressMax,
    this.onlyAlertOnce = false,
  });

  /// Identifiant stable (le même identifiant = mise à jour en place).
  final int id;
  final AppNotificationChannel channel;
  final String title;
  final String body;

  /// Charge utile décodée au clic (navigation vers le bon écran).
  final String? payload;

  final List<NotificationActionButton> actions;

  /// Notification de progression non démissible (téléchargement en cours).
  final bool ongoing;

  /// Progression indéterminée (taille totale inconnue).
  final bool indeterminate;

  /// Progression réelle : [progress] / [progressMax] (jamais estimée).
  final int? progress;
  final int? progressMax;

  /// Une seule alerte sonore (progression — règle 8, pas de spam).
  final bool onlyAlertOnce;
}

/// Réponse de l'utilisateur à une notification (clic ou action).
class NotificationTap {
  const NotificationTap({this.actionId, this.payload});

  final String? actionId;
  final String? payload;
}

/// Service de notification locale — toutes les notifications sont créées
/// SUR L'APPAREIL (règle 29 : aucune donnée vers un serveur externe).
abstract class NotificationService {
  /// Prépare le service (canaux Android compris).
  Future<bool> initialize();

  /// Permission actuellement accordée ? (Android 13+ exige l'autorisation.)
  Future<bool> isPermissionGranted();

  /// Demande la permission — jamais au premier lancement (règle 2) :
  /// l'interface présente d'abord le bénéfice, puis appelle cette méthode.
  Future<bool> requestPermission();

  /// Affiche (ou met à jour — même identifiant) une notification.
  Future<void> show(ShownNotification notification);

  /// Supprime une notification (téléchargement terminé/annulé, etc.).
  Future<void> cancel(int id);

  /// Branche le gestionnaire de clics (une seule fois).
  void setOnTap(void Function(NotificationTap tap) handler);

  /// Notification à l'origine du démarrage à froid, s'il y en a une ;
  /// consommée une seule fois.
  Future<NotificationTap?> consumeLaunchTap();
}
