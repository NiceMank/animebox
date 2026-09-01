"""Catalogue de titres et système d'alias.

Un même animé peut être annoncé sous plusieurs noms :

    Solo Leveling  ←  « Ore dake Level Up na Ken »
    One Piece      ←  « OP »

Le registre compare des formes NORMALISÉES : la résolution d'un titre est
donc insensible à la casse, aux séparateurs et aux accents. Les alias
personnalisés peuvent être ajoutés en base (table anime_alias) et rechargés.
"""

from __future__ import annotations

from dataclasses import dataclass

from .text_utils import normalize


@dataclass(frozen=True)
class AnimeTitle:
    key: str  # forme normalisée du titre canonique
    title: str  # titre affichable
    original_title: str | None = None
    release_year: int | None = None


# Catalogue intégré (démo / tests). Il est aussi seedé en base au démarrage
# du backend et peut être étendu par des alias personnalisés.
BUILTIN_CATALOG: tuple[AnimeTitle, ...] = tuple(
    AnimeTitle(key, title, original, year)
    for key, title, original, year in (
        ("solo leveling", "Solo Leveling", "Ore dake Level Up na Ken", 2024),
        ("one piece", "One Piece", None, 1999),
        ("jujutsu kaisen", "Jujutsu Kaisen", None, 2020),
        ("demon slayer", "Demon Slayer", "Kimetsu no Yaiba", 2019),
        ("attack on titan", "Attack on Titan", "Shingeki no Kyojin", 2013),
        ("86 eighty six", "86 Eighty-Six", None, 2021),
        ("jojo s bizarre adventure", "JoJo's Bizarre Adventure", None, 2012),
        ("classroom of the elite", "Classroom of the Elite", None, 2017),
        ("my hero academia", "My Hero Academia", "Boku no Hero Academia", 2016),
        ("naruto", "Naruto", None, 2002),
        ("bleach", "Bleach", None, 2004),
        ("one punch man", "One Punch Man", None, 2015),
        ("fullmetal alchemist brotherhood", "Fullmetal Alchemist: Brotherhood", None, 2009),
        ("steins gate", "Steins;Gate", None, 2011),
        ("tokyo ghoul", "Tokyo Ghoul", None, 2014),
        ("chainsaw man", "Chainsaw Man", None, 2022),
        ("spy x family", "Spy x Family", None, 2022),
        ("death note", "Death Note", None, 2006),
        ("vinland saga", "Vinland Saga", None, 2019),
        ("black clover", "Black Clover", None, 2017),
        ("dragon ball z", "Dragon Ball Z", None, 1989),
        ("hunter x hunter", "Hunter x Hunter", None, 2011),
        ("mob psycho 100", "Mob Psycho 100", None, 2016),
        ("re zero", "Re:Zero", "Re:Zero kara Hajimeru Isekai Seikatsu", 2016),
        ("konosuba", "KonoSuba", None, 2016),
        ("overlord", "Overlord", None, 2015),
        ("sword art online", "Sword Art Online", None, 2012),
        ("tokyo revengers", "Tokyo Revengers", None, 2021),
        ("blue lock", "Blue Lock", None, 2022),
        ("haikyu", "Haikyu!!", None, 2014),
        ("frieren beyond journey s end", "Frieren: Beyond Journey's End", "Sousou no Frieren", 2023),
    )
)

# Alias intégrés par titre canonique (formes normalisées).
BUILTIN_ALIASES: dict[str, tuple[str, ...]] = {
    "solo leveling": ("ore dake level up na ken", "only i level up", "sl"),
    "one piece": ("op", "wan pisu", "wanpisu"),
    "jujutsu kaisen": ("jjk", "sorcery fight"),
    "demon slayer": ("kimetsu no yaiba", "ds", "demon slayer kimetsu no yaiba"),
    "attack on titan": ("shingeki no kyojin", "snk", "aot"),
    "86 eighty six": ("86", "eighty six"),
    "jojo s bizarre adventure": ("jojo", "jojo no kimyou na bouken"),
    "classroom of the elite": ("youkoso jitsuryoku shijou shugi no kyoushitsu e", "cote"),
    "my hero academia": ("boku no hero academia", "mha"),
    "one punch man": ("opm", "wanpanman"),
    "fullmetal alchemist brotherhood": ("fma", "fmab", "fullmetal alchemist"),
    "steins gate": ("steinsgate",),
    "chainsaw man": ("csm",),
    "spy x family": ("spy family", "spyxfamily"),
    "dragon ball z": ("dbz", "dragonball z"),
    "hunter x hunter": ("hxh", "hunter hunter", "hunterxhunter"),
    "mob psycho 100": ("mob psycho",),
    "re zero": ("rezero", "rezero kara hajimeru isekai seikatsu"),
    "sword art online": ("sao",),
    "haikyu": ("haikyuu", "haikyū"),
    "frieren beyond journey s end": ("sousou no frieren", "frieren"),
}


class AliasRegistry:
    """Résolution titre normalisé → titre canonique (avec alias)."""

    def __init__(self, catalog: tuple[AnimeTitle, ...] | None = None):
        self._canonical: dict[str, AnimeTitle] = {}
        self._aliases: dict[str, AnimeTitle] = {}
        for title in catalog if catalog is not None else BUILTIN_CATALOG:
            self.register(title)
        for key, aliases in BUILTIN_ALIASES.items():
            canonical = self._canonical.get(key)
            if canonical is not None:
                self.register_aliases(canonical, aliases)

    def register(self, title: AnimeTitle) -> None:
        self._canonical[normalize(title.title)] = title
        if title.key and title.key != normalize(title.title):
            self._canonical[title.key] = title

    def register_aliases(self, title: AnimeTitle, aliases) -> None:
        for alias in aliases:
            self._aliases[normalize(alias)] = title

    def resolve(self, normalized_text: str) -> AnimeTitle | None:
        """Résout une forme normalisée (titre canonique ou alias)."""
        key = normalize(normalized_text)
        return self._canonical.get(key) or self._aliases.get(key)

    def resolve_exact(self, normalized_text: str) -> AnimeTitle | None:
        """Résolution sans passer par les alias (titre canonique uniquement)."""
        return self._canonical.get(normalize(normalized_text))

    def __len__(self) -> int:
        return len(self._canonical)
