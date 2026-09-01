import '../models/anime.dart';

/// Résultat d'une recherche dans le catalogue backend.
///
/// Les états d'interface du prompt (récupération en cours / trouvées /
/// introuvables / correspondance incertaine / mise à jour / erreur /
/// données hors-ligne) sont portés par [status] et [message].
class CatalogSearchResult {
  const CatalogSearchResult({
    required this.status,
    this.anime = const [],
    this.message,
  });

  final CatalogSearchStatus status;
  final List<Anime> anime;
  final String? message;
}

/// États d'une recherche catalogue (affichés par l'écran de recherche).
enum CatalogSearchStatus {
  /// Requête en cours.
  loading,

  /// Résultats trouvés (tous enrichis).
  found,

  /// Aucun résultat côté serveur.
  notFound,

  /// Des résultats existent mais au moins une correspondance est incertaine
  /// (METADATA_REVIEW_REQUIRED) : aucune association aveugle.
  review,

  /// Erreur réseau/serveur.
  error,

  /// Backend injoignable : seules les dernières données connues (cache
  /// local) sont proposées.
  offline,
}

/// Capacités « catalogue » d'un dépôt adossé au backend.
///
/// Les écrans détectent cette interface (`repository is CatalogRepository`)
/// pour brancher la recherche serveur, l'actualisation et la correction
/// manuelle — le dépôt mocké de démonstration n'en a pas besoin.
abstract class CatalogRepository {
  /// Charge (ou rafraîchit) le catalogue depuis le backend.
  ///
  /// En cas d'échec réseau, les dernières données connues sont conservées
  /// et [isOffline] passe à `true` (aucune perte de données).
  Future<bool> refreshCatalog();

  /// Recherche par titre (canonique, original, alternatif, alias).
  Future<CatalogSearchResult> searchCatalog(String query, {int limit = 25});

  /// Charge la fiche complète d'un animé (saisons, épisodes, versions).
  /// Mise en cache : les appels suivants réutilisent les données locales.
  Future<Anime?> refreshAnime(String id);

  /// Actualise les métadonnées d'une fiche (bouton d'administration).
  Future<bool> refreshAnimeMetadata(String id);

  /// Correction manuelle (admin) : associe explicitement un candidat.
  Future<bool> applyMetadataCandidate(String animeId, String providerId, {String? provider});

  /// Correction manuelle (admin) : ferme la demande de revue.
  Future<bool> ignoreMetadataReview(String animeId);

  /// Correction manuelle (admin) : corrige le titre affiché.
  Future<bool> updateDisplayTitle(String animeId, String title);

  /// Correction manuelle (admin) : reclasser une publication
  /// (saison/épisode), sans jamais la supprimer.
  Future<bool> reassignVersion(
    String versionId, {
    int? seasonNumber,
    int? episodeNumber,
  });

  /// Backend injoignable lors du dernier rafraîchissement ?
  bool get isOffline;

  /// Un rafraîchissement du catalogue est-il en cours ?
  bool get isLoadingCatalog;

  /// Date du dernier rafraîchissement réussi (null si jamais).
  DateTime? get catalogUpdatedAt;
}
