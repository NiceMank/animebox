import 'package:flutter/material.dart';

import '../features/anime/data/repositories/anime_repository.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/services/library_service.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/telegram/data/services/episode_grouping_service.dart';
import '../features/telegram/data/services/telegram_service.dart';
import 'bottom_navigation.dart';
import 'home_tab.dart';

/// Coquille principale : navigation basse persistante + sections.
///
/// Les sections sont conservées en mémoire ([IndexedStack]) : changer d'onglet
/// ne perd ni le défilement ni l'état de la recherche.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    required this.telegramService,
    required this.groupingService,
    required this.libraryService,
  });

  final AnimeRepository repository;
  final TelegramService telegramService;
  final EpisodeGroupingService groupingService;
  final LibraryService libraryService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  HomeTab _tab = HomeTab.home;

  void _select(HomeTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final AnimeRepository repository = widget.repository;
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: [
          HomeScreen(
            repository: repository,
            onSearchTap: () => _select(HomeTab.search),
            onLibraryTap: () => _select(HomeTab.library),
          ),
          SearchScreen(repository: repository),
          LibraryScreen(repository: repository, libraryService: widget.libraryService),
          DownloadsScreen(onBrowse: () => _select(HomeTab.library)),
          ProfileScreen(telegramService: widget.telegramService),
        ],
      ),
      bottomNavigationBar: BottomNavigation(current: _tab, onSelected: _select),
    );
  }
}
