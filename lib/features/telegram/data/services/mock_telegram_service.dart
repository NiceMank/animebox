import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/source_status.dart';
import '../models/sync_history_entry.dart';
import '../models/sync_progress.dart';
import '../models/sync_stats.dart';
import '../models/telegram_source.dart';
import 'telegram_service.dart';

/// Service Telegram MOCKÉ (simulation locale uniquement).
///
/// Aucun appel réseau : les sources, statistiques et synchronisations sont
/// simulées pour préparer l'arrivée du vrai moteur (API Telegram + backend).
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

  /// Statut simulé pour les tests d'erreur (null = comportement normal).
  @override
  SourceStatus? simulatedSourceStatus;

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

  /// Sources de démonstration.
  static List<TelegramSource> get kMockSources => [
        TelegramSource(
          id: 'src-anime-channel',
          name: 'Anime Channel 1',
          username: 'animechannel1',
          lastSync: DateTime.now().subtract(const Duration(minutes: 2)),
          analyzedPosts: 1245,
          detectedAnime: 186,
          detectedEpisodes: 924,
        ),
        TelegramSource(
          id: 'src-anime-vf',
          name: 'Anime VF',
          username: 'animevf',
          lastSync: DateTime.now().subtract(const Duration(minutes: 8)),
          analyzedPosts: 863,
          detectedAnime: 98,
          detectedEpisodes: 431,
        ),
      ];

  @override
  TelegramSource addSource({required String name, required String username}) {
    final TelegramSource source = TelegramSource(
      id: 'src-${_clock().millisecondsSinceEpoch}',
      name: name,
      username: username,
      status: simulatedSourceStatus ?? SourceStatus.active,
      lastSync: null,
    );
    _sources.add(source);
    notifyListeners();
    return source;
  }

  @override
  void removeSource(String sourceId) {
    final int index = _sources.indexWhere((TelegramSource source) => source.id == sourceId);
    if (index == -1) return;
    _sources.removeAt(index);
    notifyListeners();
  }

  @override
  void setSourceEnabled(String sourceId, bool enabled) {
    final int index = _sources.indexWhere((TelegramSource source) => source.id == sourceId);
    if (index == -1) return;
    final TelegramSource source = _sources[index];
    _sources[index] = source.copyWith(
      syncEnabled: enabled,
      status: !enabled ? SourceStatus.disabled : SourceStatus.active,
    );
    notifyListeners();
  }

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
