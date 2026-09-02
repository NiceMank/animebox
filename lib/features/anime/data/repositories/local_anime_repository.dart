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
import '../mock/mock_data.dart';
import 'anime_repository.dart';

/// Dépôt LOCAL adossé à la base SQLite de l'appareil.
///
/// - démarre immédiatement avec le catalogue de démonstration (aucun
///   blocage de l'interface) ;
/// - la base est remplie avec ce catalogue au premier lancement, puis
///   enrichie par la synchronisation Telegram locale ;
/// - favoris, progression et catalogue survivent au redémarrage ;
/// - rien n'est envoyé hors de l'appareil.
class LocalAnimeRepository extends ChangeNotifier implements AnimeRepository {
  LocalAnimeRepository({List<Anime>? seed, this.database}) {
    _anime = List.of(seed ?? kMockAnime);
    _library = _defaultLibrary();
    unawaited(_init());
  }

  /// Base locale sous-jacente (null → mode mémoire de secours).
  final LocalDatabase? database;
  late List<Anime> _anime;
  late List<LibraryEntry> _library;
  PlaybackSettings _settings = const PlaybackSettings();
  final Set<String> _completed = <String>{};
  bool _dbReady = false;

  /// La base locale est-elle disponible (false → mode mémoire de secours).
  bool get isDatabaseAvailable => _dbReady;

  Future<void> _init() async {
    final LocalDatabase? db = database;
    if (db == null) return;
    try {
      if (await db.countAnime() == 0) {
        await _seedFromMock(db);
      }
      final String? savedPreference = await db.getSetting('preferred_quality');
      if (savedPreference != null) {
        _settings = _settings.copyWith(preferredQuality: QualityPreferenceX.fromName(savedPreference));
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
  Future<void> reloadFromDatabase() async {
    final LocalDatabase? db = database;
    if (db == null) return;
    try {
      await _loadFromDatabase(db);
      _dbReady = true;
      notifyListeners();
    } catch (_) {
      _dbReady = false;
    }
  }

  // ---------------------------------------------------------------------
  // Seed initial : le catalogue de démonstration devient persistant
  // ---------------------------------------------------------------------

  Future<void> _seedFromMock(LocalDatabase db) async {
    final List<Map<String, Object?>> anime = [];
    final List<Map<String, Object?>> seasons = [];
    final List<Map<String, Object?>> episodes = [];
    final List<Map<String, Object?>> versions = [];
    for (final Anime a in kMockAnime) {
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
    final Map<String, int> progress = await db.loadProgress();

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
    // Dernière progression par animé (pour « Reprendre »).
    final Map<String, String> resumeByAnime = {};
    for (final MapEntry<String, int> item in progress.entries) {
      final int separator = item.key.indexOf('|');
      if (separator == -1) continue;
      final String animeId = item.key.substring(0, separator);
      resumeByAnime[animeId] = item.key.substring(separator + 1);
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
  List<String> get recentEpisodeIds => const ['solo-leveling', 'jujutsu-kaisen', 'one-piece'];

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
    // La bibliothèque est mise à jour quand l'entrée existe ; la
    // progression elle-même (table progress) ne dépend pas d'elle.
    if (index != -1) {
      final LibraryEntry entry = _library[index];
      _library[index] = entry.copyWith(
        progressMap: {...entry.progressMap, episodeId: clamped},
        resumeEpisodeId: episodeId,
      );
    }
    if (completed) _completed.add('$animeId|$episodeId');
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
    if (db != null) unawaited(db.setFavorite(animeId, favorite));
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

List<LibraryEntry> _defaultLibrary() => [
      for (final Anime anime in kMockAnime)
        if (const {'solo-leveling', 'one-piece', 'jujutsu-kaisen', 'demon-slayer'}.contains(anime.id))
          LibraryEntry(anime: anime, isFavorite: true),
    ];
