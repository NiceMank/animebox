import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/local/data/local_database.dart';
import 'package:animebox/features/telegram/data/services/local_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_session_manager.dart';
import 'package:animebox/features/telegram/screens/telegram_connect_screen.dart';

import 'step7_fake_gateway.dart';

void main() {
  group('Écran de connexion — flux réel (états d\'interface)', () {
    testWidgets('NOT_CONNECTED → CODE_REQUIRED → PASSWORD_REQUIRED → CONNECTED', (WidgetTester tester) async {
      // SQLite via FFI : les appels réels s'exécutent dans runAsync.
      final LocalDatabase db = (await tester.runAsync(() async => (await LocalDatabase.openInMemory())!))!;
      final FakeTelegramGateway gateway = FakeTelegramGateway(requirePassword: true);
      final LocalTelegramService service = LocalTelegramService(
        gateway: gateway,
        sessionManager: TelegramSessionManager(store: InMemoryKeyValueStore()),
        database: db,
      );
      addTearDown(() async {
        service.dispose();
        await tester.runAsync(db.close);
      });

      await tester.pumpWidget(MaterialApp(home: TelegramConnectScreen(service: service)));
      await tester.pumpAndSettle();

      // NOT_CONNECTED : bouton principal du prompt.
      expect(find.text('Connecter Telegram'), findsOneWidget);
      expect(
        find.text('Connectez votre compte Telegram pour utiliser vos propres sources dans AnimeBox.'),
        findsOneWidget,
      );

      // Numéro → CONNECTING → CODE_REQUIRED.
      await tester.tap(find.text('Connecter Telegram'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '+22901020304');
      await tester.tap(find.text('Envoyer le code'));
      await tester.pumpAndSettle();
      expect(service.authState, TelegramAuthState.codeRequired);
      expect(find.text('Code Telegram'), findsOneWidget);

      // Code → PASSWORD_REQUIRED (compte 2FA, jamais contourné).
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(service.authState, TelegramAuthState.passwordRequired);
      expect(find.text('Mot de passe Telegram'), findsOneWidget);
      expect(find.textContaining('deux facteurs'), findsOneWidget);

      // Mot de passe 2FA → CONNECTED : profil affiché, bouton Déconnecter.
      await tester.enterText(find.byType(TextField), 'motdepasse2fa');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(service.authState, TelegramAuthState.connected);
      expect(find.text('Test AnimeBox'), findsOneWidget);
      expect(find.text('@test_user'), findsOneWidget);
      expect(find.text('Déconnecter'), findsOneWidget);
    });

    testWidgets('SESSION_EXPIRED → vue de reconnexion', (WidgetTester tester) async {
      final LocalDatabase db = (await tester.runAsync(() async => (await LocalDatabase.openInMemory())!))!;
      final FakeTelegramGateway gateway = FakeTelegramGateway();
      final LocalTelegramService service = LocalTelegramService(
        gateway: gateway,
        sessionManager: TelegramSessionManager(store: InMemoryKeyValueStore()),
        database: db,
      );
      addTearDown(() async {
        service.dispose();
        await tester.runAsync(db.close);
      });

      await service.requestCode('+22901020304');
      await service.verifyCode('+22901020304', '12345');
      expect(service.authState, TelegramAuthState.connected);

      // Révocation distante de la session.
      gateway.expireSession();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(MaterialApp(home: TelegramConnectScreen(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Session expirée'), findsOneWidget);
      expect(find.text('Se reconnecter'), findsOneWidget);
    });
  });
}
