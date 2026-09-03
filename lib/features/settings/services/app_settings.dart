import 'package:flutter/foundation.dart';

import '../../local/data/local_database.dart';

/// Thème de l'interface (§7) — le design AnimeBox est SOMBRE : les biens
/// proposés sont donc « Sombre » et « Système » (qui suit Android ; le
/// fond de référence reste sombre). Aucun thème clair générique n'est
/// inventé (§27).
enum AppThemeMode { dark, system }

/// Service central des préférences (prompt 12 §25/§26).
///
/// Toutes les préférences sont :
/// 1. lisibles immédiatement (getters) ;
/// 2. modifiables de façon réelle (setters notifiés) ;
/// 3. persistantes (table `settings` → survit au redémarrage).
///
/// Le service compose les briques existantes (notifications, scheduler)
/// SANS les dupliquer : il n'enregistre que les préférences propres aux
/// paramètres généraux (langue, thème, Wi-Fi, gestion interne).
class AppSettings extends ChangeNotifier {
  AppSettings({this.database}) {
    _loadFuture = _load();
  }

  late final Future<void> _loadFuture;

  /// Fin du chargement initial — attendue avant d'appliquer des effets
  /// dépendants (contrainte Wi-Fi de la synchro au démarrage, §10).
  Future<void> ensureLoaded() => _loadFuture;

  /// Base locale injectable (tests) — persistance des préférences.
  final LocalDatabase? database;

  static const String _keyLanguage = 'app.language';
  static const String _keyTheme = 'app.theme';
  static const String _keyWifiOnly = 'sync.wifiOnly';
  static const String _keyAutoDownload = 'downloads.auto';
  static const String _keyOnboardingCompleted = 'app.onboardingCompleted';

  String _language = 'fr';
  AppThemeMode _theme = AppThemeMode.dark;
  bool _syncWifiOnly = false;

  /// Téléchargement automatique (§11) — OFF par défaut ; la structure du
  /// réglage est prête et persistée, rien n'est téléchargé sans action.
  bool _autoDownload = false;

  /// Onboarding terminé (prompt 13 §4) — affiché au premier lancement
  /// uniquement ; cette préférence survit au redémarrage.
  bool _onboardingCompleted = false;

  bool _loaded = false;

  // ---- Getters (état actuel visible). ----

  /// Code langue BCP-47 de l'interface (« fr » par défaut).
  String get language => _language;

  /// Thème courant.
  AppThemeMode get theme => _theme;

  /// Synchronisation automatique en Wi-Fi uniquement (§10).
  bool get syncWifiOnly => _syncWifiOnly;

  /// Téléchargement automatique (OFF par défaut, §11).
  bool get autoDownload => _autoDownload;

  /// Onboarding déjà validé (prompt 13 §4).
  bool get onboardingCompleted => _onboardingCompleted;

  bool get loaded => _loaded;

