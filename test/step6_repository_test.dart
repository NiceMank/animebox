import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:animebox/features/anime/data/models/anime.dart';
import 'package:animebox/features/anime/data/models/video_quality.dart';
import 'package:animebox/features/anime/data/repositories/api_anime_repository.dart';
import 'package:animebox/features/anime/data/repositories/catalog_repository.dart';
import 'package:animebox/features/telegram/data/services/secure_session_service.dart';

/// Fixture JSON d'un animé léger (liste).
Map<String, dynamic> _lightAnime(int id, String title, {String status = 'found'}) => {
      'id': id,
      'key': title.toLowerCase().replaceAll(' ', '-'),
      'canonical_title': title,
      'display_title': title,
      'original_title': 'Original $title',
      'alternative_titles': ['Alt $title'],
      'synopsis': 'Synopsis de $title.',
      'genres': ['Action', 'Fantasy'],
      'year': 2024,
      'status': 'completed',
      'season_count': 2,
      'episode_count': 24,
      'rating': 8.4,
      'duration_min': 24,
      'poster_url': '/api/assets/images/poster.jpg',
      'poster_asset': 'poster_solo_leveling',
      'metadata_source': 'local',
      'metadata_status': status,
      'metadata_confidence': 0.98,
      'metadata_updated_at': '2026-09-01T10:00:00+00:00',
      'metadata_candidates': const <Object>[],
      'manually_edited': false,
      'release_year': 2024,
      'created_at': '2026-09-01T09:00:00+00:00',
    };

Map<String, dynamic> _version(int id, String quality, String language, {String? subtitles}) => {
      'id': id,
      'quality': quality,
      'quality_rank': quality == '1080p' ? 4 : 2,
      'resolution': '1920x1080',
      'language': language,
      'subtitles': subtitles,
      'file_name': 'ep.mkv',
      'file_size': 1000000,
      'created_at': '2026-09-01T10:00:00+00:00',
      'source': {
        'channel_id': 'chan',
        'channel_username': 'sourcea',
        'telegram_message_id': id,
        'telegram_message_link': 'https://t.me/sourcea/$id',
      },
    };

Map<String, dynamic> _animeDetail(int id, String title) => {
      ..._lightAnime(id, title),
      'seasons': [
        {
          'id': 1,
          'number': 2,
          'title': null,
          'episode_count': 2,
          'episodes': [
            {
              'id': 101,
              'number': 7,
              'kind': 'regular',
              'title': null,
              'air_date': '2026-08-30T00:00:00+00:00',
              'versions': [_version(1, '1080p', 'french')],
            },
            {
              'id': 102,
              'number': 8,
              'kind': 'regular',
              'title': 'The Final Push',
              'air_date': '2026-09-01T00:00:00+00:00',
              'versions': [
                _version(2, '1080p', 'french'),
                _version(3, '480p', 'japanese', subtitles: 'french'),
              ],
            },
          ],
        },
      ],
    };

