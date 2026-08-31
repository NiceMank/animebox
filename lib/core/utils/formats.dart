/// Formatage de nombres et de dates, partagé par toute l'application.
library;

const List<String> _monthsFr = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// Formate un entier avec séparateur de milliers français : 12458 → « 12 458 ».
String formatCount(int value) {
  final String raw = value.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// Formate une date courte : 12 mai 2024.
String formatDate(DateTime date) => '${date.day} ${_monthsFr[date.month - 1]} ${date.year}';

/// Formate une date avec heure : 12 mai 2024 · 14:32.
String formatDateTime(DateTime date) {
  final String hour = date.hour.toString().padLeft(2, '0');
  final String minute = date.minute.toString().padLeft(2, '0');
  return '${formatDate(date)} · $hour:$minute';
}

/// Temps relatif : « à l'instant », « il y a 2 min », « il y a 3 h »,
/// « hier », « il y a 4 j », puis la date complète.
///
/// [now] permet des tests déterministes.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final Duration delta = reference.difference(time);

  if (delta.inSeconds < 45) return 'à l\'instant';
  if (delta.inMinutes < 60) return delta.inMinutes == 1 ? 'il y a 1 min' : 'il y a ${delta.inMinutes} min';
  if (delta.inHours < 24) return delta.inHours == 1 ? 'il y a 1 h' : 'il y a ${delta.inHours} h';

  final DateTime today = DateTime(reference.year, reference.month, reference.day);
  final DateTime day = DateTime(time.year, time.month, time.day);
  final int dayDiff = today.difference(day).inDays;
  if (dayDiff == 1) return 'hier';
  if (dayDiff < 7) return 'il y a $dayDiff j';
  return formatDate(time);
}

/// Libellé de jour pour l'historique : « Aujourd'hui », « Hier » ou la date.
String dayGroupLabel(DateTime time, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final DateTime today = DateTime(reference.year, reference.month, reference.day);
  final DateTime day = DateTime(time.year, time.month, time.day);
  final int dayDiff = today.difference(day).inDays;
  if (dayDiff == 0) return 'Aujourd\'hui';
  if (dayDiff == 1) return 'Hier';
  return formatDate(time);
}

/// Formate une durée d'intervalle d'auto-synchronisation :
/// 15 min, 1 h, 6 h, 24 h.
String formatAutoSyncInterval(Duration interval) {
  if (interval.inMinutes < 60) return '${interval.inMinutes} min';
  return '${interval.inHours} h';
}
