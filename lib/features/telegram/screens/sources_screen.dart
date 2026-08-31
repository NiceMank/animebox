import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/telegram_source_card.dart';
import '../data/models/telegram_source.dart';
import '../data/services/telegram_service.dart';
import '../../../app/router.dart';

/// Écran 7 — « Mes sources » : liste et gestion des canaux Telegram.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, required this.service});

  final TelegramService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (BuildContext context, Widget? child) {
        final List<TelegramSource> sources = service.sources;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Mes sources', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          body: sources.isEmpty
              ? _NoSources(onAdd: () => _openAdd(context))
              : CustomScrollView(
                  key: const PageStorageKey<String>('sources-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${sources.length} source${sources.length > 1 ? 's' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Auto-sync toutes les 1 h',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverList.separated(
                        itemCount: sources.length,
                        itemBuilder: (BuildContext context, int index) {
                          final TelegramSource source = sources[index];
                          return TelegramSourceCard(
                            source: source,
                            onTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.sourceDetails,
                              arguments: source.id,
                            ),
                            onSettingsTap: () => Navigator.of(context).pushNamed(
                              AppRoutes.sourceDetails,
                              arguments: source.id,
                            ),
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      sliver: SliverToBoxAdapter(
                        child: PrimaryButton(
                          label: 'Ajouter une source',
                          icon: Icons.add_rounded,
                          onTap: () => _openAdd(context),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _openAdd(BuildContext context) {
    Navigator.of(context).pushNamed(AppRoutes.sourceAdd);
  }
}

/// État vide : aucune source configurée.
class _NoSources extends StatelessWidget {
  const _NoSources({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.send_rounded,
        title: 'Aucune source Telegram',
        message: 'Ajoutez un canal pour commencer à construire votre bibliothèque.',
        actionLabel: 'Ajouter une source',
        onAction: onAdd,
      ),
    );
  }
}
