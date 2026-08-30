import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/search_filters.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';

void main() {
  group('MockAnimeRepository', () {
    late MockAnimeRepository repository;

    setUp(() => repository = MockAnimeRepository());

    test('expose les 4 animés de démonstration', () {
      expect(repository.allAnime, hasLength(4));
      expect(
        repository.allAnime.map((anime) => anime.title),
        containsAll(<String>['Solo Leveling', 'One Piece', 'Jujutsu Kaisen', 'Demon Slayer']),
      );
    });

    test('recherche insensible à la casse et aux accents', () {
      expect(repository.search('SOLO').single.title, 'Solo Leveling');
      expect(repository.search('piece').single.title, 'One Piece');
      expect(repository.search('demon').single.title, 'Demon Slayer');
      expect(repository.search('zzz'), isEmpty);
    });

    test('filtre par qualité', () {
      final results = repository.search('', filters: const SearchFilters(quality: VideoQuality.fhd));
      expect(results, hasLength(3));
      expect(results.map((anime) => anime.title), isNot(contains('One Piece')));
    });

    test('filtre par saison', () {
      final results = repository.search('', filters: const SearchFilters(season: 4));
      expect(results.single.title, 'Demon Slayer');
    });

    test('filtre par langue', () {
      final results = repository.search('', filters: const SearchFilters(language: 'VF'));
      expect(results, hasLength(3));
      expect(results.map((anime) => anime.title), isNot(contains('One Piece')));
    });

    test('filtre par genre (tous les genres requis)', () {
      final results = repository.search('', filters: const SearchFilters(genres: {'Action', 'Historique'}));
      expect(results.single.title, 'Demon Slayer');
    });

    test("l'animé mis en avant est Solo Leveling", () {
      expect(repository.featured?.title, 'Solo Leveling');
    });

    test('toggleFollow bascule l\'état de suivi', () {
      final bool before = repository.byId('solo-leveling')!.isFollowing;
      repository.toggleFollow('solo-leveling');
      expect(repository.byId('solo-leveling')!.isFollowing, isNot(before));
      repository.toggleFollow('solo-leveling');
      expect(repository.byId('solo-leveling')!.isFollowing, before);
    });

    test('toggleFavorite bascule l\'entrée de bibliothèque', () {
      final entry = repository.libraryEntryFor('demon-slayer')!;
      expect(entry.isFavorite, isFalse);
      repository.toggleFavorite('demon-slayer');
      expect(repository.libraryEntryFor('demon-slayer')!.isFavorite, isTrue);
      repository.toggleFavorite('demon-slayer');
      expect(repository.libraryEntryFor('demon-slayer')!.isFavorite, isFalse);
    });

    test('les modèles exposent totaux et dernier épisode', () {
      final onePiece = repository.byId('one-piece')!;
      expect(onePiece.totalEpisodes, 1124);
      expect(onePiece.latestEpisode!.number, 1124);
      expect(onePiece.episodeMeta, '1124 épisodes');
      expect(onePiece.latestEpisodeTag, 'Épisode 1124');

      final solo = repository.byId('solo-leveling')!;
      expect(solo.episodeMeta, 'Saison 2 · 8 épisodes');
      expect(solo.latestEpisodeTag, 'Saison 2 · Épisode 08');
      expect(solo.latestEpisodeShortTag, 'S2 · E08');
    });

    test('SearchFilters : copyWith et état actif', () {
      const SearchFilters filters = SearchFilters(season: 2);
      expect(filters.isActive, isTrue);
      expect(filters.copyWith(quality: VideoQuality.hd).season, 2);
      expect(filters.copyWith(season: null).season, isNull);
      expect(filters.copyWith(season: null).isActive, isFalse);
      expect(SearchFilters.empty.isActive, isFalse);
      expect(const SearchFilters(genres: {'Action'}).activeCount, 1);
    });
  });
}
