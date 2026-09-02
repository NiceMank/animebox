/// Fréquence SOUHAITÉE de synchronisation automatique (règle 12).
///
/// IMPORTANT : Android décide seul de l'exécution réelle des tâches
/// périodiques — il peut retarder ou regrouper les exécutions pour
/// préserver la batterie. L'interface le présente comme une fréquence
/// souhaitée, jamais comme une garantie.
enum SyncFrequency {
  disabled('off', 'Désactivée', null),
  every15Minutes('15m', 'Toutes les 15 minutes', Duration(minutes: 15)),
  every30Minutes('30m', 'Toutes les 30 minutes', Duration(minutes: 30)),
  hourly('1h', 'Toutes les heures', Duration(hours: 1)),
  every3Hours('3h', 'Toutes les 3 heures', Duration(hours: 3)),
  daily('24h', 'Une fois par jour', Duration(hours: 24));

  const SyncFrequency(this.id, this.label, this.interval);

  /// Identifiant persisté en base locale.
  final String id;

  /// Libellé affiché dans les réglages.
  final String label;

  /// Intervalle souhaité — minimum Android : 15 minutes.
  final Duration? interval;

  static SyncFrequency fromId(String? id) {
    for (final SyncFrequency frequency in SyncFrequency.values) {
      if (frequency.id == id) return frequency;
    }
    return SyncFrequency.disabled;
  }
}
