"""Tests du service d'enrichissement (prompt §5, §11, §12, §13).

Chaque test utilise des clés d'animé uniques : la base SQLite est partagée
entre tous les tests de la session.
"""

from datetime import datetime, timedelta, timezone

from app.analyzer.storage import CatalogStore
from app.metadata.base import MetadataAnime, MetadataCandidate, MetadataEpisode, MetadataProvider
from app.metadata.service import MetadataService, STATUS_FOUND, STATUS_NOT_FOUND, STATUS_REVIEW_REQUIRED


class FakeProvider(MetadataProvider):
    """Fournisseur contrôlé : catalogue fixe + compteur d'appels."""

    name = "fake"

    def __init__(self, catalogue: dict[str, MetadataAnime] | None = None):
        self.catalogue = catalogue or {}
        self.search_calls = 0
        self.fetch_calls = 0

    def search(self, title: str, limit: int = 5) -> list[MetadataCandidate]:
        self.search_calls += 1
        results = []
        for provider_id, anime in self.catalogue.items():
            if title.lower() in anime.canonical_title.lower() or anime.canonical_title.lower() in title.lower():
                results.append(
                    MetadataCandidate(
                        provider="fake",
                        provider_id=provider_id,
                        title=anime.canonical_title,
                        original_title=anime.original_title,
                        alternative_titles=anime.alternative_titles,
                        year=anime.year,
                        season_count=anime.season_count,
                        episode_count=anime.episode_count,
                        genres=anime.genres,
                        synopsis=anime.synopsis,
                        status=anime.status,
                        rating=anime.rating,
                    )
                )
        return results[:limit]

    def fetch(self, provider_id: str) -> MetadataAnime | None:
        self.fetch_calls += 1
        return self.catalogue.get(provider_id)

    def fetch_episodes(self, provider_id: str) -> tuple[MetadataEpisode, ...]:
        anime = self.catalogue.get(provider_id)
        return anime.episodes if anime else ()


def _full_anime(provider_id: str, title: str, *, episodes: tuple[MetadataEpisode, ...] = ()) -> MetadataAnime:
    return MetadataAnime(
        provider="fake",
        provider_id=provider_id,
        canonical_title=title,
        original_title=None,
        alternative_titles=(),
        synopsis="Synopsis de démonstration.",
        genres=("Action",),
        year=2024,
        status="completed",
        season_count=1,
        episode_count=12,
        rating=8.0,
        episodes=episodes,
    )


def _fresh_row(store: CatalogStore, key: str, title: str) -> dict:
    anime, _ = store.find_or_create_anime(key, title)
    return store.get_anime_public(anime["id"])


def test_enrich_found(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Trouve Exemple")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-trouve-exemple", "Trouve Exemple")
    enriched = service.enrich(row)
    assert enriched["metadata_status"] == STATUS_FOUND
    assert enriched["display_title"] == "Trouve Exemple"
    assert enriched["synopsis"] == "Synopsis de démonstration."
    assert enriched["genres"] == ["Action"]
    assert enriched["year"] == 2024
    assert enriched["metadata_source"] == "fake"
    assert enriched["metadata_updated_at"] is not None
    assert enriched["metadata_confidence"] >= 0.85


def test_enrich_review_required(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Revue Exemple 2024")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-revue-exemple", "Revue Exemple")
    enriched = service.enrich(row)
    assert enriched["metadata_status"] == STATUS_REVIEW_REQUIRED
    assert enriched["metadata_candidates"], "les candidats doivent être conservés pour revue"
    assert enriched["metadata_confidence"] < 0.85
    # Rien n'est associé : pas de fiche complète écrasée.
    assert enriched["display_title"] == "Revue Exemple"


def test_enrich_not_found_keeps_minimal_fiche(fresh_analyzer_db):
    store = CatalogStore()
    service = MetadataService([FakeProvider()])
    row = _fresh_row(store, "svc-inconnu-total", "Inconnu Total")
    enriched = service.enrich(row)
    assert enriched["metadata_status"] == STATUS_NOT_FOUND
    # Le contenu Telegram n'est jamais perdu : la fiche minimale demeure.
    assert enriched["canonical_title"] == "Inconnu Total"


