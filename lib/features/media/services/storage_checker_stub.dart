import 'storage_checker.dart';

/// Version sans mesure (web / environnement sans canal plateforme) :
/// l'espace est toujours inconnu — jamais inventé.
StorageChecker createStorageChecker() => NullStorageChecker();

class NullStorageChecker implements StorageChecker {
  @override
  Future<int?> freeBytes(String? path) async => null;
}
