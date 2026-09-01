/// Extraction des attributs structurés : saison, épisode, qualité, langue,
/// année, titre — port fidèle de `backend/app/analyzer/extractors.py`.
library;

import 'aliases.dart';
import 'language.dart';
import 'quality.dart' as quality;
import 'text_utils.dart';

// ---------------------------------------------------------------------------
// Motifs (tous testés sur du texte déjà normalisé)
// ---------------------------------------------------------------------------

final RegExp reNumber = RegExp(r'^\d{1,4}$');
final RegExp reYear = RegExp(r'^(19|20)\d{2}$');
final RegExp reSxE = RegExp(r'^s(\d{1,2})e(\d{1,3})$');
final RegExp reCross = RegExp(r'^(\d{1,2})x(\d{1,3})$');
final RegExp reSOnly = RegExp(r'^s(\d{1,2})$');
final RegExp reEOnly = RegExp(r'^e(\d{1,3})$');
final RegExp reEpNum = RegExp(r'^ep(\d{1,3})$');

const Set<String> seasonWords = {'season', 'seasons', 'saison', 'saisons'};
const Set<String> episodeWords = {'episode', 'episodes', 'ep', 'eps', 'épisode', 'épisodes', 'ép'};
const Set<String> specialWords = {'special', 'spécial', 'specials', 'spéciaux'};

/// Mots de « scène » (release tags) retirés du titre.
const Set<String> releaseTags = {
  'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'av1', 'vp9',
  'aac', 'ac3', 'eac3', 'dts', 'dtshd', 'truehd', 'flac', 'opus',
  '10bit', 'hi10', 'hdr', 'hdr10', 'dv', 'sdr',
  'webdl', 'webrip', 'web', 'dl',
  'bluray', 'bdrip', 'brrip', 'dvdrip', 'hdtv',
  'proper', 'repack', 'remux', 'dual', 'dualaudio', 'mkv', 'mp4',
};

/// Nombres « résolution » jamais candidats à un épisode.
const Set<String> _resolutionNumbers = {'2160', '1440', '1080', '720', '480', '360'};

const String sourceCombined = 'combined';
const String sourceStandalone = 'standalone';
const String sourceBare = 'heuristic';
const String sourceBareKnown = 'heuristic_known';
const String sourceSpecial = 'special';

/// Attributs détectés sur UNE source de texte (nom de fichier, caption…).
class Extraction {
  Extraction({required this.source});

  final String source;
  int? season;
  int? episode;
  String? episodeKind;
  String? episodeSource;
  String? seasonSource;
  int? year;
  String? quality;
  String? qualityOriginal;
  String? language;
  String? subtitles;
  final Set<int> consumed = {};
  final List<String> warnings = [];

  void note(String warning) {
    if (!warnings.contains(warning)) warnings.add(warning);
  }
}

bool isYearToken(String token) => reYear.hasMatch(token);

bool looksLikeEpisodeNumber(String token) {
  if (isYearToken(token) || _resolutionNumbers.contains(token)) return false;
  return reNumber.hasMatch(token) && int.parse(token) <= 1999;
}

void _setEpisode(Extraction extraction, int number, String source) {
  if (extraction.episode == null) {
    extraction.episode = number;
    extraction.episodeSource = source;
  } else if (extraction.episode != number) {
    extraction.note('épisodes contradictoires : ${extraction.episode} et $number');
  }
}

// ---------------------------------------------------------------------------
// Détecteurs
// ---------------------------------------------------------------------------

