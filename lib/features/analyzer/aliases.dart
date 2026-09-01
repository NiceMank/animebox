/// Catalogue de titres et système d'alias — port fidèle de
/// `backend/app/analyzer/aliases.py`.
library;

import 'text_utils.dart';

/// Un titre connu du catalogue.
class AnimeTitle {
  const AnimeTitle({
    required this.key,
    required this.title,
    this.originalTitle,
    this.releaseYear,
  });

  final String key;
  final String title;
  final String? originalTitle;
  final int? releaseYear;
}

/// Catalogue intégré (identique au moteur Python — démo / détection).
const List<(String, String, String?, int?)> _catalogEntries = [
  ('solo leveling', 'Solo Leveling', 'Ore dake Level Up na Ken', 2024),
  ('one piece', 'One Piece', null, 1999),
  ('jujutsu kaisen', 'Jujutsu Kaisen', null, 2020),
  ('demon slayer', 'Demon Slayer', 'Kimetsu no Yaiba', 2019),
  ('attack on titan', 'Attack on Titan', 'Shingeki no Kyojin', 2013),
  ('86 eighty six', '86 Eighty-Six', null, 2021),
  ("jojo s bizarre adventure", "JoJo's Bizarre Adventure", null, 2012),
  ('classroom of the elite', 'Classroom of the Elite', null, 2017),
  ('my hero academia', 'My Hero Academia', 'Boku no Hero Academia', 2016),
  ('naruto', 'Naruto', null, 2002),
  ('bleach', 'Bleach', null, 2004),
  ('one punch man', 'One Punch Man', null, 2015),
  ('fullmetal alchemist brotherhood', 'Fullmetal Alchemist: Brotherhood', null, 2009),
  ('steins gate', 'Steins;Gate', null, 2011),
  ('tokyo ghoul', 'Tokyo Ghoul', null, 2014),
  ('chainsaw man', 'Chainsaw Man', null, 2022),
  ('spy x family', 'Spy x Family', null, 2022),
  ('death note', 'Death Note', null, 2006),
  ('vinland saga', 'Vinland Saga', null, 2019),
  ('black clover', 'Black Clover', null, 2017),
  ('dragon ball z', 'Dragon Ball Z', null, 1989),
  ('hunter x hunter', 'Hunter x Hunter', null, 2011),
  ('mob psycho 100', 'Mob Psycho 100', null, 2016),
  ('re zero', 'Re:Zero', 'Re:Zero kara Hajimeru Isekai Seikatsu', 2016),
  ('konosuba', 'KonoSuba', null, 2016),
  ('overlord', 'Overlord', null, 2015),
  ('sword art online', 'Sword Art Online', null, 2012),
  ('tokyo revengers', 'Tokyo Revengers', null, 2021),
  ('blue lock', 'Blue Lock', null, 2022),
  ('haikyu', 'Haikyu!!', null, 2014),
  ("frieren beyond journey s end", "Frieren: Beyond Journey's End", 'Sousou no Frieren', 2023),
];

/// Alias intégrés par titre canonique (formes normalisées).
const Map<String, List<String>> _builtinAliases = {
  'solo leveling': ['ore dake level up na ken', 'only i level up', 'sl'],
  'one piece': ['op', 'wan pisu', 'wanpisu'],
  'jujutsu kaisen': ['jjk', 'sorcery fight'],
  'demon slayer': ['kimetsu no yaiba', 'ds', 'demon slayer kimetsu no yaiba'],
  'attack on titan': ['shingeki no kyojin', 'snk', 'aot'],
  '86 eighty six': ['86', 'eighty six'],
  "jojo s bizarre adventure": ['jojo', 'jojo no kimyou na bouken'],
  'classroom of the elite': ['youkoso jitsuryoku shijou shugi no kyoushitsu e', 'cote'],
  'my hero academia': ['boku no hero academia', 'mha'],
  'one punch man': ['opm', 'wanpanman'],
  'fullmetal alchemist brotherhood': ['fma', 'fmab', 'fullmetal alchemist'],
  'steins gate': ['steinsgate'],
  'sword art online': ['sao'],
  'dragon ball z': ['dbz'],
  'hunter x hunter': ['hxh'],
  'mob psycho 100': ['mob psycho'],
  'spy x family': ['spy family'],
  'frieren beyond journey s end': ['sousou no frieren', 'frieren'],
};

/// Registre de titres : compare des formes NORMALISÉES.
class AliasRegistry {
  AliasRegistry({Map<String, AnimeTitle>? catalog, Map<String, List<String>>? aliases})
      : _catalog = catalog ?? {
          for (final (String key, String title, String? original, int? year) in _catalogEntries)
            key: AnimeTitle(key: key, title: title, originalTitle: original, releaseYear: year),
        },
        _aliases = aliases ?? _builtinAliases;

  final Map<String, AnimeTitle> _catalog;
  final Map<String, List<String>> _aliases;

  List<AnimeTitle> get titles => _catalog.values.toList(growable: false);

  /// Résout un titre normalisé : canonique exact, sinon alias.
  AnimeTitle? resolve(String normalizedKey) {
    final AnimeTitle? exact = _catalog[normalizedKey];
    if (exact != null) return exact;
    for (final MapEntry<String, List<String>> entry in _aliases.entries) {
      if (entry.value.contains(normalizedKey)) return _catalog[entry.key];
    }
    return null;
  }

  /// Résout uniquement le titre canonique exact (sans alias).
  AnimeTitle? resolveExact(String normalizedKey) => _catalog[normalizedKey];

  /// Ajoute un alias personnalisé (persisté par l'appelant si nécessaire).
  void addAlias(String canonicalKey, String alias) {
    _aliases.putIfAbsent(canonicalKey, () => []).add(normalize(alias));
  }
}
