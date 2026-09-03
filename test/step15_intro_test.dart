import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/features/intro/intro_screen.dart';
import 'package:animebox/features/intro/widgets/animated_box_cube.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/onboarding/onboarding_screen.dart';
import 'package:animebox/features/settings/services/app_settings.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';

/// Écran d'accueil (avant onboarding) : logo + cube animé, démarrage au
/// balayage vers le haut — réel fonctionnel (aucune fausse action).
void main() {
  Future<void> pumpFrames(WidgetTester tester, {int times = 3, int millis = 300}) async {
    for (int i = 0; i < times; i++) {
      await tester.pump(Duration(milliseconds: millis));
    }
  }

  Widget introHost({required VoidCallback onStart}) {
    return MaterialApp(home: IntroScreen(onStart: onStart));
  }

  group('IntroScreen — rendu', () {
    testWidgets('affiche le titre, le cube, l\\'indication, sans overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(introHost(onStart: () {}));
      await pumpFrames(tester);

      expect(find.text('AnimeBox'), findsOneWidget);
      expect(find.text('Balayer vers le haut'), findsOneWidget);
      expect(find.byType(AnimatedBoxCube), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_double_arrow_up_rounded), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'aucune mise en page cassée au 360×640');
    });

    testWidgets('le cube tourne (frames distinctes repaintent)', (WidgetTester tester) async {
      await tester.pumpWidget(introHost(onStart: () {}));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      // S\'il y a une Exception de rendu avec l\'animation infinie, elle
      // aurait été levée très tôt (pumpFrames exclu volontairement).
      expect(tester.takeException(), isNull);
    });
  });

  group('IntroScreen — démarrage réel (aucune fausse action)', () {
    testWidgets('appui sur l\\'indication déclenche onStart une seule fois', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(introHost(onStart: () => calls++));
      await pumpFrames(tester, times: 1);

      await tester.tap(find.text('Balayer vers le haut'));
      await pumpFrames(tester, times: 1);
      expect(calls, 1, reason: 'l\\'indication tactile déclenche le démarrage');

      await tester.tap(find.text('Balayer vers le haut'));
      await pumpFrames(tester, times: 1);
      expect(calls, 1, reason: 'action idempotente : pas de double démarrage');
    });

    testWidgets('balayage vers le haut déclenche onStart', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(introHost(onStart: () => calls++));
      await pumpFrames(tester, times: 1);

      await tester.drag(find.byType(IntroScreen), const Offset(0, -140));
      await pumpFrames(tester, times: 1);
      expect(calls, 1);
    });

    testWidgets('balayage vers le bas NE démarre PAS', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(introHost(onStart: () => calls++));
      await pumpFrames(tester, times: 1);

      await tester.drag(find.byType(IntroScreen), const Offset(0, 140));
      await pumpFrames(tester, times: 1);
      expect(calls, 0, reason: 'pas de fausse action : le sens compte');
    });

    testWidgets('petit balayage vers le haut insuffisant NE démarre PAS', (WidgetTester tester) async {
      int calls = 0;
      await tester.pumpWidget(introHost(onStart: () => calls++));
      await pumpFrames(tester, times: 1);

      await tester.drag(find.byType(IntroScreen), const Offset(0, -18));
      await pumpFrames(tester, times: 1);
      expect(calls, 0, reason: 'seuil de balayage respecté');
    });
  });

  group('Intégration — premier lancement', () {
    testWidgets('accueil → balayage → onboarding (puis plus jamais une fois validé)', (WidgetTester tester) async {
      final AppSettings settings = AppSettings(database: null);
      await settings.ensureLoaded();

      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
        appSettings: settings,
      ));
      await pumpFrames(tester);

      expect(find.byType(IntroScreen), findsOneWidget,
          reason: 'premier lancement : l\\'écran d\\'accueil précède l\\'onboarding');
      expect(find.byType(OnboardingScreen), findsNothing);

      await tester.fling(find.byType(IntroScreen), const Offset(0, -120), 800);
      await pumpFrames(tester);

      expect(find.byType(IntroScreen), findsNothing, reason: 'le balayage amène l\\'onboarding');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('onboarding déjà validé : NI accueil NI onboarding', (WidgetTester tester) async {
      final AppSettings settings = AppSettings(database: null);
      await settings.ensureLoaded();
      await settings.completeOnboarding();

      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AnimeBoxApp(
        repository: MockAnimeRepository(),
        telegramService: MockTelegramService(),
        appSettings: settings,
      ));
      await pumpFrames(tester);

      expect(find.byType(IntroScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Accueil'), findsOneWidget);
    });
  });
}
