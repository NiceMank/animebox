import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../gateway/telegram_gateway.dart';
import '../models/api_exception.dart';
import '../models/resolved_channel.dart';
import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_input.dart';
import '../models/telegram_message.dart';
import '../models/telegram_source.dart';
import '../models/telegram_user.dart';
import 'telegram_service.dart';

/// Service Telegram MOCKÉ (simulation locale uniquement).
///
/// Reproduit le contrat complet du service réel (connexion, résolution de
/// canaux, publications, synchronisation) avec des données déterministes.
/// Aucun appel réseau, aucun secret.
class MockTelegramService extends ChangeNotifier implements TelegramService {
  MockTelegramService({List<TelegramSource>? seedSources, SyncStats? seedStats, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _sources = List.of(seedSources ?? kMockSources),
        _stats = seedStats ?? const SyncStats(
          analyzedPosts: 12458,
          detectedAnime: 342,
          detectedEpisodes: 4821,
          duplicatesGrouped: 1273,
          newEpisodes: 18,
        );

  final DateTime Function() _clock;
  final List<TelegramSource> _sources;
  SyncStats _stats;
  final List<SyncHistoryEntry> _history = [
    SyncHistoryEntry(id: 'h-3', date: DateTime.now().subtract(const Duration(minutes: 2)), success: true, analyzedPosts: 12458, newEpisodes: 18),
    SyncHistoryEntry(id: 'h-2', date: DateTime.now().subtract(const Duration(hours: 1)), success: true, analyzedPosts: 12310, newEpisodes: 3),
    SyncHistoryEntry(id: 'h-1', date: DateTime.now().subtract(const Duration(days: 1, hours: 3)), success: true, analyzedPosts: 12004, newEpisodes: 42),
  ];

  final Random _random = Random(7);
  bool _isSyncing = false;
  SyncProgress? _progress;

  // -------------------------------------------------------------------
  // Authentification (simulation)
  // -------------------------------------------------------------------

  TelegramAuthState _authState = TelegramAuthState.connected;
  TelegramUser? _currentUser = const TelegramUser(
    firstName: 'Démo',
    lastName: 'AnimeBox',
    username: 'animebox_demo',
  );
  String? _authError;

  @override
  bool get isBackendApi => false;

  @override
  bool get isRealTelegram => false;

  @override
  TelegramGateway? get mediaGateway => null;

  @override
  String? get apiBaseUrl => null;

  @override
  TelegramAuthState get authState => _authState;

  @override
  TelegramUser? get currentUser => _currentUser;

  @override
  String? get authError => _authError;

  @override
  Future<void> requestCode(String phone) async {
    // Simulation : Telegram envoie le code immédiatement.
    _authState = TelegramAuthState.codeRequired;
    _authError = null;
    notifyListeners();
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    if (code.trim().length != 5) {
      throw const ApiException(ApiErrorKind.invalidCode);
    }
    _currentUser = const TelegramUser(firstName: 'Démo', lastName: 'AnimeBox', username: 'animebox_demo');
    _authState = TelegramAuthState.connected;
    _authError = null;
    notifyListeners();
  }

  @override
  Future<void> requestPassword(String password) async {
    // Simulation : le mot de passe 2FA (non vide) est accepté.
    if (password.isEmpty) {
      throw const ApiException(ApiErrorKind.telegram, message: 'Mot de passe 2FA incorrect.');
    }
    _authState = TelegramAuthState.connected;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _currentUser = null;
    _authState = TelegramAuthState.disconnected;
    notifyListeners();
  }

  @override
  Future<void> refreshSession() async {
    // Simulation : la session reste valide.
  }

  @override
  SourceStatus? simulatedSourceStatus;

  /// Sources de démonstration.
  static List<TelegramSource> get kMockSources => [
        TelegramSource(
          id: 'src-anime-channel',
          name: 'Anime Channel 1',
          username: 'animechannel1',
          avatarAsset: 'assets/img/src_avatar1.png',
          lastSync: DateTime.now().subtract(const Duration(minutes: 2)),
          analyzedPosts: 1245,
          detectedAnime: 186,
          detectedEpisodes: 924,
        ),
        TelegramSource(
          id: 'src-anime-vf',
          name: 'Anime VF',
          username: 'animevf',
          avatarAsset: 'assets/img/src_avatar2.png',
          lastSync: DateTime.now().subtract(const Duration(minutes: 8)),
          analyzedPosts: 863,
          detectedAnime: 98,
          detectedEpisodes: 431,
          // Canal privé : les liens des publications utilisent t.me/c/….
          telegramChannelId: 2000000123,
        ),
      ];

  @override
  List<TelegramSource> get sources => List.unmodifiable(_sources);

  @override
  TelegramSource? sourceById(String id) {
    for (final TelegramSource source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<void> loadSources() async {}

  @override
  Future<ResolvedChannel> resolveChannel(String input) async {
    final String username = TelegramInputParser.parse(input);
    if (username == 'introuvable') {
      throw const ApiException(ApiErrorKind.notFound);
    }
    if (username == 'prive') {
      throw const ApiException(ApiErrorKind.inaccessible);
    }
    return ResolvedChannel(
      username: username,
      title: TelegramInputParser.titleFromUsername(username),
      description: 'Canal de démonstration AnimeBox (@$username).',
    );
  }

  @override
  Future<TelegramSource> addSource({
    required String name,
    required String username,
    String? channelId,
    String kind = 'channel',
    String? inviteHash,
  }) async {
    final TelegramSource source = TelegramSource(
      id: 'src-${_clock().millisecondsSinceEpoch}',
      name: name,
      username: username,
      avatarAsset: 'assets/img/src_avatar3.png',
      status: simulatedSourceStatus ?? SourceStatus.active,
      lastSync: null,
    );
    _sources.add(source);
    notifyListeners();
    return source;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    final int index = _sources.indexWhere((TelegramSource source) => source.id == sourceId);
    if (index == -1) return;
    _sources.removeAt(index);
    notifyListeners();
  }

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final int index = _sources.indexWhere((TelegramSource source) => source.id == sourceId);
    if (index == -1) return;
    final TelegramSource source = _sources[index];
    _sources[index] = source.copyWith(
      syncEnabled: enabled,
      status: !enabled ? SourceStatus.disabled : SourceStatus.active,
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Publications simulées
  // -------------------------------------------------------------------

  static const List<(String, String, int, String)> _captions = [
    ('Solo Leveling S02E08 1080p VF', 'video', 1288490188, 'solo-leveling-s02e08-1080p.mkv'),
    ('Solo Leveling S02E08 720p VF', 'video', 697932185, 'solo-leveling-s02e08-720p.mkv'),
    ('Solo Leveling S02E08 480p VOSTFR', 'video', 375809638, 'solo-leveling-s02e08-480p.mkv'),
    ('One Piece 1124 720p VOSTFR', 'video', 644245094, 'one-piece-1124-720p.mkv'),
    ('Jujutsu Kaisen S02E17 1080p VF', 'video', 1180591620, 'jujutsu-kaisen-s02e17.mkv'),
    ('Demon Slayer S04E07 1080p VOSTFR', 'video', 1288490188, 'demon-slayer-s04e07.mkv'),
    ('Solo Leveling S02E09 1080p VF', 'video', 1288490188, 'solo-leveling-s02e09.mkv'),
    ('One Piece 1125 1080p VOSTFR', 'document', 1073741824, 'one-piece-1125.mkv'),
  ];

  @override
  Future<List<TelegramMessage>> fetchMessages(String sourceId, {int limit = 20}) async {
    final TelegramSource? source = sourceById(sourceId);
    if (source == null) {
      throw const ApiException(ApiErrorKind.notFound, message: 'Source introuvable.');
    }
    final DateTime now = _clock();
    return [
      for (int index = 0; index < min(limit, _captions.length); index++)
        TelegramMessage(
          messageId: 12345 - index,
          channelUsername: source.username,
          channelId: source.telegramChannelId,
          date: now.subtract(Duration(hours: index * 5)),
          text: _captions[index].$1,
          mediaType: TelegramMediaType.fromApi(_captions[index].$2),
          fileSize: _captions[index].$3,
          fileName: _captions[index].$4,
          // Le dernier message simulé n'a pas de lien : le bouton doit
          // être proprement désactivé (on n'invente jamais de lien).
          messageLink: index < _captions.length - 1
              ? (source.telegramChannelId != null
                  ? 'https://t.me/c/${source.telegramChannelId}/${12345 - index}'
                  : 'https://t.me/${source.username}/${12345 - index}')
              : null,
        ),
    ];
  }

  // -------------------------------------------------------------------
  // Synchronisation simulée
  // -------------------------------------------------------------------

  @override
  SyncStats get stats => _stats;

  @override
  bool get isSyncing => _isSyncing;

  @override
  SyncProgress? get currentProgress => _progress;

  @override
  List<SyncHistoryEntry> get history {
    final List<SyncHistoryEntry> copy = List.of(_history)
      ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(copy);
  }

  @override
  Future<void> loadStats() async {}

  @override
  Future<void> syncSource({String? sourceId}) async {
    if (_isSyncing) return;

    if (sourceId != null) {
      final int index = _sources.indexWhere((TelegramSource source) => source.id == sourceId);
      if (index == -1) return;
      _sources[index] = _sources[index].copyWith(status: SourceStatus.syncing);
    } else {
      for (int i = 0; i < _sources.length; i++) {
        if (_sources[i].syncEnabled) {
          _sources[i] = _sources[i].copyWith(status: SourceStatus.syncing);
        }
      }
    }

    _isSyncing = true;
    _progress = const SyncProgress(fraction: 0.04, phase: 'Analyzing publications...', analyzedPosts: 0, totalPosts: 12458);
    notifyListeners();

    await _runSimulation(sourceId: sourceId);

    if (sourceId != null) {
      final TelegramSource? current = sourceById(sourceId);
      if (current != null) {
        final int index = _sources.indexOf(current);
        _sources[index] = current.copyWith(status: SourceStatus.active);
      }
    }
    _isSyncing = false;
    _progress = null;
    notifyListeners();
  }

  @override
  Future<void> syncAll() => syncSource();

  @override
  Future<void> cancelSync() async {
    _isSyncing = false;
    _progress = null;
    notifyListeners();
  }

  /// Simule une analyse progressive des publications.
  Future<void> _runSimulation({String? sourceId}) async {
    const int totalPosts = 12458;
    const Duration tickInterval = Duration(milliseconds: 140);
    int analyzed = 0;
    double fraction = 0.04;

    await Future<void>.delayed(tickInterval);

    final int newEpisodes = _random.nextInt(24);
    _stats = _stats.copyWith(
      analyzedPosts: _stats.analyzedPosts + 3,
      detectedAnime: _stats.detectedAnime + 1,
      detectedEpisodes: _stats.detectedEpisodes + newEpisodes,
      duplicatesGrouped: _stats.duplicatesGrouped + 2,
      newEpisodes: newEpisodes,
      lastSync: _clock(),
    );

    if (sourceId != null) {
      final TelegramSource? current = sourceById(sourceId);
      if (current != null) {
        final int index = _sources.indexOf(current);
        _sources[index] = current.copyWith(
          lastSync: _clock(),
          analyzedPosts: current.analyzedPosts + 3,
          detectedEpisodes: current.detectedEpisodes + newEpisodes,
        );
      }
    }

    while (analyzed < totalPosts) {
      analyzed = min(totalPosts, analyzed + 700 + _random.nextInt(400));
      fraction = min(0.92, 0.04 + 0.88 * (analyzed / totalPosts));
      _progress = SyncProgress(fraction: fraction, phase: 'Analyzing publications...', analyzedPosts: analyzed, totalPosts: totalPosts);
      notifyListeners();
      await Future<void>.delayed(tickInterval);
    }

    _progress = SyncProgress(fraction: 0.96, phase: 'Regroupement des doublons...', analyzedPosts: totalPosts, totalPosts: totalPosts);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    _progress = const SyncProgress(fraction: 1.0, phase: 'Analyse terminée', analyzedPosts: totalPosts, totalPosts: totalPosts);
    notifyListeners();

    _history.insert(0, SyncHistoryEntry(
      id: 'h-${_clock().millisecondsSinceEpoch}',
      date: _clock(),
      success: true,
      analyzedPosts: totalPosts,
      newEpisodes: newEpisodes,
    ));
  }
}
