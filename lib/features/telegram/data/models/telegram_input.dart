import 'api_exception.dart';

/// Analyse et valide la saisie d'une source Telegram.
///
/// Formats acceptés : `@username`, `https://t.me/username`, `username`.
/// Aucune vérification réseau ici : la résolution réelle est déléguée au
/// backend (service Telegram).
abstract final class TelegramInputParser {
  TelegramInputParser._();

  /// Retourne le username normalisé ou lève une [ApiException]
  /// (invalidInput) avec le message attendu.
  static String parse(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ApiException(ApiErrorKind.invalidInput, message: 'Veuillez saisir une source.');
    }

    String candidate = trimmed;
    if (candidate.startsWith('@')) candidate = candidate.substring(1);
    final Uri? uri = Uri.tryParse(candidate);
    if (uri != null && uri.host.isNotEmpty && candidate.startsWith('http')) {
      if (uri.host != 't.me' || uri.pathSegments.isEmpty) {
        throw const ApiException(ApiErrorKind.invalidInput, message: 'Format de source invalide.');
      }
      candidate = uri.pathSegments.first;
    } else if (candidate.contains('/')) {
      throw const ApiException(ApiErrorKind.invalidInput, message: 'Format de source invalide.');
    }

    final RegExp valid = RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,31}$');
    if (!valid.hasMatch(candidate)) {
      throw const ApiException(ApiErrorKind.invalidInput, message: 'Format de source invalide.');
    }
    return candidate;
  }

  /// Nom lisible proposé à partir d'un username (« anime_channel » →
  /// « Anime channel »).
  static String titleFromUsername(String username) => username
      .replaceAll('_', ' ')
      .split(' ')
      .map((String word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
