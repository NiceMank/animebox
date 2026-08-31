/// Stockage de la session Telegram côté application.
///
/// La session (jeton d'accès + profil public) n'est JAMAIS écrite dans les
/// préférences classiques : l'implémentation de production utilise le
/// stockage sécurisé de la plateforme (Keystore Android), et une
/// implémentation en mémoire est fournie pour le web et les tests.
abstract class TelegramSessionService {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clear();

  Future<String?> readUserJson();
  Future<void> writeUserJson(String json);
}
