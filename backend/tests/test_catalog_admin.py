"""Correction manuelle (admin) : associer un candidat, ignorer, reclasser
une publication (prompt §12 « Correction manuelle (admin) »)."""

from app.analyzer.storage import CatalogStore
from app.metadata.local import LocalMetadataProvider
from app.metadata.service import (
    STATUS_FOUND,
    STATUS_IGNORED,
    MetadataService,
)


def test_apply_candidate_associates_explicitly(fresh_analyzer_db):
    store = CatalogStore()
    provider = LocalMetadataProvider()
    # « Ore dake » avec le fournisseur local → correspondance incertaine
    # possible seulement si le titre est proche ; on simule une revue en
    # créant une fiche dont le fournisseur ne connaît pas le titre.
    anime, _ = store.find_or_create_anime("sl-variante", "Solo Leveling 2nd Season")
    service = MetadataService([provider])
    enriched = service.enrich(store.get_anime_public(anime["id"]))
    assert enriched["metadata_status"] != STATUS_FOUND  # pas d'association auto ici

    # L'admin associe explicitement le bon candidat (titre canonique).
    candidate = provider.search("Solo Leveling")[0]
    updated = service.apply_candidate(anime, candidate.provider_id, candidate.provider)
    assert updated is not None
    assert updated["metadata_status"] == STATUS_FOUND
    assert updated["display_title"] == "Solo Leveling"
    assert updated["manually_edited"] is True  # gel de l'enrichissement auto


def test_ignore_closes_review(fresh_analyzer_db):
    store = CatalogStore()
    anime, _ = store.find_or_create_anime("ignore-moi", "Ignore Moi")
    service = MetadataService([LocalMetadataProvider()])
    service.enrich(store.get_anime_public(anime["id"]))
    updated = service.ignore_anime(anime)
    assert updated["metadata_status"] == STATUS_IGNORED
    # La fiche reste intacte (le contenu Telegram n'est jamais supprimé).
    assert updated["canonical_title"] == "Ignore Moi"


def test_reassign_version_moves_publication(fresh_analyzer_db):
    from types import SimpleNamespace

    store = CatalogStore()
    anime, _ = store.find_or_create_anime("reclasser", "Reclasser")
    season = store.find_or_create_season(anime["id"], 1)
    episode, _ = store.find_or_create_episode(season["id"], 5, "regular", None)
    store.upsert_version(
        episode["id"],
        SimpleNamespace(
            telegram_message_id=42,
            telegram_channel_id="s1",
            telegram_message_link="https://t.me/c/42",
            file_name="reclasser.e05.mkv",
            file_size=100,
            quality="1080p",
            quality_rank=4,
            language="french",
            subtitles=None,
            media_type="video",
            mime_type=None,
            duration=None,
            width=None,
            height=None,
        ),
    )
    detail = store.anime_detail(anime["id"])
    version_id = detail["seasons"][0]["episodes"][0]["versions"][0]["id"]

    # Reclassement vers la saison 2, épisode 7 (créés à la volée).
    updated = store.reassign_version(version_id, season_number=2, episode_number=7)
    assert updated is not None
    detail = store.anime_detail(anime["id"])
    season2 = next(s for s in detail["seasons"] if s["number"] == 2)
    assert any(e["number"] == 7 and e["version_count"] == 1 for e in season2["episodes"])
    # La publication d'origine est conservée (aucune suppression).
    season1 = next(s for s in detail["seasons"] if s["number"] == 1)
    assert any(e["number"] == 5 and e["version_count"] == 0 for e in season1["episodes"])
