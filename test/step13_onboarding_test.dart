// Prompt 13 — Onboarding : 3 écrans exacts, premier lancement uniquement,
// persistance onboardingCompleted, « Commencer » branché sur le vrai
// parcours Telegram existant, aucune donnée fictive.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/onboarding/models/onboarding_page_data.dart';
import 'package:animebox/features/onboarding/onboarding_screen.dart';
import 'package:animebox/features/settings/services/app_settings.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';
import 'package:animebox/features/telegram/screens/telegram_connect_screen.dart';
import 'package:animebox/shared/widgets/carousel_indicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Contenu et préférence (§1/§4)', () {
    test('1. EXACTEMENT 3 écrans avec les titres officiels', () {
      expect(kOnboardingPages.length, 3);
      expect(kOnboardingPages[0].titleTop + kOnboardingPages[0].titleAccent, 'Bienvenue sur AnimeBox');
      expect(kOnboardingPages[1].titleTop + kOnboardingPages[1].titleAccent,
          'Tous vos animés au même endroit');
      expect(kOnboardingPages[2].titleTop + kOnboardingPages[2].titleAccent, 'Sécurisé & 100 % privé');
      expect(kOnboardingPages[2].bullets.length, 4, reason: 'les 4 points de confidentialité réels');
    });

    test('2. onboardingCompleted : false par défaut, persisté à la validation', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      await settings.ensureLoaded();
      expect(settings.onboardingCompleted, isFalse);

      int notified = 0;
      settings.addListener(() => notified++);
      await settings.completeOnboarding();

      expect(settings.onboardingCompleted, isTrue);
      expect(notified, greaterThan(0));
      expect(await db.getSetting('app.onboardingCompleted'), 'true');
    });

    test('3. §4 : la validation survit au redémarrage (même base)', () async {
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings first = AppSettings(database: db);
      await first.ensureLoaded();
      await first.completeOnboarding();

      final AppSettings second = AppSettings(database: db);
      await second.ensureLoaded();
      expect(second.onboardingCompleted, isTrue,
          reason: 'l\'onboarding ne réapparaît plus après redémarrage');
    });
  });

  group('2. Écran onboarding — affichage et navigation (§1/§2)', () {
    testWidgets('4. affichage initial : titre, indicateur 3 points, Suivant, Passer',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () {}, onSkip: () {}),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bienvenue sur AnimeBox', findRichText: true), findsOneWidget);
      final CarouselIndicator indicator =
          tester.widget<CarouselIndicator>(find.byType(CarouselIndicator));
      expect(indicator.count, 3);
      expect(indicator.index, 0);
      expect(find.text('Suivant'), findsOneWidget);
      expect(find.text('Passer'), findsOneWidget);
      expect(find.text('Commencer'), findsNothing,
          reason: '« Commencer » uniquement sur l\'écran 3 (§2)');
    });

    testWidgets('5. Suivant navigue page 1 → 2 → 3, indicateur suit', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () {}, onSkip: () {}),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Tous vos animés au même endroit', findRichText: true), findsOneWidget);
      expect(tester.widget<CarouselIndicator>(find.byType(CarouselIndicator)).index, 1);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Sécurisé & 100 % privé', findRichText: true), findsOneWidget);
      expect(tester.widget<CarouselIndicator>(find.byType(CarouselIndicator)).index, 2);
      expect(find.text('Commencer'), findsOneWidget, reason: 'bouton principal de l\'écran 3 (§2)');
      expect(find.text('Suivant'), findsNothing);
    });

    testWidgets('6. « Commencer » déclenche le vrai callback, « Passer » aussi',
        (WidgetTester tester) async {
      bool started = false;
      bool skipped = false;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () => started = true, onSkip: () => skipped = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();
      expect(started, isTrue, reason: '« Commencer » lance le parcours réel (§5)');
      expect(skipped, isFalse);

      // « Passer » : validation immédiate du parcours.
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () => started = true, onSkip: () => skipped = true),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();
      expect(skipped, isTrue);
    });

    testWidgets('7. petit écran 360x640 : les 3 pages sans overflow (§6/§14)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () {}, onSkip: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue sur AnimeBox', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Tous vos animés au même endroit', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Commencer'), findsOneWidget);
      // Aucune exception Flutter (overflow) n'a été levée — le test passe.
    });
  });

  group('3. Intégration application (§4/§5/§8)', () {
    testWidgets('8. premier lancement : onboarding affiché à la place de l\'accueil',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
        database: db,
        appSettings: AppSettings(database: db),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Bienvenue sur AnimeBox', findRichText: true), findsOneWidget);
    });

    testWidgets('9. « Commencer » persiste l\'état et lance le flow Telegram (§5)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final AppSettings settings = AppSettings(database: db);
      final MockTelegramService telegram = MockTelegramService();
      await telegram.disconnect(); // aucun compte configuré (cas réel §8.10)

      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: telegram,
        database: db,
        appSettings: settings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();

      // État sauvegardé (§8.6) + application ouverte + vrai parcours
      // Telegram poussé au-dessus de l'accueil (§5 — aucun nouvel écran).
      expect(await db.getSetting('app.onboardingCompleted'), 'true');
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(TelegramConnectScreen), findsOneWidget);
    });

    testWidgets('10. compte Telegram déjà configuré : pas de reconnexion forcée (§5/§8.11)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final MockTelegramService telegram = MockTelegramService(); // connecté par défaut
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: telegram,
        database: db,
        appSettings: AppSettings(database: db),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();

      expect(find.byType(TelegramConnectScreen), findsNothing,
          reason: 'compte existant → la logique existante est respectée');
      expect(find.text('Accueil'), findsOneWidget, reason: 'l\'application normale s\'ouvre');
    });

    testWidgets('11. « Passer » valide sans forcer le parcours Telegram (§5)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      final MockTelegramService telegram = MockTelegramService();
      await telegram.disconnect();
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: telegram,
        database: db,
        appSettings: AppSettings(database: db),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();

      expect(await db.getSetting('app.onboardingCompleted'), 'true');
      expect(find.byType(TelegramConnectScreen), findsNothing,
          reason: 'Passer = validation sans imposer la connexion');
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('12. redémarrage après validation : onboarding disparu (§8.7-9)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // Base où l'onboarding a déjà été validé lors d'une session passée.
      final LocalDatabase db = (await LocalDatabase.openInMemory())!;
      await db.setSetting('app.onboardingCompleted', 'true');

      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
        database: db,
        appSettings: AppSettings(database: db),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing,
          reason: 'préférence conservée → plus jamais d\'onboarding');
      expect(find.text('Accueil'), findsOneWidget);
    });
  });
}
