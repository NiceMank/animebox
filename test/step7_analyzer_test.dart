import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/analyzer/engine.dart';
import 'package:animebox/features/analyzer/models.dart';
import 'package:animebox/features/analyzer/text_utils.dart';

void main() {
  final RuleBasedAnalyzer analyzer = RuleBasedAnalyzer();

  Map<String, Object?> message({
    String? fileName,
    String? caption,
    int? fileSize,
    String? mimeType,
    int? duration,
    int? width,
    int? height,
    int? messageId,
    String? channelId,
    String? channelUsername,
    String? link,
    String? mediaType,
  }) =>
      {
        'file_name': fileName,
        'text': caption,
        'file_size': fileSize,
        'mime_type': mimeType,
        'duration': duration,
        'width': width,
        'height': height,
        'telegram_message_id': messageId,
        'telegram_channel_id': channelId,
        'telegram_channel_username': channelUsername,
        'telegram_message_link': link,
        'media_type': mediaType,
      };

  group('normalisation (parité moteur Python)', () {
    test('séparateurs, casse, crochets', () {
      expect(normalize('Solo_Leveling_S02_E08_1080p'), 'solo leveling s02 e08 1080p');
      expect(normalize('Solo.Leveling.S02E08.1080p'), 'solo leveling s02e08 1080p');
      expect(normalize('SOLO LEVELING 08 VOSTFR'), 'solo leveling 08 vostfr');
      expect(normalize('[HorribleSubs] One Piece - 1124'), 'horriblesubs one piece 1124');
      expect(normalize('Ore dake Level Up na Ken'), 'ore dake level up na ken');
    });

    test('titlecase', () {
      expect(titlecase('solo leveling'), 'Solo Leveling');
      expect(titlecase('one piece'), 'One Piece');
    });

    test('stripExtension', () {
      expect(stripExtension('Solo.Leveling.S02E08.1080p.VF.mkv'), 'Solo.Leveling.S02E08.1080p.VF');
      expect(stripExtension('sans extension'), 'sans extension');
      expect(stripExtension(null), isNull);
    });
  });

  group('analyse — cas de référence Python', () {
    test('Solo.Leveling.S02E08.1080p.VF.mkv → HIGH 98', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv',
        messageId: 1001,
        channelId: '7',
        channelUsername: 'sourcea',
        link: 'https://t.me/sourcea/1001',
      ));
      expect(result.title, 'Solo Leveling');
      expect(result.titleKey, 'solo leveling');
      expect(result.titleMatched, isTrue);
      expect(result.animeKey, 'solo leveling');
      expect(result.season, 2);
      expect(result.seasonSource, 'combined');
      expect(result.episode, 8);
      expect(result.episodeSource, 'combined');
      expect(result.quality, '1080p');
      expect(result.qualitySource, 'explicit');
      expect(result.language, 'french');
      expect(result.subtitles, isNull);
      expect(result.status, kStatusHigh);
      expect(result.confidence, 98);
      expect(result.telegramMessageId, 1001);
      expect(result.telegramMessageLink, 'https://t.me/sourcea/1001');
      expect(result.telegramChannelUsername, 'sourcea');
    });

    test('720p VF', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'Solo.Leveling.S02E08.720p.VF.mkv',
        messageId: 1002,
      ));
      expect(result.quality, '720p');
      expect(result.language, 'french');
      expect(result.episode, 8);
      expect(result.season, 2);
    });

    test('480p VOSTFR (espaces, autre source)', () {
      final AnalysisResult result = analyzer.analyze(message(
        caption: 'Solo Leveling S02E08 480p VOSTFR',
        mediaType: 'video',
        messageId: 1003,
        channelUsername: 'sourceb',
      ));
      expect(result.title, 'Solo Leveling');
      expect(result.episode, 8);
      expect(result.quality, '480p');
      expect(result.language, 'japanese');
      expect(result.subtitles, 'french');
      expect(result.status, kStatusHigh);
    });

    test('Ore dake Level Up na Ken S2E8 → alias → Solo Leveling', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'Ore.dake.Level.Up.na.Ken.S02E08.1080p.mkv',
      ));
      expect(result.title, 'Solo Leveling');
      expect(result.titleMatched, isTrue);
      expect(result.titleViaAlias, isTrue);
      expect(result.animeKey, 'solo leveling');
      // Alias : +26 au lieu de +33 → 81 % (MEDIUM), comme le moteur Python.
      expect(result.confidence, 81);
      expect(result.status, kStatusMedium);
    });

    test('One Piece 1124 (numéro seul, titre connu)', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'One Piece 1124 1080p VOSTFR.mkv',
      ));
      expect(result.title, 'One Piece');
      expect(result.season, isNull);
      expect(result.episode, 1124);
      expect(result.episodeSource, 'heuristic_known');
      expect(result.quality, '1080p');
    });

    test('épisode seul sans titre → NEEDS_REVIEW, jamais classé aveuglément', () {
      final AnalysisResult result = analyzer.analyze(message(
        caption: 'Épisode 08 disponible',
      ));
      expect(result.titleKey, isNull);
      expect(result.episode, 8);
      expect(result.status, kStatusNeedsReview);
    });

    test('numéro seul avec titre inconnu → confiance réduite', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'Serie Inconnue 17 720p.mkv',
      ));
      expect(result.titleKey, 'serie inconnue');
      expect(result.episode, 17);
      expect(result.episodeSource, 'heuristic');
      expect(result.status, kStatusNeedsReview);
    });

    test('année jamais confondue avec un épisode', () {
      final AnalysisResult result = analyzer.analyze(message(
        fileName: 'Solo Leveling 2024 1080p.mkv',
      ));
      expect(result.year, 2024);
      expect(result.episode, isNull);
    });

    test('qualité déduite des dimensions quand absente du texte', () {
      final AnalysisResult result = analyzer.analyze(message(
        caption: 'Solo Leveling S02E08',
        width: 1920,
        height: 1080,
      ));
      expect(result.quality, '1080p');
      expect(result.qualitySource, 'metadata');
    });

    test('références Telegram conservées (jamais inventées si absentes)', () {
      final AnalysisResult result = analyzer.analyze(message(fileName: 'Solo Leveling S02E08.mkv'));
      expect(result.telegramMessageId, isNull);
      expect(result.telegramMessageLink, isNull);
    });

    test('type de média détecté', () {
      expect(
        analyzer.analyze(message(fileName: 'x.mkv', mediaType: 'document')).mediaType,
        'video',
      );
      expect(
        analyzer.analyze(message(fileName: 'x.mp3')).mediaType,
        'audio',
      );
      expect(analyzer.analyze(message(caption: 'bonjour')).mediaType, 'unknown');
    });
  });

  group('regroupement des qualités (scénario §16)', () {
    test('trois publications → un seul épisode, trois versions', () {
      final List<AnalysisResult> results = [
        analyzer.analyze(message(fileName: 'Solo.Leveling.S02E08.1080p.VF.mkv', messageId: 1001, channelUsername: 'a')),
        analyzer.analyze(message(fileName: 'Solo.Leveling.S02E08.720p.VF.mkv', messageId: 1002, channelUsername: 'a')),
        analyzer.analyze(message(caption: 'Solo Leveling S02E08 480p VOSTFR', mediaType: 'video', messageId: 1003, channelUsername: 'b')),
      ];
      final List<AnalysisResult> ingestible =
          results.where((AnalysisResult r) => kIngestibleStatuses.contains(r.status)).toList();
      expect(ingestible.length, 3);
      // Même animé, même saison, même épisode.
      expect(ingestible.map((AnalysisResult r) => r.animeKey).toSet(), {'solo leveling'});
      expect(ingestible.map((AnalysisResult r) => r.season).toSet(), {2});
      expect(ingestible.map((AnalysisResult r) => r.episode).toSet(), {8});
      // Trois qualités distinctes, toutes conservées.
      expect(ingestible.map((AnalysisResult r) => r.quality).toSet(), {'1080p', '720p', '480p'});
      expect(ingestible.map((AnalysisResult r) => r.telegramMessageId).toSet(), {1001, 1002, 1003});
    });
  });
}
