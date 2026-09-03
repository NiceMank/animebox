import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/features/telegram/data/gateway/tdlib_gateway.dart';
import 'package:animebox/features/telegram/data/gateway/telegram_gateway.dart';

/// Fiabilité du démarrage TDLib (régression « connexion muette ») : tout
/// échec doit devenir un état d'erreur VISIBLE — jamais de boucle
/// silencieuse sans réseau.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('échec de démarrage du client natif ⇒ état error + message lisible', () async {
    final TdlibTelegramGateway gateway = TdlibTelegramGateway(apiId: 39526821, apiHash: 'faux-hash-de-test');
    // En environnement de test (VM), la bibliothèque native n'existe pas :
    // l'initialisation échoue — c'est précisément ce chemin que l'on verrouille.
    await gateway.connect();
    expect(gateway.authState, GatewayAuthState.error,
        reason: "aucun blocage silencieux : l'échec est matérialisé");
    expect(gateway.lastError, isNotNull);
    expect(gateway.lastError, isNotEmpty);
  });

  test('les paramètres obsolètes de TDLib (use_*) ont disparu de la passerelle', () {
    // Les TDLib récents rejettent use_message_database / use_secret_chats /
    // use_file_database / use_chat_info_database avec « Option not supported »,
    // ce qui bloquait la connexion en silence (aucun octet émis). Le contrat
    // minimal garanti est vérifié sur l'archive source.
    final List<String> deprecated = <String>[
      "'use_file_database'",
      "'use_chat_info_database'",
      "'use_message_database'",
      "'use_secret_chats'",
    ];
    final String source =
        File('lib/features/telegram/data/gateway/tdlib_gateway.dart').readAsStringSync();
    for (final String key in deprecated) {
      expect(source.contains(key), isFalse, reason: '$key est rejeté par les TDLib récents');
    }
  });

  test('démarrage natif : instance après initialisation + lib embarquée nommée', () {
    // Régression « moteur jamais démarré » : l'instance du plugin ne doit
    // JAMAIS être capturée avant l'initialisation (bouchon UnimplementedError),
    // et la bibliothèque Android doit être chargée par son nom.
    final String source =
        File('lib/features/telegram/data/gateway/tdlib_gateway.dart').readAsStringSync();
    expect(source.contains('TdNativePlugin.registerWith()'), isTrue,
        reason: "le vrai initialiseur FFI doit remplacer le bouchon");
    expect(source.contains("'libtdjson.so'"), isTrue,
        reason: 'sur Android, DynamicLibrary.process() ne voit pas les symboles');
    expect(source.contains('final TdPlugin plugin = TdPlugin.instance'), isFalse,
        reason: 'capture avant initialisation = bouchon → client jamais démarré');
  });

  test('la cause réelle du démarrage remonte via requestCode', () {
    // Si le moteur natif échoue, c'est SON message (gateway.lastError) qui
    // doit parvenir à l'écran — pas le générique « client non démarré ».
    final String source =
        File('lib/features/telegram/data/services/local_telegram_service.dart').readAsStringSync();
    expect(source.contains('GatewayError(_gateway.lastError'), isTrue,
        reason: 'la cause du gateway doit être propagée au service');
  });
}