def test_ttl_cache_avoids_refetch(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Cache Exemple")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-cache-exemple", "Cache Exemple")
    service.enrich(row)
    calls = provider.search_calls
    service.ensure_enriched(store.get_anime_public(row["id"]))
    service.ensure_enriched(store.get_anime_public(row["id"]))
    assert provider.search_calls == calls  # cache : aucune nouvelle recherche


def test_ttl_expiry_triggers_refresh(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Expiration Exemple")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-expiration-exemple", "Expiration Exemple")
    service.enrich(row)
    # Vieillissement artificiel : metadata_updated_at dans le passé.
    stale = datetime.now(timezone.utc) - timedelta(days=service.ttl.days + 2)
    store.update_anime_metadata(row["id"], {"metadata_updated_at": stale.isoformat()})
    public = store.get_anime_public(row["id"])
    calls = provider.search_calls
    service.ensure_enriched(public)
    assert provider.search_calls == calls + 1  # cache expiré → re-vérification


def test_force_refresh(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Force Exemple")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-force-exemple", "Force Exemple")
    service.enrich(row)
    calls = provider.search_calls
    service.enrich(store.get_anime_public(row["id"]), force=True)
    assert provider.search_calls == calls + 1


def test_manual_edit_blocks_auto_enrich(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Manuel Exemple")})
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-manuel-exemple", "Manuel Exemple")
    store.update_anime_metadata(
        row["id"], {"manually_edited": True, "display_title": "Mon Titre Corrigé"}
    )
    calls = provider.search_calls
    enriched = service.enrich(store.get_anime_public(row["id"]))
    assert provider.search_calls == calls  # pas d'enrichissement auto
    assert enriched["display_title"] == "Mon Titre Corrigé"
    # Le rafraîchissement forcé reste possible (administration).
    service.enrich(store.get_anime_public(row["id"]), force=True)
    assert provider.search_calls == calls + 1


def test_episode_titles_filled_never_invented(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({
        "p1": _full_anime(
            "p1",
            "Titres Exemple",
            episodes=(
                MetadataEpisode(8, title="The New Power"),
                MetadataEpisode(9, title=None),  # absent chez le fournisseur
            ),
        )
    })
    service = MetadataService([provider])
    row = _fresh_row(store, "svc-titres-exemple", "Titres Exemple")
    anime, _ = store.find_or_create_anime("svc-titres-exemple", "Titres Exemple")
    season = store.find_or_create_season(anime["id"], 2)
    store.find_or_create_episode(season["id"], 8, "regular", None)
    store.find_or_create_episode(season["id"], 9, "regular", None)
    service.enrich(row)
    detail = store.anime_detail(anime["id"])
    episodes = {e["number"]: e for e in detail["seasons"][0]["episodes"]}
    assert episodes[8]["title"] == "The New Power"  # titre officiel appliqué
    assert episodes[9]["title"] is None  # jamais inventé → « Épisode 9 »


def test_same_provider_id_flags_duplicate(fresh_analyzer_db):
    store = CatalogStore()
    provider = FakeProvider({"p1": _full_anime("p1", "Doublon Fournisseur")})
    service = MetadataService([provider])
    first = _fresh_row(store, "svc-doublon-a", "Doublon Fournisseur")
    assert service.enrich(first)["metadata_status"] == STATUS_FOUND
    # Une seconde fiche renvoie vers le même identifiant fournisseur.
    provider.catalogue["p1"] = _full_anime("p1", "Doublon Fournisseur Bis")
    second = _fresh_row(store, "svc-doublon-b", "Doublon Fournisseur Bis")
    assert service.enrich(second)["metadata_status"] == STATUS_FOUND
    duplicates = store.list_duplicates(status="review_required")
    assert any(d["reason"] == "same_provider_id" for d in duplicates)


def test_provider_failure_falls_back(fresh_analyzer_db):
    store = CatalogStore()

    class BrokenProvider(FakeProvider):
        name = "broken"

        def search(self, title: str, limit: int = 5):
            raise RuntimeError("boom")

    good = FakeProvider({"p1": _full_anime("p1", "Repli Exemple")})
    # Le service tente le fournisseur cassé puis le suivant.
    service = MetadataService([BrokenProvider(), good])
    row = _fresh_row(store, "svc-repli-exemple", "Repli Exemple")
    enriched = service.enrich(row)
    assert enriched["metadata_status"] == STATUS_FOUND
