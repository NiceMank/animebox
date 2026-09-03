import 'dart:async';
import 'dart:io';

/// Instantané RÉEL du stockage AnimeBox (prompt 12 §12).
/// Toute valeur non mesurable est `null` — jamais inventée.
class StorageSnapshot {
  const StorageSnapshot({
    this.downloadsBytes,
    this.cacheBytes,
    this.freeBytes,
  });

  /// Taille totale des fichiers téléchargés (lia_FileStat réel).
  final int? downloadsBytes;

  /// Taille du cache applicatif (hors vidéos téléchargées).
  final int? cacheBytes;

  /// Espace libre sur le volume (StatFs Android — null si inconnu).
  final int? freeBytes;
}

/// Contrat du service de stockage (§12/13/14) — abstraction pour les tests.
abstract class StorageService {
  /// Mesure réelle des espaces (nést pas bloquant, §35).
  Future<StorageSnapshot> snapshot();

  /// Vide UNIQUEMENT le cache applicatif (§13) : ni vidéos téléchargées,
  /// ni favoris, ni historique, ni catalogue, ni sources ne sont touchés.
  /// Retourne le nombre d'octets libérés (0 si rien).
  Future<int> clearCache();

  /// Supprime le fichier d'un téléchargement terminé (§14).
  Future<void> deleteFile(String? path);
}

/// Implémentation de production : fichiers réels sur l'appareil.
class DeviceStorageService implements StorageService {
  DeviceStorageService({required this.cacheDirectory, this.freeBytesOf});

  /// Dossier cache réel de l'application — null s'il est inaccessible
  /// (les tailles associées s'affichent alors « inconnues », §12).
  final Directory? cacheDirectory;

  /// Mesure de l'espace libre du volume (StatFs — null toléré).
  final Future<int?> Function()? freeBytesOf;

  late List<String> _downloadPaths = const [];

  /// Chemins des fichiers téléchargés réellement présents — alimenté par
  /// l'écran depuis le DownloadManager (données réelles §12).
  void setDownloadPaths(Iterable<String?> paths) {
    _downloadPaths = [for (final String? p in paths) if (p != null && p.isNotEmpty) p];
  }

  static Future<int?> _sizeOf(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) return await file.length();
      return 0;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StorageSnapshot> snapshot() async {
    // Téléchargements : taille des fichiers organisés (réels).
    int? totalDownloads = 0;
    for (final String path in _downloadPaths) {
      final int? size = await _sizeOf(path);
      if (size == null) {
        totalDownloads = null;
        break;
      }
      totalDownloads = (totalDownloads ?? 0) + size;
    }

    // Cache applicatif (§12) — calcul sans bloquer l'interface (§35).
    int? cacheTotal = 0;
    try {
      final Directory? cacheDir = cacheDirectory;
      if (cacheDir != null && await cacheDir.exists()) {
        await for (final FileSystemEntity entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            try {
              cacheTotal = (cacheTotal ?? 0) + await entity.length();
            } catch (_) {
              cacheTotal = null;
            }
          }
        }
      }
    } catch (_) {
      cacheTotal = null;
    }

    final Future<int?> Function()? freeBytesOf = this.freeBytesOf;
    final int? free = freeBytesOf == null ? null : await freeBytesOf();
    return StorageSnapshot(downloadsBytes: totalDownloads, cacheBytes: cacheTotal, freeBytes: free);
  }

  @override
  Future<int> clearCache() async {
    int freed = 0;
    try {
      final Directory? cacheDir = cacheDirectory;
      if (cacheDir == null || !await cacheDir.exists()) return 0;
      await for (final FileSystemEntity entity in cacheDir.list()) {
        try {
          if (entity is File) {
            freed += await entity.length();
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          // continue — le nettoyage est best-effort (§28).
        }
      }
    } catch (_) {
      // Cache inaccessible (§28) : message géré à l'écran.
    }
    return freed;
  }

  @override
  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Fichier déjà parti — statut cohérent.
    }
  }
}

/// Service de stockage simulé (tests uniquement).
class FakeStorageService implements StorageService {
  StorageSnapshot current = const StorageSnapshot();
  int freedOnClear = 0;
  int clearCalls = 0;
  final List<String?> deletedPaths = [];

  @override
  Future<StorageSnapshot> snapshot() async => current;

  @override
  Future<int> clearCache() async {
    clearCalls++;
    return freedOnClear;
  }

  @override
  Future<void> deleteFile(String? path) async {
    deletedPaths.add(path);
  }
}

/// Format lisible d'une taille (affichage §12).
String formatBytes(int bytes) {
  if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} Go';
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} Mo';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  return '$bytes o';
}
