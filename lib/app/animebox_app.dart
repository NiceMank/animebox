import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/anime/data/repositories/anime_repository.dart';
import '../features/anime/data/repositories/mock_anime_repository.dart';
import '../features/library/services/library_service.dart';
import '../features/telegram/data/services/episode_grouping_service.dart';
import '../features/telegram/data/services/mock_telegram_service.dart';
import '../features/telegram/data/services/telegram_service.dart';
import '../navigation/home_shell.dart';
import 'router.dart';

/// Racine de l'application : thème global, services et routes.
class AnimeBoxApp extends StatefulWidget {
  const AnimeBoxApp({
    super.key,
    this.repository,
    this.telegramService,
    this.groupingService,
    this.libraryService,
  });

  /// Source de données injectée depuis `main()`.
  ///
  /// Les services mock sont créés par défaut ; ils seront remplacés par
  /// leurs versions adossées à l'API/au backend sans toucher aux écrans.
  final AnimeRepository? repository;
  final TelegramService? telegramService;
  final EpisodeGroupingService? groupingService;
  final LibraryService? libraryService;

  @override
  State<AnimeBoxApp> createState() => _AnimeBoxAppState();
}

class _AnimeBoxAppState extends State<AnimeBoxApp> {
  late final AnimeRepository _repository = widget.repository ?? MockAnimeRepository();
  late final TelegramService _telegramService = widget.telegramService ?? MockTelegramService();
  late final EpisodeGroupingService _groupingService = widget.groupingService ?? EpisodeGroupingService();
  late final LibraryService _libraryService =
      widget.libraryService ?? LibraryService(repository: _repository, groupingService: _groupingService);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimeBox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeShell(
        repository: _repository,
        telegramService: _telegramService,
        groupingService: _groupingService,
        libraryService: _libraryService,
      ),
      onGenerateRoute: AppRouter.onGenerateRoute(_repository, _telegramService),
    );
  }
}
