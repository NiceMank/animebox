import 'package:animebox/features/settings/services/app_settings.dart';

/// Préférences avec onboarding DÉJÀ validé — utilisé par les tests des
/// écrans historiques qui attendent directement l'accueil (prompt 13 :
/// l'onboarding ne s'affiche qu'au premier lancement réel).
Future<AppSettings> completedOnboardingSettings() async {
  final AppSettings settings = AppSettings();
  await settings.completeOnboarding();
  return settings;
}
