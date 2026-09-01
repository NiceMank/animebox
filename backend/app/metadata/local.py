"""Fournisseur local : fiches intégrées (démo, tests, hors-ligne).

Aucune requête réseau. Les fiches couvrent le catalogue intégré du moteur ;
un titre inconnu renvoie simplement « aucune correspondance » (le contenu
Telegram n'est jamais perdu : une fiche minimale est conservée).

Les données sont factuelles (années, genres, statuts, nombres d'épisodes
indicatifs). Aucun titre d'épisode n'est inventé : les fiches n'en
fournissent pas — l'interface affiche alors « Épisode N ».
"""

from __future__ import annotations

from ..analyzer.text_utils import normalize
from .base import MetadataAnime, MetadataCandidate, MetadataProvider

# Fiches locales par clé du catalogue (titre normalisé).
_LOCAL = {
    "solo leveling": dict(
        provider_id="solo leveling",
        original_title="Ore dake Level Up na Ken",
        alternative_titles=("Only I Level Up",),
        synopsis=(
            "Dix ans après l'apparition de portails reliant notre monde à des donjons "
            "remplis de monstres, Sung Jinwoo, le chasseur le plus faible de l'humanité, "
            "survit de justesse à un donjon maudit et obtient un pouvoir unique : un "
            "système qui lui permet de devenir plus fort sans limite."
        ),
        genres=("Action", "Aventure", "Fantastique"),
        year=2024,
        status="completed",
        season_count=2,
        episode_count=25,
        rating=8.8,
        duration_min=24,
        poster_asset="assets/img/poster_solo_leveling.png",
        backdrop_asset="assets/img/backdrop_solo_leveling.png",
    ),
    "one piece": dict(
        provider_id="one piece",
        original_title=None,
        alternative_titles=("OP",),
        synopsis=(
            "Monkey D. Luffy, un jeune garçon devenu élastique après avoir mangé un fruit "
            "du démon, parcourt les mers avec son équipage à la recherche du One Piece, le "
            "trésor légendaire qui fera de lui le Roi des Pirates."
        ),
        genres=("Action", "Aventure", "Comédie", "Fantastique"),
        year=1999,
        status="ongoing",
        season_count=1,
        episode_count=1124,
        rating=8.9,
        duration_min=24,
        poster_asset="assets/img/poster_one_piece.png",
        backdrop_asset="assets/img/backdrop_one_piece.png",
    ),
    "jujutsu kaisen": dict(
        provider_id="jujutsu kaisen",
        original_title="Jujutsu Kaisen",
        alternative_titles=("JJK",),
        synopsis=(
            "Yuji Itadori avale un doigt maudit pour sauver ses camarades et devient "
            "l'hôte de Ryomen Sukuna, le roi des fléaux. Recruté par l'école d'exorcisme "
            "de Tokyo, il apprend à combattre les malédictions aux côtés d'autres sorciers."
        ),
        genres=("Action", "Fantastique", "Surnaturel"),
        year=2020,
        status="completed",
        season_count=2,
        episode_count=47,
        rating=8.6,
        duration_min=24,
        poster_asset="assets/img/poster_jujutsu_kaisen.png",
        backdrop_asset="assets/img/backdrop_jujutsu_kaisen.png",
    ),
    "demon slayer": dict(
        provider_id="demon slayer",
        original_title="Kimetsu no Yaiba",
        alternative_titles=("DS",),
        synopsis=(
            "Après le massacre de sa famille par un démon, Tanjiro Kamado devient "
            "pourfendeur de démons pour rendre à sa sœur Nezuko, transformée en démon, "
            "son humanité — et venger les siens."
        ),
        genres=("Action", "Aventure", "Fantastique", "Historique"),
        year=2019,
        status="ongoing",
        season_count=4,
        episode_count=63,
        rating=8.7,
        duration_min=24,
        poster_asset="assets/img/poster_demon_slayer.png",
        backdrop_asset="assets/img/backdrop_demon_slayer.png",
    ),
    "attack on titan": dict(
        provider_id="attack on titan",
        original_title="Shingeki no Kyojin",
        alternative_titles=(),
        synopsis=None,
        genres=("Action", "Drame", "Fantastique"),
        year=2013,
        status="completed",
        season_count=4,
        episode_count=94,
        rating=9.0,
    ),
    "naruto": dict(provider_id="naruto", genres=("Action", "Aventure"), year=2002, status="completed", season_count=5, episode_count=220, rating=8.0),
    "bleach": dict(provider_id="bleach", genres=("Action", "Surnaturel"), year=2004, status="completed", season_count=17, episode_count=366, rating=8.1),
    "one punch man": dict(provider_id="one punch man", genres=("Action", "Comédie"), year=2015, status="ongoing", season_count=2, episode_count=24, rating=8.7),
    "death note": dict(provider_id="death note", genres=("Thriller", "Psychologique"), year=2006, status="completed", season_count=1, episode_count=37, rating=8.9),
    "my hero academia": dict(provider_id="my hero academia", original_title="Boku no Hero Academia", genres=("Action", "Fantastique"), year=2016, status="ongoing", season_count=7, episode_count=159, rating=8.2),
    "chainsaw man": dict(provider_id="chainsaw man", genres=("Action", "Fantastique"), year=2022, status="ongoing", season_count=1, episode_count=12, rating=8.4),
    "dragon ball z": dict(provider_id="dragon ball z", genres=("Action", "Aventure"), year=1989, status="completed", season_count=9, episode_count=291, rating=8.7),
    "tokyo ghoul": dict(provider_id="tokyo ghoul", genres=("Action", "Horreur", "Psychologique"), year=2014, status="completed", season_count=4, episode_count=48, rating=7.8),
    "hunter x hunter": dict(provider_id="hunter x hunter", genres=("Action", "Aventure"), year=2011, status="completed", season_count=1, episode_count=148, rating=9.1),
    "sword art online": dict(provider_id="sword art online", genres=("Action", "Aventure", "Romance"), year=2012, status="ongoing", season_count=4, episode_count=100, rating=7.5),
    "fullmetal alchemist brotherhood": dict(provider_id="fullmetal alchemist brotherhood", genres=("Action", "Aventure", "Fantastique"), year=2009, status="completed", season_count=1, episode_count=64, rating=9.2),
    "steins gate": dict(provider_id="steins gate", genres=("Science-fiction", "Thriller"), year=2011, status="completed", season_count=1, episode_count=24, rating=9.2),
    "classroom of the elite": dict(provider_id="classroom of the elite", genres=("Drame", "Psychologique"), year=2017, status="ongoing", season_count=3, episode_count=38, rating=8.1),
    "jojo s bizarre adventure": dict(provider_id="jojo s bizarre adventure", genres=("Action", "Aventure"), year=2012, status="ongoing", season_count=6, episode_count=190, rating=8.5),
    "86 eighty six": dict(provider_id="86 eighty six", original_title="86", genres=("Action", "Drame", "Science-fiction"), year=2021, status="completed", season_count=1, episode_count=23, rating=8.4),
    "black clover": dict(provider_id="black clover", genres=("Action", "Fantastique"), year=2017, status="completed", season_count=1, episode_count=170, rating=8.1),
    "mob psycho 100": dict(provider_id="mob psycho 100", genres=("Action", "Comédie", "Surnaturel"), year=2016, status="completed", season_count=3, episode_count=37, rating=8.6),
    "re zero": dict(provider_id="re zero", original_title="Re:Zero kara Hajimeru Isekai Seikatsu", genres=("Fantastique", "Psychologique"), year=2016, status="ongoing", season_count=3, episode_count=75, rating=8.4),
    "konosuba": dict(provider_id="konosuba", genres=("Comédie", "Fantastique"), year=2016, status="ongoing", season_count=3, episode_count=31, rating=8.1),
    "overlord": dict(provider_id="overlord", genres=("Action", "Fantastique"), year=2015, status="ongoing", season_count=4, episode_count=52, rating=7.9),
    "tokyo revengers": dict(provider_id="tokyo revengers", genres=("Action", "Drame"), year=2021, status="ongoing", season_count=3, episode_count=50, rating=7.9),
    "blue lock": dict(provider_id="blue lock", genres=("Sport"), year=2022, status="ongoing", season_count=2, episode_count=38, rating=8.2),
    "haikyu": dict(provider_id="haikyu", genres=("Sport", "Comédie"), year=2014, status="ongoing", season_count=4, episode_count=85, rating=8.7),
    "frieren beyond journey s end": dict(provider_id="frieren beyond journey s end", original_title="Sousou no Frieren", alternative_titles=("Frieren",), genres=("Aventure", "Drame", "Fantastique"), year=2023, status="ongoing", season_count=1, episode_count=28, rating=9.3),
    "spy x family": dict(provider_id="spy x family", genres=("Action", "Comédie"), year=2022, status="ongoing", season_count=2, episode_count=37, rating=8.6),
    "vinland saga": dict(provider_id="vinland saga", genres=("Action", "Drame", "Historique"), year=2019, status="ongoing", season_count=2, episode_count=48, rating=8.8),
}


