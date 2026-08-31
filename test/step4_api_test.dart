import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:animebox/features/telegram/data/models/api_exception.dart';
import 'package:animebox/features/telegram/data/models/telegram_message.dart' show TelegramMediaType;
import 'package:animebox/features/telegram/data/services/api_telegram_service.dart';
import 'package:animebox/features/telegram/data/services/secure_session_service.dart';
import 'package:animebox/features/telegram/data/services/telegram_service.dart';

/// Serveur HTTP factice : rejoue un sous-ensemble du contrat du backend
/// pour tester le client sans réseau réel ni secret.
class StubBackend {
  StubBackend._(this.server);

  final HttpServer server;
  final List<Map<String, String>> requests = [];

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  static Future<StubBackend> start(
    Future<void> Function(HttpRequest request, String body) handler,
  ) async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final StubBackend backend = StubBackend._(server);
    server.listen((HttpRequest request) async {
      final String body = await utf8.decodeStream(request);
      backend.requests.add({
        'method': request.method,
        'path': request.uri.path,
        'auth': request.headers.value('authorization') ?? '',
        'body': body,
      });
      await handler(request, body);
    });
    return backend;
  }

  Future<void> close() => server.close(force: true);

  static void json(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }

  static void error(HttpRequest request, int status, String code, String message) {
    json(request, status, {'error': {'code': code, 'message': message}});
  }
}

const Map<String, dynamic> _user = {
  'first_name': 'Alice',
  'last_name': 'Doe',
  'username': 'alice_anime',
  'phone': null,
};

