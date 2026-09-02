import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../anime/data/models/anime.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../notifications/services/notification_service.dart';
import '../../notifications/services/notification_settings.dart';
import '../../sync/models/sync_frequency.dart';
import '../../telegram/data/models/telegram_source.dart';
import '../../telegram/data/services/telegram_service.dart';

/// Écran Réglages — Notifications & synchronisation (prompt 9).
///
/// - permission de notification demandée AU MOMENT OPPORTUN, avec une
///   explication claire (règle 2) — jamais au premier lancement ;
/// - nouveaux épisodes, téléchargements, progression (règles 4/8) ;
/// - mode silencieux (règle 19), heures silencieuses (règle 20) ;
/// - fréquence SOUHAITÉE de synchronisation automatique (règle 12) ;
/// - préférences par source (règle 17) et par animé (règle 18).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.settings,
    required this.notifications,
    this.telegramService,
    this.repository,
  });

  final NotificationSettings settings;
  final NotificationService notifications;
  final TelegramService? telegramService;
  final AnimeRepository? repository;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool? _permissionGranted;
  bool _permissionDismissed = false; // « Plus tard » (règle 2)

  /// Préférences par source et par animé (chargées une fois, mises à
  /// jour localement à chaque bascule).
  final Map<String, bool> _sourcePrefs = <String, bool>{};
  final Map<String, bool> _animePrefs = <String, bool>{};

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPermission());
    unawaited(_loadPrefs());
  }

  Future<void> _refreshPermission() async {
    final bool granted = await widget.notifications.isPermissionGranted();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _loadPrefs() async {
    final TelegramService? service = widget.telegramService;
    for (final TelegramSource source in service?.sources ?? const <TelegramSource>[]) {
      _sourcePrefs[source.id] = await widget.settings.isSourceNotificationsEnabled(source.id);
    }
    for (final Anime anime in widget.repository?.allAnime ?? const <Anime>[]) {
      _animePrefs[anime.id] = await widget.settings.isAnimeNotificationsEnabled(anime.id);
    }
    if (mounted) setState(() {});
  }

  /// Règle 2 : la permission est demandée APRÈS l'explication, uniquement
  /// sur action explicite de l'utilisateur.
  Future<void> _askPermission() async {
    final bool granted = await widget.notifications.requestPermission();
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
    // Android n'affiche la boîte système qu'un nombre limité de fois ;
    // si l'utilisateur a refusé, l'application continue normalement
    // (règle 2) — la carte d'information reste disponible.
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorisation refusée : AnimeBox continue de fonctionner, '
            'les alertes resteront désactivées par le système.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotificationSettings settings = widget.settings;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Notifications & synchronisation',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: widget.telegramService == null
            ? settings
            : Listenable.merge(<Listenable>[settings, widget.telegramService!]),
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              if (_permissionGranted == false && !_permissionDismissed) _buildPermissionCard(context),
              _SectionTitle('Alertes'),
              _SwitchCard(
                icon: Icons.notifications_active_outlined,
                title: 'Nouveaux épisodes',
                subtitle: 'Prévenu quand un épisode est détecté dans vos sources',
                value: settings.newEpisodesEnabled,
                onChanged: settings.setNewEpisodesEnabled,
              ),
              _SwitchCard(
                icon: Icons.download_rounded,
                title: 'Téléchargements',
                subtitle: 'Fin et interruption des téléchargements',
                value: settings.downloadNotificationsEnabled,
                onChanged: settings.setDownloadNotificationsEnabled,
              ),
              _SwitchCard(
                icon: Icons.sync_alt_rounded,
                title: 'Progression en direct',
                subtitle: 'Pourcentage réel pendant le téléchargement',
                value: settings.downloadProgressEnabled,
                enabled: settings.downloadNotificationsEnabled,
                onChanged: settings.setDownloadProgressEnabled,
              ),
              const SizedBox(height: 18),
              _SectionTitle('Discrétion'),
              _SwitchCard(
                icon: Icons.notifications_off_outlined,
                title: 'Notifications silencieuses',
                subtitle: 'Toujours créées, sans son ni vibration',
                value: settings.silentMode,
                onChanged: settings.setSilentMode,
              ),
              _buildQuietHoursCard(context, settings),
              const SizedBox(height: 18),
              _SectionTitle('Synchronisation automatique'),
              _buildFrequencyCard(context, settings),
              const SizedBox(height: 18),
              if ((widget.telegramService?.sources.isNotEmpty ?? false) ||
                  (widget.repository?.allAnime.isNotEmpty ?? false)) ...[
                _SectionTitle('Préférences'),
                ..._buildSourceCards(context, settings),
                ..._buildAnimeCards(context, settings),
              ],
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Les vidéos ne sont jamais téléchargées automatiquement : '
                  'la synchronisation ne récupère que les informations nécessaires.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------
  // Permission (règle 2)
  // -------------------------------------------------------------------

  Widget _buildPermissionCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_outlined, color: AppColors.primaryBright, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Autoriser les notifications',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'AnimeBox peut vous prévenir lorsqu\'un nouvel épisode est détecté dans vos sources.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              PrimaryButton(label: 'Autoriser', expanded: false, onTap: _askPermission),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => setState(() => _permissionDismissed = true),
                child: const Text('Plus tard', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Heures silencieuses (règle 20)
  // -------------------------------------------------------------------

  Widget _buildQuietHoursCard(BuildContext context, NotificationSettings settings) {
    final String start = _formatMinutes(settings.quietStartMinutes);
    final String end = _formatMinutes(settings.quietEndMinutes);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_outlined, color: AppColors.primaryBright, size: 21),
            title: const Text('Heures silencieuses',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text(
              settings.quietHoursEnabled ? '$start → $end' : 'Désactivées',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            value: settings.quietHoursEnabled,
            activeThumbColor: AppColors.primaryBright,
            onChanged: settings.setQuietHoursEnabled,
          ),
          if (settings.quietHoursEnabled) ...[
            const Divider(height: 1, color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: _TimeCell(
                    label: 'Début',
                    value: start,
                    onTap: () => _pickQuietTime(context, settings, start: true),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
                Expanded(
                  child: _TimeCell(
                    label: 'Fin',
                    value: end,
                    onTap: () => _pickQuietTime(context, settings, start: false),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Pendant cette période, les alertes sont créées sans son ni '
                'vibration. Les nouveaux épisodes restent enregistrés.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickQuietTime(BuildContext context, NotificationSettings settings, {required bool start}) async {
    final int initial = start ? settings.quietStartMinutes : settings.quietEndMinutes;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    final int minutes = picked.hour * 60 + picked.minute;
    await settings.setQuietHours(
      startMinutes: start ? minutes : settings.quietStartMinutes,
      endMinutes: start ? settings.quietEndMinutes : minutes,
    );
  }

  static String _formatMinutes(int minutes) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // -------------------------------------------------------------------
  // Fréquence de synchronisation automatique (règle 12)
  // -------------------------------------------------------------------

  Widget _buildFrequencyCard(BuildContext context, NotificationSettings settings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.schedule_rounded, color: AppColors.primaryBright, size: 21),
            title: const Text('Fréquence souhaitée',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text(settings.syncFrequency.label,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            onTap: () => _pickFrequency(context, settings),
          ),
          if (settings.syncFrequency != SyncFrequency.disabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Android décide de l\'exécution réelle : il peut retarder la '
                'synchronisation pour préserver la batterie. « Synchroniser '
                'maintenant » reste toujours disponible.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickFrequency(BuildContext context, NotificationSettings settings) async {
    final SyncFrequency? picked = await showModalBottomSheet<SyncFrequency>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Synchronisation automatique',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final SyncFrequency frequency in SyncFrequency.values)
              ListTile(
                title: Text(frequency.label, style: const TextStyle(fontSize: 13.5)),
                trailing: frequency == settings.syncFrequency
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryBright)
                    : null,
                onTap: () => Navigator.of(context).pop(frequency),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                'Fréquence souhaitée : le système Android peut modifier ou '
                'retarder l\'exécution réelle.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked != settings.syncFrequency) {
      await settings.setSyncFrequency(picked);
    }
  }

  // -------------------------------------------------------------------
  // Préférences par source (règle 17) et par animé (règle 18)
  // -------------------------------------------------------------------

  List<Widget> _buildSourceCards(BuildContext context, NotificationSettings settings) {
    final List<TelegramSource> sources = widget.telegramService?.sources ?? const <TelegramSource>[];
    if (sources.isEmpty) return const <Widget>[];
    return <Widget>[
      const _SubTitle('Par source'),
      for (final TelegramSource source in sources)
        _SwitchCard(
          icon: Icons.rss_feed_rounded,
          title: source.name,
          subtitle: source.syncEnabled ? 'Source synchronisée' : 'Source désactivée',
          value: _sourcePrefs[source.id] ?? true,
          onChanged: (bool value) async {
            await settings.setSourceNotificationsEnabled(source.id, value);
            if (mounted) setState(() => _sourcePrefs[source.id] = value);
          },
        ),
    ];
  }

  List<Widget> _buildAnimeCards(BuildContext context, NotificationSettings settings) {
    final List<Anime> animes = widget.repository?.allAnime ?? const <Anime>[];
    if (animes.isEmpty) return const <Widget>[];
    return <Widget>[
      const _SubTitle('Par animé'),
      for (final Anime anime in animes.take(30))
        _SwitchCard(
          icon: Icons.movie_outlined,
          title: anime.title,
          subtitle: 'Les notifications n\'enlèvent jamais l\'animé du catalogue',
          value: _animePrefs[anime.id] ?? true,
          onChanged: (bool value) async {
            await settings.setAnimeNotificationsEnabled(anime.id, value);
            if (mounted) setState(() => _animePrefs[anime.id] = value);
          },
        ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: enabled ? AppColors.primaryBright : AppColors.textMuted, size: 21),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: enabled ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        value: value,
        activeThumbColor: AppColors.primaryBright,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
