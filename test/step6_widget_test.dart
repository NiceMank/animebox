import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/anime.dart';
import 'package:animebox/features/anime/data/models/anime_alias.dart';
import 'package:animebox/features/anime/data/models/library_entry.dart';
import 'package:animebox/features/anime/data/models/metadata_status.dart';
import 'package:animebox/features/anime/data/models/playback_progress.dart';
import 'package:animebox/features/anime/data/models/playback_settings.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/models/search_filters.dart';
import 'package:animebox/features/anime/data/repositories/anime_repository.dart';
import 'package:animebox/features/anime/data/repositories/catalog_repository.dart';
import 'package:animebox/features/details/anime_details_screen.dart';
import 'package:animebox/features/home/home_screen.dart';
import 'package:animebox/features/search/search_screen.dart';

const Anime _solo = Anime(
  id: '1',
  title: 'Solo Leveling',
  posterAsset: 'assets/img/poster_solo_leveling.png',
  backdropAsset: 'assets/img/backdrop_solo_leveling.png',
  description: 'Synopsis.',
  genres: ['Action'],
  year: 2024,
  seasons: [],
  canonicalTitle: 'Solo Leveling',
  originalTitle: 'Ore dake Level Up na Ken',
  metadataStatus: MetadataStatus.found,
  metadataSource: 'local',
);

/// Dépôt factice : données fixes + états de recherche contrôlés.
class FakeCatalogRepository extends ChangeNotifier implements AnimeRepository, CatalogRepository {
  FakeCatalogRepository({this.offline = false});

  bool offline;

  /// Anime renvoyé par [byId]/[allAnime] (remplaçable par test).
  Anime animeOverride = _solo;

  CatalogSearchResult nextSearchResult =
      const CatalogSearchResult(status: CatalogSearchStatus.found);

  /// Quand renseigné, la recherche reste en attente jusqu'à la complétion
  /// (permet de tester l'état « Récupération en cours… »).
  Completer<CatalogSearchResult>? searchGate;

  int searchCalls = 0;
  int refreshCalls = 0;

  @override
  bool get isOffline => offline;

  @override
  bool get isLoadingCatalog => false;

  @override
  DateTime? get catalogUpdatedAt => DateTime(2026, 9, 1);

  @override
  Future<bool> refreshCatalog() async {
    refreshCalls += 1;
    return !offline;
  }

  @override
  Future<CatalogSearchResult> searchCatalog(String query, {int limit = 25}) async {
    searchCalls += 1;
    final Completer<CatalogSearchResult>? gate = searchGate;
    if (gate != null) return gate.future;
    return nextSearchResult;
  }

  @override
  Future<Anime?> refreshAnime(String id) async => _solo;

  @override
  Future<bool> refreshAnimeMetadata(String id) async => true;

  @override
  Future<bool> applyMetadataCandidate(String animeId, String providerId, {String? provider}) async => true;

  @override
  Future<bool> ignoreMetadataReview(String animeId) async => true;

  @override
  Future<bool> updateDisplayTitle(String animeId, String title) async => true;

  @override
  Future<bool> reassignVersion(String versionId, {int? seasonNumber, int? episodeNumber}) async => true;

  @override
  List<Anime> get allAnime => [animeOverride];

  @override
  Anime? byId(String id) => id == animeOverride.id ? animeOverride : null;

  @override
  Anime? get featured => animeOverride;

  @override
  List<Anime> get latestReleases => const [];

  @override
  List<String> get recentEpisodeIds => const [];

  @override
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty}) =>
      query.isEmpty ? const [] : const [_solo];

  @override
  List<LibraryEntry> get libraryEntries => const [];

  @override
  LibraryEntry? libraryEntryFor(String animeId) => null;

  @override
  List<String> get availableGenres => const ['Action'];

  @override
  List<String> get availableLanguages => const ['VOSTFR'];

  @override
  List<String> get availableSources => const ['Telegram'];

  @override
  List<int> get availableSeasons => const [1];

  @override
  Duration? episodeProgress(String animeId, String episodeId) => null;

  @override
  void recordProgress(
    String animeId,
    String episodeId,
    Duration position, {
    Duration duration = Duration.zero,
    bool completed = false,
  }) {}

  @override
  bool episodeCompleted(String animeId, String episodeId) => false;

  @override
  void setPreferredQuality(QualityPreference preference) {}

  @override
  List<PlaybackProgress> progressHistory(String animeId) => const [];

  @override
  List<PlaybackProgress> get watchHistory => const [];

  @override
  void clearWatchHistory() {}

  @override
  PlaybackSettings get playbackSettings => const PlaybackSettings();

  @override
  void setAutoPlayNext(bool enabled) {}

  @override
  void toggleFollow(String animeId) {}

  @override
  void toggleFavorite(String animeId) {}
}

