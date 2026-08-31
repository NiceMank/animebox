/// Utilisateur Telegram connecté — uniquement des informations publiques
/// de profil. Aucun secret (jeton, code, hash) n'est porté par ce modèle.
class TelegramUser {
  const TelegramUser({
    required this.firstName,
    this.lastName,
    this.username,
    this.phone,
    this.photoUrl,
  });

  final String firstName;
  final String? lastName;
  final String? username;

  /// Numéro de téléphone — masqué par le backend avant envoi au client.
  final String? phone;
  final String? photoUrl;

  String get fullName => [firstName, lastName].whereType<String>().join(' ').trim();

  String get initials {
    final String first = firstName.isNotEmpty ? firstName[0] : '?';
    final String last = lastName?.isNotEmpty == true ? lastName![0] : '';
    return (first + last).toUpperCase();
  }

  factory TelegramUser.fromJson(Map<String, dynamic> json) => TelegramUser(
        firstName: (json['first_name'] as String?) ?? 'Utilisateur',
        lastName: json['last_name'] as String?,
        username: json['username'] as String?,
        phone: json['phone'] as String?,
        photoUrl: json['photo_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'phone': phone,
        'photo_url': photoUrl,
      };
}
