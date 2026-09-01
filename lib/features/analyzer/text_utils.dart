/// Normalisation de texte — port fidèle du moteur Python
/// (`backend/app/analyzer/text_utils.py`).
///
/// Toutes les variantes de casse et de séparateurs sont réduites à une forme
/// canonique unique avant détection :
///
///     Solo_Leveling_S02_E08_1080p   →  solo leveling s 02 e 08 1080p
///     Solo.Leveling.S02E08.1080p    →  solo leveling s02e08 1080p
///     SOLO LEVELING 08 VOSTFR       →  solo leveling 08 vostfr
library;

/// Mots génériques qui ne peuvent pas constituer un titre à eux seuls.
const Set<String> kGenericWords = {
  'disponible', 'available', 'nouvel', 'nouveau', 'nouvelle', 'new',
  'sortie', 'dispo', 'bonus', 'bientot', 'bientôt', 'soon', 'up', 'de',
  'du', 'episode', 'épisode', 'special', 'spécial',
};

final RegExp _separatorRe = RegExp(r'[\u00B7\u2022._\u2010-\u2014-]+');
final RegExp _bracketsRe = RegExp(r'[\[\]\(\){}<>«»"\u201C\u201D]+');
final RegExp _punctRe = RegExp(r"[^0-9a-zàâäçéèêëîïôöùûüÿœæ\s]+");
final RegExp _wsRe = RegExp(r'\s+');

/// Pliage Unicode restreint : équivalents pleine chasse → ASCII (NFKC
/// partiel, suffisant pour les noms de fichiers).
const Map<String, String> _fullWidth = {
  'ａ': 'a', 'ｂ': 'b', 'ｃ': 'c', 'ｄ': 'd', 'ｅ': 'e', 'ｆ': 'f', 'ｇ': 'g',
  'ｈ': 'h', 'ｉ': 'i', 'ｊ': 'j', 'ｋ': 'k', 'ｌ': 'l', 'ｍ': 'm', 'ｎ': 'n',
  'ｏ': 'o', 'ｐ': 'p', 'ｑ': 'q', 'ｒ': 'r', 'ｓ': 's', 'ｔ': 't', 'ｕ': 'u',
  'ｖ': 'v', 'ｗ': 'w', 'ｘ': 'x', 'ｙ': 'y', 'ｚ': 'z',
  '０': '0', '１': '1', '２': '2', '３': '3', '４': '4',
  '５': '5', '６': '6', '７': '7', '８': '8', '９': '9',
};

String _foldWidth(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    final String character = String.fromCharCode(rune);
    buffer.write(_fullWidth[character] ?? character);
  }
  return buffer.toString();
}

/// Normalise un texte libre pour la détection de motifs.
String normalize(String? text) {
  if (text == null || text.isEmpty) return '';
  String value = _foldWidth(text.toLowerCase());
  value = value.replaceAll(_separatorRe, ' ');
  value = value.replaceAll(_bracketsRe, ' ');
  value = value.replaceAll(_punctRe, ' ');
  return value.replaceAll(_wsRe, ' ').trim();
}

/// Mot normalisé avec sa position dans le texte normalisé.
class Token {
  const Token(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;

  @override
  String toString() => 'Token($text@$start)';
}

/// Découpe le texte normalisé en mots.
List<Token> tokenize(String normalizedText) {
  final List<Token> tokens = [];
  for (final Match match in RegExp(r'\S+').allMatches(normalizedText)) {
    tokens.add(Token(match.group(0)!, match.start, match.end));
  }
  return tokens;
}

/// Rejoint des mots en texte normalisé.
String tokensToText(List<Token> tokens) => tokens.map((Token t) => t.text).join(' ');

/// Reconstruit un affichage propre (« solo leveling » → « Solo Leveling »).
String titlecase(String? text) {
  const Set<String> small = {
    'of', 'the', 'a', 'an', 'in', 'on', 'and', 'et', 'for', 'to',
    'de', 'la', 'le', 'les', 'des', 'du', 's',
  };
  final List<String> words = (text ?? '').split(' ');
  final List<String> out = [];
  for (int index = 0; index < words.length; index++) {
    final String word = words[index];
    if (small.contains(word) && index != 0 && index != words.length - 1) {
      out.add(word);
    } else if (word.isNotEmpty) {
      out.add('${word[0].toUpperCase()}${word.substring(1)}');
    } else {
      out.add(word);
    }
  }
  return out.join(' ');
}

/// Retire l'extension d'un nom de fichier avant analyse.
String? stripExtension(String? fileName) {
  if (fileName == null || fileName.isEmpty) return null;
  final int dot = fileName.lastIndexOf('.');
  return dot == -1 ? fileName : fileName.substring(0, dot);
}