  Future<void> _load() async {
    final LocalDatabase? db = database;
    if (db == null) {
      _loaded = true;
      return;
    }
    try {
      _language = await db.getSetting(_keyLanguage) ?? 'fr';
      _theme = (await db.getSetting(_keyTheme)) == 'system' ? AppThemeMode.system : AppThemeMode.dark;
      _syncWifiOnly = (await db.getSetting(_keyWifiOnly)) == 'true';
      _autoDownload = (await db.getSetting(_keyAutoDownload)) == 'true';
      _onboardingCompleted = (await db.getSetting(_keyOnboardingCompleted)) == 'true';
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> _persist(String key, String value) async {
    try {
      await database?.setSetting(key, value);
    } catch (_) {
      // Stockage inaccessible (§28) : l'état mémoire reste, l'écran
      // affiche déjà un message compréhensible via [AppSettingsError].
    }
  }

  // ---- Setters (modification réelle + notification + persistance). ----

  /// Change la langue de l'interface (§5/§6) — persistante.
  Future<void> setLanguage(String code) async {
    if (code == _language) return;
    _language = code;
    notifyListeners();
    await _persist(_keyLanguage, code);
  }

  Future<void> setTheme(AppThemeMode mode) async {
    if (mode == _theme) return;
    _theme = mode;
    notifyListeners();
    await _persist(_keyTheme, switch (mode) { AppThemeMode.dark => 'dark', AppThemeMode.system => 'system' });
  }

  /// §10 — Wi-Fi uniquement : le planificateur de synchro applique la
  /// contrainte réseau réelle (unmetered) via [AutoSyncScheduler].
  Future<void> setSyncWifiOnly(bool value) async {
    if (value == _syncWifiOnly) return;
    _syncWifiOnly = value;
    notifyListeners();
    await _persist(_keyWifiOnly, '$value');
  }

  Future<void> setAutoDownload(bool value) async {
    if (value == _autoDownload) return;
    _autoDownload = value;
    notifyListeners();
    await _persist(_keyAutoDownload, '$value');
  }

  /// Marque l'onboarding comme terminé (prompt 13 §4/§5) — persistant :
  /// l'onboarding ne réapparaît plus après fermeture/redémarrage.
  Future<void> completeOnboarding() async {
    if (_onboardingCompleted) return;
    _onboardingCompleted = true;
    notifyListeners();
    await _persist(_keyOnboardingCompleted, 'true');
  }

  // Note : la fréquence de synchronisation reste centralisée dans
  // NotificationSettings/SyncFrequency existants (composition, jamais de
  // redondance) — voir l'écran Paramètres.
}

/// Chaînes d'interface des écrans Paramètres (§5 : structure i18n en
/// place — les autres sections de l'app restent francophones pour cette
/// étape ; aucune traduction automatique externe).
class SettingsStrings {
  const SettingsStrings(this.language);

  final String language;

  String get title => language == 'en' ? 'Settings' : 'Paramètres';
  String get sectionAccount => language == 'en' ? 'ACCOUNT' : 'COMPTE';
  String get sectionPreferences => language == 'en' ? 'PREFERENCES' : 'PRÉFÉRENCES';
  String get sectionSync => language == 'en' ? 'SYNCHRONISATION' : 'SYNCHRONISATION';
  String get sectionNotifications => 'NOTIFICATIONS';
  String get sectionStorage => language == 'en' ? 'STORAGE' : 'STOCKAGE';
  String get sectionAppearance => language == 'en' ? 'APPEARANCE' : 'APPARENCE';
  String get sectionData => language == 'en' ? 'DATA' : 'DONNÉES';
  String get sectionAbout => language == 'en' ? 'ABOUT' : 'À PROPOS';

  String get preferredQuality => language == 'en' ? 'Preferred quality' : 'Qualité préférée';
  String get autoQualityDetail =>
      language == 'en' ? 'Best quality actually available' : 'Meilleure qualité réellement disponible';
  String get languageLabel => language == 'en' ? 'Language' : 'Langue';
  String get themeLabel => language == 'en' ? 'Theme' : 'Thème';
  String get themeDark => language == 'en' ? 'Dark' : 'Sombre';
  String get themeSystem => language == 'en' ? 'System' : 'Système';
  String get themeNote => language == 'en'
      ? 'The AnimeBox identity is dark — System currently follows the dark identity.'
      : 'L\'identité AnimeBox est sombre — Système suit actuellement l\'identité sombre.';

  String get syncFrequency => language == 'en' ? 'Background sync frequency' : 'Fréquence de synchronisation';
  String get syncFrequencyNote => language == 'en'
      ? 'Desired frequency — Android decides the real schedule.'
      : 'Fréquence souhaitée — Android décide de l\'heure réelle.';
  String get syncWifiOnly => language == 'en' ? 'Sync on Wi-Fi only' : 'Synchroniser uniquement en Wi-Fi';
  String get syncWifiOnlyNote =>
      language == 'en' ? 'Never downloads videos — metadata only.' : 'Ne télécharge jamais les vidéos — métadonnées seules.';
  String get autoDownloadLabel => language == 'en' ? 'Automatic download' : 'Téléchargement automatique';
  String get autoDownloadNote => language == 'en' ? 'OFF by default.' : 'OFF par défaut.';

  String get notificationsSummary => language == 'en' ? 'Open notification preferences' : 'Ouvrir les préférences de notifications';
  String get episodesNotif => language == 'en' ? 'New episodes' : 'Nouveaux épisodes';
  String get downloadsNotif => language == 'en' ? 'Downloads' : 'Téléchargements';
  String get downloadProgressNotif =>
      language == 'en' ? 'Download progress' : 'Progression des téléchargements';

  String get spaceUsed => language == 'en' ? 'Space used by AnimeBox' : 'Espace utilisé par AnimeBox';
  String get storageDownloads => language == 'en' ? 'Downloads' : 'Téléchargements';
  String get storageCache => 'Cache';
  String get storageFree => language == 'en' ? 'Available' : 'Disponible';
  String get storageUnknown => language == 'en' ? 'Unknown' : 'Inconnue';
  String get clearCache => language == 'en' ? 'Clear cache' : 'Vider le cache';
  String get clearCacheConfirm => language == 'en'
      ? 'Clear the application cache? Your downloads, favorites, history, sources and catalog are kept.'
      : 'Vider le cache de l\'application ? Téléchargements, favoris, historique, sources et catalogue seront conservés.';
  String get manageDownloads => language == 'en' ? 'Manage downloads' : 'Gérer les téléchargements';
  String get lowSpace => language == 'en'
      ? 'Your storage is almost full — freed space is recomanded.'
      : 'Votre espace de stockage est presque plein.';
  String get manageStorage => language == 'en' ? 'Manage storage' : 'Gérer le stockage';

  String get eraseLocalData => language == 'en' ? 'Erase local data' : 'Effacer les données locales';
  String get eraseLocalDataNote => language == 'en'
      ? 'Catalog, favorites, history, preferences — destructive action.'
      : 'Catalogue, favoris, historique, préférences — action destructive.';
  String get eraseLocalDataConfirm => language == 'en'
      ? 'This will erase your AnimeBox local data (catalog, favorites, history, preferences). Downloaded videos will be kept. Continue?'
      : 'Cette action supprimera vos données locales AnimeBox (catalogue, favoris, historique, préférences). Les vidéos téléchargées seront conservées. Continuer ?';
  String get resetApp => language == 'en' ? 'Reset AnimeBox' : 'Réinitialiser AnimeBox';
  String get resetAppNote => language == 'en'
      ? 'All data, downloads and Telegram sign-out — final warning required.'
      : 'Toutes les données, téléchargements et session Telegram — avertissement final exigé.';
  String get resetAppConfirm => language == 'en'
      ? 'This will RESET AnimeBox: catalog, favorites, history, preferences, sources, downloaded videos AND Telegram session will be erased. This action is irreversible. Continue?'
      : 'Cette action RÉINITIALISE AnimeBox : catalogue, favoris, historique, préférences, sources, vidéos téléchargées ET session Telegram seront effacés. Action irréversible. Continuer ?';
  String get resetAppFinal => language == 'en'
      ? 'Final warning — all data will be lost. Confirm reset?'
      : 'Dernier avertissement — toutes vos données seront perdues. Confirmer la réinitialisation ?';

  String get privacyNote => language == 'en'
      ? 'Your data stays on your device whenever possible. AnimeBox does not route your videos through an intermediate server.'
      : 'Vos données restent sur votre appareil lorsque cela est possible. AnimeBox ne fait pas transiter vos vidéos par un serveur intermédiaire.';
  String get about => language == 'en' ? 'About AnimeBox' : 'À propos d\'AnimeBox';
  String get buildLabel => 'Build';

  String get cancel => language == 'en' ? 'Cancel' : 'Annuler';
  String get confirm => language == 'en' ? 'Confirm' : 'Confirmer';
  String get erase => language == 'en' ? 'Erase' : 'Effacer';
  String get delete => language == 'en' ? 'Delete' : 'Supprimer';
  String get done => language == 'en' ? 'Done' : 'Terminé';
  String get ok => 'OK';
}
