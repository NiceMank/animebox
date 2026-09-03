/// Contenu des 3 pages de l'onboarding (prompt 13 §1).
///
/// Textes officiels de la fonctionnalité — aucune donnée utilisateur,
/// aucun chiffre inventé : ces pages décrivent la VRAIE application.
class OnboardingPageData {
  const OnboardingPageData({
    required this.titleTop,
    required this.titleAccent,
    required this.description,
    this.bullets = const <String>[],
  });

  /// Première partie du titre (blanche).
  final String titleTop;

  /// Partie accentuée (violette) du titre — vide si tout est blanc.
  final String titleAccent;

  /// Description principale (fonctionnement réel de l'application).
  final String description;

  /// Points clés factuels (écran 3 — confidentialité).
  final List<String> bullets;
}

/// Les EXACTEMENT 3 écrans exigés (prompt 13 §1).
const List<OnboardingPageData> kOnboardingPages = <OnboardingPageData>[
  OnboardingPageData(
    titleTop: 'Bienvenue sur ',
    titleAccent: 'AnimeBox',
    description:
        'Retrouvez et organisez les animés de vos propres sources Telegram, réunis dans une seule application.',
  ),
  OnboardingPageData(
    titleTop: 'Tous vos animés ',
    titleAccent: 'au même endroit',
    description:
        'AnimeBox analyse les sources Telegram que vous configurez et organise automatiquement les contenus en animés, saisons et épisodes.',
  ),
  OnboardingPageData(
    titleTop: 'Sécurisé & ',
    titleAccent: '100 % privé',
    description: 'Vos données restent sur votre appareil autant que possible.',
    bullets: <String>[
      'Votre compte Telegram vous appartient — AnimeBox s\'y connecte directement.',
      'Vos sources vous appartiennent — vous choisissez ce qui est synchronisé.',
      'Vos données restent conservées localement, sur cet appareil.',
      'Aucun serveur central n\'est nécessaire pour fonctionner.',
    ],
  ),
];