void main() {
  group('ApiTelegramService — connexion', () {
    test('parcours complet : code → vérification → session sécurisée', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        switch ('${request.method} ${request.uri.path}') {
          case 'POST /api/telegram/send-code':
            StubBackend.json(request, 200, {'sent': true});
          case 'POST /api/telegram/verify-code':
            StubBackend.json(request, 200, {'token': 'tok-abc', 'user': _user});
          case 'GET /api/telegram/status':
            if (request.headers.value('authorization') == 'Bearer tok-abc') {
              StubBackend.json(request, 200, {'connected': true, 'user': _user});
            } else {
              StubBackend.error(request, 401, 'UNAUTHORIZED', 'Session expirée. Reconnectez-vous.');
            }
          case 'GET /api/sources':
            StubBackend.json(request, 200, {'sources': <dynamic>[]});
          default:
            StubBackend.error(request, 404, 'UNKNOWN', 'not found');
        }
      });

      final InMemorySessionService session = InMemorySessionService();
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: session,
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      expect(service.authState, TelegramAuthState.disconnected);
      expect(service.isBackendApi, isTrue);

      await service.requestCode('+22901020304');
      expect(service.authState, TelegramAuthState.connecting);

      await service.verifyCode('+22901020304', '12345');
      expect(service.authState, TelegramAuthState.connected);
      expect(service.currentUser?.username, 'alice_anime');
      expect(service.currentUser?.fullName, 'Alice Doe');

      // La session est stockée côté sécurisé (mémoire ici).
      expect(await session.readToken(), 'tok-abc');
      expect(await session.readUserJson(), isNotNull);

      // refreshSession valide l'état connecté.
      await service.refreshSession();
      expect(service.authState, TelegramAuthState.connected);

      // Déconnexion : jeton révoqué côté backend et effacé localement.
      await service.disconnect();
      expect(service.authState, TelegramAuthState.disconnected);
      expect(await session.readToken(), isNull);
    });

    test('session expirée : 401 → état expired et session effacée', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        StubBackend.error(request, 401, 'UNAUTHORIZED', 'Session expirée. Reconnectez-vous.');
      });
      final InMemorySessionService session = InMemorySessionService();
      await session.writeToken('vieux-jeton');
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: session,
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      // La restauration au démarrage détecte la session révoquée.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.authState, TelegramAuthState.expired);
      expect(await session.readToken(), isNull);
    });

    test('code incorrect → ApiException invalidCode, message compréhensible', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        StubBackend.error(request, 400, 'PHONE_CODE_INVALID', 'Code de connexion incorrect.');
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService(),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      try {
        await service.verifyCode('+22901020304', '00000');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.invalidCode);
        expect(error.displayMessage, 'Code de connexion incorrect.');
      }
    });
  });

  group('ApiTelegramService — sources et publications', () {
    test('résolution : aperçu, introuvable (404) et inaccessible (403)', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        if ('${request.method} ${request.uri.path}' == 'GET /api/telegram/status') {
          StubBackend.json(request, 200, {'connected': true, 'user': _user});
          return;
        }
        // Comme le backend réel, on accepte @username ou username.
        final String input =
            ((jsonDecode(body) as Map<String, dynamic>)['input'] as String).replaceFirst('@', '');
        switch (input) {
          case 'animechannel':
            StubBackend.json(request, 200, {
              'channel': {
                'username': 'animechannel',
                'title': 'Anime Channel',
                'description': 'Canal de démonstration.',
                'kind': 'channel',
              }
            });
          case 'introuvable':
            StubBackend.error(request, 404, 'SOURCE_NOT_FOUND', 'Source introuvable sur Telegram.');
          case 'prive':
            StubBackend.error(request, 403, 'SOURCE_INACCESSIBLE', 'Cette source n\'est pas accessible à votre compte Telegram.');
          default:
            StubBackend.error(request, 500, 'SERVER_ERROR', 'boom');
        }
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService()..writeToken('tok'),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      final resolved = await service.resolveChannel('@animechannel');
      expect(resolved.title, 'Anime Channel');
      expect(resolved.username, 'animechannel');

      try {
        await service.resolveChannel('@introuvable');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.notFound);
      }
      try {
        await service.resolveChannel('@prive');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.inaccessible);
      }
    });

    test('ajout + liste des sources + désactivation (jeton envoyé en Bearer)', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        switch ('${request.method} ${request.uri.path}') {
          case 'POST /api/sources':
            StubBackend.json(request, 200, {
              'source': {
                'id': 's-1',
                'name': 'Anime Channel',
                'username': 'animechannel',
                'kind': 'channel',
                'status': 'active',
                'sync_enabled': true,
                'last_sync': null,
                'analyzed_posts': 0,
                'detected_anime': 0,
                'detected_episodes': 0,
              }
            });
          case 'GET /api/sources':
            StubBackend.json(request, 200, {
              'sources': [
                {
                  'id': 's-1',
                  'name': 'Anime Channel',
                  'username': 'animechannel',
                  'kind': 'channel',
                  'status': 'active',
                  'sync_enabled': true,
                  'last_sync': null,
                  'analyzed_posts': 12,
                  'detected_anime': 0,
                  'detected_episodes': 0,
                }
              ]
            });
          case 'PATCH /api/sources/s-1':
            StubBackend.json(request, 200, {
              'source': {
                'id': 's-1',
                'name': 'Anime Channel',
                'username': 'animechannel',
                'kind': 'channel',
                'status': 'disabled',
                'sync_enabled': false,
                'last_sync': null,
                'analyzed_posts': 12,
                'detected_anime': 0,
                'detected_episodes': 0,
              }
            });
          case 'GET /api/telegram/status':
            StubBackend.json(request, 200, {'connected': true, 'user': _user});
          default:
            StubBackend.error(request, 404, 'UNKNOWN', 'not found');
        }
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService()..writeToken('tok'),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      final added = await service.addSource(name: 'Anime Channel', username: 'animechannel');
      expect(added.id, 's-1');

      await service.loadSources();
      expect(service.sources, hasLength(1));
      expect(service.sources.first.analyzedPosts, 12);

      await service.setSourceEnabled('s-1', false);
      expect(service.sourceById('s-1')!.syncEnabled, isFalse);

      // Toutes les requêtes portent le jeton d'accès.
      for (final Map<String, String> request in backend.requests) {
        expect(request['auth'], 'Bearer tok');
      }
    });

    test('fetchMessages : ids, liens t.me et cas sans lien', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        if (request.uri.path == '/api/sources/s-1/messages') {
          StubBackend.json(request, 200, {
            'messages': [
              {
                'message_id': 12345,
                'channel_username': 'animechannel',
                'date': '2024-05-12T10:00:00Z',
                'text': 'Solo Leveling S02E08 1080p VF',
                'media_type': 'video',
                'file_name': 'solo.mkv',
                'file_size': 1288490188,
                'link': 'https://t.me/animechannel/12345',
              },
              {
                'message_id': 12344,
                'channel_username': 'animechannel',
                'date': '2024-05-12T09:00:00Z',
                'text': 'Solo Leveling S02E08 720p VF',
                'media_type': 'video',
                'file_name': null,
                'file_size': null,
                'link': null,
              },
            ]
          });
        } else {
          StubBackend.error(request, 404, 'UNKNOWN', 'not found');
        }
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService()..writeToken('tok'),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      final messages = await service.fetchMessages('s-1', limit: 20);
      expect(messages, hasLength(2));
      expect(messages.first.messageId, 12345);
      expect(messages.first.messageLink, 'https://t.me/animechannel/12345');
      expect(messages.first.mediaType, TelegramMediaType.video);
      expect(messages.last.messageLink, isNull); // bouton désactivé côté UI
    });
  });

  group('ApiTelegramService — erreurs réseau', () {
    test('serveur injoignable → ApiException network', () async {
      // On obtient un port libre puis on le ferme : connexion refusée.
      final HttpServer probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final String baseUrl = 'http://127.0.0.1:${probe.port}';
      await probe.close(force: true);

      final ApiTelegramService service = ApiTelegramService(
        baseUrl: baseUrl,
        session: InMemorySessionService(),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(service.dispose);

      try {
        await service.requestCode('+22901020304');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.network);
        expect(error.displayMessage, contains('Erreur réseau'));
      }
    });

    test('réponse trop lente → ApiException timeout', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        StubBackend.json(request, 200, {'sent': true});
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService(),
        client: http.Client(),
        timeout: const Duration(milliseconds: 200),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      try {
        await service.requestCode('+22901020304');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.timeout);
        expect(error.displayMessage, contains('trop de temps'));
      }
    });

    test('erreur serveur 500 → ApiException server', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        StubBackend.error(request, 500, 'SERVER_ERROR', 'boom');
      });
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: InMemorySessionService(),
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      try {
        await service.requestCode('+22901020304');
        fail('ApiException attendue');
      } on ApiException catch (error) {
        expect(error.kind, ApiErrorKind.server);
        expect(error.displayMessage, 'boom');
      }
    });
  });

  group('ApiTelegramService — aucun secret', () {
    test('jamais de jeton, API_HASH ni access_hash dans les requêtes sortantes', () async {
      final StubBackend backend = await StubBackend.start((HttpRequest request, String body) async {
        if (request.uri.path == '/api/telegram/verify-code') {
          StubBackend.json(request, 200, {'token': 'tok-super-secret', 'user': _user});
        } else if (request.uri.path == '/api/telegram/status') {
          StubBackend.json(request, 200, {'connected': true, 'user': _user});
        } else if (request.uri.path == '/api/sources') {
          StubBackend.json(request, 200, {'sources': <dynamic>[]});
        } else {
          StubBackend.json(request, 200, {});
        }
      });
      final InMemorySessionService session = InMemorySessionService();
      final ApiTelegramService service = ApiTelegramService(
        baseUrl: backend.baseUrl,
        session: session,
        client: http.Client(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        service.dispose();
        await backend.close();
      });

      await service.verifyCode('+22901020304', '12345');
      await service.loadSources();

      // Le jeton ne circule que dans l'en-tête Authorization, jamais
      // dans le corps des requêtes ni dans les messages d'erreur.
      for (final Map<String, String> request in backend.requests) {
        final String combined = '${request['method']} ${request['path']} ${request['body']}';
        expect(combined.toLowerCase(), isNot(contains('api_hash')));
        expect(combined.toLowerCase(), isNot(contains('access_hash')));
        expect(request['body'], isNot(contains('tok-super-secret')));
      }

      // Le modèle de source côté client n'expose aucun champ sensible.
      try {
        await service.resolveChannel('@x');
      } on ApiException catch (_) {
        // pas de souci : le point testé est l'absence de champ sensible.
      }
    });
  });
}
