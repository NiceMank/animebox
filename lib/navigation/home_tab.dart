import 'package:flutter/material.dart';

/// Sections de la navigation basse persistante.
enum HomeTab {
  home('Accueil', Icons.home_rounded, Icons.home_outlined),
  search('Recherche', Icons.search_rounded, Icons.search_outlined),
  library('Bibliothèque', Icons.video_library_rounded, Icons.video_library_outlined),
  downloads('Téléchargements', Icons.download_rounded, Icons.download_outlined),
  profile('Profil', Icons.person_rounded, Icons.person_outlined);

  const HomeTab(this.label, this.icon, this.outlinedIcon);

  final String label;
  final IconData icon;
  final IconData outlinedIcon;
}
