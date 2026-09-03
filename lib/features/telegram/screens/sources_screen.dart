import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/telegram_source_card.dart';
import '../data/models/api_exception.dart';
import '../data/models/telegram_source.dart';
import '../data/services/telegram_service.dart';
import '../../../app/router.dart';

/// Écran 7 — « Mes sources » : liste et gestion des canaux Telegram.
///
/// Les données proviennent du backend ([TelegramService.loadSources]) ;
/// le service simulé fournit ses données locales. États gérés : chargement
/// (skeleton), erreur (réessayer), liste vide, bannière « non connecté ».
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, required this.service});

  final TelegramService service;

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.loadSources();
      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.displayMessage;
      });
    }
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).pushNamed(AppRoutes.sourceAdd);
    if (mounted) await _load();
  }

  Future<void> _openDetail(TelegramSource source) async {
    await Navigator.of(context).pushNamed(AppRoutes.sourceDetails, arguments: source.id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (BuildContext context, Widget? child) {
        final TelegramService service = widget.service;
        final List<TelegramSource> sources = service.sources;
        final bool showConnectBanner = service.authState == TelegramAuthState.disconnected ||
            service.authState == TelegramAuthState.expired;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Mes sources', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          body: _buildBody(sources, showConnectBanner),
        );
      },
    );
  }

  Widget _buildBody(List<TelegramSource> sources, bool showConnectBanner) {
    if (_loading) {
      return SkeletonPulse(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          itemCount: 4,
          itemBuilder: (_, _) => const SourceCardSkeleton(),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: 'Réessayer', icon: Icons.refresh_rounded, expanded: false, onTap: _load),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey<String>('sources-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (showConnectBanner)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              sliver: SliverToBoxAdapter(child: _ConnectBanner(service: widget.service)),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sources.isEmpty ? 'Aucune source' : '${sources.length} source${sources.length > 1 ? 's' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.service.isBackendApi ? 'Synchronisées via le backend' : 'Auto-sync toutes les 1 h',
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
          if (sources.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.send_rounded,
                title: 'Aucune source Telegram',
                message: 'Ajoutez un canal pour commencer à construire votre bibliothèque.',
                actionLabel: 'Ajouter une source',
                onAction: _openAdd,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList.separated(
                itemCount: sources.length,
                itemBuilder: (BuildContext context, int index) {
                  final TelegramSource source = sources[index];
                  return TelegramSourceCard(
                    source: source,
                    onTap: () => _openDetail(source),
                    onSettingsTap: () => _openDetail(source),
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
                  onTap: _openAdd,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bannière « connectez Telegram » affichée quand le backend est utilisé
/// sans session active.
class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner({required this.service});

  final TelegramService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_off_rounded, size: 21, color: AppColors.primaryBright),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              service.authState == TelegramAuthState.expired
                  ? 'Session expirée. Reconnectez-vous pour accéder à vos sources.'
                  : 'Connectez Telegram pour ajouter des sources.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.telegramConnect),
            child: Text('Connecter', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
          ),
        ],
      ),
    );
  }
}