/// Formats combinés : S02E08, 2x08, S2 E8, S 02 E 08, Season 2 Episode 8…
void scanSeasonEpisode(Extraction extraction, List<Token> tokens) {
  final int count = tokens.length;
  int index = 0;
  while (index < count) {
    (int, int?, int?)? matched;
    final String token = tokens[index].text;

    final Match? sxMatch = reSxE.firstMatch(token);
    if (sxMatch != null) {
      matched = (1, int.parse(sxMatch.group(1)!), int.parse(sxMatch.group(2)!));
    } else {
      final Match? crossMatch = reCross.firstMatch(token);
      if (crossMatch != null) {
        matched = (1, int.parse(crossMatch.group(1)!), int.parse(crossMatch.group(2)!));
      } else {
        final Match? sMatch = reSOnly.firstMatch(token);
        if (sMatch != null) {
          final int season = int.parse(sMatch.group(1)!);
          if (index + 1 < count) {
            final String next = tokens[index + 1].text;
            if (reEOnly.hasMatch(next)) {
              matched = (2, season, int.parse(next.substring(1)));
            } else if (looksLikeEpisodeNumber(next) && quality.specForToken(next) == null) {
              matched = (2, season, int.parse(next));
            } else if (index + 2 < count &&
                episodeWords.contains(next) &&
                looksLikeEpisodeNumber(tokens[index + 2].text)) {
              matched = (3, season, int.parse(tokens[index + 2].text));
            }
          }
        } else if (seasonWords.contains(token)) {
          if (index + 1 < count && looksLikeEpisodeNumber(tokens[index + 1].text)) {
            final int season = int.parse(tokens[index + 1].text);
            matched = (2, season, null);
            if (index + 3 < count &&
                episodeWords.contains(tokens[index + 2].text) &&
                looksLikeEpisodeNumber(tokens[index + 3].text)) {
              matched = (4, season, int.parse(tokens[index + 3].text));
            }
          }
        } else if (token == 's') {
          if (index + 3 < count &&
              looksLikeEpisodeNumber(tokens[index + 1].text) &&
              tokens[index + 2].text == 'e' &&
              looksLikeEpisodeNumber(tokens[index + 3].text)) {
            matched = (4, int.parse(tokens[index + 1].text), int.parse(tokens[index + 3].text));
          }
        }
      }
    }

    if (matched != null) {
      final (int span, int? season, int? episode) = matched;
      for (int offset = 0; offset < span; offset++) {
        extraction.consumed.add(index + offset);
      }
      if (season != null) {
        if (extraction.season == null) {
          extraction.season = season;
          extraction.seasonSource = sourceCombined;
        } else if (extraction.season != season) {
          extraction.note('saisons contradictoires : ${extraction.season} et $season');
        }
      }
      if (episode != null) _setEpisode(extraction, episode, sourceCombined);
      index += span;
    } else {
      index += 1;
    }
  }
}

/// Saison seule : « S2 », « S 01 », « Saison 2 », « Season 2 ».
void scanSeasonAlone(Extraction extraction, List<Token> tokens) {
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    final String token = tokens[index].text;
    final Match? match = reSOnly.firstMatch(token);
    if (match != null) {
      extraction.consumed.add(index);
      if (extraction.season == null) {
        extraction.season = int.parse(match.group(1)!);
        extraction.seasonSource = sourceStandalone;
      }
      continue;
    }
    if (token == 's' && index + 1 < tokens.length) {
      final String candidate = tokens[index + 1].text;
      if (reNumber.hasMatch(candidate) && int.parse(candidate) <= 99 && !isYearToken(candidate)) {
        extraction.consumed.addAll([index, index + 1]);
        if (extraction.season == null) {
          extraction.season = int.parse(candidate);
          extraction.seasonSource = sourceStandalone;
        }
        continue;
      }
    }
    if (seasonWords.contains(token) && index + 1 < tokens.length) {
      final String candidate = tokens[index + 1].text;
      if (looksLikeEpisodeNumber(candidate) && int.parse(candidate) <= 99) {
        extraction.consumed.addAll([index, index + 1]);
        if (extraction.season == null) {
          extraction.season = int.parse(candidate);
          extraction.seasonSource = sourceStandalone;
        }
      }
    }
  }
}

