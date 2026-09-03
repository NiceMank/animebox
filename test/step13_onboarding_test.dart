// Prompt 13 — Onboarding : 3 écrans exacts, premier lancement uniquement,
// persistance onboardingCompleted, « Commencer » branché sur le vrai
// parcours Telegram existant, aucune donnée fictive.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/intro/intro_screen.dart';
import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/onboarding/models/onboarding_page_data.dart';
import 'package:animebox/features/onboarding/onboarding_screen.dart';
import 'package:animebox/features/settings/services/app_settings.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';
import 'package:animebox/features/telegram/screens/telegram_connect_screen.dart';
import 'package:animebox/shared/widgets/carousel_indicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Avance le temps de quelques frames SANS attendre la fin des
  /// animations infinies (pulse discret des illustrations §2 —
  /// pumpAndSettle n'est pas utilisable tant que l'onboarding est visible).
  Future<void> pumpFrames(WidgetTester tester, {int times = 3, int millis = 300}) async {
    for (int i = 0; i < times; i++) {
      await tester.pump(Duration(milliseconds: millis));
    }
  }

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
      await pumpFrames(tester);

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
      await pumpFrames(tester);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      expect(find.text('Tous vos animés au même endroit', findRichText: true), findsOneWidget);
      expect(tester.widget<CarouselIndicator>(find.byType(CarouselIndicator)).index, 1);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
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
      await pumpFrames(tester);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Commencer'));
      await pumpFrames(tester);
      expect(started, isTrue, reason: '« Commencer » lance le parcours réel (§5)');
      expect(skipped, isFalse);

      // « Passer » : validation immédiate du parcours.
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onStart: () => started = true, onSkip: () => skipped = true),
      ));
      await pumpFrames(tester);
      await tester.tap(find.text('Passer'));
      await pumpFrames(tester);
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
      await pumpFrames(tester);
      expect(find.text('Bienvenue sur AnimeBox', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      expect(find.text('Tous vos animés au même endroit', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      expect(find.text('Commencer'), findsOneWidget);
      // Aucune exception Flutter (overflow) n'a été levée — le test passe.
    });
  });

  group('3. Intégration application (§4/§5/§8)', () {
    // NOTE : les tests d'intégration vérifient le CÂBLAGE (ondoarding ↔
    // app ↔ flow Telegram) avec des préférences injectées maîtrisées ;
    // la persistance SQL est prouvée séparément (tests 2/3 + test 12) —
    // la base « :memory: » étant partagée au sein d'un même isolate de
    // test, elle ne peut pas servir d'état frais fiable ici.

    Future<void> pumpAppWith(
      WidgetTester tester, {
      required AppSettings settings,
      required MockTelegramService telegram,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: telegram,
        appSettings: settings,
      ));
      await pumpFrames(tester);
    }

    Future<AppSettings> freshSettings() async {
      final AppSettings settings = AppSettings(database: null);
      await settings.ensureLoaded();
      return settings;
    }

    /// Franchit l'écran d'accueil (balayage vers le haut → onboarding).
    Future<void> passIntro(WidgetTester tester) async {
      expect(find.byType(IntroScreen), findsOneWidget,
          reason: "l'accueil animé précède toujours l'onboarding au premier lancement");
      await tester.fling(find.byType(IntroScreen), const Offset(0, -120), 800);
      await pumpFrames(tester);
      expect(find.byType(IntroScreen), findsNothing);
    }

    testWidgets('8. premier lancement : onboarding affiché à la place de l\'accueil',
        (WidgetTester tester) async {
      await pumpAppWith(tester, settings: await freshSettings(), telegram: MockTelegramService());
      await passIntro(tester);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Bienvenue sur AnimeBox', findRichText: true), findsOneWidget);
    });

    testWidgets('9. « Commencer » valide l\'état et lance le flow Telegram (§5)',
        (WidgetTester tester) async {
      final AppSettings settings = await freshSettings();
      final MockTelegramService telegram = MockTelegramService();
      await telegram.disconnect(); // aucun compte configuré (cas réel §8.10)
      await pumpAppWith(tester, settings: settings, telegram: telegram);
      await passIntro(tester);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Commencer'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle(); // onboarding démonté → settle possible

      // État validé (§8.6) + application ouverte + vrai parcours
      // Telegram poussé au-dessus de l'accueil (§5 — aucun nouvel écran).
      expect(settings.onboardingCompleted, isTrue);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(TelegramConnectScreen), findsOneWidget);
    });

    testWidgets('10. compte Telegram déjà configuré : pas de reconnexion forcée (§5/§8.11)',
        (WidgetTester tester) async {
      final MockTelegramService telegram = MockTelegramService(); // connecté par défaut
      await pumpAppWith(tester, settings: await freshSettings(), telegram: telegram);
      await passIntro(tester);

      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Suivant'));
      await pumpFrames(tester);
      await tester.tap(find.text('Commencer'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(TelegramConnectScreen), findsNothing,
          reason: 'compte existant → la logique existante est respectée');
      expect(find.text('Accueil'), findsOneWidget, reason: 'l\'application normale s\'ouvre');
    });

    testWidgets('11. « Passer » valide sans forcer le parcours Telegram (§5)',
        (WidgetTester tester) async {
      final AppSettings settings = await freshSettings();
      final MockTelegramService telegram = MockTelegramService();
      await telegram.disconnect();
      await pumpAppWith(tester, settings: settings, telegram: telegram);
      await passIntro(tester);

      await tester.tap(find.text('Passer'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(settings.onboardingCompleted, isTrue);
      expect(find.byType(TelegramConnectScreen), findsNothing,
          reason: 'Passer = validation sans imposer la connexion');
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    // Persistance DISQUE réelle entre deux « sessions » — hors
    // testWidgets : les accès SQLite réels exigent la boucle async
    // réelle (test() simple), pas l'horloge factice des widget-tests.
    test('12. redémarrage : préférence DISQUE relue après fermeture (§8.7-9)', () async {
      final Directory dir = await Directory.systemTemp.createTemp('animebox_step13');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      // Session 1 : onboarding validé, application fermée.
      final LocalDatabase firstDb = (await LocalDatabase.open(directoryPath: dir.path))!;
      final AppSettings first = AppSettings(database: firstDb);
      await first.ensureLoaded();
      await first.completeOnboarding();
      await firstDb.close();

      // Session 2 : nouvelle ouverture sur le MÊME fichier → relue.
      final LocalDatabase secondDb = (await LocalDatabase.open(directoryPath: dir.path))!;
      addTearDown(() => secondDb.close());
      final AppSettings second = AppSettings(database: secondDb);
      await second.ensureLoaded();
      expect(second.onboardingCompleted, isTrue,
          reason: 'préférence relue depuis le disque après redémarrage réel');
    });

    testWidgets('13. état restauré « terminé » : l\'app saute l\'onboarding (§8.9)',
        (WidgetTester tester) async {
      final AppSettings settings = AppSettings(database: null);
      await settings.ensureLoaded();
      await settings.completeOnboarding(); // état restauré « session précédente validée »

      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
        appSettings: settings,
      ));
      await pumpFrames(tester);

      expect(find.byType(OnboardingScreen), findsNothing,
          reason: 'préférence conservée → plus jamais d\'onboarding');
      expect(find.text('Accueil'), findsOneWidget);
    });
  });
}
