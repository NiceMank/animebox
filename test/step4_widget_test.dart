import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/telegram/data/services/mock_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';
import 'package:animebox/features/telegram/screens/publications_screen.dart';
import 'package:animebox/features/telegram/screens/source_add_screen.dart';
import 'package:animebox/features/telegram/screens/source_detail_screen.dart';
import 'package:animebox/features/telegram/screens/sources_screen.dart';
import 'package:animebox/features/telegram/screens/telegram_connect_screen.dart';

Future<void> pumpApp(WidgetTester tester, TelegramService service) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AnimeBoxApp(repository: MockAnimeRepository(), telegramService: service));
  await tester.pumpAndSettle();
}

Future<void> openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Profil'));
  await tester.pumpAndSettle();
}

void main() {
  group('Connexion Telegram (écran)', () {
    testWidgets('parcours complet : numéro → code → compte connecté', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await service.disconnect(); // démarre déconnecté pour tester le flux
      await pumpApp(tester, service);

      await openProfile(tester);
      expect(find.text('Connectez votre compte Telegram'), findsOneWidget);

      await tester.tap(find.text('Connexion Telegram'));
      await tester.pumpAndSettle();
      expect(find.byType(TelegramConnectScreen), findsOneWidget);
      expect(
        find.text('Connectez votre compte Telegram pour utiliser vos propres sources dans AnimeBox.'),
        findsOneWidget,
      );

      // Étape 1 : numéro.
      await tester.tap(find.text('Connecter Telegram'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '+22901020304');
      await tester.tap(find.text('Envoyer le code'));
      await tester.pumpAndSettle();

      // Étape 2 : code.
      expect(find.text('Code Telegram'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      // Étape 3 : compte connecté (jamais de secret affiché).
      expect(service.authState, TelegramAuthState.connected);
      expect(find.text('Démo AnimeBox'), findsOneWidget);
      expect(find.text('@animebox_demo'), findsOneWidget);
      expect(find.text('CONNECTÉ'), findsOneWidget);

      // Déconnexion (bouton principal, puis confirmation explicite).
      await tester.tap(find.text('Déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Se déconnecter'),
      ));
      await tester.pumpAndSettle();
      expect(service.authState, TelegramAuthState.disconnected);
      expect(find.text('Connecter Telegram'), findsOneWidget);
    });

    testWidgets('code incorrect → message compréhensible, sans secret', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await service.disconnect();
      await pumpApp(tester, service);

      await openProfile(tester);
      await tester.tap(find.text('Connexion Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connecter Telegram'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '+22901020304');
      await tester.tap(find.text('Envoyer le code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(find.text('Code de connexion incorrect.'), findsOneWidget);
      expect(service.authState, isNot(TelegramAuthState.connected));
    });
  });

  group('Publications récentes (écran de vérification)', () {
    testWidgets('liste des publications : IDs, médias et liens Telegram', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await pumpApp(tester, service);

      await openProfile(tester);
      await tester.tap(find.text('Mes sources Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anime Channel 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publications récentes'));
      await tester.pumpAndSettle();

      expect(find.byType(PublicationsScreen), findsOneWidget);
      expect(find.text('Message #12345'), findsOneWidget);
      expect(find.text('Vidéo'), findsWidgets);
      expect(find.textContaining('Solo Leveling S02E08 1080p VF'), findsOneWidget);

      // Bouton actif (lien présent) → feuille avec le lien.
      await tester.tap(find.byTooltip('Ouvrir dans Telegram').first);
      await tester.pumpAndSettle();
      expect(find.text('Lien Telegram'), findsOneWidget);
      expect(find.textContaining('https://t.me/animechannel1/12345'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      // Dernière publication simulée : pas de lien → bouton désactivé.
      final Finder disabled = find.byTooltip('Aucun lien Telegram disponible');
      await tester.scrollUntilVisible(
        disabled,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(disabled, findsWidgets);
      final IconButton button = tester.widget<IconButton>(
        find.ancestor(of: disabled, matching: find.byType(IconButton)).first,
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('source supprimée avec confirmation explicite', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await pumpApp(tester, service);

      await openProfile(tester);
      await tester.tap(find.text('Mes sources Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anime VF'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Supprimer la source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer la source'));
      await tester.pumpAndSettle();

      // Confirmation obligatoire — jamais de suppression silencieuse.
      expect(find.text('Supprimer cette source ?'), findsOneWidget);
      expect(
        find.text('Les données associées à cette source pourront également être supprimées selon les règles de conservation définies par l\'application.'),
        findsOneWidget,
      );

      // Annuler : la source reste.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-vf'), isNotNull);

      // Supprimer : la source disparaît.
      await tester.tap(find.text('Supprimer la source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-vf'), isNull);
      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(find.text('Anime VF'), findsNothing);
    });

    testWidgets('interrupteur de synchronisation automatique', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await pumpApp(tester, service);

      await openProfile(tester);
      await tester.tap(find.text('Mes sources Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anime Channel 1'));
      await tester.pumpAndSettle();

      expect(find.byType(SourceDetailScreen), findsOneWidget);
      expect(find.text('Synchronisation automatique'), findsOneWidget);
      expect(find.text('Activée'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-channel')!.syncEnabled, isFalse);
      expect(find.text('Désactivée'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(service.sourceById('src-anime-channel')!.syncEnabled, isTrue);
    });
  });

  group('Ajout d\'une source via résolution', () {
    testWidgets('aperçu du canal puis ajout ; erreurs introuvable/inaccessible', (WidgetTester tester) async {
      final MockTelegramService service = MockTelegramService();
      await pumpApp(tester, service);

      await openProfile(tester);
      await tester.tap(find.text('Mes sources Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter une source'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceAddScreen), findsOneWidget);

      // Canal introuvable.
      await tester.enterText(find.byType(TextField), '@introuvable');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Source introuvable sur Telegram.'), findsOneWidget);

      // Canal inaccessible.
      await tester.enterText(find.byType(TextField), '@prive');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Cette source n\'est pas accessible à votre compte.'), findsOneWidget);

      // Canal accessible : aperçu puis ajout.
      await tester.enterText(find.byType(TextField), '@animechannel1');
      await tester.tap(find.text('Vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu de la source'), findsOneWidget);
      expect(find.text('Animechannel1'), findsOneWidget);
      expect(find.textContaining('Canal de démonstration AnimeBox'), findsOneWidget);

      await tester.tap(find.text('Ajouter cette source'));
      await tester.pumpAndSettle();
      expect(find.byType(SourcesScreen), findsOneWidget);
      expect(find.text('Animechannel1'), findsOneWidget);
      expect(service.sources, hasLength(3));
    });
  });
}
