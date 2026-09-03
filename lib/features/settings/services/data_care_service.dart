import '../../local/data/local_database.dart';

/// Contrat minimal du planificateur de téléchargements pour la purge —
/// composition sans dépendance dure (testable, §26).
abstract class DownloadPurger {
  /// Supprime le téléchargement (et son fichier) ; ne lève rien.
  Future<void> delete(String versionId);

  /// versionIds des téléchargements connus (tous statuts).
  List<String> downloadVersionIds();

  /// Chemins de fichiers téléchargés connus (pour purge complète §18).
  List<String?> downloadFilePaths();
}

/// Contrat minimal de la session Telegram (déconnexion §18).
abstract class TelegramSignOut {
  Future<void> disconnect();
}

/// Résultat d'une opération destructive — compteurs réels, jamais faux.
class DataCareResult {
  const DataCareResult({
    required this.success,
    this.downloadsRemoved = 0,
    this.signedOut = false,
    this.error,
  });

  final bool success;
  final int downloadsRemoved;

  /// True si la session Telegram a bien été révoquée.
  final bool signedOut;
  final String? error;
}

/// Service « Données » (prompt 12 §16/§17/§18).
///
/// Deux actions, toutes destructrices et précédées d'une confirmation
/// explicite AFFICHÉE PAR L'ÉCRAN (le service n'affiche rien) :
/// - [eraseLocalData] : catalogue, favoris, historique, préférences —
///   conserve compte Telegram, sources et fichiers téléchargés (§16).
/// - [resetEverything] : TOUT (§18) + suppression des fichiers vidéo +
///   déconnexion Telegram.
class DataCareService {
  DataCareService({
    LocalDatabase? database,
    DownloadPurger? downloads,
    TelegramSignOut? telegram,
  })  : _database = database,
        _downloads = downloads,
        _telegram = telegram;

  final LocalDatabase? _database;
  final DownloadPurger? _downloads;
  final TelegramSignOut? _telegram;

  /// §16 — Effacement des données locales (sans déconnexion ni fichiers).
  Future<DataCareResult> eraseLocalData() async {
    final LocalDatabase? db = _database;
    if (db == null) {
      return const DataCareResult(success: false, error: 'stockage-inaccessible');
    }
    try {
      await db.clearLocalData();
      return const DataCareResult(success: true);
    } catch (e) {
      return DataCareResult(success: false, error: e.toString());
    }
  }

  /// §18 — Réinitialisation complète : fichiers vidéo effacés, base vidée
  /// (toutes tables), session Telegram déconnectée. Irréversible — l'écran
  /// exige une double confirmation AVANT d'appeler cette méthode (§17).
  Future<DataCareResult> resetEverything() async {
    int removed = 0;

    // 1) Suppression des téléchargements connus (base + fichiers).
    final DownloadPurger? downloads = _downloads;
    if (downloads != null) {
      final List<String> versionIds = List<String>.of(downloads.downloadVersionIds());
      for (final String versionId in versionIds) {
        try {
          await downloads.delete(versionId);
          removed++;
        } catch (_) {
          // best-effort — on continue la purge (§28).
        }
      }
    }

    // 2) Purge complète de la base locale.
    final LocalDatabase? db = _database;
    try {
      await db?.resetEverything();
    } catch (e) {
      return DataCareResult(success: false, downloadsRemoved: removed, error: e.toString());
    }

    // 3) Déconnexion Telegram (session révoquée — §18).
    bool signedOut = false;
    final TelegramSignOut? telegram = _telegram;
    if (telegram != null) {
      try {
        await telegram.disconnect();
        signedOut = true;
      } catch (_) {
        signedOut = false;
      }
    }

    return DataCareResult(success: true, downloadsRemoved: removed, signedOut: signedOut);
  }
}
