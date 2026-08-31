import 'source_status.dart';

/// Une source (canal Telegram) utilisée pour construire la bibliothèque.
///
/// Les données sont fournies par le backend : l'access_hash n'est JAMAIS
/// transmis au client mobile. `telegramChannelId` est conservé car il est
/// nécessaire pour construire les liens des publications (t.me/c/…).
class TelegramSource {
  const TelegramSource({
    required this.id,
    required this.name,
    required this.username,
    this.avatarAsset,
    this.photoUrl,
    this.description,
    this.kind = 'channel',
    this.status = SourceStatus.active,
    this.lastSync,
    this.analyzedPosts = 0,
    this.detectedAnime = 0,
    this.detectedEpisodes = 0,
    this.syncEnabled = true,
    this.autoSyncInterval = const Duration(hours: 1),
    this.telegramChannelId,
  });

  final String id;
  final String name;
  final String username;

  /// Avatar local (démo) — prioritaire si présent.
  final String? avatarAsset;

  /// Photo de profil servie par le backend (mode réel).
  final String? photoUrl;
  final String? description;

  /// `channel` | `group` | `private`.
  final String kind;
  final SourceStatus status;
  final DateTime? lastSync;
  final int analyzedPosts;
  final int detectedAnime;
  final int detectedEpisodes;
  final bool syncEnabled;
  final Duration autoSyncInterval;
  final int? telegramChannelId;

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
        photoUrl: photoUrl,
        description: description,
        kind: kind,
        status: status ?? this.status,
        lastSync: lastSync ?? this.lastSync,
        analyzedPosts: analyzedPosts ?? this.analyzedPosts,
        detectedAnime: detectedAnime ?? this.detectedAnime,
        detectedEpisodes: detectedEpisodes ?? this.detectedEpisodes,
        syncEnabled: syncEnabled ?? this.syncEnabled,
        autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
        telegramChannelId: telegramChannelId,
      );

  factory TelegramSource.fromJson(Map<String, dynamic> json) => TelegramSource(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        photoUrl: json['photo_url'] as String?,
        description: json['description'] as String?,
        kind: (json['kind'] as String?) ?? 'channel',
        status: switch (json['status'] as String?) {
          'disabled' => SourceStatus.disabled,
          'error' => SourceStatus.error,
          'syncing' => SourceStatus.syncing,
          _ => SourceStatus.active,
        },
        lastSync: DateTime.tryParse((json['last_sync'] as String?) ?? ''),
        analyzedPosts: (json['analyzed_posts'] as num?)?.toInt() ?? 0,
        detectedAnime: (json['detected_anime'] as num?)?.toInt() ?? 0,
        detectedEpisodes: (json['detected_episodes'] as num?)?.toInt() ?? 0,
        syncEnabled: (json['sync_enabled'] as bool?) ?? true,
        telegramChannelId: (json['channel_id'] as num?)?.toInt(),
      );
}
