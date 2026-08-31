import 'source_status.dart';

/// Une source (canal Telegram) utilisée pour construire la bibliothèque.
///
/// Les champs [telegramChannelId] et [accessHash] sont réservés pour le
/// branchement de l'API Telegram réelle (prochaine étape) : ils ne sont
/// pas utilisés pour l'instant.
class TelegramSource {
  const TelegramSource({
    required this.id,
    required this.name,
    required this.username,
    this.avatarAsset,
    this.status = SourceStatus.active,
    this.lastSync,
    this.analyzedPosts = 0,
    this.detectedAnime = 0,
    this.detectedEpisodes = 0,
    this.syncEnabled = true,
    this.autoSyncInterval = const Duration(hours: 1),
    this.telegramChannelId,
    this.accessHash,
  });

  final String id;
  final String name;
  final String username;

  /// Avatar local (optionnel) ; sinon les initiales sont affichées.
  final String? avatarAsset;
  final SourceStatus status;
  final DateTime? lastSync;
  final int analyzedPosts;
  final int detectedAnime;
  final int detectedEpisodes;
  final bool syncEnabled;
  final Duration autoSyncInterval;

  // Champs réservés pour l'API Telegram réelle (non utilisés).
  final int? telegramChannelId;
  final String? accessHash;

  String get telegramLink => 'https://t.me/$username';

  TelegramSource copyWith({
    String? name,
    SourceStatus? status,
    DateTime? lastSync,
    int? analyzedPosts,
    int? detectedAnime,
    int? detectedEpisodes,
    bool? syncEnabled,
    Duration? autoSyncInterval,
  }) =>
      TelegramSource(
        id: id,
        name: name ?? this.name,
        username: username,
        avatarAsset: avatarAsset,
        status: status ?? this.status,
        lastSync: lastSync ?? this.lastSync,
        analyzedPosts: analyzedPosts ?? this.analyzedPosts,
        detectedAnime: detectedAnime ?? this.detectedAnime,
        detectedEpisodes: detectedEpisodes ?? this.detectedEpisodes,
        syncEnabled: syncEnabled ?? this.syncEnabled,
        autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
        telegramChannelId: telegramChannelId,
        accessHash: accessHash,
      );
}
