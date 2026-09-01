/// Type de source Telegram.
enum ChannelKind {
  channel('Canal'),
  group('Groupe'),
  private('Source privée');

  const ChannelKind(this.label);
  final String label;

  static ChannelKind fromApi(String? value) => switch (value) {
        'group' => ChannelKind.group,
        'private' => ChannelKind.private,
        _ => ChannelKind.channel,
      };
}

/// Aperçu d'un canal résolu par le backend (avant son ajout comme source).
///
/// Ne contient que des informations publiques : l'access_hash n'est
/// jamais transmis au client mobile.
class ResolvedChannel {
  const ResolvedChannel({
    required this.username,
    required this.title,
    this.description,
    this.photoUrl,
    this.channelId,
    this.kind = ChannelKind.channel,
    this.memberCount,
    this.inviteHash,
  });

  final String username;
  final String title;
  final String? description;
  final String? photoUrl;
  final int? channelId;
  final ChannelKind kind;

  /// Nombre d'abonnés si accessible (aperçu avant ajout).
  final int? memberCount;

  /// Hash du lien d'invitation (canal privé), si résolu via t.me/+hash.
  final String? inviteHash;

  factory ResolvedChannel.fromJson(Map<String, dynamic> json) => ResolvedChannel(
        username: (json['username'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        description: json['description'] as String?,
        photoUrl: json['photo_url'] as String?,
        channelId: (json['channel_id'] as num?)?.toInt(),
        kind: ChannelKind.fromApi(json['kind'] as String?),
        memberCount: (json['member_count'] as num?)?.toInt(),
      );
}