Future<void> _pumpSearch(WidgetTester tester, FakeCatalogRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SearchScreen(repository: repository))),
  );
  await tester.pumpAndSettle();
}

Future<void> _typeQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(); // reconstruction immédiate
  await tester.pump(const Duration(milliseconds: 400)); // anti-rebond
}

void main() {
  testWidgets('recherche distante : état de récupération puis résultats', (WidgetTester tester) async {
    final FakeCatalogRepository repository = FakeCatalogRepository();
    final Completer<CatalogSearchResult> gate = Completer<CatalogSearchResult>();
    repository.searchGate = gate;
    await _pumpSearch(tester, repository);

    await _typeQuery(tester, 'Solo');
    // La requête est en vol : l'état « Récupération en cours… » est affiché.
    expect(find.text('Récupération en cours…'), findsOneWidget);

    gate.complete(const CatalogSearchResult(status: CatalogSearchStatus.found, anime: [_solo]));
    await tester.pumpAndSettle();
    expect(repository.searchCalls, 1);
    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('1 résultat(s)'), findsOneWidget);
  });

  testWidgets('recherche distante : introuvable', (WidgetTester tester) async {
    final FakeCatalogRepository repository = FakeCatalogRepository();
    repository.nextSearchResult = const CatalogSearchResult(status: CatalogSearchStatus.notFound);
    await _pumpSearch(tester, repository);

    await _typeQuery(tester, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
  });

  testWidgets('recherche distante : hors-ligne avec indication claire', (WidgetTester tester) async {
    final FakeCatalogRepository repository = FakeCatalogRepository();
    repository.nextSearchResult = const CatalogSearchResult(
      status: CatalogSearchStatus.offline,
      anime: [_solo],
    );
    await _pumpSearch(tester, repository);

    await _typeQuery(tester, 'Solo');
    await tester.pumpAndSettle();
    expect(find.textContaining('Hors-ligne'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    // Les dernières données connues restent affichées.
    expect(find.text('Solo Leveling'), findsOneWidget);
  });

  testWidgets('recherche distante : correspondance incertaine signalée', (WidgetTester tester) async {
    final FakeCatalogRepository repository = FakeCatalogRepository();
    const Anime review = Anime(
      id: '2',
      title: 'Solo Leveling Special',
      posterAsset: 'assets/img/poster_placeholder.png',
      backdropAsset: 'assets/img/poster_placeholder.png',
      description: '',
      genres: [],
      year: 2024,
      seasons: [],
      metadataStatus: MetadataStatus.reviewRequired,
      metadataCandidates: [MetadataCandidateInfo(providerId: '1', title: 'Solo Leveling', score: 0.7)],
    );
    repository.nextSearchResult = const CatalogSearchResult(
      status: CatalogSearchStatus.review,
      anime: [review],
      message: 'Certaines correspondances restent à vérifier.',
    );
    await _pumpSearch(tester, repository);

    await _typeQuery(tester, 'Solo');
    await tester.pumpAndSettle();
    expect(find.textContaining('Certaines correspondances restent à vérifier'), findsOneWidget);
    expect(find.text('À vérifier'), findsOneWidget);
  });

  testWidgets('accueil : bandeau hors-ligne + bouton réessayer', (WidgetTester tester) async {
    final FakeCatalogRepository repository = FakeCatalogRepository(offline: true);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(repository: repository, onSearchTap: () {}, onLibraryTap: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hors-ligne — dernières données connues'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 1);
  });

  testWidgets('fiche animé : bannière « Correspondance à vérifier »', (WidgetTester tester) async {
    const Anime review = Anime(
      id: '1',
      title: 'Solo Leveling Special',
      posterAsset: 'assets/img/poster_placeholder.png',
      backdropAsset: 'assets/img/poster_placeholder.png',
      description: 'Synopsis.',
      genres: [],
      year: 2024,
      seasons: [],
      metadataStatus: MetadataStatus.reviewRequired,
      metadataCandidates: [MetadataCandidateInfo(providerId: '1', title: 'Solo Leveling', score: 0.7)],
    );
    final FakeCatalogRepository reviewRepository = FakeCatalogRepository()
      ..animeOverride = review;
    await tester.pumpWidget(
      MaterialApp(home: AnimeDetailsScreen(repository: reviewRepository, animeId: '1')),
    );
    await tester.pumpAndSettle();
    // La bannière vit dans l'onglet « Détails » de la fiche.
    await tester.tap(find.text('Détails'));
    await tester.pumpAndSettle();
    expect(find.text('Correspondance à vérifier'), findsOneWidget);
    expect(find.text('Corriger'), findsOneWidget);
  });
}
