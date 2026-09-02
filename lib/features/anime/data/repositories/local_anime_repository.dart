import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../local/data/local_database.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/episode_quality.dart';
import '../models/library_entry.dart';
import '../models/playback_progress.dart';
import '../models/playback_settings.dart';
import '../models/search_filters.dart';
import '../models/season.dart';
import '../models/video_quality.dart';
import 'anime_repository.dart';

/// Dépôt LOCAL adossé à la base SQLite de l'appareil.
///
/// - NE PEUPLE JAMAIS automatiquement la base de données de démonstration
///   (règle prompt 10 §34) : le catalogue ne contient que les animés
///   réellement détectés par les sources Telegram de l'utilisateur ; l'état
///   vide est explicite (§5) ;
/// - un [seed] explicite sert UNIQUEMENT aux tests et à la démo contrôlée ;
/// - favoris, progression et catalogue survivent au redémarrage ;
/// - rien n'est envoyé hors de l'appareil.
class LocalAnimeRepository extends ChangeNotifier implements AnimeRepository {
  LocalAnimeRepository({List<Anime>? seed, this.database}) : _explicitSeed = seed {
    _anime = List.of(seed ?? const []);
    _library = const [];
    unawaited(_init());
  }

  /// Base locale sous-jacente (null → mode mémoire de secours).
  final LocalDatabase? database;
  late List<Anime> _anime;
  late List<LibraryEntry> _library;
  final List<Anime>? _explicitSeed;
  PlaybackSettings _settings = const PlaybackSettings();
  final Set<String> _completed = <String>{};

  /// Historique réel par clé `animeId|episodeId` (positions, durées,
  /// statuts et dates de dernière lecture issus de la base — prompt 10).
  final Map<String, PlaybackProgress> _history = <String, PlaybackProgress>{};
  bool _dbReady = false;

  /// La base locale est-elle disponible (false → mode mémoire de secours).
  bool get isDatabaseAvailable => _dbReady;

  Future<void> _init() async {
    await _queueLoad(seedIfEmpty: true);
  }

  // Chargements SÉRIALISÉS : un chargement n'en écrase jamais un autre en
  // vol (initialisation, rechargement après synchronisation) — sinon les
  // mutations intervenant entre-temps (favoris, progression) pourraient
  // être perdues par course.
  Future<void>? _loadChain;

  Future<void> _queueLoad({bool seedIfEmpty = false}) {
    final Future<void> task =
        (_loadChain ?? Future<void>.value()).then((_) => _loadOnce(seedIfEmpty: seedIfEmpty));
    _loadChain = task;
    return task;
  }

  Future<void> _loadOnce({bool seedIfEmpty = false}) async {
    final LocalDatabase? db = database;
    if (db == null) return;
    try {
      if (seedIfEmpty) {
        final String? savedPreference = await db.getSetting('preferred_quality');
        if (savedPreference != null) {
          _settings = _settings.copyWith(preferredQuality: QualityPreferenceX.fromName(savedPreference));
        }
        // Persistence d'un seed EXPLICITE (tests uniquement) — jamais de
        // catalogue de démonstration automatique (prompt 10 §34).
        if (_explicitSeed != null && _explicitSeed.isNotEmpty && await db.countAnime() == 0) {
          await _persistSeed(db);
        }
      }
      await _loadFromDatabase(db);
      _dbReady = true;
      notifyListeners();
    } catch (_) {
      // Base indisponible : le catalogue mémoire reste affiché.
      _dbReady = false;
    }
  }

  /// Recharge le catalogue depuis la base (après une synchronisation).
  /// Retourne quand la base est effectivement lue — les mutations
  /// ultérieures sont stables.
  Future<void> reloadFromDatabase() async {
    await _queueLoad();
  }

  // ---------------------------------------------------------------------
  // Seed explicite (tests/démo contrôlée) — persiste le seed passé au
  // constructeur. Jamais appelé sans liste fournie (§34).
  // ---------------------------------------------------------------------

