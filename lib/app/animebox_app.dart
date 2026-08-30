import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/anime/data/repositories/anime_repository.dart';
import '../features/anime/data/repositories/mock_anime_repository.dart';
import '../navigation/home_shell.dart';
import 'router.dart';

/// Racine de l'application : thème global et routes.
class AnimeBoxApp extends StatefulWidget {
  const AnimeBoxApp({super.key, this.repository});

  /// Source de données injectée depuis `main()`.
  ///
  /// Un dépôt mock est créé par défaut ; il sera remplacé par un dépôt
  /// adossé à l'API backend dans une étape ultérieure, sans toucher aux
  /// écrans (qui ne dépendent que de l'interface [AnimeRepository]).
  final AnimeRepository? repository;

  @override
  State<AnimeBoxApp> createState() => _AnimeBoxAppState();
}

class _AnimeBoxAppState extends State<AnimeBoxApp> {
  late final AnimeRepository _repository = widget.repository ?? MockAnimeRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimeBox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeShell(repository: _repository),
      onGenerateRoute: AppRouter.onGenerateRoute(_repository),
    );
  }
}
