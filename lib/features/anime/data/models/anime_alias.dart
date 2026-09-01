/// Alias de titre d'un animé (titre alternatif, original, abrégé…).
///
/// Le moteur de correspondance backend s'appuie sur ces alias pour retrouver
/// le même animé sous des titres différents (ex. « Ore dake Level Up na Ken »
/// → Solo Leveling).
class AnimeAlias {
  const AnimeAlias({required this.value, this.type});

  factory AnimeAlias.fromJson(Object? json) {
    if (json is String) return AnimeAlias(value: json);
    if (json is Map<String, dynamic>) {
      return AnimeAlias(
        value: json['value']?.toString() ?? json['title']?.toString() ?? '',
        type: json['type']?.toString(),
      );
    }
    return const AnimeAlias(value: '');
  }

  final String value;
  final String? type;
}

/// Candidat de métadonnées proposé lors d'une correspondance incertaine
/// (`METADATA_REVIEW_REQUIRED`). Affiche la liste des fiches possibles pour
/// que l'administrateur tranche — jamais d'association aveugle.
class MetadataCandidateInfo {
  const MetadataCandidateInfo({
    required this.providerId,
    required this.title,
    this.provider,
    this.year,
    this.score,
  });

  factory MetadataCandidateInfo.fromJson(Map<String, dynamic> json) => MetadataCandidateInfo(
        providerId: json['provider_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        provider: json['provider']?.toString(),
        year: json['year'] as int?,
        score: (json['score'] as num?)?.toDouble(),
      );

  final String providerId;
  final String title;
  final String? provider;
  final int? year;
  final double? score;
}
