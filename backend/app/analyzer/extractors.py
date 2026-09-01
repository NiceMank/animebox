"""Extraction des attributs structurés : saison, épisode, qualité, langue,
année, titre.

Chaque détecteur travaille sur la liste de mots normalisés et marque les
mots qu'il « consomme » : le titre est ensuite reconstruit à partir des
mots restants. Cette approche évite les collisions entre les motifs
(par exemple « 1080p » ne peut jamais se retrouver dans un titre).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from . import quality
from .language import LanguageMatch, SUBTITLES_UNKNOWN, match_token, merge
from .text_utils import GENERIC_WORDS, Token, titlecase, tokenize

# ---------------------------------------------------------------------------
# Motifs (tous testés sur du texte déjà normalisé)
# ---------------------------------------------------------------------------

RE_NUMBER = re.compile(r"^\d{1,4}$")
RE_YEAR = re.compile(r"^(19|20)\d{2}$")
RE_SXE = re.compile(r"^s(\d{1,2})e(\d{1,3})$")  # s02e08
RE_CROSS = re.compile(r"^(\d{1,2})x(\d{1,3})$")  # 2x08
RE_S_ONLY = re.compile(r"^s(\d{1,2})$")  # s2
RE_E_ONLY = re.compile(r"^e(\d{1,3})$")  # e8
RE_EP_NUM = re.compile(r"^ep(\d{1,3})$")  # ep08
SEASON_WORDS = {"season", "seasons", "saison", "saisons"}
EPISODE_WORDS = {"episode", "episodes", "ep", "eps", "épisode", "épisodes", "ép"}
SPECIAL_WORDS = {"special", "spécial", "specials", "spéciaux"}

# Mots de « scène » (release tags) à retirer du titre : codecs, conteneurs,
# sources. « hd » / « fhd » / « hdrip » n'en font PAS partie (qualité).
RELEASE_TAGS = {
    "x264", "x265", "h264", "h265", "hevc", "avc", "av1", "vp9",
    "aac", "ac3", "eac3", "dts", "dtshd", "truehd", "flac", "opus",
    "10bit", "hi10", "hdr", "hdr10", "dv", "sdr",
    "webdl", "webrip", "web", "dl",
    "bluray", "bdrip", "brrip", "dvdrip", "hdtv",
    "proper", "repack", "remux", "dual", "dualaudio", "mkv", "mp4",
}

# Nombres « résolution » jamais candidats à un épisode.
_RESOLUTION_NUMBERS = {"2160", "1440", "1080", "720", "480", "360"}

SOURCE_COMBINED = "combined"  # s02e08 / 2x08 / s2 e8 / saison 2 episode 8
SOURCE_STANDALONE = "standalone"  # e08 / episode 08 seul
SOURCE_BARE = "heuristic"  # numéro seul, titre inconnu
SOURCE_BARE_KNOWN = "heuristic_known"  # numéro seul, titre reconnu au catalogue
SOURCE_SPECIAL = "special"  # « épisode spécial »


@dataclass
class Extraction:
    """Attributs détectés sur UNE source de texte (nom de fichier, caption…).

    ``source`` identifie l'origine (« file_name » / « text ») afin
    d'appliquer la stratégie de priorité au moment de la fusion.
    """

    source: str
    season: int | None = None
    episode: int | None = None
    episode_kind: str | None = None
    episode_source: str | None = None
    season_source: str | None = None
    year: int | None = None
    quality: str | None = None
    quality_original: str | None = None
    language: str | None = None
    subtitles: str | None = None
    consumed: set[int] = field(default_factory=set)
    warnings: list[str] = field(default_factory=list)

    def note(self, warning: str) -> None:
        if warning not in self.warnings:
            self.warnings.append(warning)


# ---------------------------------------------------------------------------
# Détecteurs de saison / épisode
# ---------------------------------------------------------------------------

def _is_year(token: str) -> bool:
    return bool(RE_YEAR.match(token))


def _looks_like_episode_number(token: str) -> bool:
    """Un nombre peut être un épisode s'il n'est ni une année ni une résolution."""
    if _is_year(token) or token in _RESOLUTION_NUMBERS:
        return False
    return bool(RE_NUMBER.match(token)) and int(token) <= 1999


def scan_season_episode(extraction: Extraction, tokens: list[Token]) -> None:
    """Formats combinés : S02E08, 2x08, S2 E8, S 02 E 08, Season 2 Episode 8…"""
    count = len(tokens)
    index = 0
    while index < count:
        matched: tuple[int, dict] | None = None
        token = tokens[index].text

        if (match := RE_SXE.match(token)):  # s02e08
            matched = (1, {"season": int(match.group(1)), "episode": int(match.group(2))})
        elif (match := RE_CROSS.match(token)):  # 2x08
            matched = (1, {"season": int(match.group(1)), "episode": int(match.group(2))})
        elif (match := RE_S_ONLY.match(token)):  # s2 + [e8 | 08 | episode 8]
            season = int(match.group(1))
            if index + 1 < count:
                nxt = tokens[index + 1].text
                if RE_E_ONLY.match(nxt):
                    matched = (2, {"season": season, "episode": int(nxt[1:])})
                elif _looks_like_episode_number(nxt) and not quality.spec_for_token(nxt):
                    matched = (2, {"season": season, "episode": int(nxt)})
                elif (
                    index + 2 < count
                    and nxt in EPISODE_WORDS
                    and _looks_like_episode_number(tokens[index + 2].text)
                ):
                    matched = (3, {"season": season, "episode": int(tokens[index + 2].text)})
        elif token in SEASON_WORDS:  # season 2 [episode 8]
            if index + 1 < count and _looks_like_episode_number(tokens[index + 1].text):
                season = int(tokens[index + 1].text)
                matched = (2, {"season": season, "episode": None})
                if (
                    index + 3 < count
                    and tokens[index + 2].text in EPISODE_WORDS
                    and _looks_like_episode_number(tokens[index + 3].text)
                ):
                    matched = (4, {"season": season, "episode": int(tokens[index + 3].text)})
        elif token == "s":  # s 02 e 08
            if (
                index + 3 < count
                and _looks_like_episode_number(tokens[index + 1].text)
                and tokens[index + 2].text == "e"
                and _looks_like_episode_number(tokens[index + 3].text)
            ):
                matched = (4, {
                    "season": int(tokens[index + 1].text),
                    "episode": int(tokens[index + 3].text),
                })

        if matched is not None:
            span, values = matched
            for offset in range(span):
                extraction.consumed.add(index + offset)
            if values["season"] is not None:
                if extraction.season is None:
                    extraction.season = values["season"]
                    extraction.season_source = SOURCE_COMBINED
                elif extraction.season != values["season"]:
                    extraction.note(
                        f"saisons contradictoires : {extraction.season} et {values['season']}"
                    )
            if values.get("episode") is not None:
                _set_episode(extraction, values["episode"], SOURCE_COMBINED)
            index += span
        else:
            index += 1


def scan_season_alone(extraction: Extraction, tokens: list[Token]) -> None:
    """Saison seule : « S2 », « S 01 », « Saison 2 », « Season 2 »."""
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        match = RE_S_ONLY.match(token.text)
        if match:
            extraction.consumed.add(index)
            if extraction.season is None:
                extraction.season = int(match.group(1))
                extraction.season_source = SOURCE_STANDALONE
            continue
        if token.text == "s" and index + 1 < len(tokens):
            candidate = tokens[index + 1].text
            if RE_NUMBER.match(candidate) and int(candidate) <= 99 and not _is_year(candidate):
                extraction.consumed.update((index, index + 1))
                if extraction.season is None:
                    extraction.season = int(candidate)
                    extraction.season_source = SOURCE_STANDALONE
                continue
        if token.text in SEASON_WORDS and index + 1 < len(tokens):
            candidate = tokens[index + 1].text
            if _looks_like_episode_number(candidate) and int(candidate) <= 99:
                extraction.consumed.update((index, index + 1))
                if extraction.season is None:
                    extraction.season = int(candidate)
                    extraction.season_source = SOURCE_STANDALONE


def scan_episode_alone(extraction: Extraction, tokens: list[Token]) -> None:
    """Épisode seul : « E08 », « EP08 », « Episode 08 », « Épisode 08 »."""
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        match = RE_E_ONLY.match(token.text)
        if match:
            extraction.consumed.add(index)
            _set_episode(extraction, int(match.group(1)), SOURCE_STANDALONE)
            continue
        match = RE_EP_NUM.match(token.text)
        if match:
            extraction.consumed.add(index)
            _set_episode(extraction, int(match.group(1)), SOURCE_STANDALONE)
            continue
        if token.text in EPISODE_WORDS and index + 1 < len(tokens):
            candidate = tokens[index + 1].text
            if _looks_like_episode_number(candidate):
                extraction.consumed.update((index, index + 1))
                _set_episode(extraction, int(candidate), SOURCE_STANDALONE)


def scan_episode_special(extraction: Extraction, tokens: list[Token]) -> None:
    """« Épisode spécial » : marqueur sans numéro — ne JAMAIS inventer un numéro."""
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        if token.text in EPISODE_WORDS and index + 1 < len(tokens):
            if tokens[index + 1].text in SPECIAL_WORDS:
                extraction.consumed.update((index, index + 1))
                extraction.episode_kind = "special"
                extraction.episode_source = SOURCE_SPECIAL
        elif token.text in SPECIAL_WORDS and extraction.episode_source == SOURCE_SPECIAL:
            extraction.consumed.add(index)


def _set_episode(extraction: Extraction, number: int, source: str) -> None:
    if extraction.episode is None:
        extraction.episode = number
        extraction.episode_source = source
    elif extraction.episode != number:
        extraction.note(
            f"épisodes contradictoires : {extraction.episode} et {number}"
        )


def scan_year(extraction: Extraction, tokens: list[Token]) -> None:
    """Année de sortie (jamais confondue avec un épisode)."""
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        if _is_year(token.text):
            extraction.consumed.add(index)
            if extraction.year is None:
                extraction.year = int(token.text)


def scan_quality(extraction: Extraction, tokens: list[Token]) -> None:
    """Qualité : 1080p, FHD, HD… (voir quality.py)."""
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        if token.text == "full" and index + 1 < len(tokens):
            pair = f"full {tokens[index + 1].text}"
            spec = quality.spec_for_token(pair)
            if spec is not None:
                extraction.consumed.update((index, index + 1))
                _set_quality(extraction, spec, pair)
                continue
        spec = quality.spec_for_token(token.text)
        if spec is not None:
            extraction.consumed.add(index)
            _set_quality(extraction, spec, token.text)


def _set_quality(extraction: Extraction, spec, original: str) -> None:
    if extraction.quality is None:
        extraction.quality = spec.canonical
        extraction.quality_original = original
    elif spec.rank > quality.rank_of(extraction.quality):
        extraction.quality = spec.canonical
        extraction.quality_original = original
        extraction.note("plusieurs qualités détectées, la plus haute a été retenue")
    elif spec.rank < quality.rank_of(extraction.quality):
        extraction.note("plusieurs qualités détectées, la plus haute a été retenue")


def scan_language(extraction: Extraction, tokens: list[Token]) -> None:
    """Langue audio et sous-titres (voir language.py)."""
    current: LanguageMatch | None = None
    for index, token in enumerate(tokens):
        if index in extraction.consumed:
            continue
        rule = match_token(token.text)
        if rule is None:
            continue
        # « sub fr » (deux mots) → sous-titres français.
        if rule.subtitles == SUBTITLES_UNKNOWN and index + 1 < len(tokens):
            follower = tokens[index + 1].text
            if follower in ("fr", "french", "francais", "français"):
                rule = LanguageMatch(rule.language, "french")
                extraction.consumed.add(index + 1)
            elif follower in ("en", "eng", "english"):
                rule = LanguageMatch(rule.language, "english")
                extraction.consumed.add(index + 1)
        extraction.consumed.add(index)
        if (
            current is not None
            and rule.language
            and current.language
            and rule.language != current.language
        ):
            extraction.note(f"langues contradictoires : {current.language} et {rule.language}")
        current = merge(current, rule)
    if current is not None:
        extraction.language = current.language
        extraction.subtitles = current.subtitles


def scan_bare_episode(extraction: Extraction, tokens: list[Token], registry) -> None:
    """Numéro seul (« One Piece 1124 », « Solo Leveling 08 »).

    Règles de sécurité :
    - un seul numéro candidat ;
    - jamais une année ni une résolution ;
    - jamais le tout premier mot (les chiffres peuvent faire partie du
      titre : « 86 Eighty-Six ») ;
    - le titre sans le numéro est connu du catalogue, OU le numéro suit au
      moins deux mots alphabétiques (titre inconnu → confiance réduite).
    """
    if extraction.episode is not None or extraction.episode_kind is not None:
        return
    candidates: list[tuple[int, int]] = []
    for index, token in enumerate(tokens):
        if index in extraction.consumed or index == 0:
            continue
        if not _looks_like_episode_number(token.text):
            continue
        candidates.append((index, int(token.text)))
    if len(candidates) != 1:
        return
    index, number = candidates[0]
    before = [token.text for token in tokens[:index] if token.text not in RELEASE_TAGS]
    if not before:
        return
    title_candidate = " ".join(before)
    known = registry.resolve(title_candidate) is not None
    has_word = any(not RE_NUMBER.match(word) for word in before)
    if known and has_word:
        extraction.consumed.add(index)
        _set_episode(extraction, number, SOURCE_BARE_KNOWN)
    elif has_word and len(before) >= 2 and all(not RE_NUMBER.match(word) for word in before):
        extraction.consumed.add(index)
        _set_episode(extraction, number, SOURCE_BARE)
        extraction.note("numéro d'épisode déduit sans titre connu")


# ---------------------------------------------------------------------------
# Titre
# ---------------------------------------------------------------------------

@dataclass
class TitleResult:
    key: str | None  # titre normalisé (None = aucun titre fiable)
    display: str | None  # titre affichable
    matched: bool  # reconnu dans le catalogue/alias
    via_alias: bool  # reconnu via un alias plutôt que le titre canonique
    anime: object | None  # AnimeTitle du catalogue si matched


def build_title(extraction: Extraction, tokens: list[Token], registry) -> TitleResult:
    """Reconstruit le titre à partir des mots non consommés par les détecteurs."""
    remaining = [
        tokens[index].text
        for index in range(len(tokens))
        if index not in extraction.consumed and tokens[index].text not in RELEASE_TAGS
    ]
    # Un titre ne peut pas être composé uniquement de mots génériques
    # (« disponible », « nouvel épisode »…) ; les mots génériques en tête
    # sont retirés (« de Solo Leveling » → « Solo Leveling »).
    if remaining and all(word in GENERIC_WORDS for word in remaining):
        remaining = []
    while len(remaining) > 1 and remaining[0] in GENERIC_WORDS:
        remaining.pop(0)
    key = " ".join(remaining).strip()
    if not key:
        return TitleResult(None, None, False, False, None)
    canonical = registry.resolve_exact(key)
    if canonical is not None:
        return TitleResult(key, canonical.title, True, False, canonical)
    via_alias = registry.resolve(key)
    if via_alias is not None:
        return TitleResult(key, via_alias.title, True, True, via_alias)
    return TitleResult(key, titlecase(key), False, False, None)


# ---------------------------------------------------------------------------
# Analyse complète d'une source de texte
# ---------------------------------------------------------------------------

@dataclass
class TextAnalysis:
    extraction: Extraction
    title: TitleResult

    @property
    def title_key(self) -> str | None:
        return self.title.key


def analyze_text(text: str, source_label: str, registry) -> TextAnalysis:
    """Pipeline complet sur une source de texte (nom de fichier ou caption)."""
    tokens = tokenize(text)
    extraction = Extraction(source=source_label)
    scan_season_episode(extraction, tokens)
    scan_quality(extraction, tokens)
    scan_language(extraction, tokens)
    scan_year(extraction, tokens)
    scan_season_alone(extraction, tokens)
    scan_episode_alone(extraction, tokens)
    scan_episode_special(extraction, tokens)
    # Numéro seul : décidé par rapport au titre reconstruit sans lui.
    scan_bare_episode(extraction, tokens, registry)
    title = build_title(extraction, tokens, registry)
    return TextAnalysis(extraction=extraction, title=title)
