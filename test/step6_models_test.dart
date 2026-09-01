import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/anime/data/models/anime.dart';
import 'package:animebox/features/anime/data/models/anime_alias.dart';
import 'package:animebox/features/anime/data/models/episode.dart';
import 'package:animebox/features/anime/data/models/episode_quality.dart';
import 'package:animebox/features/anime/data/models/episode_version.dart';
import 'package:animebox/features/anime/data/models/metadata_status.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';

void main() {
  group('EpisodeVersion (catalogue)', () {
    test('parse une version API avec références Telegram', () {
      final EpisodeVersion version = EpisodeVersion.fromJson(const {
        'id': 12,
        'quality': '1080p',
        'file_size': 1450000000,
        'language': 'french',
        'subtitles': null,
        'created_at': '2026-09-01T10:00:00+00:00',
        'source': {
          'channel_id': 'chan-a',
          'channel_username': 'sourcea',
          'telegram_message_id': 50001,
          'telegram_message_link': 'https://t.me/sourcea/50001',
        },
      });

      expect(version.quality, VideoQuality.fhd);
      expect(version.sizeBytes, 1450000000);
      expect(version.language, 'french');
      expect(version.sourceChannelUsername, 'sourcea');
      expect(version.telegramMessageId, 50001);
      expect(version.hasTelegramLink, isTrue);
      expect(version.createdAt, isNotNull);
    });

    test('un lien Telegram absent reste absent (jamais inventé)', () {
      final EpisodeVersion version = EpisodeVersion.fromJson(const {
        'id': 3,
        'quality': '480p',
        'source': {'channel_id': 'chan-b', 'channel_username': 'sourceb'},
      });
      expect(version.hasTelegramLink, isFalse);
      expect(version.telegramMessageLink, isNull);
    });

    test('se convertit en EpisodeQuality pour les écrans existants', () {
      final EpisodeVersion version = EpisodeVersion.fromJson(const {
        'id': 7,
        'quality': '720p',
        'file_size': 900000000,
        'language': 'french',
        'source': {'channel_username': 'sourcea'},
      });
      final EpisodeQuality quality = version.toEpisodeQuality();
      expect(quality.id, '7');
      expect(quality.quality, VideoQuality.hd);
      expect(quality.language, 'french');
      expect(quality.sourceChannelUsername, 'sourcea');
      expect(quality.hasTelegramLink, isFalse);
    });

    test('qualité inconnue → basse, sans casser le tri', () {
      final EpisodeVersion version = EpisodeVersion.fromJson(const {'id': 1, 'quality': 'x264'});
      expect(version.quality, VideoQuality.low);
    });
  });

  group('MetadataStatus', () {
    test('parse les statuts de l\'API', () {
      expect(MetadataStatus.fromApi('found'), MetadataStatus.found);
      expect(MetadataStatus.fromApi('review_required'), MetadataStatus.reviewRequired);
      expect(MetadataStatus.fromApi('not_found'), MetadataStatus.notFound);
      expect(MetadataStatus.fromApi('ignored'), MetadataStatus.ignored);
      expect(MetadataStatus.fromApi('pending'), MetadataStatus.pending);
      expect(MetadataStatus.fromApi(null), MetadataStatus.pending);
      expect(MetadataStatus.fromApi('inconnu'), MetadataStatus.pending);
    });

    test('fiche minimale vs revue', () {
      expect(MetadataStatus.pending.isPendingInfo, isTrue);
      expect(MetadataStatus.notFound.isPendingInfo, isTrue);
      expect(MetadataStatus.found.isPendingInfo, isFalse);
      expect(MetadataStatus.reviewRequired.needsReview, isTrue);
    });
  });

  group('AnimeAlias / MetadataCandidateInfo', () {
    test('alias depuis chaîne et depuis objet', () {
      final AnimeAlias a = AnimeAlias.fromJson('Ore dake Level Up na Ken');
      final AnimeAlias b = AnimeAlias.fromJson(const {'value': 'SL', 'type': 'abbreviation'});
      expect(a.value, 'Ore dake Level Up na Ken');
      expect(b.value, 'SL');
      expect(b.type, 'abbreviation');
    });

    test('candidat de revue', () {
      final MetadataCandidateInfo candidate = MetadataCandidateInfo.fromJson(const {
        'provider_id': '1',
        'title': 'Solo Leveling',
        'year': 2024,
        'score': 0.7,
      });
      expect(candidate.providerId, '1');
      expect(candidate.title, 'Solo Leveling');
      expect(candidate.year, 2024);
      expect(candidate.score, 0.7);
    });
  });

  group('Anime enrichi', () {
    test('tous les titres connus alimentent la recherche locale', () {
      const Anime anime = Anime(
        id: '1',
        title: 'Solo Leveling',
        posterAsset: 'a.png',
        backdropAsset: 'b.png',
        description: '',
        genres: [],
        year: 2024,
        seasons: [],
        canonicalTitle: 'Solo Leveling',
        originalTitle: 'Ore dake Level Up na Ken',
        alternativeTitles: ['Solo Leveling S2'],
        aliases: [AnimeAlias(value: 'SL')],
      );
      final List<String> titles = anime.allTitles.map((String t) => t.toLowerCase()).toList();
      expect(titles, contains('solo leveling'));
      expect(titles, contains('ore dake level up na ken'));
      expect(titles, contains('solo leveling s2'));
      expect(titles, contains('sl'));
    });

    test('total annoncé distinct des épisodes disponibles', () {
      const Anime anime = Anime(
        id: '1',
        title: 'T',
        posterAsset: 'a.png',
        backdropAsset: 'b.png',
        description: '',
        genres: [],
        year: 0,
        seasons: [],
        totalEpisodesDeclared: 24,
      );
      expect(anime.totalEpisodes, 0);
      expect(anime.totalEpisodesAnnounced, 24);
    });

    test('statuts dérivés', () {
      const Anime anime = Anime(
        id: '1',
        title: 'T',
        posterAsset: 'a.png',
        backdropAsset: 'b.png',
        description: '',
        genres: [],
        year: 0,
        seasons: [],
        metadataStatus: MetadataStatus.reviewRequired,
      );
      expect(anime.needsMetadataReview, isTrue);
      expect(anime.isMetadataPending, isFalse);
    });
  });

  group('Épisode sans titre officiel', () {
    test('affiche « Épisode N » — jamais de titre inventé', () {
      final Episode episode = Episode(
        id: 'e8',
        number: 8,
        title: null,
        thumbnail: 't.png',
        date: DateTime(2026, 9, 1),
        qualities: const [],
      );
      expect(episode.title, isNull);
      expect(episode.label, 'Épisode 8');
    });
  });
}
