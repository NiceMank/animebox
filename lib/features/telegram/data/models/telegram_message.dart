/// Type de média d'une publication Telegram.
enum TelegramMediaType {
  video('Vidéo'),
  image('Image'),
  document('Document'),
  text('Texte');

  const TelegramMediaType(this.label);
  final String label;

  static TelegramMediaType fromApi(String? value) => switch (value) {
        'video' => TelegramMediaType.video,
        'image' => TelegramMediaType.image,
        'document' => TelegramMediaType.document,
        _ => TelegramMediaType.text,
      };
}

/// Une publication brute récupérée depuis une source Telegram.
///
/// À ce stade, seules les informations nécessaires pour vérifier la
/// communication sont remontées (id, date, texte, média, fichier, lien).
/// L'analyse intelligente (titre, saison, épisode, qualité) viendra dans
/// une étape ultérieure.
class TelegramMessage {
  const TelegramMessage({
    required this.messageId,
    required this.channelUsername,
    this.channelId,
    required this.date,
    this.text,
    required this.mediaType,
    this.fileName,
    this.fileSize,
    this.messageLink,
  });

  final int messageId;
  final String channelUsername;

  /// Identifiant numérique du canal (nécessaire pour construire les liens
  /// des canaux privés : t.me/c/{channelId}/{messageId}).
  final int? channelId;
  final DateTime date;
  final String? text;
  final TelegramMediaType mediaType;
  final String? fileName;
  final int? fileSize;

  /// Lien t.me vers la publication — null quand Telegram ne permet pas
  /// de construire un lien (le bouton « Ouvrir dans Telegram » est alors
  /// proprement désactivé, on n'invente jamais de lien).
  final String? messageLink;

  factory TelegramMessage.fromJson(Map<String, dynamic> json) => TelegramMessage(
        messageId: (json['message_id'] as num).toInt(),
        channelUsername: (json['channel_username'] as String?) ?? '',
        channelId: (json['channel_id'] as num?)?.toInt(),
        date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
        text: json['text'] as String?,
        mediaType: TelegramMediaType.fromApi(json['media_type'] as String?),
        fileName: json['file_name'] as String?,
        fileSize: (json['file_size'] as num?)?.toInt(),
        messageLink: json['link'] as String?,
      );
}
