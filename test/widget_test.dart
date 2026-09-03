import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'onboarding_helper.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/details/anime_details_screen.dart';
import 'package:animebox/features/episodes/episode_list_screen.dart';
import 'package:animebox/features/player/player_screen.dart';
import 'package:animebox/features/quality/quality_select_screen.dart';
import 'package:animebox/shared/widgets/episode_card.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AnimeBoxApp(
    repository: MockAnimeRepository(),
    appSettings: await completedOnboardingSettings(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("l'accueil affiche le héros et les sections principales", (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('ANIMEBOX'), findsOneWidget);
    expect(find.text('SOLO LEVELING'), findsOneWidget); // carte héros
    expect(find.text('Nouveaux épisodes'), findsOneWidget);

    final Finder scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Mes animés'), 250, scrollable: scrollable);
    expect(find.text('Mes animés'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Continuer'), 250, scrollable: scrollable);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('la navigation basse change de section', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Rechercher un animé…'), findsOneWidget);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(find.text('Favoris'), findsOneWidget);

    await tester.tap(find.text('Téléchargements'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun téléchargement'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion Telegram'), findsOneWidget);
  });

  testWidgets('recherche locale : « solo » filtre les résultats et ouvre la fiche', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();

    // Sans saisie : grille « Tendances ».
    expect(find.text('Tendances'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'solo');
    await tester.pumpAndSettle();

    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('One Piece'), findsNothing);

    await tester.tap(find.text('Solo Leveling'));
    await tester.pumpAndSettle();

    expect(find.byType(AnimeDetailsScreen), findsOneWidget);
    expect(find.text('Épisodes'), findsOneWidget);
    expect(find.text('Détails'), findsOneWidget);
  });

  testWidgets('le filtre qualité se reflète dans les résultats', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Filtres'), findsOneWidget);

    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appliquer les filtres'));
    await tester.pumpAndSettle();

    expect(find.text('4 résultat(s)'), findsOneWidget);
    expect(find.text('One Piece'), findsOneWidget);
  });

  testWidgets('favori et suivi se basculent sur la fiche animé', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'demon');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demon Slayer'));
    await tester.pumpAndSettle();

    // Pas encore favori.
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Suivi.
    expect(find.text('Suivre'), findsOneWidget);
    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();
    expect(find.text('Suivi'), findsOneWidget);
  });

  testWidgets('fiche → liste des épisodes : saisons, tri et navigation vers la qualité',
      (WidgetTester tester) async {
    await pumpApp(tester);

    // Accueil → fiche de Solo Leveling (bouton du héros).
    await tester.tap(find.text('Voir la fiche'));
    await tester.pumpAndSettle();
    expect(find.byType(AnimeDetailsScreen), findsOneWidget);

    // Onglet Épisodes → premier épisode (S2 E09) → liste complète.
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeListScreen), findsOneWidget);
    expect(find.text('9 épisodes'), findsOneWidget);

    // Changement de saison.
    await tester.tap(find.text('Saison 1'));
    await tester.pumpAndSettle();
    expect(find.text('12 épisodes'), findsOneWidget);

    // Tri croissant : le premier épisode devient l'épisode 1.
    await tester.tap(find.text('Trier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Numéro croissant'));
    await tester.pumpAndSettle();
    expect(find.text('Épisode 1'), findsOneWidget);

    // Un appui ouvre le choix de qualité.
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(QualitySelectScreen), findsOneWidget);
    expect(find.text('Qualité disponible'), findsOneWidget);
    expect(find.text('Langue / Sous-titres'), findsOneWidget);
    expect(find.text('Lire maintenant'), findsOneWidget);
  });

  testWidgets('sélection qualité et langue, puis lecture (contrôles, prochain épisode)',
      (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Voir la fiche'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();

    // Saison 1, tri croissant → Épisode 1 (qui a un épisode suivant).
    await tester.tap(find.text('Saison 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Numéro croissant'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();

    // Sélection d'une version (la langue est portée par la version réelle).
    await tester.tap(find.text('720p').first);
    await tester.pumpAndSettle();

    // Lecture.
    await tester.ensureVisible(find.text('Lire maintenant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire maintenant'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.textContaining('S01E01'), findsOneWidget);
    expect(find.text('Lecture automatique'), findsOneWidget);

    // Prochain épisode → choix de qualité de l'épisode 2.
    expect(find.text('Prochain épisode'), findsOneWidget);
    await tester.tap(find.text('Épisode 2').first);
    await tester.pumpAndSettle();
    expect(find.byType(QualitySelectScreen), findsOneWidget);
    expect(find.text('Qualité disponible'), findsOneWidget);
  });

  testWidgets("le lecteur affiche le repli honnête en mode démonstration (aucune fausse lecture)",
      (WidgetTester tester) async {
    final MockAnimeRepository repository = MockAnimeRepository();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AnimeBoxApp(repository: repository, appSettings: await completedOnboardingSettings()));
    await tester.pumpAndSettle();

    // Solo Leveling S2 E09 : ouvrir le lecteur depuis le choix de qualité.
    await tester.tap(find.text('Voir la fiche'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EpisodeCard).first);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Lire maintenant'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire maintenant'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerScreen), findsOneWidget);
    // Aucun média réel en mode démonstration : l'écran ne simule JAMAIS
    // une lecture (règle 39) — il propose le repli Telegram réel.
    expect(
      find.textContaining('Lecture directe indisponible'),
      findsWidgets,
    );
    // Le libellé de l'épisode reste affiché (top bar).
    expect(find.textContaining('S02E09'), findsOneWidget);
  });

  test('la progression réelle est persistée : position, durée, statut terminé', () {
    final MockAnimeRepository repository = MockAnimeRepository();
    // Position intermédiaire (comme un vrai lecteur à 12 min 40 / 24 min).
    repository.recordProgress(
      'solo-leveling',
      'sl-s2e9',
      const Duration(minutes: 12, seconds: 40),
      duration: const Duration(minutes: 24),
    );
    expect(repository.episodeProgress('solo-leveling', 'sl-s2e9'),
        const Duration(minutes: 12, seconds: 40));
    expect(repository.episodeCompleted('solo-leveling', 'sl-s2e9'), isFalse);

    // Le lecteur signale la fin : position = durée, statut terminé.
    repository.recordProgress(
      'solo-leveling',
      'sl-s2e9',
      const Duration(minutes: 24),
      duration: const Duration(minutes: 24),
      completed: true,
    );
    expect(repository.episodeCompleted('solo-leveling', 'sl-s2e9'), isTrue);
    // Règle 21 : un épisode terminé reprend du début.
  });
}
