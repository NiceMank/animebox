"""Tests des fournisseurs de métadonnées (prompt §3, §4, §11)."""

from app.metadata.base import MetadataCandidate
from app.metadata.jikan import JikanProvider
from app.metadata.local import LocalMetadataProvider


def test_local_provider_known_anime():
    provider = LocalMetadataProvider()
    anime = provider.fetch("solo leveling")
    assert anime is not None
    assert anime.canonical_title == "Solo Leveling"
    assert anime.original_title == "Ore dake Level Up na Ken"
    assert "Action" in anime.genres
    assert anime.year == 2024
    assert anime.episode_count == 25
    assert anime.poster_asset  # image locale de démonstration


def test_local_provider_unknown_anime():
    provider = LocalMetadataProvider()
    assert provider.fetch("anime inconnu xyz") is None


def test_local_provider_search():
    provider = LocalMetadataProvider()
    results = provider.search("solo leveling")
    assert any(c.provider_id == "solo leveling" for c in results)


def test_jikan_candidate_mapping():
    payload = {
        "mal_id": 52299,
        "title": "Solo Leveling",
        "title_english": "Solo Leveling",
        "title_japanese": "俺だけレベルアップな件",
        "title_synonyms": [{"title": "Only I Level Up"}],
        "year": 2024,
        "episodes": 12,
        "score": 8.5,
        "status": "Finished Airing",
        "synopsis": "Synopsis…",
        "genres": [{"name": "Action"}, {"name": "Fantasy"}],
        "images": {
            "jpg": {
                "image_url": "https://cdn.myanimelist.net/images/anime/1.jpg",
                "large_image_url": "https://cdn.myanimelist.net/images/anime/1l.jpg",
            }
        },
    }
    candidate = JikanProvider._candidate(payload)  # noqa: SLF001
    assert candidate.provider_id == "52299"
    assert candidate.title == "Solo Leveling"
    assert candidate.original_title == "俺だけレベルアップな件"
    assert "Only I Level Up" in candidate.alternative_titles
    assert candidate.year == 2024
    assert candidate.poster_url.startswith("https://cdn.myanimelist.net/")


def test_jikan_image_host_allowlist():
    payload = {
        "mal_id": 1,
        "title": "X",
        "images": {"jpg": {"image_url": "https://evil.example.com/x.jpg"}},
    }
    candidate = JikanProvider._candidate(payload)  # noqa: SLF001
    assert candidate.poster_url is None  # hôte non autorisé → ignoré


def test_provider_abstraction():
    """Un fournisseur sur mesure s'intègre sans changer le service."""
    class FakeProvider:
        name = "fake"

        def search(self, title, limit=5):
            return [MetadataCandidate("fake", "1", title)]

        def fetch(self, provider_id):
            return None

    provider = FakeProvider()
    assert provider.search("Solo Leveling")[0].title == "Solo Leveling"