def _candidate_from_entry(key: str, entry: dict) -> MetadataCandidate:
    return MetadataCandidate(
        provider="local",
        provider_id=key,
        title=" ".join(part.capitalize() for part in key.split()),
        original_title=entry.get("original_title"),
        alternative_titles=tuple(entry.get("alternative_titles", ())),
        year=entry.get("year"),
        season_count=entry.get("season_count"),
        episode_count=entry.get("episode_count"),
        genres=tuple(entry.get("genres", ())),
        synopsis=entry.get("synopsis"),
        status=entry.get("status"),
        rating=entry.get("rating"),
        poster_url=entry.get("poster_url"),
        backdrop_url=entry.get("backdrop_url"),
    )


class LocalMetadataProvider(MetadataProvider):
    """Fiches intégrées — jamais de réseau, jamais de secret."""

    name = "local"

    def search(self, title: str, limit: int = 5) -> list[MetadataCandidate]:
        query = normalize(title)
        if not query:
            return []
        results: list[MetadataCandidate] = []
        for key, entry in _LOCAL.items():
            if query in key or key in query:
                results.append(_candidate_from_entry(key, entry))
        results.sort(key=lambda candidate: -len(candidate.title))
        return results[:limit]

    def fetch(self, provider_id: str) -> MetadataAnime | None:
        entry = _LOCAL.get(normalize(provider_id))
        if entry is None:
            return None
        return MetadataAnime(
            provider="local",
            provider_id=normalize(provider_id),
            canonical_title=" ".join(part.capitalize() for part in normalize(provider_id).split()),
            original_title=entry.get("original_title"),
            alternative_titles=tuple(entry.get("alternative_titles", ())),
            synopsis=entry.get("synopsis"),
            genres=tuple(entry.get("genres", ())),
            year=entry.get("year"),
            status=entry.get("status"),
            season_count=entry.get("season_count"),
            episode_count=entry.get("episode_count"),
            rating=entry.get("rating"),
            duration_min=entry.get("duration_min"),
            poster_url=entry.get("poster_url"),
            backdrop_url=entry.get("backdrop_url"),
            poster_asset=entry.get("poster_asset"),
            backdrop_asset=entry.get("backdrop_asset"),
        )
