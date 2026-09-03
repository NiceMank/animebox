/// Typologie des erreurs d'API — chaque erreur donne lieu à un message
/// compréhensible, jamais à un secret ni à une trace technique.
enum ApiErrorKind {
  network,
  timeout,
  server,
  unauthorized,
  invalidCode,
  invalidInput,
  notFound,
  inaccessible,
  forbidden,
  telegram,
  unknown,
}

/// Exception normalisée portée par le service Telegram (messages
/// simulé pour les mêmes codes d'erreur).
class ApiException implements Exception {
  const ApiException(this.kind, {this.message, this.code});

  final ApiErrorKind kind;

  /// Message destiné à l'utilisateur (français, sans donnée sensible).
  final String? message;

  /// Code d'erreur stable du backend (ex. SOURCE_NOT_FOUND).
  final String? code;

  String get displayMessage => message ?? _defaultMessage(kind);

  static String _defaultMessage(ApiErrorKind kind) => switch (kind) {
        ApiErrorKind.network => 'Erreur réseau. Vérifiez votre connexion et réessayez.',
        ApiErrorKind.timeout => 'Le serveur met trop de temps à répondre. Réessayez.',
        ApiErrorKind.server => 'Erreur serveur. Réessayez plus tard.',
        ApiErrorKind.unauthorized => 'Session expirée. Reconnectez-vous.',
        ApiErrorKind.invalidCode => 'Code de connexion incorrect.',
        ApiErrorKind.invalidInput => 'Format de source invalide.',
        ApiErrorKind.notFound => 'Source introuvable sur Telegram.',
        ApiErrorKind.inaccessible => 'Cette source n\'est pas accessible à votre compte.',
        ApiErrorKind.forbidden => 'Compte non autorisé.',
        ApiErrorKind.telegram => 'Erreur Telegram.',
        ApiErrorKind.unknown => 'Une erreur est survenue.',
      };

  @override
  String toString() => 'ApiException($kind, $displayMessage)';
}

/// Convertit une réponse HTTP en [ApiException].
ApiException apiErrorFromResponse(int status, Map<String, dynamic>? body) {
  final Map<String, dynamic>? error = body?['error'] as Map<String, dynamic>?;
  final String? code = error?['code'] as String?;
  final String? message = error?['message'] as String?;

  if (status == 401) return ApiException(ApiErrorKind.unauthorized, code: code);
  if (status == 404) {
    return ApiException(ApiErrorKind.notFound, message: message, code: code);
  }
  if (status == 403) {
    if (code == 'SOURCE_INACCESSIBLE') {
      return ApiException(ApiErrorKind.inaccessible, message: message, code: code);
    }
    return ApiException(ApiErrorKind.forbidden, message: message, code: code);
  }
  if (status == 429) {
    return ApiException(ApiErrorKind.telegram, message: message ?? 'Trop de requêtes. Réessayez plus tard.', code: code);
  }
  if (status >= 500) {
    return ApiException(ApiErrorKind.server, message: message, code: code);
  }
  switch (code) {
    case 'PHONE_CODE_INVALID':
    case 'PHONE_CODE_EXPIRED':
      return ApiException(ApiErrorKind.invalidCode, message: message, code: code);
    case 'INVALID_INPUT':
      return ApiException(ApiErrorKind.invalidInput, message: message, code: code);
    case 'NOT_CONNECTED':
      return ApiException(ApiErrorKind.unauthorized, message: 'Compte Telegram non connecté. Reconnectez-vous.', code: code);
    case 'SOURCE_NOT_FOUND':
      return ApiException(ApiErrorKind.notFound, message: message, code: code);
    case 'SOURCE_INACCESSIBLE':
      return ApiException(ApiErrorKind.inaccessible, message: message, code: code);
    case 'FORBIDDEN':
      return ApiException(ApiErrorKind.forbidden, message: message, code: code);
    case 'TWO_STEP_NEEDED':
    case 'FLOOD':
    case 'TELEGRAM_ERROR':
      return ApiException(ApiErrorKind.telegram, message: message, code: code);
  }
  return ApiException(ApiErrorKind.unknown, message: message, code: code);
}
