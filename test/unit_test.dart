import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/episode_quality.dart';
import 'package:animebox/features/anime/data/models/search_filters.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';

void main() {
  group('MockAnimeRepository — catalogue', () {
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

    test('filtre par qualité (1080p disponible partout)', () {
      final results = repository.search('', filters: const SearchFilters(quality: VideoQuality.fhd));
      expect(results, hasLength(4));
      expect(results.map((anime) => anime.title), contains('One Piece'));
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
      expect(onePiece.totalEpisodes, 1125);
      expect(onePiece.latestEpisode!.number, 1125);
      expect(onePiece.episodeMeta, '1125 épisodes');
      expect(onePiece.latestEpisodeTag, 'Épisode 1125');

      final solo = repository.byId('solo-leveling')!;
      expect(solo.episodeMeta, 'Saison 2 · 9 épisodes');
      expect(solo.latestEpisodeTag, 'Saison 2 · Épisode 09');
      expect(solo.latestEpisodeShortTag, 'S2 · E09');
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

  group('MockAnimeRepository — épisodes et qualités', () {
    late MockAnimeRepository repository;

    setUp(() => repository = MockAnimeRepository());

    test('un épisode regroupe plusieurs qualités', () {
      final episode = repository.byId('solo-leveling')!.episodeById('sl-s2e8')!;
      expect(episode.qualities, hasLength(3));
      expect(episode.qualities.map((q) => q.quality.label), containsAll(['1080p', '720p', '480p']));
      expect(episode.bestQuality!.quality, VideoQuality.fhd);
    });

    test('les qualités portent langue et taille mockées', () {
      final best = repository.byId('solo-leveling')!.episodeById('sl-s2e8')!.bestQuality!;
      expect(best.language, 'VF');
      expect(best.sizeLabel, '1.2 GB');
      expect(formatBytes(650 * 1024 * 1024), '650 MB');
    });

    test('le 9e épisode de la saison 2 est marqué nouveau et dispose de 360p', () {
      final episode = repository.byId('solo-leveling')!.episodeById('sl-s2e9')!;
      expect(episode.isNew, isTrue);
      expect(episode.qualities.map((q) => q.quality.label), contains('360p'));
    });

    test('les épisodes ont titres, dates et vignettes', () {
      final episode = repository.byId('solo-leveling')!.episodeById('sl-s2e8')!;
      expect(episode.title, 'Le roi des ombres');
      expect(episode.date, DateTime(2024, 5, 12));
      expect(episode.thumbnail, isNotEmpty);
    });

    test('les spéciaux sont exposés par saison', () {
      final solo = repository.byId('solo-leveling')!;
      expect(solo.hasSpecials, isTrue);
      expect(solo.seasons.last.specials, hasLength(2));
    });

    test('nextEpisodeOf suit la saison puis passe à la suivante', () {
      final solo = repository.byId('solo-leveling')!;
      final e8 = solo.episodeById('sl-s2e8')!;
      final e9 = solo.episodeById('sl-s2e9')!;
      expect(solo.nextEpisodeOf(e8)!.id, 'sl-s2e9');
      expect(solo.nextEpisodeOf(e9), isNull);

      final s1e12 = solo.episodeById('sl-s1e12')!;
      expect(solo.nextEpisodeOf(s1e12)!.id, 'sl-s2e1');
    });
  });

  group('MockAnimeRepository — progression de lecture', () {
    late MockAnimeRepository repository;

    setUp(() => repository = MockAnimeRepository());

    test('la progression initiale est exposée (reprise)', () {
      expect(repository.episodeProgress('solo-leveling', 'sl-s2e7'), const Duration(minutes: 13, seconds: 12));
      expect(repository.episodeProgress('solo-leveling', 'sl-s2e8'), isNull);
    });

    test('recordProgress enregistre et borne la position', () {
      repository.recordProgress('solo-leveling', 'sl-s2e8', const Duration(minutes: 10, seconds: 24));
      expect(repository.episodeProgress('solo-leveling', 'sl-s2e8'), const Duration(minutes: 10, seconds: 24));
      // Borne à la durée de l'épisode (24 min).
      repository.recordProgress('solo-leveling', 'sl-s2e8', const Duration(minutes: 99));
      expect(repository.episodeProgress('solo-leveling', 'sl-s2e8'), const Duration(minutes: 24));
    });

    test('progressHistory liste les épisodes commencés', () {
      final history = repository.progressHistory('solo-leveling');
      expect(history, isNotEmpty);
      expect(history.first.episodeId, 'sl-s2e7');
      expect(history.first.fraction, greaterThan(0.5));
    });

    test('la lecture automatique est paramétrable', () {
      expect(repository.playbackSettings.autoPlayNext, isTrue);
      repository.setAutoPlayNext(false);
      expect(repository.playbackSettings.autoPlayNext, isFalse);
    });

    test('l\'entrée de bibliothèque expose l\'épisode repris', () {
      final entry = repository.libraryEntryFor('one-piece')!;
      expect(entry.resumeEpisode!.id, 'op-s1e1123');
      expect(entry.resumePosition, const Duration(minutes: 17, seconds: 17));
      expect(entry.resumeFraction(), closeTo(0.72, 0.01));
    });
  });
}