/// Épisode seul : « E08 », « EP08 », « Episode 08 », « Épisode 08 ».
void scanEpisodeAlone(Extraction extraction, List<Token> tokens) {
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    final String token = tokens[index].text;
    final Match? eMatch = reEOnly.firstMatch(token);
    if (eMatch != null) {
      extraction.consumed.add(index);
      _setEpisode(extraction, int.parse(eMatch.group(1)!), sourceStandalone);
      continue;
    }
    final Match? epMatch = reEpNum.firstMatch(token);
    if (epMatch != null) {
      extraction.consumed.add(index);
      _setEpisode(extraction, int.parse(epMatch.group(1)!), sourceStandalone);
      continue;
    }
    if (episodeWords.contains(token) && index + 1 < tokens.length) {
      final String candidate = tokens[index + 1].text;
      if (looksLikeEpisodeNumber(candidate)) {
        extraction.consumed.addAll([index, index + 1]);
        _setEpisode(extraction, int.parse(candidate), sourceStandalone);
      }
    }
  }
}

/// « Épisode spécial » : marqueur sans numéro — jamais de numéro inventé.
void scanEpisodeSpecial(Extraction extraction, List<Token> tokens) {
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    final String token = tokens[index].text;
    if (episodeWords.contains(token) && index + 1 < tokens.length) {
      if (specialWords.contains(tokens[index + 1].text)) {
        extraction.consumed.addAll([index, index + 1]);
        extraction.episodeKind = 'special';
        extraction.episodeSource = sourceSpecial;
      }
    } else if (specialWords.contains(token) && extraction.episodeSource == sourceSpecial) {
      extraction.consumed.add(index);
    }
  }
}

/// Année de sortie (jamais confondue avec un épisode).
void scanYear(Extraction extraction, List<Token> tokens) {
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    if (isYearToken(tokens[index].text)) {
      extraction.consumed.add(index);
      extraction.year ??= int.parse(tokens[index].text);
    }
  }
}

void _setQuality(Extraction extraction, quality.QualitySpec spec, String original) {
  if (extraction.quality == null) {
    extraction.quality = spec.canonical;
    extraction.qualityOriginal = original;
  } else if (spec.rank > quality.rankOf(extraction.quality)) {
    extraction.quality = spec.canonical;
    extraction.qualityOriginal = original;
    extraction.note('plusieurs qualités détectées, la plus haute a été retenue');
  } else if (spec.rank < quality.rankOf(extraction.quality)) {
    extraction.note('plusieurs qualités détectées, la plus haute a été retenue');
  }
}

/// Qualité : 1080p, FHD, HD…
void scanQuality(Extraction extraction, List<Token> tokens) {
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    final String token = tokens[index].text;
    if (token == 'full' && index + 1 < tokens.length) {
      final String pair = 'full ${tokens[index + 1].text}';
      final quality.QualitySpec? spec = quality.specForToken(pair);
      if (spec != null) {
        extraction.consumed.addAll([index, index + 1]);
        _setQuality(extraction, spec, pair);
        continue;
      }
    }
    final quality.QualitySpec? spec = quality.specForToken(token);
    if (spec != null) {
      extraction.consumed.add(index);
      _setQuality(extraction, spec, token);
    }
  }
}

/// Langue audio et sous-titres.
void scanLanguage(Extraction extraction, List<Token> tokens) {
  LanguageMatch? current;
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index)) continue;
    final String token = tokens[index].text;
    LanguageMatch? rule = matchToken(token);
    if (rule == null) continue;
    // « sub fr » (deux mots) → sous-titres français.
    if (rule.subtitles == kSubtitlesUnknown && index + 1 < tokens.length) {
      final String follower = tokens[index + 1].text;
      if (const {'fr', 'french', 'francais', 'français'}.contains(follower)) {
        rule = LanguageMatch(rule.language, 'french');
        extraction.consumed.add(index + 1);
      } else if (const {'en', 'eng', 'english'}.contains(follower)) {
        rule = LanguageMatch(rule.language, 'english');
        extraction.consumed.add(index + 1);
      }
    }
    extraction.consumed.add(index);
    if (current != null &&
        rule.language != null &&
        current.language != null &&
        rule.language != current.language) {
      extraction.note('langues contradictoires : ${current.language} et ${rule.language}');
    }
    current = mergeMatches(current, rule);
  }
  if (current != null) {
    extraction.language = current.language;
    extraction.subtitles = current.subtitles;
  }
}