  Future<void> _persistSeed(LocalDatabase db) async {
    final List<Map<String, Object?>> anime = [];
    final List<Map<String, Object?>> seasons = [];
    final List<Map<String, Object?>> episodes = [];
    final List<Map<String, Object?>> versions = [];
    for (final Anime a in _anime) {
      anime.add({
        'id': a.id,
        'title': a.title,
        'canonical_title': a.title,
        'poster_asset': a.posterAsset,
        'backdrop_asset': a.backdropAsset,
        'description': a.description,
        'genres': LocalDatabase.encodeList(a.genres),
        'year': a.year,
        'source': a.source,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final Season season in a.seasons) {
        seasons.add({'id': season.id, 'anime_id': a.id, 'number': season.number});
        for (final Episode episode in season.episodes) {
          episodes.add({
            'id': episode.id,
            'season_id': season.id,
            'number': episode.number,
            'kind': 'regular',
            'title': episode.title,
            'date': episode.date.toIso8601String(),
            'is_new': episode.isNew ? 1 : 0,
          });
          for (final EpisodeQuality quality in episode.qualities) {
            versions.add({
              'id': quality.id,
              'episode_id': episode.id,
              'quality': quality.quality.label,
              'quality_rank': _rankOf(quality.quality),
              'language': quality.language,
              'subtitles': quality.subtitles,
              'size': quality.size,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }
      }
    }
    await db.saveCatalogGraph(anime: anime, seasons: seasons, episodes: episodes, versions: versions);

    // Favoris et progression initiaux (démo) persistés.
    for (final LibraryEntry entry in _library) {
      if (entry.isFavorite) await db.setFavorite(entry.anime.id, true);
      for (final MapEntry<String, Duration> item in entry.progressMap.entries) {
        if (item.value > Duration.zero) {
          await db.saveProgress(entry.anime.id, item.key, item.value.inMilliseconds);
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Chargement depuis la base
  // ---------------------------------------------------------------------

  Future<void> _loadFromDatabase(LocalDatabase db) async {
    final Map<String, Object?> catalog = await db.loadCatalog();
    final List<Map<String, Object?>> animeRows = (catalog['anime'] as List<dynamic>? ?? const []).cast<Map<String, Object?>>();
    final List<Map<String, Object?>> seasonRows = (catalog['seasons'] as List<dynamic>? ?? const []).cast<Map<String, Object?>>();
    final List<Map<String, Object?>> episodeRows = (catalog['episodes'] as List<dynamic>? ?? const []).cast<Map<String, Object?>>();
    final List<Map<String, Object?>> versionRows = (catalog['versions'] as List<dynamic>? ?? const []).cast<Map<String, Object?>>();

    final Map<String, List<Map<String, Object?>>> versionsByEpisode = {};
    for (final Map<String, Object?> v in versionRows) {
      versionsByEpisode.putIfAbsent(v['episode_id']! as String, () => []).add(v);
    }
    final Map<String, List<Map<String, Object?>>> episodesBySeason = {};
    for (final Map<String, Object?> e in episodeRows) {
      episodesBySeason.putIfAbsent(e['season_id']! as String, () => []).add(e);
    }
    final Map<String, List<Map<String, Object?>>> seasonsByAnime = {};
    for (final Map<String, Object?> s in seasonRows) {
      seasonsByAnime.putIfAbsent(s['anime_id']! as String, () => []).add(s);
    }

    final Set<String> favorites = await db.loadFavorites();
    final Map<String, Map<String, Object?>> progressDetails = await db.loadProgressDetails();
    final Map<String, int> progress = {
      for (final MapEntry<String, Map<String, Object?>> e in progressDetails.entries)
        e.key: (e.value['positionMs'] as num?)?.toInt() ?? 0,
    };

    // Historique réel (dates de dernière lecture issues de la base).
    _history
      ..clear()
      ..addAll({
        for (final MapEntry<String, Map<String, Object?>> e in progressDetails.entries)
          e.key: PlaybackProgress(
            animeId: e.key.substring(0, e.key.indexOf('|')),
            episodeId: e.key.substring(e.key.indexOf('|') + 1),
            position: Duration(milliseconds: (e.value['positionMs'] as num?)?.toInt() ?? 0),
            duration: Duration(milliseconds: (e.value['durationMs'] as num?)?.toInt() ?? 0),
            savedAt: DateTime.tryParse('${e.value['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
            completed: e.value['completed'] == true,
          ),
      });
    _completed
      ..clear()
      ..addAll([for (final MapEntry<String, Map<String, Object?>> e in progressDetails.entries) if (e.value['completed'] == true) e.key]);

    final List<Anime> loaded = [];
    for (final Map<String, Object?> a in animeRows) {
      final String animeId = a['id']! as String;
      final List<Season> seasons = [];
      final List<Map<String, Object?>> seasonList = seasonsByAnime[animeId] ?? const [];
      seasonList.sort((Map<String, Object?> x, Map<String, Object?> y) =>
          ((x['number'] as num?)?.toInt() ?? 0).compareTo((y['number'] as num?)?.toInt() ?? 0));
      for (final Map<String, Object?> s in seasonList) {
        final String seasonId = s['id']! as String;
        final List<Map<String, Object?>> episodeList = episodesBySeason[seasonId] ?? const [];
        episodeList.sort((Map<String, Object?> x, Map<String, Object?> y) =>
            ((x['number'] as num?)?.toInt() ?? 0).compareTo((y['number'] as num?)?.toInt() ?? 0));
        seasons.add(Season(
          id: seasonId,
          number: (s['number'] as num?)?.toInt() ?? 0,
          title: s['title']?.toString(),
          episodes: [
            for (final Map<String, Object?> e in episodeList)
              Episode(
                id: e['id']! as String,
                number: (e['number'] as num?)?.toInt() ?? 0,
                title: e['title']?.toString(), // officiel ou null → « Épisode N »
                thumbnail: '',
                date: DateTime.tryParse(e['date']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
                isNew: (e['is_new'] as num?)?.toInt() == 1,
                qualities: _qualitiesFrom(versionsByEpisode[e['id']] ?? const []),
                progress: Duration(
                  milliseconds: progress['$animeId|${e['id']}'] ?? 0,
                ),
              ),
          ],
        ));
      }
      final String poster = a['poster_asset']?.toString() ?? '';
      loaded.add(Anime(
        id: animeId,
        title: a['title']! as String,
        posterAsset: poster.isEmpty ? kLocalFallbackPosterAsset : poster,
        backdropAsset: (a['backdrop_asset']?.toString().isNotEmpty ?? false)
            ? a['backdrop_asset']!.toString()
            : kLocalFallbackPosterAsset,
        description: a['description']?.toString() ?? '',
        genres: LocalDatabase.decodeList(a['genres']),
        year: (a['year'] as num?)?.toInt() ?? 0,
        seasons: seasons,
        source: a['source']?.toString() ?? 'Local',
        status: AnimeStatus.ongoing,
      ));
    }

    _anime = loaded;
    _rebuildLibrary(favorites, progress);
  }

  void _rebuildLibrary(Set<String> favorites, Map<String, int> progress) {
    // « Reprendre » = épisode le plus RÉCEMMENT lu (date réelle de la
    // base), pas une entrée arbitraire.
    final Map<String, String> resumeByAnime = {};
    final Map<String, DateTime> lastPlayedAtByAnime = {};
    for (final MapEntry<String, int> item in progress.entries) {
      final int separator = item.key.indexOf('|');
      if (separator == -1) continue;
      final String animeId = item.key.substring(0, separator);
      final DateTime playedAt = _history[item.key]?.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime? best = lastPlayedAtByAnime[animeId];
      if (best == null || playedAt.isAfter(best)) {
        lastPlayedAtByAnime[animeId] = playedAt;
        resumeByAnime[animeId] = item.key.substring(separator + 1);
      }
    }
    _library = [
      for (final Anime anime in _anime)
        if (favorites.contains(anime.id) || progress.keys.any((String k) => k.startsWith('${anime.id}|')))
          LibraryEntry(
            anime: anime,
            isFavorite: favorites.contains(anime.id),
            progressMap: {
              for (final MapEntry<String, int> item in progress.entries)
                if (item.key.startsWith('${anime.id}|'))
                  item.key.substring(item.key.indexOf('|') + 1): Duration(milliseconds: item.value),
            },
            resumeEpisodeId: resumeByAnime[anime.id],
          ),
    ];
  }

  List<EpisodeQuality> _qualitiesFrom(List<Map<String, Object?>> rows) {
    final List<Map<String, Object?>> sorted = List.of(rows)
      ..sort((Map<String, Object?> a, Map<String, Object?> b) =>
          ((b['quality_rank'] as num?)?.toInt() ?? 0).compareTo((a['quality_rank'] as num?)?.toInt() ?? 0));
    return [
      for (final Map<String, Object?> row in sorted)
        EpisodeQuality(
          id: row['id']! as String,
          quality: _qualityFrom((row['quality'] as String?) ?? ''),
          resolution: _qualityFrom((row['quality'] as String?) ?? '').resolution,
          size: (row['size'] as num?)?.toInt() ?? 0,
          language: _languageLabel(row['language']?.toString(), row['subtitles']?.toString()),
          subtitles: _subtitlesLabel(row['subtitles']?.toString()),
          sourceChannelUsername: row['telegram_channel_username']?.toString(),
          telegramMessageId: (row['telegram_message_id'] as num?)?.toInt(),
          telegramMessageLink: row['telegram_message_link']?.toString(),
        ),
    ];
  }

  static VideoQuality _qualityFrom(String label) {
    final VideoQuality? quality = VideoQualityX.fromLabel(label);
    return quality ?? VideoQuality.low;
  }

  static int _rankOf(VideoQuality quality) => switch (quality) {
        VideoQuality.fhd => 4,
        VideoQuality.hd => 3,
        VideoQuality.sd => 2,
        VideoQuality.low => 1,
      };

  static String _languageLabel(String? language, String? subtitles) {
    switch (language) {
      case 'french':
        return 'VF';
      case 'japanese':
        return subtitles == 'french' ? 'VOSTFR' : 'VO';
      case 'english':
        return 'VO';
      case 'multi':
        return 'MULTI';
      default:
        return subtitles == 'french' ? 'VOSTFR' : 'VO';
    }
  }

  static String _subtitlesLabel(String? subtitles) => switch (subtitles) {
        'french' => 'FR',
        'english' => 'EN',
        _ => 'Aucun',
      };

  // ---------------------------------------------------------------------
  // Contrat AnimeRepository
  // ---------------------------------------------------------------------

  @override
  List<Anime> get allAnime => List.unmodifiable(_anime);

  @override
  Anime? byId(String id) {
    for (final Anime anime in _anime) {
      if (anime.id == id) return anime;
    }
    return null;
  }

  @override
  Anime? get featured {
    final List<Anime> releases = latestReleases;
    return releases.isEmpty ? null : releases.first;
  }

  @override
  List<Anime> get latestReleases => List.unmodifiable(_anime.where((Anime anime) => anime.latestEpisode != null));

  @override
  List<String> get recentEpisodeIds {
    // Nouveautés RÉELLES : animés avec au moins un épisode marqué nouveau
    // par la synchronisation, du plus récent au plus ancien (date réelle
    // de la publication Telegram, jamais de liste en dur — prompt 10 §15).
    final List<MapEntry<String, DateTime>> dated = [];
    for (final Anime anime in _anime) {
      DateTime? latest;
      bool hasNew = false;
      for (final Season season in anime.seasons) {
        for (final Episode episode in season.episodes) {
          if (!episode.isNew) continue;
          hasNew = true;
          if (latest == null || episode.date.isAfter(latest)) latest = episode.date;
        }
      }
      if (hasNew) dated.add(MapEntry(anime.id, latest ?? DateTime.fromMillisecondsSinceEpoch(0)));
    }
    dated.sort((MapEntry<String, DateTime> a, MapEntry<String, DateTime> b) => b.value.compareTo(a.value));
    return [for (final MapEntry<String, DateTime> item in dated) item.key];
  }

  @override
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty}) {
    final String normalizedQuery = _normalize(query.trim());
    final List<String> terms = normalizedQuery.split(' ').where((String t) => t.isNotEmpty).toList();

    final List<Anime> results = _anime.where((Anime anime) {
      if (terms.isNotEmpty &&
          !terms.every((String term) => anime.allTitles.any((String title) => _normalize(title).contains(term)))) {
        return false;
      }
      if (filters.season != null && !anime.seasons.any((Season s) => s.number == filters.season)) return false;
      if (filters.episode != null && !anime.seasons.any((Season s) => s.episodes.any((Episode e) => e.number == filters.episode))) return false;
      if (filters.quality != null && !anime.availableQualities.contains(filters.quality)) return false;
      if (filters.language != null && !anime.languages.contains(filters.language)) return false;
      if (filters.genres.isNotEmpty && !filters.genres.every(anime.genres.contains)) return false;
      if (filters.source != null && anime.source != filters.source) return false;
      return true;
    }).toList();

    results.sort((Anime a, Anime b) {
      if (terms.isNotEmpty) {
        final int aPrefix = _normalize(a.title).startsWith(normalizedQuery) ? 0 : 1;
        final int bPrefix = _normalize(b.title).startsWith(normalizedQuery) ? 0 : 1;
        if (aPrefix != bPrefix) return aPrefix - bPrefix;
      }
      return b.popularity.compareTo(a.popularity);
    });
    return results;
  }

  @override
  List<LibraryEntry> get libraryEntries => List.unmodifiable(_library);

  @override
  LibraryEntry? libraryEntryFor(String animeId) {
    for (final LibraryEntry entry in _library) {
      if (entry.anime.id == animeId) return entry;
    }
    return null;
  }

  @override
  List<String> get availableGenres => _sortedUnique([for (final anime in _anime) ...anime.genres]);

  @override
  List<String> get availableLanguages => _sortedUnique([for (final anime in _anime) ...anime.languages]);

  @override
  List<String> get availableSources => _sortedUnique([for (final anime in _anime) anime.source]);

  @override
  List<int> get availableSeasons {
    final Set<int> numbers = {for (final anime in _anime) for (final season in anime.seasons) season.number};
    final List<int> sorted = numbers.toList()..sort();
    return sorted;
  }

  // ---------------------------------------------------------------------
  // Progression de lecture (persistée)
  // ---------------------------------------------------------------------

  @override
  Duration? episodeProgress(String animeId, String episodeId) => libraryEntryFor(animeId)?.progressFor(episodeId);

  @override
  void recordProgress(
    String animeId,
    String episodeId,
    Duration position, {
    Duration duration = Duration.zero,
    bool completed = false,
  }) {
    final int index = _library.indexWhere((LibraryEntry entry) => entry.anime.id == animeId);
    final Anime? anime = byId(animeId);
    // Rien d'exploitable : ni fiche connue, ni durée fournie → aucune
    // progression enregistrée (comportement historique préservé).
    if (anime == null && duration == Duration.zero) return;
    final Duration total = duration > Duration.zero
        ? duration
        : Duration(minutes: anime!.episodeDurationMin.toInt());
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (position > total ? total : position);
    // La bibliothèque suit la lecture : commencer un épisode ajoute
    // automatiquement l'animé (prompt 10 §9).
    if (index != -1) {
      final LibraryEntry entry = _library[index];
      _library[index] = entry.copyWith(
        progressMap: {...entry.progressMap, episodeId: clamped},
        resumeEpisodeId: episodeId,
      );
    } else if (anime != null) {
      _library.add(LibraryEntry(
        anime: anime,
        progressMap: {episodeId: clamped},
        resumeEpisodeId: episodeId,
      ));
    }
    if (completed) _completed.add('$animeId|$episodeId');
    // Historique réel (date réelle de lecture) — prompt 10 §10/§12.
    _history['$animeId|$episodeId'] = PlaybackProgress(
      animeId: animeId,
      episodeId: episodeId,
      position: clamped,
      duration: total,
      savedAt: DateTime.now(),
      completed: completed || _completed.contains('$animeId|$episodeId'),
    );
    final LocalDatabase? db = database;
    if (db != null) {
      unawaited(_persistProgress(
        db,
        animeId,
        episodeId,
        clamped.inMilliseconds,
        durationMs: total.inMilliseconds,
        completed: completed,
      ));
    }
    notifyListeners();
  }

  /// Persistance incassable de la progression : une base fermée ou
  /// indisponible ne plante jamais la lecture (l'état mémoire prime).
  Future<void> _persistProgress(
    LocalDatabase db,
    String animeId,
    String episodeId,
    int positionMs, {
    required int durationMs,
    required bool completed,
  }) async {
    try {
      await db.saveProgress(
        animeId,
        episodeId,
        positionMs,
        durationMs: durationMs,
        completed: completed,
      );
    } catch (_) {
      // Ignoré : l'état mémoire reste la référence de session.
    }
  }

  @override
  bool episodeCompleted(String animeId, String episodeId) => _completed.contains('$animeId|$episodeId');

  @override
  void setPreferredQuality(QualityPreference preference) {
    _settings = _settings.copyWith(preferredQuality: preference);
    final LocalDatabase? db = database;
    if (db != null) {
      unawaited(db.setSetting('preferred_quality', preference.name));
    }
    notifyListeners();
  }

  @override
  List<PlaybackProgress> progressHistory(String animeId) {
    // Données réelles : positions, durées et dates issues de la base.
    final List<PlaybackProgress> items = [
      for (final MapEntry<String, PlaybackProgress> item in _history.entries)
        if (item.value.animeId == animeId && item.value.position > Duration.zero) item.value,
    ];
    items.sort((PlaybackProgress a, PlaybackProgress b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(items);
  }

  @override
  List<PlaybackProgress> get watchHistory {
    final List<PlaybackProgress> items = [
      for (final PlaybackProgress item in _history.values) if (item.position > Duration.zero || item.completed) item,
    ];
    items.sort((PlaybackProgress a, PlaybackProgress b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(items);
  }

  @override
  void clearWatchHistory() {
    // Efface uniquement l'historique : ni favoris, ni téléchargements, ni
    // épisodes, ni sources ne sont touchés (prompt 10 §13).
    _history.clear();
    _completed.clear();
    _library = [
      for (final LibraryEntry entry in _library)
        entry.copyWith(progressMap: const {}, resetResume: true),
    ];
    final LocalDatabase? db = database;
    if (db != null) {
      unawaited(db.deleteAllProgress().catchError((_) {
        // Base fermée/indisponible : l'état mémoire reste la référence.
      }));
    }
    notifyListeners();
  }

  @override
  PlaybackSettings get playbackSettings => _settings;

  @override
  void setAutoPlayNext(bool enabled) {
    _settings = _settings.copyWith(autoPlayNext: enabled);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Favoris / suivi (persistés)
  // ---------------------------------------------------------------------

  @override
  void toggleFollow(String animeId) {
    final int index = _anime.indexWhere((Anime anime) => anime.id == animeId);
    if (index == -1) return;
    final Anime anime = _anime[index];
    _anime[index] = anime.copyWith(isFollowing: !anime.isFollowing);
    notifyListeners();
  }

  @override
  void toggleFavorite(String animeId) {
    final int index = _library.indexWhere((LibraryEntry entry) => entry.anime.id == animeId);
    bool favorite;
    if (index == -1) {
      final Anime? anime = byId(animeId);
      if (anime == null) return;
      _library.add(LibraryEntry(anime: anime, isFavorite: true));
      favorite = true;
    } else {
      final LibraryEntry entry = _library[index];
      favorite = !entry.isFavorite;
      _library[index] = entry.copyWith(isFavorite: favorite);
    }
    final LocalDatabase? db = database;
    if (db != null) {
      unawaited(db.setFavorite(animeId, favorite).catchError((_) {
        // Base fermée/indisponible : l'état mémoire reste la référence.
      }));
    }
    notifyListeners();
  }

  List<String> _sortedUnique(Iterable<String> values) => values.toSet().toList()..sort();

  String _normalize(String value) {
    const String accented = 'áàâäãåéèêëíìîïóòôöõúùûüçñ';
    const String plain = 'aaaaaaeeeeiiiiooooouuuucn';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in value.toLowerCase().runes) {
      final String character = String.fromCharCode(rune);
      final int index = accented.indexOf(character);
      buffer.write(index >= 0 ? plain[index] : character);
    }
    return buffer.toString();
  }
}

/// Affiche de secours quand aucun poster n'est connu.
const String kLocalFallbackPosterAsset = 'assets/img/poster_placeholder.png';