MockClient _catalogBackend({
  required int totalAnime,
  required Map<String, dynamic>? Function(String path, Map<String, String>? query) handler,
  List<String>? requestLog,
  List<Map<String, String>>? headerLog,
}) {
  return MockClient((http.Request request) async {
    requestLog?.add('${request.method} ${request.url.path}');
    headerLog?.add(request.headers);
    final String path = request.url.path;
    if (path == '/api/catalog/anime') {
      final int offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      final int limit = int.parse(request.url.queryParameters['limit'] ?? '50');
      final int remaining = (totalAnime - offset).clamp(0, limit);
      return http.Response(
        jsonEncode({
          'anime': [for (int i = 0; i < remaining; i++) _lightAnime(offset + i + 1, 'Anime ${offset + i + 1}')],
          'total': totalAnime,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/catalog/recent') {
      return http.Response(
        jsonEncode({
          'recent': [
            {
              'anime_id': 1,
              'anime_title': 'Anime 1',
              'season_number': 2,
              'number': 8,
              'episode_title': null,
              'versions': [_version(2, '1080p', 'french')],
              'metadata_status': 'found',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final Map<String, dynamic>? body = handler(path, request.url.queryParameters);
    if (body == null) return http.Response('not found', 404);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
}

void main() {
  test('refreshCatalog : pagination + récents + meilleure version', () async {
    final List<String> requests = [];
    final List<Map<String, String>> headers = [];
    final InMemorySessionService session = InMemorySessionService();
    await session.writeToken('jeton-test');
    final ApiAnimeRepository repository = ApiAnimeRepository(
      baseUrl: 'https://api.example.com/',
      session: session,
      client: _catalogBackend(totalAnime: 120, handler: (_, _) => null, requestLog: requests, headerLog: headers),
      pageSize: 50,
    );

    final bool ok = await repository.refreshCatalog();
    expect(ok, isTrue);
    expect(repository.isOffline, isFalse);
    expect(repository.catalogUpdatedAt, isNotNull);
    // 120 animés : 3 pages (50 + 50 + 20).
    expect(requests.where((String r) => r == 'GET /api/catalog/anime').length, 3);
    expect(repository.allAnime.length, 120);
    // Le flux récent alimente l'accueil.
    expect(repository.recentEpisodeIds, ['1']);
    final Anime? first = repository.byId('1');
    expect(first, isNotNull);
    expect(first!.latestEpisode?.number, 8);
    expect(first.latestEpisode?.bestQuality?.quality, VideoQuality.fhd);
    // L'en-tête Bearer porte la session.
    expect(headers.every((Map<String, String> h) => h['Authorization'] == 'Bearer jeton-test'), isTrue);
    // Les URLs d'images relatives sont résolues vers le backend.
    expect(first.posterUrl, 'https://api.example.com/api/assets/images/poster.jpg');
  });

  test('hors-ligne après un premier chargement : le cache répond', () async {
    bool failing = false;
    final InMemorySessionService session = InMemorySessionService();
    final ApiAnimeRepository repository = ApiAnimeRepository(
      baseUrl: 'https://api.example.com',
      session: session,
      client: MockClient((http.Request request) async {
        if (failing) throw Exception('réseau coupé');
        final String path = request.url.path;
        if (path == '/api/catalog/anime') {
          return http.Response(
            jsonEncode({
              'anime': [for (int i = 0; i < 3; i++) _lightAnime(i + 1, 'Anime ${i + 1}')],
              'total': 3,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/catalog/recent') {
          return http.Response(jsonEncode({'recent': const <Object>[]}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (path == '/api/catalog/search') {
          return http.Response(
            jsonEncode({'results': const <Object>[], 'total': 0, 'query': ''}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    expect(await repository.refreshCatalog(), isTrue);
    expect(repository.allAnime.length, 3);

    // Le backend devient injoignable : rien n'est perdu.
    failing = true;
    expect(await repository.refreshCatalog(), isFalse);
    expect(repository.isOffline, isTrue);
    expect(repository.lastError, isNotNull);
    expect(repository.allAnime.length, 3);

    // La recherche bascule sur les dernières données connues, avec une
    // indication claire d'impossibilité d'actualisation.
    final CatalogSearchResult result = await repository.searchCatalog('anime');
    expect(result.status, CatalogSearchStatus.offline);
    expect(result.anime, isNotEmpty);
  });

  test('searchCatalog : trouvée / introuvable / correspondance incertaine', () async {
    final InMemorySessionService session = InMemorySessionService();
    ApiAnimeRepository repository(String status) => ApiAnimeRepository(
          baseUrl: 'https://api.example.com',
          session: session,
          client: MockClient((http.Request request) async {
            final Map<String, dynamic> body = request.url.path == '/api/catalog/search'
                ? {
                    'results': [for (int i = 0; i < (request.url.queryParameters['q'] == 'rien' ? 0 : 2); i++) _lightAnime(i + 1, 'Résultat ${i + 1}', status: status)],
                    'total': 2,
                    'query': request.url.queryParameters['q'],
                  }
                : {};
            return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
          }),
        );

    final CatalogSearchResult found = await repository('found').searchCatalog('Solo');
    expect(found.status, CatalogSearchStatus.found);
    expect(found.anime.length, 2);

    final CatalogSearchResult none = await repository('found').searchCatalog('rien');
    expect(none.status, CatalogSearchStatus.notFound);

    final CatalogSearchResult review = await repository('review_required').searchCatalog('Solo');
    expect(review.status, CatalogSearchStatus.review);
    expect(review.anime.every((Anime a) => a.needsMetadataReview), isTrue);
  });

  test('refreshAnime : fiche complète, versions multiples, titres jamais inventés', () async {
    final InMemorySessionService session = InMemorySessionService();
    final ApiAnimeRepository repository = ApiAnimeRepository(
      baseUrl: 'https://api.example.com',
      session: session,
      client: MockClient((http.Request request) async {
        if (request.url.path == '/api/catalog/anime/1') {
          return http.Response(jsonEncode({'anime': _animeDetail(1, 'Solo Leveling')}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      }),
    );

    final Anime? anime = await repository.refreshAnime('1');
    expect(anime, isNotNull);
    expect(anime!.seasons.length, 1);
    expect(anime.seasons.first.number, 2);
    final Map<int, dynamic> episodes = {for (final e in anime.seasons.first.episodes) e.number: e};
    // Titre officiel appliqué quand fourni, « Épisode N » sinon (jamais inventé).
    expect(episodes[7].title, isNull);
    expect(episodes[7].label, 'Épisode 7');
    expect(episodes[8].title, 'The Final Push');
    // Trois publications regroupées : 1080p VF + 480p VOSTFR, toutes conservées.
    expect(episodes[8].qualities.length, 2);
    expect(episodes[8].bestQuality?.quality, VideoQuality.fhd);
    expect(episodes[8].qualities.any((q) => q.sourceChannelUsername == 'sourcea'), isTrue);
    // La fiche est en cache : byId renvoie le détail complet.
    expect(repository.byId('1')?.seasons.length, 1);
  });

  test('correction manuelle : titre, candidat, ignorer, reclasser', () async {
    final List<String> calls = [];
    final InMemorySessionService session = InMemorySessionService();
    final ApiAnimeRepository repository = ApiAnimeRepository(
      baseUrl: 'https://api.example.com',
      session: session,
      client: MockClient((http.Request request) async {
        calls.add('${request.method} ${request.url.path}');
        final String path = request.url.path;
        if (path == '/api/catalog/anime/1/apply-candidate') {
          return http.Response(
              jsonEncode({'anime': _lightAnime(1, 'Solo Leveling')}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (path == '/api/catalog/anime/1/ignore') {
          return http.Response(
              jsonEncode({'anime': _lightAnime(1, 'Solo Leveling', status: 'ignored')}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (path == '/api/catalog/anime/1') {
          return http.Response(
              jsonEncode({'anime': _lightAnime(1, 'Solo Leveling (2024)')}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (path == '/api/catalog/versions/9/reassign') {
          return http.Response(jsonEncode({'anime': _lightAnime(1, 'Solo Leveling')}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      }),
    );

    expect(await repository.updateDisplayTitle('1', 'Solo Leveling (2024)'), isTrue);
    expect(await repository.applyMetadataCandidate('1', '1', provider: 'local'), isTrue);
    expect(await repository.ignoreMetadataReview('1'), isTrue);
    expect(repository.byId('1')?.metadataStatus.apiValue, 'ignored');
    expect(await repository.reassignVersion('9', seasonNumber: 2, episodeNumber: 8), isTrue);
    expect(calls, contains('PATCH /api/catalog/anime/1'));
    expect(calls, contains('POST /api/catalog/anime/1/apply-candidate'));
    expect(calls, contains('POST /api/catalog/anime/1/ignore'));
    expect(calls, contains('POST /api/catalog/versions/9/reassign'));
  });

  test('recherche locale sur le cache (alias et titres alternatifs)', () async {
    final InMemorySessionService session = InMemorySessionService();
    final ApiAnimeRepository repository = ApiAnimeRepository(
      baseUrl: 'https://api.example.com',
      session: session,
      client: _catalogBackend(totalAnime: 3, handler: (_, _) => null),
    );
    await repository.refreshCatalog();
    // « Original » (titre original) et « alt » (titre alternatif) retrouvent la fiche.
    expect(repository.search('original anime 1'), isNotEmpty);
    expect(repository.search('alt anime 1'), isNotEmpty);
    expect(repository.search('introuvable partout'), isEmpty);
  });
}
