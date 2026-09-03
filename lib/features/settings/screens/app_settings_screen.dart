import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../anime/data/models/video_quality.dart';
import '../../anime/data/repositories/anime_repository.dart';
import '../../notifications/services/notification_settings.dart';
import '../../sync/models/sync_frequency.dart';
import '../../telegram/data/models/telegram_user.dart';
import '../../telegram/data/services/telegram_service.dart';
import '../services/app_settings.dart';
import '../services/data_care_service.dart';
import '../services/settings_dependencies.dart';
import '../services/version_reader.dart';
import 'storage_screen.dart';

/// Écran Paramètres — prompt 12 : les 8 catégories réelles.
///
/// Règle absolue (§27) : chaque option affichée est RÉELLEMENT branchée
/// (persistance + effet). Une option qui n'existe pas n'est pas montrée.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key, required this.dependencies});

  final SettingsDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final List<Listenable> listenables = <Listenable>[
      dependencies.appSettings,
      if (dependencies.notificationSettings != null) dependencies.notificationSettings!,
      if (dependencies.repository != null) dependencies.repository!,
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (BuildContext context, _) {
          final SettingsStrings s = SettingsStrings(dependencies.appSettings.language);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                _SettingsHeader(title: s.title),
                const SizedBox(height: 20),
                ..._accountSection(context, s),
                ..._preferencesSection(context, s),
                ..._syncSection(context, s),
                ..._notificationsSection(context, s),
                ..._storageSection(context, s),
                ..._appearanceSection(context, s),
                ..._dataSection(context, s),
                ..._aboutSection(context, s),
              ],
            ),
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // COMPTE
  // -----------------------------------------------------------------------

  List<Widget> _accountSection(BuildContext context, SettingsStrings s) {
    final TelegramService? service = dependencies.telegramService;
    if (service == null) return const [];
    final TelegramUser? user = service.currentUser;
    final bool connected = service.authState == TelegramAuthState.connected;
    return [
      _SectionLabel(s.sectionAccount),
      _SettingsCard(children: [
        _SettingsTile(
          icon: Icons.send_rounded,
          title: 'Telegram',
          subtitle: connected && user != null
              ? '${user.fullName}${user.username != null ? ' · @${user.username}' : ''}'
              : (s.language == 'en' ? 'Not connected' : 'Non connecté'),
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.telegramConnect),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.rss_feed_rounded,
          title: s.language == 'en' ? 'My Telegram sources' : 'Mes sources Telegram',
          subtitle: '${service.sources.length}',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.sources),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  // -----------------------------------------------------------------------
  // PRÉFÉRENCES (qualité §4, langue §5/§6, téléchargement auto §11)
  // -----------------------------------------------------------------------

  List<Widget> _preferencesSection(BuildContext context, SettingsStrings s) {
    final AnimeRepository? repo = dependencies.repository;
    final AppSettings settings = dependencies.appSettings;
    return [
      _SectionLabel(s.sectionPreferences),
      _SettingsCard(children: [
        if (repo != null) ...[
          _SettingsTile(
            icon: Icons.high_quality_rounded,
            title: s.preferredQuality,
            subtitle: repo.playbackSettings.preferredQuality == QualityPreference.auto
                ? '${repo.playbackSettings.preferredQuality.label} — ${s.autoQualityDetail}'
                : repo.playbackSettings.preferredQuality.label,
            onTap: () => _pickQuality(context, s, repo),
          ),
          const _Divider(),
        ],
        _SettingsTile(
          icon: Icons.translate_rounded,
          title: s.languageLabel,
          subtitle: settings.language == 'en' ? 'English' : 'Français',
          onTap: () => _pickLanguage(context, s, settings),
        ),
        const _Divider(),
        _SettingsSwitchTile(
          icon: Icons.download_rounded,
          title: s.autoDownloadLabel,
          subtitle: s.autoDownloadNote,
          value: settings.autoDownload,
          onChanged: (bool v) => settings.setAutoDownload(v),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  Future<void> _pickQuality(BuildContext context, SettingsStrings s, AnimeRepository repo) async {
    final QualityPreference current = repo.playbackSettings.preferredQuality;
    final QualityPreference? picked = await showModalBottomSheet<QualityPreference>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.preferredQuality, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final QualityPreference preference in QualityPreference.values)
            ListTile(
              title: Text(preference.label, style: const TextStyle(color: AppColors.textPrimary)),
              subtitle: preference == QualityPreference.auto
                  ? Text(s.autoQualityDetail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
                  : null,
              trailing: preference == current ? const Icon(Icons.check_rounded, color: AppColors.primaryBright) : null,
              onTap: () => Navigator.of(context).pop(preference),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null && picked != current) repo.setPreferredQuality(picked);
  }

  Future<void> _pickLanguage(BuildContext context, SettingsStrings s, AppSettings settings) async {
    final String current = settings.language;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.languageLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final MapEntry<String, String> lang
              in const <String, String>{'fr': 'Français', 'en': 'English'}.entries)
            ListTile(
              title: Text(lang.value, style: const TextStyle(color: AppColors.textPrimary)),
              trailing: lang.key == current ? const Icon(Icons.check_rounded, color: AppColors.primaryBright) : null,
              onTap: () => Navigator.of(context).pop(lang.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null && picked != current) await settings.setLanguage(picked);
  }

  // -----------------------------------------------------------------------
  // SYNCHRONISATION (§9 fréquence souhaitée, §10 Wi-Fi only)
  // -----------------------------------------------------------------------

  List<Widget> _syncSection(BuildContext context, SettingsStrings s) {
    final NotificationSettings? notif = dependencies.notificationSettings;
    final AppSettings settings = dependencies.appSettings;
    if (notif == null) return const [];
    return [
      _SectionLabel(s.sectionSync),
      _SettingsCard(children: [
        _SettingsTile(
          icon: Icons.sync_rounded,
          title: s.syncFrequency,
          subtitle: '${notif.syncFrequency.label}\n${s.syncFrequencyNote}',
          onTap: () => _pickSyncFrequency(context, s, notif, settings),
        ),
        const _Divider(),
        _SettingsSwitchTile(
          icon: Icons.wifi_rounded,
          title: s.syncWifiOnly,
          subtitle: s.syncWifiOnlyNote,
          value: settings.syncWifiOnly,
          onChanged: (bool v) async {
            await settings.setSyncWifiOnly(v);
            // §10 : la contrainte réseau réelle est ré-appliquée
            // immédiatement au planificateur (unmetered ⇄ connected).
            await notif.setSyncFrequency(notif.syncFrequency, wifiOnly: v);
          },
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.open_in_new_rounded,
          title: s.language == 'en' ? 'Open synchronization' : 'Ouvrir la synchronisation',
          subtitle: s.language == 'en' ? 'Engine, statistics, history' : 'Moteur, statistiques, historique',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.sync),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  Future<void> _pickSyncFrequency(
    BuildContext context,
    SettingsStrings s,
    NotificationSettings notif,
    AppSettings settings,
  ) async {
    final SyncFrequency current = notif.syncFrequency;
    final SyncFrequency? picked = await showModalBottomSheet<SyncFrequency>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.syncFrequency, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final SyncFrequency frequency in SyncFrequency.values)
            ListTile(
              title: Text(frequency.label, style: const TextStyle(color: AppColors.textPrimary)),
              trailing: frequency == current ? const Icon(Icons.check_rounded, color: AppColors.primaryBright) : null,
              onTap: () => Navigator.of(context).pop(frequency),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(s.syncFrequencyNote, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ]),
      ),
    );
    if (picked != null) await notif.setSyncFrequency(picked, wifiOnly: settings.syncWifiOnly);
  }

  // -----------------------------------------------------------------------
  // NOTIFICATIONS (§8 — toggles réellement branchés, Prompt 9)
  // -----------------------------------------------------------------------

  List<Widget> _notificationsSection(BuildContext context, SettingsStrings s) {
    final NotificationSettings? notif = dependencies.notificationSettings;
    if (notif == null) return const [];
    return [
      _SectionLabel(s.sectionNotifications),
      _SettingsCard(children: [
        _SettingsSwitchTile(
          icon: Icons.notifications_active_outlined,
          title: s.episodesNotif,
          value: notif.newEpisodesEnabled,
          onChanged: (bool v) => notif.setNewEpisodesEnabled(v),
        ),
        const _Divider(),
        _SettingsSwitchTile(
          icon: Icons.download_done_rounded,
          title: s.downloadsNotif,
          value: notif.downloadNotificationsEnabled,
          onChanged: (bool v) => notif.setDownloadNotificationsEnabled(v),
        ),
        const _Divider(),
        _SettingsSwitchTile(
          icon: Icons.sync_alt_rounded,
          title: s.downloadProgressNotif,
          value: notif.downloadProgressEnabled,
          onChanged: (bool v) => notif.setDownloadProgressEnabled(v),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.tune_rounded,
          title: s.notificationsSummary,
          subtitle: s.language == 'en' ? 'Quiet hours, per source…' : 'Heures silencieuses, par source…',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.notificationSettings),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  // -----------------------------------------------------------------------
  // STOCKAGE (§12–§15 → écran de gestion dédié)
  // -----------------------------------------------------------------------

  List<Widget> _storageSection(BuildContext context, SettingsStrings s) {
    return [
      _SectionLabel(s.sectionStorage),
      _SettingsCard(children: [
        _SettingsTile(
          icon: Icons.storage_rounded,
          title: s.manageStorage,
          subtitle: s.language == 'en'
              ? 'Real sizes, cache, downloads'
              : 'Tailles réelles, cache, téléchargements',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StorageScreen(dependencies: dependencies),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  // -----------------------------------------------------------------------
  // APPARENCE (§7 — identité sombre : Sombre/Système, pas de clair générique)
  // -----------------------------------------------------------------------

  List<Widget> _appearanceSection(BuildContext context, SettingsStrings s) {
    final AppSettings settings = dependencies.appSettings;
    return [
      _SectionLabel(s.sectionAppearance),
      _SettingsCard(children: [
        _SettingsTile(
          icon: Icons.dark_mode_rounded,
          title: s.themeLabel,
          subtitle: '${settings.theme == AppThemeMode.dark ? s.themeDark : s.themeSystem}\n${s.themeNote}',
          onTap: () => _pickTheme(context, s, settings),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  Future<void> _pickTheme(BuildContext context, SettingsStrings s, AppSettings settings) async {
    final AppThemeMode current = settings.theme;
    final AppThemeMode? picked = await showModalBottomSheet<AppThemeMode>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.themeLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final MapEntry<AppThemeMode, String> entry in <AppThemeMode, String>{
            AppThemeMode.dark: s.themeDark,
            AppThemeMode.system: s.themeSystem,
          }.entries)
            ListTile(
              leading: Icon(
                entry.key == AppThemeMode.dark ? Icons.dark_mode_rounded : Icons.brightness_auto_rounded,
                color: AppColors.textSecondary,
              ),
              title: Text(entry.value, style: const TextStyle(color: AppColors.textPrimary)),
              trailing: entry.key == current ? const Icon(Icons.check_rounded, color: AppColors.primaryBright) : null,
              onTap: () => Navigator.of(context).pop(entry.key),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(s.themeNote, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ]),
      ),
    );
    if (picked != null && picked != current) await settings.setTheme(picked);
  }

  // -----------------------------------------------------------------------
  // DONNÉES (§16 effacement, §17 confirmations, §18 réinitialisation, §19)
  // -----------------------------------------------------------------------

  List<Widget> _dataSection(BuildContext context, SettingsStrings s) {
    return [
      _SectionLabel(s.sectionData),
      _SettingsCard(children: [
        _SettingsTile(
          icon: Icons.privacy_tip_outlined,
          title: s.language == 'en' ? 'Privacy' : 'Confidentialité',
          subtitle: s.privacyNote,
          onTap: () => _showPrivacyInfo(context, s),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.delete_sweep_rounded,
          iconColor: AppColors.warning,
          title: s.eraseLocalData,
          subtitle: s.eraseLocalDataNote,
          onTap: () => _confirmEraseLocalData(context, s),
        ),
        const _Divider(),
        _SettingsTile(
          icon: Icons.dangerous_outlined,
          iconColor: AppColors.danger,
          title: s.resetApp,
          titleColor: AppColors.danger,
          subtitle: s.resetAppNote,
          onTap: () => _confirmReset(context, s),
        ),
      ]),
      const SizedBox(height: 18),
    ];
  }

  void _showPrivacyInfo(BuildContext context, SettingsStrings s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.privacy_tip_outlined, size: 22, color: AppColors.primaryBright),
              SizedBox(width: 10),
              Text('Confidentialité',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
            const SizedBox(height: 14),
            const Text(
              'Vos sources Telegram et votre catalogue sont traités localement sur votre appareil.\n\n'
              'AnimeBox ne transmet ni votre session Telegram, ni vos messages, ni vos fichiers, ni aucune information privée à un serveur distant.\n\n'
              'La session Telegram est conservée dans un stockage chiffré, propre à cet appareil.\n\n'
              'L\'option « Wi-Fi uniquement » et les fréquences de synchronisation ne concernent que les métadonnées — jamais le téléchargement de vidéos.',
              style: TextStyle(fontSize: 13, height: 1.55, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.ok)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    Color confirmColor = AppColors.danger,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _confirmEraseLocalData(BuildContext context, SettingsStrings s) async {
    // §17 : confirmation explicite AVANT toute action destructive.
    final bool ok = await _confirm(
      context,
      title: s.eraseLocalData,
      message: s.eraseLocalDataConfirm,
      confirmLabel: s.erase,
      cancelLabel: s.cancel,
      confirmColor: AppColors.warning,
    );
    if (!ok || !context.mounted) return;
    final DataCareResult result = await dependencies.buildDataCareService().eraseLocalData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? (s.language == 'en' ? 'Local data erased.' : 'Données locales effacées.')
          : '${s.language == 'en' ? 'Error' : 'Erreur'} : ${result.error ?? ''}'),
    ));
  }

  Future<void> _confirmReset(BuildContext context, SettingsStrings s) async {
    // §17 : double confirmation pour l'action irréversible (§18).
    final bool first = await _confirm(
      context,
      title: s.resetApp,
      message: s.resetAppConfirm,
      confirmLabel: s.confirm,
      cancelLabel: s.cancel,
    );
    if (!first || !context.mounted) return;
    final bool second = await _confirm(
      context,
      title: s.resetApp,
      message: s.resetAppFinal,
      confirmLabel: s.erase,
      cancelLabel: s.cancel,
    );
    if (!second || !context.mounted) return;
    final DataCareResult result = await dependencies.buildDataCareService().resetEverything();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? (s.language == 'en'
              ? 'AnimeBox has been reset (${result.downloadsRemoved} download(s) removed).'
              : 'AnimeBox a été réinitialisé (${result.downloadsRemoved} téléchargement(s) supprimé(s)).')
          : '${s.language == 'en' ? 'Error' : 'Erreur'} : ${result.error ?? ''}'),
    ));
  }

  // -----------------------------------------------------------------------
  // À PROPOS (§21/§22 — version RÉELLE du projet, rien de fictif)
  // -----------------------------------------------------------------------

  List<Widget> _aboutSection(BuildContext context, SettingsStrings s) {
    return [
      _SectionLabel(s.sectionAbout),
      _SettingsCard(children: [
        _VersionTile(reader: dependencies.versionReader, english: s.language == 'en', about: s.about),
      ]),
      const SizedBox(height: 24),
    ];
  }
}

/// Tuile « À propos » — version RÉELLE lue une fois (§21/§22) : si la
/// lecture échoue, « inconnue » est affichée, jamais un faux numéro.
class _VersionTile extends StatefulWidget {
  const _VersionTile({required this.reader, required this.english, required this.about});

  final VersionReader reader;
  final bool english;
  final String about;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  late final Future<String?> _future = widget.reader.read();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String version = snapshot.data ?? (widget.english ? 'unknown' : 'inconnue');
        return _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: widget.about,
          subtitle: 'Version $version',
        );
      },
    );
  }
}

// ===========================================================================
// Composants d'écran (style existant conservé — §29, icônes pro §30).
// ===========================================================================

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(title,
            semanticsLabel: title,
            style: Theme.of(context).textTheme.headlineMedium),
      ),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, indent: 58, color: AppColors.divider.withValues(alpha: 0.6));
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
    this.iconColor = AppColors.primaryBright,
    this.titleColor = AppColors.textPrimary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Action au toucher — null pour une tuile purement informative
  /// (aucun chevron n'est alors affiché : pas de fausse action, §27).
  final VoidCallback? onTap;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleColor)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
      trailing:
          onTap == null ? null : const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: AppColors.primaryBright),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
      trailing: Switch(value: value, activeThumbColor: AppColors.primary, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
