import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/core/utils/formats.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/library/library_screen.dart';
import 'package:animebox/features/player/player_screen.dart';
import 'package:animebox/features/telegram/data/models/source_status.dart';
import 'package:animebox/features/telegram/data/models/telegram_source.dart';
import 'package:animebox/features/telegram/data/services/episode_grouping_service.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';
import 'package:animebox/features/telegram/screens/source_add_screen.dart';
import 'package:animebox/features/telegram/screens/source_detail_screen.dart';
import 'package:animebox/features/telegram/screens/sources_screen.dart';
import 'package:animebox/features/telegram/screens/sync_screen.dart';

void main() {
  group('formats', () {
    test('formatCount utilise le séparateur de milliers', () {
      expect(formatCount(12458), '12 458');
      expect(formatCount(924), '924');
      expect(formatCount(1000000), '1 000 000');
    });

    test('formatRelativeTime couvre les principales durées', () {
      final DateTime now = DateTime(2024, 5, 12, 12, 0);
      expect(formatRelativeTime(now.subtract(const Duration(seconds: 5)), now: now), 'à l\'instant');
      expect(formatRelativeTime(now.subtract(const Duration(minutes: 2)), now: now), 'il y a 2 min');
      expect(formatRelativeTime(now.subtract(const Duration(hours: 8)), now: now), 'il y a 8 h');
      expect(formatRelativeTime(now.subtract(const Duration(days: 1)), now: now), 'hier');
      expect(formatRelativeTime(now.subtract(const Duration(days: 4)), now: now), 'il y a 4 j');
    });

    test('dayGroupLabel regroupe Aujourd\'hui / Hier', () {
      final DateTime now = DateTime(2024, 5, 12, 18, 0);
      expect(dayGroupLabel(now.subtract(const Duration(hours: 2)), now: now), 'Aujourd\'hui');
      expect(dayGroupLabel(now.subtract(const Duration(days: 1, hours: 2)), now: now), 'Hier');
    });
  });

  group('EpisodeGroupingService', () {
    late EpisodeGroupingService service;

    setUp(() => service = EpisodeGroupingService());

    test('trois publications de qualités différentes = UN seul épisode', () {
      const publications = [
        RawPublication(channelUsername: 'animehd', animeTitle: 'Solo Leveling', seasonNumber: 2, episodeNumber: 8, qualityLabel: '1080p', language: 'VF', sizeBytes: 1200),
        RawPublication(channelUsername: 'animehd', animeTitle: 'Solo Leveling', seasonNumber: 2, episodeNumber: 8, qualityLabel: '720p', language: 'VF', sizeBytes: 650),
        RawPublication(channelUsername: 'animevf', animeTitle: 'Solo Leveling', seasonNumber: 2, episodeNumber: 8, qualityLabel: '480p', language: 'VOSTFR', sizeBytes: 350),
      ];

      final grouped = service.group(publications);

      expect(grouped, hasLength(1)); // un seul animé
      expect(grouped.first.seasons, hasLength(1)); // une seule saison
      expect(grouped.first.seasons.first.episodes, hasLength(1)); // UN épisode
      final episode = grouped.first.seasons.first.episodes.first;
      expect(episode.number, 8);
      expect(episode.qualities, hasLength(3));
      expect(episode.qualities.map((q) => q.quality.label), containsAll(['1080p', '720p', '480p']));
    });

    test('la clé de regroupement ignore la qualité', () {
      const a = RawPublication(channelUsername: 'x', animeTitle: 'One Piece', seasonNumber: 1, episodeNumber: 1150, qualityLabel: '1080p', language: 'VOSTFR');
      const b = RawPublication(channelUsername: 'x', animeTitle: 'One Piece', seasonNumber: 1, episodeNumber: 1150, qualityLabel: '480p', language: 'VOSTFR');
      expect(a.groupingKey, b.groupingKey);
    });

    test('mergeIntoCatalog crée une nouvelle saison avec l\'épisode détecté', () {
      const publications = [
        RawPublication(channelUsername: 'animehd', animeTitle: 'One Piece', seasonNumber: 2, episodeNumber: 1, qualityLabel: '1080p', language: 'VOSTFR', sizeBytes: 900),
      ];
      final grouped = service.group(publications);
      final catalog = MockAnimeRepository().allAnime;
      final before = catalog.map((a) => a.totalEpisodes).fold<int>(0, (s, e) => s + e);

      final created = service.mergeIntoCatalog(grouped, catalog);

      expect(created, hasLength(1));
      final after = catalog.map((a) => a.totalEpisodes).fold<int>(0, (s, e) => s + e);
      expect(after, before + 1);
    });
  });

  group('MockTelegramService', () {
    late MockTelegramService service;

    setUp(() => service = MockTelegramService(clock: () => DateTime(2024, 5, 12, 10, 0)));

    test('deux sources mockées par défaut', () {
      expect(service.sources, hasLength(2));
      expect(service.sources.first.username, 'animechannel1');
    });

    test('addSource / removeSource / setSourceEnabled', () async {
      final TelegramSource added = await service.addSource(name: 'Test Canal', username: 'testcanal');
      expect(service.sources, hasLength(3));
      expect(service.sourceById(added.id), isNotNull);

      await service.setSourceEnabled(added.id, false);
      expect(service.sourceById(added.id)!.status, SourceStatus.disabled);
      expect(service.sourceById(added.id)!.syncEnabled, isFalse);

      await service.removeSource(added.id);
      expect(service.sources, hasLength(2));
    });

    test('syncAll simule une synchronisation complète et enrichit l\'historique', () {
      final int historyBefore = service.history.length;
      final int episodesBefore = service.stats.detectedEpisodes;

      fakeAsync((FakeAsync async) {
        service.syncAll();
        // Progression visible pendant la simulation.
        async.elapse(const Duration(milliseconds: 300));
        expect(service.isSyncing, isTrue);
        expect(service.currentProgress, isNotNull);
        expect(service.currentProgress!.percent, greaterThan(0));

        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(service.isSyncing, isFalse);
        expect(service.stats.detectedEpisodes, greaterThan(episodesBefore));
        expect(service.stats.lastSync, DateTime(2024, 5, 12, 10, 0));
        expect(service.history.length, historyBefore + 1);
        expect(service.history.first.success, isTrue);
      });
    });
  });

  group('widgets — sources et synchronisation', () {
    Future<void> pumpApp(WidgetTester tester, {TelegramService? telegramService}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: telegramService ?? MockTelegramService(clock: () => DateTime(2024, 5, 12, 10, 0)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openSources(WidgetTester tester) async {
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes sources Telegram'));
      await tester.pumpAndSettle();
    }

    testWidgets('profil → sources : liste, détails, désactivation', (WidgetTester tester) async {
      final TelegramService service = MockTelegramService(clock: () => DateTime(2024, 5, 12, 10, 0));
      await pumpApp(tester, telegramService: service);
      await openSources(tester);

      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(find.text('Anime Channel 1'), findsOneWidget);
      expect(find.text('Anime VF'), findsOneWidget);
      expect(find.text('@animechannel1'), findsOneWidget);

      // Détails de la première source.
      await tester.tap(find.text('Anime Channel 1'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceDetailScreen), findsOneWidget);
      expect(find.text('Synchroniser maintenant'), findsOneWidget);

      // Désactivation via l'interrupteur « Synchronisation automatique ».
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-channel')!.syncEnabled, isFalse);
      expect(find.text('Désactivée'), findsOneWidget);

      // Réactivation.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-channel')!.syncEnabled, isTrue);
    });

    testWidgets('ajout d\'une source avec validation locale', (WidgetTester tester) async {
      final TelegramService service = MockTelegramService(clock: () => DateTime(2024, 5, 12, 10, 0));
      await pumpApp(tester, telegramService: service);
      await openSources(tester);

      await tester.tap(find.text('Ajouter une source'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceAddScreen), findsOneWidget);

      // Champ vide.
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une source.'), findsOneWidget);

      // Format invalide.
      await tester.enterText(find.byType(TextField), 'pas un lien valide!');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Format de source invalide.'), findsOneWidget);

      // Format valide (@username).
      await tester.enterText(find.byType(TextField), '@otakustream');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu de la source'), findsOneWidget);
      expect(find.text('Otakustream'), findsOneWidget);

      // Ajout effectif.
      await tester.ensureVisible(find.text('Ajouter cette source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter cette source'));
      await tester.pumpAndSettle();
      expect(service.sources, hasLength(3));
      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(find.text('Otakustream'), findsOneWidget);
    });

    testWidgets('synchronisation : progression simulée puis historique enrichi', (WidgetTester tester) async {
      final TelegramService service = MockTelegramService(clock: () => DateTime(2024, 5, 12, 10, 0));
      await pumpApp(tester, telegramService: service);

      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synchronisation'));
      await tester.pumpAndSettle();
      expect(find.byType(SyncScreen), findsOneWidget);
      expect(find.text('Moteur actif'), findsOneWidget);
      expect(find.text('12 458'), findsOneWidget);

      final int historyBefore = service.history.length;

      await tester.tap(find.text('Synchroniser maintenant'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Analyzing publications...'), findsOneWidget);

      // Fait avancer la simulation jusqu'à la fin.
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(service.isSyncing, isFalse);
      expect(service.history.length, historyBefore + 1);
      expect(find.text('Synchroniser maintenant'), findsOneWidget);
    });
  });

  group('widgets — bibliothèque', () {
    Future<void> tapCategory(WidgetTester tester, String label) async {
      final Finder chips = find.byWidgetPredicate(
        (Widget widget) => widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      // La rangée de catégories conserve sa position de défilement : on
      // revient au début pour une recherche fiable (les puces hors écran
      // sont démontées par la ListView paresseuse).
      for (int i = 0; i < 8; i++) {
        await tester.drag(chips.first, const Offset(600, 0), warnIfMissed: false);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text(label), 80, scrollable: chips);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AnimeBoxApp(repository: MockAnimeRepository()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bibliothèque'));
      await tester.pumpAndSettle();
    }

    testWidgets('catégories : favoris par défaut, puis récents et tous', (WidgetTester tester) async {
      await pumpApp(tester);

      // Favoris par défaut : 3 animés en grille.
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.text('Solo Leveling'), findsOneWidget);
      expect(find.text('One Piece'), findsOneWidget);
      expect(find.text('Jujutsu Kaisen'), findsOneWidget);

      // Récemment ajoutés.
      await tapCategory(tester, 'Récemment ajoutés');
      expect(find.text('Demon Slayer'), findsNothing);

      // Tous les animés.
      await tapCategory(tester, 'Tous les animés');
      expect(find.text('Demon Slayer'), findsOneWidget);

      // Vue liste.
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Demon Slayer'), findsOneWidget);

      // Tri par nom.
      await tester.tap(find.text('Trier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nom A → Z'));
      await tester.pumpAndSettle();
      expect(find.text('Demon Slayer'), findsOneWidget);
    });

    testWidgets('suivis : carte avec progression après avoir suivi un animé', (WidgetTester tester) async {
      await pumpApp(tester);

      await tapCategory(tester, 'Suivis');
      expect(find.text('Aucun animé suivi'), findsOneWidget);

      // Suivre Solo Leveling depuis sa fiche.
      await tapCategory(tester, 'Tous les animés');
      await tester.tap(find.text('Solo Leveling'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Suivre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivre'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      await tapCategory(tester, 'Suivis');
      expect(find.text('Solo Leveling'), findsOneWidget);
      expect(find.textContaining('Dernier épisode disponible'), findsOneWidget);
    });

    testWidgets('continuer : ouvre le lecteur à la position enregistrée', (WidgetTester tester) async {
      await pumpApp(tester);

      await tapCategory(tester, 'Continuer');

      // Solo Leveling S2E07 avec progression 13:12.
      expect(find.textContaining('Reprendre à'), findsWidgets);
      await tester.tap(find.textContaining('Reprendre à').first);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.textContaining('S02E07'), findsOneWidget);
    });

    testWidgets('récemment ajoutés : ouvre le choix de qualité du dernier épisode', (WidgetTester tester) async {
      await pumpApp(tester);

      await tapCategory(tester, 'Récemment ajoutés');
      expect(find.text('S2E09'), findsOneWidget);

      await tester.tap(find.text('S2E09'));
      await tester.pumpAndSettle();
      expect(find.text('Qualité disponible'), findsOneWidget);
    });
  });
}
