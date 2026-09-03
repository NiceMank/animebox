import 'package:path_provider/path_provider.dart';

import '../../anime/data/repositories/anime_repository.dart';
import '../../local/data/local_database.dart';
import '../../media/services/media_service.dart';
import '../../media/services/storage_checker.dart';
import '../../notifications/services/notification_settings.dart';
import '../../telegram/data/services/telegram_service.dart';
import 'app_settings.dart';
import 'data_care_service.dart';
import 'storage_service.dart';
import 'version_reader.dart';

/// Adaptateur : purge des téléchargements via [MediaService] existant
/// (suppression fichier + base — même chemin que l'écran Téléchargements).
class MediaDownloadPurger implements DownloadPurger {
  MediaDownloadPurger(this._media);

  final MediaService _media;

  @override
  Future<void> delete(String versionId) => _media.deleteDownload(versionId);

  @override
  List<String> downloadVersionIds() =>
      <String>[for (final task in _media.downloadManager.tasks) task.versionId];

  @override
  List<String?> downloadFilePaths() =>
      <String?>[for (final task in _media.downloadManager.tasks) task.localPath];
}

/// Adaptateur : déconnexion via [TelegramService] existant (session
/// révoquée, catalogue conservé/en base — logique éprouvée prompt 11).
class TelegramServiceSignOut implements TelegramSignOut {
  TelegramServiceSignOut(this._service);

  final TelegramService _service;

  @override
  Future<void> disconnect() => _service.disconnect();
}

/// Dépendances de la section Paramètres (prompt 12 §26) :
/// UI → Controller ([AppSettings]) → Repository → Stockage.
///
/// Tout est injectable : les tests fournissent des simulacres,
/// l'application fournit les vraies briques — aucune valeur fictive
/// n'apparaît à l'écran (§27).
class SettingsDependencies {
  const SettingsDependencies({
    required this.appSettings,
    this.notificationSettings,
    this.repository,
    this.telegramService,
    this.mediaService,
    this.storageChecker,
    this.database,
    this.storageService,
    this.versionReader = const VersionReader(),
  });

  /// Préférences centrales persistantes (langue, thème, Wi-Fi…).
  final AppSettings appSettings;

  /// Réglages de notifications/synchronisation existants (réutilisés,
  /// jamais dupliqués — composition).
  final NotificationSettings? notificationSettings;

  /// Dépôt — qualité préférée (réglages de lecture déjà persistés).
  final AnimeRepository? repository;

  final TelegramService? telegramService;

  /// Téléchargements (tailles réelles, multi-suppression §14).
  final MediaService? mediaService;

  /// Mesure de l'espace libre (StatFs Android — null toléré).
  final StorageChecker? storageChecker;

  final LocalDatabase? database;

  /// Service de stockage injecté (tests) — sinon dossier cache réel.
  final StorageService? storageService;

  /// Lecteur de la version RÉELLE du projet (§21/§22).
  final VersionReader versionReader;

  /// Service « Données » branché sur les vraies briques de l'écran.
  DataCareService buildDataCareService() => DataCareService(
        database: database,
        downloads: mediaService == null ? null : MediaDownloadPurger(mediaService!),
        telegram: telegramService == null ? null : TelegramServiceSignOut(telegramService!),
      );

  /// Résout le service de stockage : injecté en test, sinon mesure le
  /// VRAI dossier cache de l'application (path_provider).
  Future<StorageService> resolveStorageService() async {
    final StorageService? injected = storageService;
    if (injected != null) return injected;
    try {
      final cacheDir = await getTemporaryDirectory();
      return DeviceStorageService(
        cacheDirectory: cacheDir,
        freeBytesOf: () async {
          final StorageChecker? checker = storageChecker;
          if (checker == null) return null;
          try {
            final docs = await getApplicationDocumentsDirectory();
            return checker.freeBytes(docs.path);
          } catch (_) {
            return null;
          }
        },
      );
    } catch (_) {
      // Dossier cache inaccessible : valeurs affichées « inconnues ».
      return DeviceStorageService(
        cacheDirectory: null,
        freeBytesOf: () async => null,
      );
    }
  }
}
