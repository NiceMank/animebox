import 'package:flutter/foundation.dart';

import '../models/anime.dart';
import '../models/episode.dart';
import '../models/library_entry.dart';
import '../models/search_filters.dart';
import 'anime_repository.dart';
import '../mock/mock_data.dart';

/// Dépôt de données local (mocké) pour l'étape 1.
///
/// Il est notifiable : les écrans s'abonnent via [ListenableBuilder] pour
/// réagir aux bascules « favori » / « suivre » sans rechargement manuel.
class MockAnimeRepository extends ChangeNotifier implements AnimeRepository {
  MockAnimeRepository({List<Anime>? seed}) : _anime = List.of(seed ?? kMockAnime) {
    _library = _buildLibrary();
  }

  final List<Anime> _anime;
  late final List<LibraryEntry> _library;

  LibraryEntry _entry(String animeId, {bool favorite = false, double progress = 0, String? lastEpisodeId}) {
    final Anime anime = byId(animeId)!;
    Episode? lastWatched;
    if (lastEpisodeId != null) {
      for (final season in anime.seasons) {
        for (final episode in season.episodes) {
          if (episode.id == lastEpisodeId) lastWatched = episode;
        }
      }
    }
    return LibraryEntry(anime: anime, isFavorite: favorite, progress: progress, lastWatched: lastWatched);
  }

  /// Bibliothèque initiale de démonstration.
  List<LibraryEntry> _buildLibrary() => [
        _entry('solo-leveling', favorite: true, progress: 0.55, lastEpisodeId: 'sl-s2e7'),
        _entry('one-piece', favorite: true, progress: 0.72, lastEpisodeId: 'op-s1e1123'),
        _entry('jujutsu-kaisen', favorite: true, progress: 0.12, lastEpisodeId: 'jjk-s2e3'),
        _entry('demon-slayer'),
      ];

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
  List<Anime> get latestReleases =>
      List.unmodifiable(_anime.where((Anime anime) => anime.latestEpisode != null));

  @override
  List<Anime> search(String query, {SearchFilters filters = SearchFilters.empty}) {
    final String normalizedQuery = _normalize(query.trim());
    final List<String> terms = normalizedQuery.split(' ').where((String t) => t.isNotEmpty).toList();

    final List<Anime> results = _anime.where((Anime anime) {
      if (terms.isNotEmpty && !terms.every((String term) => _normalize(anime.title).contains(term))) {
        return false;
      }
      if (filters.season != null && !anime.seasons.any((s) => s.number == filters.season)) return false;
      if (filters.episode != null && !anime.seasons.any((s) => s.episodes.any((e) => e.number == filters.episode))) return false;
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
    if (index == -1) {
      final Anime? anime = byId(animeId);
      if (anime == null) return;
      _library.add(LibraryEntry(anime: anime, isFavorite: true));
    } else {
      final LibraryEntry entry = _library[index];
      _library[index] = LibraryEntry(
        anime: entry.anime,
        isFavorite: !entry.isFavorite,
        lastWatched: entry.lastWatched,
        progress: entry.progress,
      );
    }
    notifyListeners();
  }

  List<String> _sortedUnique(Iterable<String> values) {
    final List<String> sorted = values.toSet().toList()..sort();
    return sorted;
  }

  /// Normalisation pour la recherche : minuscules + suppression des accents.
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
