import 'package:flutter/material.dart';

import '../../shared/widgets/empty_state.dart';

/// Écran Téléchargements — placeholder (fonctionnalité prévue plus tard).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text('Téléchargements', style: Theme.of(context).textTheme.headlineMedium),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.download_rounded,
              title: 'Aucun téléchargement',
              message: 'Les épisodes téléchargés apparaîtront ici. Cette fonctionnalité arrive dans une prochaine étape.',
              actionLabel: 'Parcourir la bibliothèque',
              onAction: onBrowse,
            ),
          ),
        ],
      ),
    );
  }
}
