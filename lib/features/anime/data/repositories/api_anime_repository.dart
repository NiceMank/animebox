import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../telegram/data/services/telegram_session_service.dart';
import '../models/anime.dart';
import '../models/anime_alias.dart';
import '../models/episode.dart';
import '../models/episode_version.dart';
import '../models/library_entry.dart';
import '../models/metadata_status.dart';
import '../models/playback_progress.dart';
import '../models/playback_settings.dart';
import '../models/video_quality.dart';
import '../models/search_filters.dart';
import '../models/season.dart';
import 'anime_repository.dart';
import 'catalog_repository.dart';

/// Affiche de secours (aucun poster renvoyé par le backend).
const String kFallbackPosterAsset = 'assets/img/poster_placeholder.png';

/// Dépôt du catalogue adossé au backend API (étape 6).
///
/// - Toutes les données viennent de `/api/catalog/*` (Bearer session).
/// - Cache local en mémoire : les dernières données connues restent
///   affichables si le backend devient injoignable (mode hors-ligne).
/// - Chargement progressif : la liste est légère, la fiche complète
///   (saisons, épisodes, versions) est chargée à l'ouverture puis mise
///   en cache.
/// - La meilleure version d'un épisode est proposée en premier, toutes les
///   autres restent accessibles (aucune suppression).
class ApiAnimeRepository extends ChangeNotifier implements AnimeRepository, CatalogRepository {
  ApiAnimeRepository({
    required String baseUrl,
    required TelegramSessionService session,
    http.Client? client,
    this.pageSize = 50,
    this.timeout = const Duration(seconds: 12),
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        // ignore: prefer_initializing_formals
        _session = session,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final TelegramSessionService _session;
  final http.Client _client;
  final bool _ownsClient;

  /// Taille de page pour le chargement paginé du catalogue.
  final int pageSize;

  /// Délai maximal des requêtes (injectable pour les tests).
  final Duration timeout;

  // ---- Données connues (dernières valeurs affichées) ----

  final Map<String, Anime> _anime = {};
  final List<String> _recentIds = [];
  final Map<String, LibraryEntry> _library = {};
  PlaybackSettings _settings = const PlaybackSettings();

  bool _isOffline = false;
  bool _isLoading = false;
  DateTime? _catalogUpdatedAt;
  String? _lastError;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Catalogue (CatalogRepository)
  // ---------------------------------------------------------------------

  @override
  bool get isOffline => _isOffline;

  @override
  bool get isLoadingCatalog => _isLoading;

  @override
  DateTime? get catalogUpdatedAt => _catalogUpdatedAt;

  /// Dernière erreur de rafraîchissement (null si tout va bien).
  String? get lastError => _lastError;

  /// Résout une URL d'image relative (ex. `/api/assets/images/x.jpg`) en
  /// URL absolue vers le backend.
  String _absolute(String url) => url.startsWith('/') ? '$_baseUrl$url' : url;

  /// Charge le catalogue : liste paginée (léger) + flux des épisodes récents.
  /// En cas d'échec, les données déjà connues sont conservées (hors-ligne).
  @override
  Future<bool> refreshCatalog() async {
    if (_isLoading) return false;
    _isLoading = true;
    _lastError = null;
    _notify();
    try {
      final Map<String, dynamic> firstPage = await _request('GET', '/api/catalog/anime', query: {
        'offset': '0',
        'limit': '$pageSize',
      });
      final int total = (firstPage['total'] as num?)?.toInt() ?? 0;
      final List<dynamic> animeJson = firstPage['anime'] as List<dynamic>? ?? const [];
      final Map<String, Anime> fresh = {
        for (final dynamic item in animeJson)
          if (item is Map<String, dynamic>)
            _idOf(item): _animeFromJson(item),
      };
      // Pagination : on continue tant qu'il reste des pages (borné).
      int offset = animeJson.length;
      while (offset < total && offset < 2000) {
        final Map<String, dynamic> page = await _request('GET', '/api/catalog/anime', query: {
          'offset': '$offset',
          'limit': '$pageSize',
        });
        final List<dynamic> items = page['anime'] as List<dynamic>? ?? const [];
        if (items.isEmpty) break;
        for (final dynamic item in items) {
          if (item is Map<String, dynamic>) fresh[_idOf(item)] = _animeFromJson(item);
        }
        offset += items.length;
      }

      // Épisodes récents (avec meilleure version) — alimentent l'accueil.
      final Map<String, dynamic> recentPage = await _request('GET', '/api/catalog/recent', query: {
        'limit': '50',
      });
      final List<dynamic> recentJson = recentPage['recent'] as List<dynamic>? ?? const [];
      final List<String> recentIds = [];
      for (final dynamic item in recentJson) {
        if (item is! Map<String, dynamic>) continue;
        final String id = item['anime_id'].toString();
        recentIds.add(id);
        // Complète la fiche légère avec le dernier épisode publié.
        final Anime? known = fresh[id] ?? _anime[id];
        final Anime withEpisode = _animeWithRecentEpisode(known, item);
        fresh[id] = withEpisode;
      }

      // Remplace l'état connu uniquement après un rafraîchissement complet :
      // les fiches détaillées déjà chargées (plus riches) sont conservées.
      for (final MapEntry<String, Anime> entry in fresh.entries) {
        final Anime? existing = _anime[entry.key];
        _anime[entry.key] =
            (existing != null && existing.seasons.isNotEmpty) ? existing : entry.value;
      }
      _recentIds
        ..clear()
        ..addAll(recentIds);
      _isOffline = false;
      _catalogUpdatedAt = DateTime.now();
      _notify();
      return true;
    } catch (error) {
      // Hors-ligne : on GARDE les dernières données connues.
      _isOffline = true;
      _lastError = _describe(error);
      _notify();
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Recherche distante (titre canonique, original, alternatifs, alias).
  /// Si le backend est injoignable, renvoie [CatalogSearchStatus.offline]
  /// avec les résultats du cache local (dernières données connues).
  @override
  Future<CatalogSearchResult> searchCatalog(String query, {int limit = 25}) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const CatalogSearchResult(status: CatalogSearchStatus.notFound);
    try {
      final Map<String, dynamic> response = await _request('GET', '/api/catalog/search', query: {
        'q': trimmed,
        'limit': '$limit',
      });
      final List<dynamic> results = response['results'] as List<dynamic>? ?? const [];
      if (results.isEmpty) {
        return const CatalogSearchResult(
          status: CatalogSearchStatus.notFound,
          message: 'Aucun animé ne correspond à cette recherche.',
        );
      }
      final List<Anime> anime = [
        for (final dynamic item in results)
          if (item is Map<String, dynamic>) _animeFromJson(item, cache: true),
      ];
      // Correspondance incertaine ? Jamais d'association aveugle :
      // l'écran affiche le badge « À vérifier » sur ces résultats.
      final bool hasReview = anime.any((Anime item) => item.needsMetadataReview);
      return CatalogSearchResult(
        status: hasReview ? CatalogSearchStatus.review : CatalogSearchStatus.found,
        anime: anime,
        message: hasReview
            ? 'Certaines correspondances restent à vérifier.'
            : null,
      );
    } catch (error) {
      // Hors-ligne : recherche dans les dernières données connues.
      final List<Anime> local = search(trimmed).take(limit).toList();
      _isOffline = true;
      _notify();
      return CatalogSearchResult(
        status: CatalogSearchStatus.offline,
        anime: local,
        message: 'Backend injoignable — résultats issus des données locales.',
      );
    }
  }

  /// Charge la fiche complète (saisons, épisodes, versions) puis la met en
  /// cache : les appels suivants réutilisent les données locales.
  @override
  Future<Anime?> refreshAnime(String id) async {
    try {
      final Map<String, dynamic> response = await _request('GET', '/api/catalog/anime/$id');
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson == null) return null;
      final Anime anime = _animeDetailFromJson(animeJson);
      // Conserve la progression locale (réservée au dépôt, pas à l'API).
      final LibraryEntry? entry = _library[id];
      _anime[id] = anime;
      if (entry != null) {
        _library[id] = entry.copyWith();
        _library[id] = LibraryEntry(
          anime: anime,
          isFavorite: entry.isFavorite,
          progressMap: entry.progressMap,
          resumeEpisodeId: entry.resumeEpisodeId,
        );
      }
      _notify();
      return anime;
    } catch (error) {
      _isOffline = true;
      _lastError = _describe(error);
      _notify();
      return _anime[id];
    }
  }

  @override
  Future<bool> refreshAnimeMetadata(String id) async {
    try {
      final Map<String, dynamic> response =
          await _request('POST', '/api/catalog/anime/$id/refresh-metadata');
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson != null) _anime[id] = _animeFromJson(animeJson);
      _notify();
      return animeJson != null;
    } catch (_) {
      return false;
    }
  }

  // ---- Correction manuelle (admin) ----

  @override
  Future<bool> applyMetadataCandidate(String animeId, String providerId, {String? provider}) async {
    try {
      final Map<String, dynamic> response = await _request(
        'POST',
        '/api/catalog/anime/$animeId/apply-candidate',
        body: {
          'provider_id': providerId,
          'provider': ?provider,
        },
      );
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson != null) _anime[animeId] = _animeFromJson(animeJson);
      _notify();
      return animeJson != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ignoreMetadataReview(String animeId) async {
    try {
      final Map<String, dynamic> response = await _request('POST', '/api/catalog/anime/$animeId/ignore');
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson != null) _anime[animeId] = _animeFromJson(animeJson);
      _notify();
      return animeJson != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> updateDisplayTitle(String animeId, String title) async {
    try {
      final Map<String, dynamic> response = await _request(
        'PATCH',
        '/api/catalog/anime/$animeId',
        body: {'display_title': title},
      );
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson != null) _anime[animeId] = _animeFromJson(animeJson);
      _notify();
      return animeJson != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> reassignVersion(String versionId, {int? seasonNumber, int? episodeNumber}) async {
    try {
      final Map<String, dynamic> response = await _request(
        'POST',
        '/api/catalog/versions/$versionId/reassign',
        body: {
          'season_number': ?seasonNumber,
          'episode_number': ?episodeNumber,
        },
      );
      final Map<String, dynamic>? animeJson = response['anime'] as Map<String, dynamic>?;
      if (animeJson != null) {
        final String? animeId = animeJson['id']?.toString();
        if (animeId != null) await refreshAnime(animeId);
      }
      _notify();
      return animeJson != null;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Contrat AnimeRepository
  // ---------------------------------------------------------------------

  @override
  List<Anime> get allAnime => List.unmodifiable(_anime.values);

  @override
  Anime? byId(String id) => _anime[id];

  @override
  Anime? get featured {
    for (final String id in _recentIds) {
      final Anime? anime = _anime[id];
      if (anime != null && anime.latestEpisode != null) return anime;
    }
    for (final Anime anime in _anime.values) {
      if (anime.latestEpisode != null) return anime;
    }
    return _anime.values.isEmpty ? null : _anime.values.first;
  }

  @override
  List<Anime> get latestReleases => List.unmodifiable(
        _anime.values.where((Anime anime) => anime.latestEpisode != null),
      );

  @override
  List<String> get recentEpisodeIds => List.unmodifiable(_recentIds);

  @override
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty}) {
    final String normalizedQuery = _normalize(query.trim());
    final List<String> terms =
        normalizedQuery.split(' ').where((String term) => term.isNotEmpty).toList();
    final List<Anime> results = _anime.values.where((Anime anime) {
      if (terms.isNotEmpty) {
        final List<String> titles = [for (final String title in anime.allTitles) _normalize(title)];
        if (!terms.every((String term) => titles.any((String title) => title.contains(term)))) {
          return false;
        }
      }
      if (filters.season != null && !anime.seasons.any((Season s) => s.number == filters.season)) {
        return false;
      }
      if (filters.episode != null &&
          !anime.allEpisodes.any((Episode e) => e.number == filters.episode)) {
        return false;
      }
      if (filters.quality != null && !anime.availableQualities.contains(filters.quality)) {
        return false;
      }
      if (filters.language != null && !anime.languages.contains(filters.language)) {
        return false;
      }
      if (filters.genres.isNotEmpty && !anime.genres.any(filters.genres.contains)) {
        return false;
      }
      if (filters.source != null && anime.source != filters.source) {
        return false;
      }
      return true;
    }).toList()
      ..sort((Anime a, Anime b) {
        final int aPrefix = _normalize(a.title).startsWith(normalizedQuery) ? 0 : 1;
        final int bPrefix = _normalize(b.title).startsWith(normalizedQuery) ? 0 : 1;
        return aPrefix != bPrefix ? aPrefix - bPrefix : a.title.compareTo(b.title);
      });
    return results;
  }

  @override
  List<LibraryEntry> get libraryEntries => List.unmodifiable(_library.values);

  @override
  LibraryEntry? libraryEntryFor(String animeId) => _library[animeId] ?? _ensureLibraryEntry(animeId);

  LibraryEntry? _ensureLibraryEntry(String animeId) {
    final Anime? anime = byId(animeId);
    if (anime == null) return null;
    return _library.putIfAbsent(animeId, () => LibraryEntry(anime: anime));
  }

  @override
  List<String> get availableGenres =>
      _sortedUnique([for (final Anime anime in _anime.values) ...anime.genres]);

  @override
  List<String> get availableLanguages =>
      _sortedUnique([for (final Anime anime in _anime.values) ...anime.languages]);

  @override
  List<String> get availableSources =>
      _sortedUnique([for (final Anime anime in _anime.values) anime.source]);

  @override
  List<int> get availableSeasons {
    final Set<int> numbers = {
      for (final Anime anime in _anime.values)
        for (final Season season in anime.seasons) season.number,
    };
    final List<int> sorted = numbers.toList()..sort();
    return sorted;
  }

  // ---- Progression de lecture (locale) ----

  @override
  Duration? episodeProgress(String animeId, String episodeId) =>
      libraryEntryFor(animeId)?.progressFor(episodeId);

  @override
  void recordProgress(
    String animeId,
    String episodeId,
    Duration position, {
    Duration duration = Duration.zero,
    bool completed = false,
  }) {
    final Anime? anime = byId(animeId);
    final LibraryEntry? entry = libraryEntryFor(animeId);
    if (anime == null || entry == null) return;
    final Duration total = duration > Duration.zero
        ? duration
        : Duration(minutes: anime.episodeDurationMin.toInt());
    final Duration clamped =
        position < Duration.zero ? Duration.zero : (position > total ? total : position);
    _library[animeId] = entry.copyWith(
      progressMap: {...entry.progressMap, episodeId: clamped},
      resumeEpisodeId: episodeId,
    );
    if (completed) {
      _completed.add('$animeId|$episodeId');
      _history['$animeId|$episodeId'] = PlaybackProgress(
        animeId: animeId, episodeId: episodeId, position: clamped,
        duration: total, savedAt: DateTime.now(), completed: true);
    } else if (clamped > Duration.zero) {
      _history['$animeId|$episodeId'] = PlaybackProgress(
        animeId: animeId, episodeId: episodeId, position: clamped,
        duration: total, savedAt: DateTime.now());
    }
    _notify();
  }

  final Set<String> _completed = <String>{};
  final Map<String, PlaybackProgress> _history = <String, PlaybackProgress>{};

  @override
  List<PlaybackProgress> get watchHistory {
    final List<PlaybackProgress> items = List.of(_history.values);
    items.sort((PlaybackProgress a, PlaybackProgress b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(items);
  }

  @override
  void clearWatchHistory() {
    _history.clear();
    _completed.clear();
    final List<String> keys = _library.keys.toList();
    for (final String key in keys) {
      _library[key] = _library[key]!.copyWith(progressMap: const {}, resetResume: true);
    }
    _notify();
  }

  @override
  bool episodeCompleted(String animeId, String episodeId) => _completed.contains('$animeId|$episodeId');

  @override
  void setPreferredQuality(QualityPreference preference) {
    _settings = _settings.copyWith(preferredQuality: preference);
    _notify();
  }

  @override
  List<PlaybackProgress> progressHistory(String animeId) {
    final LibraryEntry? entry = libraryEntryFor(animeId);
    final Anime? anime = byId(animeId);
    if (entry == null || anime == null) return const [];
    final Duration total = Duration(minutes: anime.episodeDurationMin.toInt());
    return [
      for (final MapEntry<String, Duration> item in entry.progressMap.entries)
        if (item.value > Duration.zero)
          PlaybackProgress(
            animeId: animeId,
            episodeId: item.key,
            position: item.value,
            duration: total,
            savedAt: DateTime.now(),
          ),
    ];
  }

  @override
  PlaybackSettings get playbackSettings => _settings;

  @override
  void setAutoPlayNext(bool enabled) {
    _settings = _settings.copyWith(autoPlayNext: enabled);
    _notify();
  }

  // ---- Favoris / suivi ----

  @override
  void toggleFollow(String animeId) {
    final Anime? anime = byId(animeId);
    if (anime == null) return;
    _anime[animeId] = anime.copyWith(isFollowing: !anime.isFollowing);
    _notify();
  }

  @override
  void toggleFavorite(String animeId) {
    final Anime? anime = byId(animeId);
    if (anime == null) return;
    final LibraryEntry? entry = libraryEntryFor(animeId);
    _library[animeId] = LibraryEntry(
      anime: entry?.anime ?? anime,
      isFavorite: !(entry?.isFavorite ?? false),
      progressMap: entry?.progressMap ?? const {},
      resumeEpisodeId: entry?.resumeEpisodeId,
    );
    _notify();
  }

  // ---------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------

  /// Requête authentifiée (Bearer session). Les erreurs remontent telles
  /// quelles : l'appelant décide (hors-ligne, message…).
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final String? token = await _session.readToken();
    final Uri uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final Map<String, String> headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final http.Response response = switch (method) {
      'GET' => await _client.get(uri, headers: headers).timeout(timeout),
      'POST' => await _client.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(timeout),
      'PATCH' => await _client.patch(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(timeout),
      _ => throw StateError('Méthode non prise en charge : $method'),
    };
    if (response.statusCode >= 400) {
      throw ApiRepositoryException('Erreur serveur ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiRepositoryException('Réponse inattendue du serveur.');
    }
    return decoded;
  }

  static String _describe(Object error) =>
      error is ApiRepositoryException ? error.message : 'Backend injoignable.';

  // ---------------------------------------------------------------------
  // Mappage JSON → modèles
  // ---------------------------------------------------------------------

  static String _idOf(Map<String, dynamic> json) => json['id'].toString();

  /// Anime « léger » (liste, recherche, récents) : pas encore d'épisodes.
  Anime _animeFromJson(Map<String, dynamic> json, {bool cache = false}) {
    final String id = _idOf(json);
    final Anime? cached = cache ? _anime[id] : null;
    final Anime anime = Anime(
      id: id,
      title: json['display_title']?.toString() ?? json['canonical_title']?.toString() ?? '',
      posterAsset: _posterAsset(json),
      backdropAsset: _backdropAsset(json),
      posterUrl: _posterUrl(json),
      backdropUrl: _backdropUrl(json),
      description: json['synopsis']?.toString() ?? '',
      genres: [for (final dynamic genre in json['genres'] as List<dynamic>? ?? const []) genre.toString()],
      year: (json['year'] as num?)?.toInt() ?? 0,
      seasons: cached?.seasons ?? const [],
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      status: _statusFromApi(json['status']),
      languages: cached?.languages ?? const ['VOSTFR'],
      episodeDurationMin: (json['duration_min'] as num?)?.toInt() ?? 24,
      source: json['metadata_source']?.toString() ?? 'Telegram',
      canonicalTitle: json['canonical_title']?.toString(),
      originalTitle: json['original_title']?.toString(),
      alternativeTitles: [
        for (final dynamic title in json['alternative_titles'] as List<dynamic>? ?? const [])
          title.toString(),
      ],
      aliases: [
        for (final dynamic alias in json['aliases'] as List<dynamic>? ?? const [])
          AnimeAlias.fromJson(alias),
      ],
      metadataStatus: MetadataStatus.fromApi(json['metadata_status']),
      metadataSource: json['metadata_source']?.toString(),
      metadataUpdatedAt: json['metadata_updated_at']?.toString(),
      metadataCandidates: [
        for (final dynamic candidate in json['metadata_candidates'] as List<dynamic>? ?? const [])
          if (candidate is Map<String, dynamic>) MetadataCandidateInfo.fromJson(candidate),
      ],
      totalEpisodesDeclared: (json['episode_count'] as num?)?.toInt(),
      seasonCountDeclared: (json['season_count'] as num?)?.toInt(),
      isFollowing: cached?.isFollowing ?? false,
    );
    return anime;
  }

  /// Fiche complète (détail) : saisons, épisodes, versions.
  Anime _animeDetailFromJson(Map<String, dynamic> json) {
    final Anime base = _animeFromJson(json);
    final List<Season> seasons = [];
    for (final dynamic seasonJson in json['seasons'] as List<dynamic>? ?? const []) {
      if (seasonJson is! Map<String, dynamic>) continue;
      seasons.add(_seasonFromJson(seasonJson, base));
    }
    return Anime(
      id: base.id,
      title: base.title,
      posterAsset: base.posterAsset,
      backdropAsset: base.backdropAsset,
      posterUrl: base.posterUrl,
      backdropUrl: base.backdropUrl,
      description: base.description,
      genres: base.genres,
      year: base.year,
      seasons: seasons,
      rating: base.rating,
      status: base.status,
      languages: base.languages,
      episodeDurationMin: base.episodeDurationMin,
      source: base.source,
      popularity: base.popularity,
      followers: base.followers,
      isFollowing: base.isFollowing,
      canonicalTitle: base.canonicalTitle,
      originalTitle: base.originalTitle,
      alternativeTitles: base.alternativeTitles,
      aliases: base.aliases,
      metadataStatus: base.metadataStatus,
      metadataSource: base.metadataSource,
      metadataUpdatedAt: base.metadataUpdatedAt,
      metadataCandidates: base.metadataCandidates,
      totalEpisodesDeclared: base.totalEpisodesDeclared,
      seasonCountDeclared: base.seasonCountDeclared,
      episodeDurationMinDeclared: base.episodeDurationMinDeclared,
    );
  }

  Season _seasonFromJson(Map<String, dynamic> json, Anime anime) {
    final List<Episode> episodes = [];
    for (final dynamic episodeJson in json['episodes'] as List<dynamic>? ?? const []) {
      if (episodeJson is! Map<String, dynamic>) continue;
      episodes.add(_episodeFromJson(episodeJson, anime));
    }
    return Season(
      id: json['id'].toString(),
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      episodes: episodes,
    );
  }

  Episode _episodeFromJson(Map<String, dynamic> json, Anime anime) {
    final List<dynamic> versionsJson = json['versions'] as List<dynamic>? ?? const [];
    final versions = [
      for (final dynamic version in versionsJson)
        if (version is Map<String, dynamic>) EpisodeVersion.fromJson(version),
    ];
    final DateTime? airDate = DateTime.tryParse(json['air_date']?.toString() ?? '');
    final String? created = versions.isEmpty
        ? null
        : versions.map((EpisodeVersion v) => v.createdAt).nonNulls.firstOrNull;
    final DateTime date = airDate ?? DateTime.tryParse(created ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final String episodeId = json['id'].toString();
    return Episode(
      id: episodeId,
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(), // jamais inventé : null → « Épisode N »
      thumbnail: 'assets/img/op_t1.png',
      thumbnailUrl: null,
      date: date,
      isNew: DateTime.now().difference(date).inDays.abs() <= 7,
      qualities: [for (final EpisodeVersion version in versions) version.toEpisodeQuality()],
      progress: _library[anime.id]?.progressFor(episodeId) ?? Duration.zero,
    );
  }

  /// Construit (ou complète) une fiche à partir d'une entrée du flux
  /// « épisodes récents » : dernière saison/épisode + versions connues.
  Anime _animeWithRecentEpisode(Anime? known, Map<String, dynamic> item) {
    final String animeId = item['anime_id'].toString();
    final String animeTitle = item['anime_title']?.toString() ?? known?.title ?? '';
    final int seasonNumber = (item['season_number'] as num?)?.toInt() ?? 0;
    final int episodeNumber = (item['number'] as num?)?.toInt() ?? 0;
    final List<dynamic> versionsJson = item['versions'] as List<dynamic>? ?? const [];
    final List<EpisodeVersion> versions = [
      for (final dynamic version in versionsJson)
        if (version is Map<String, dynamic>) EpisodeVersion.fromJson(version),
    ];
    final String? publishedAt = versions.isEmpty
        ? null
        : versions.map((EpisodeVersion v) => v.createdAt).nonNulls.firstOrNull;

    final Episode episode = Episode(
      id: 'recent-$animeId-s$seasonNumber-e$episodeNumber',
      number: episodeNumber,
      title: item['episode_title']?.toString(), // officiel ou null → « Épisode N »
      thumbnail: 'assets/img/op_t1.png',
      date: DateTime.tryParse(publishedAt ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      isNew: true,
      qualities: [for (final EpisodeVersion version in versions) version.toEpisodeQuality()],
    );
    final Season season = Season(
      id: 'recent-$animeId-s$seasonNumber',
      number: seasonNumber,
      episodes: [episode],
    );

    // Ne remplace pas une fiche détaillée déjà chargée.
    if (known != null && known.seasons.isNotEmpty) return known;
    final Anime base = known ?? Anime(
      id: animeId,
      title: animeTitle,
      posterAsset: _posterAsset(item),
      backdropAsset: _backdropAsset(item),
      posterUrl: _posterUrl(item),
      backdropUrl: _backdropUrl(item),
      description: '',
      genres: const [],
      year: 0,
      seasons: const [],
      metadataStatus: MetadataStatus.fromApi(item['metadata_status']),
    );
    return Anime(
      id: base.id,
      title: base.title,
      posterAsset: base.posterAsset,
      backdropAsset: base.backdropAsset,
      posterUrl: base.posterUrl,
      backdropUrl: base.backdropUrl,
      description: base.description,
      genres: base.genres,
      year: base.year,
      seasons: [season],
      rating: base.rating,
      status: base.status,
      languages: base.languages,
      episodeDurationMin: base.episodeDurationMin,
      source: base.source,
      popularity: base.popularity,
      followers: base.followers,
      isFollowing: base.isFollowing,
      canonicalTitle: base.canonicalTitle,
      originalTitle: base.originalTitle,
      alternativeTitles: base.alternativeTitles,
      aliases: base.aliases,
      metadataStatus: base.metadataStatus,
      metadataSource: base.metadataSource,
      metadataUpdatedAt: base.metadataUpdatedAt,
      metadataCandidates: base.metadataCandidates,
      totalEpisodesDeclared: base.totalEpisodesDeclared,
      seasonCountDeclared: base.seasonCountDeclared,
      episodeDurationMinDeclared: base.episodeDurationMinDeclared,
    );
  }

  String _posterAsset(Map<String, dynamic> json) {
    final String? asset = json['poster_asset']?.toString();
    if (asset != null && asset.isNotEmpty) return 'assets/img/$asset.png';
    return kFallbackPosterAsset;
  }

  String _backdropAsset(Map<String, dynamic> json) {
    final String? asset = json['backdrop_asset']?.toString();
    if (asset != null && asset.isNotEmpty) return 'assets/img/$asset.png';
    return kFallbackPosterAsset;
  }

  String? _posterUrl(Map<String, dynamic> json) {
    final String? url = json['poster_url']?.toString();
    return (url == null || url.isEmpty) ? null : _absolute(url);
  }

  String? _backdropUrl(Map<String, dynamic> json) {
    final String? url = json['backdrop_url']?.toString();
    return (url == null || url.isEmpty) ? null : _absolute(url);
  }

  static AnimeStatus _statusFromApi(Object? value) => switch (value?.toString()) {
        'completed' => AnimeStatus.completed,
        'ongoing' || 'airing' => AnimeStatus.ongoing,
        'upcoming' || 'not_yet_aired' => AnimeStatus.upcoming,
        _ => AnimeStatus.ongoing,
      };

  // ---------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------

  static List<String> _sortedUnique(List<String> values) => values.toSet().toList()..sort();

  /// Normalisation insensible à la casse et aux accents.
  static String _normalize(String value) {
    const String accented = 'áàâäãåéèêëíìîïóòôöõúùûüñç';
    const String plain = 'aaaaaaeeeeiiiiooooouuuunc';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in value.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      final int index = accented.indexOf(character);
      buffer.write(index == -1 ? character : plain[index]);
    }
    return buffer.toString();
  }
}

/// Erreur propre du dépôt catalogue (jamais de contenu sensible).
class ApiRepositoryException implements Exception {
  const ApiRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
