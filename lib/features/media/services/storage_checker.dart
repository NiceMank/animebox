/// Vérification de l'espace de stockage disponible (règle 15).
///
/// La mesure réelle vient du canal plateforme Android (`StatFs`). Quand la
/// mesure est impossible (plateforme, tests), le résultat est `null` :
/// AnimeBox n'invente jamais une valeur d'espace — il saute alors
/// simplement la vérification.
library;

import 'storage_checker_io.dart' if (dart.library.js_interop) 'storage_checker_stub.dart'
    as implementation;

/// Contrat du vérificateur d'espace.
abstract class StorageChecker {
  /// Octets libres sur le volume hébergeant [path] — null si inconnu.
  Future<int?> freeBytes(String? path);
}

StorageChecker createStorageChecker() => implementation.createStorageChecker();

/// Vérificateur à valeur fixe (tests uniquement).
class FixedStorageChecker implements StorageChecker {
  FixedStorageChecker(this.freeBytesValue);

  final int? freeBytesValue;

  @override
  Future<int?> freeBytes(String? path) async => freeBytesValue;
}