/// Numéro seul (« One Piece 1124 », « Solo Leveling 08 ») — règles de
/// sécurité : un seul candidat, jamais une année ni une résolution, jamais
/// le premier mot.
void scanBareEpisode(Extraction extraction, List<Token> tokens, AliasRegistry registry) {
  if (extraction.episode != null || extraction.episodeKind != null) return;
  final List<(int, int)> candidates = [];
  for (int index = 0; index < tokens.length; index++) {
    if (extraction.consumed.contains(index) || index == 0) continue;
    if (!looksLikeEpisodeNumber(tokens[index].text)) continue;
    candidates.add((index, int.parse(tokens[index].text)));
  }
  if (candidates.length != 1) return;
  final (int index, int number) = candidates[0];
  final List<String> before = [
    for (final Token t in tokens.sublist(0, index))
      if (!releaseTags.contains(t.text)) t.text,
  ];
  if (before.isEmpty) return;
  final String titleCandidate = before.join(' ');
  final bool known = registry.resolve(titleCandidate) != null;
  final bool hasWord = before.any((String word) => !reNumber.hasMatch(word));
  if (known && hasWord) {
    extraction.consumed.add(index);
    _setEpisode(extraction, number, sourceBareKnown);
  } else if (hasWord &&
      before.length >= 2 &&
      before.every((String word) => !reNumber.hasMatch(word))) {
    extraction.consumed.add(index);
    _setEpisode(extraction, number, sourceBare);
    extraction.note("numéro d'épisode déduit sans titre connu");
  }
}

/// Résultat de la reconstruction du titre.
class TitleResult {
  const TitleResult({this.key, this.display, this.matched = false, this.viaAlias = false, this.anime});

  final String? key;
  final String? display;
  final bool matched;
  final bool viaAlias;
  final AnimeTitle? anime;
}

/// Reconstruit le titre à partir des mots non consommés par les détecteurs.
TitleResult buildTitle(Extraction extraction, List<Token> tokens, AliasRegistry registry) {
  List<String> remaining = [
    for (int index = 0; index < tokens.length; index++)
      if (!extraction.consumed.contains(index) && !releaseTags.contains(tokens[index].text))
        tokens[index].text,
  ];
  if (remaining.isNotEmpty && remaining.every(kGenericWords.contains)) {
    remaining = [];
  }
  while (remaining.length > 1 && kGenericWords.contains(remaining.first)) {
    remaining.removeAt(0);
  }
  final String key = remaining.join(' ').trim();
  if (key.isEmpty) return const TitleResult();
  final AnimeTitle? canonical = registry.resolveExact(key);
  if (canonical != null) {
    return TitleResult(key: key, display: canonical.title, matched: true, viaAlias: false, anime: canonical);
  }
  final AnimeTitle? viaAlias = registry.resolve(key);
  if (viaAlias != null) {
    return TitleResult(key: key, display: viaAlias.title, matched: true, viaAlias: true, anime: viaAlias);
  }
  return TitleResult(key: key, display: titlecase(key), matched: false, viaAlias: false);
}

/// Analyse complète d'une source de texte.
class TextAnalysis {
  const TextAnalysis(this.extraction, this.title);

  final Extraction extraction;
  final TitleResult title;

  String? get titleKey => title.key;
}

/// Pipeline complet sur une source de texte (nom de fichier ou caption).
TextAnalysis analyzeText(String text, String sourceLabel, AliasRegistry registry) {
  final List<Token> tokens = tokenize(text);
  final Extraction extraction = Extraction(source: sourceLabel);
  scanSeasonEpisode(extraction, tokens);
  scanQuality(extraction, tokens);
  scanLanguage(extraction, tokens);
  scanYear(extraction, tokens);
  scanSeasonAlone(extraction, tokens);
  scanEpisodeAlone(extraction, tokens);
  scanEpisodeSpecial(extraction, tokens);
  scanBareEpisode(extraction, tokens, registry);
  final TitleResult title = buildTitle(extraction, tokens, registry);
  return TextAnalysis(extraction, title);
}
