import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animebox/app/animebox_app.dart';
import 'package:animebox/features/anime/data/repositories/mock_anime_repository.dart';
import 'package:animebox/features/details/anime_details_screen.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AnimeBoxApp(repository: MockAnimeRepository()));
    await tester.pumpAndSettle();
  }

  testWidgets("l'accueil affiche le héros et les sections principales", (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('ANIMEBOX'), findsOneWidget);
    expect(find.text('SOLO LEVELING'), findsOneWidget); // carte héros
    expect(find.text('🔥 Nouveaux épisodes'), findsOneWidget);

    final Finder scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('⭐ Mes animés'), 250, scrollable: scrollable);
    expect(find.text('⭐ Mes animés'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('▶ Continuer'), 250, scrollable: scrollable);
    expect(find.text('▶ Continuer'), findsOneWidget);
  });

  testWidgets('la navigation basse change de section', (WidgetTester tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Recherche'));
    await tester.pumpAndSettle();
    expect(find.text('Rechercher un animé…'), findsOneWidget);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(find.text('❤️ Favoris'), findsOneWidget);

    await tester.tap(find.text('Téléchargements'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun téléchargement'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Connecter Telegram'), findsOneWidget);
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

    expect(find.text('3 résultat(s)'), findsOneWidget);
    expect(find.text('One Piece'), findsNothing);
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
}
