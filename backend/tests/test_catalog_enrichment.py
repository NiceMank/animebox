"""Tests du catalogue enrichi : recherche, récents, priorités, doublons,
corrections manuelles et traçabilité Telegram (prompt §14–§19, §28)."""

from app.analyzer.engine import RuleBasedAnalyzer
from app.analyzer.grouping import EpisodeGrouper
from app.analyzer.storage import CatalogStore
from app.catalog.priorities import best_version
from app.metadata.service import MetadataService, STATUS_FOUND
from app.metadata.local import LocalMetadataProvider


def _ingest(store: CatalogStore, texts: list[dict]) -> None:
    from app.analyzer.batch import BatchAnalyzer
    from app.analyzer.storage import AnalysisCache

    batch = BatchAnalyzer(RuleBasedAnalyzer(), cache=AnalysisCache(), store=store)
    batch.run(texts, source={"id": "s1", "channel_id": "7"})


def test_search_by_canonical_title(fresh_analyzer_db):
    store = CatalogStore()
    results = store.search_anime("Solo Leveling")
    assert results and results[0]["key"] == "solo leveling"
    assert results[0]["match"]["matched_via"] == "title"


def test_search_by_original_title(fresh_analyzer_db):
    store = CatalogStore()
    results = store.search_anime("Ore dake Level Up na Ken")
    assert results and results[0]["key"] == "solo leveling"


def test_search_by_alias(fresh_analyzer_db):
    store = CatalogStore()
    results = store.search_anime("OP")
    assert any(r["key"] == "one piece" for r in results)


def test_search_by_alternative_title(fresh_analyzer_db):
    store = CatalogStore()
    store.update_anime_metadata(
        store.find_anime_by_key_or_alias("one piece")["id"],
        {"alternative_titles": ["Wan Pisu"]},
    )
    results = store.search_anime("wan pisu")
    assert results and results[0]["key"] == "one piece"


def test_search_pagination(fresh_analyzer_db):
    store = CatalogStore()
    page = store.list_anime(offset=0, limit=5)
    assert len(page) == 5
    assert store.count_anime() >= 30
    assert store.list_anime(offset=5, limit=5)[0]["id"] != page[0]["id"]


def test_recent_episodes_and_best_version(fresh_analyzer_db):
    store = CatalogStore()
    _ingest(
        store,
        [
            {"text": "Solo Leveling S02E08 1080p VF", "media_type": "video", "file_name": "a.mkv", "file_size": 1000, "message_id": 1, "link": "https://t.me/c/1"},
            {"text": "Solo Leveling S02E08 720p VF", "media_type": "video", "file_name": "b.mkv", "file_size": 900, "message_id": 2, "link": "https://t.me/c/2"},
        ],
    )
    recent = store.recent_episodes(limit=10)
    assert recent, "un épisode récent doit apparaître"
    episode = recent[0]
    assert episode["anime_title"] == "Solo Leveling"
    assert episode["season_number"] == 2 and episode["number"] == 8
    assert episode["version_count"] == 2
    assert episode["best"]["quality"] == "1080p"
    # Les références Telegram sont conservées.
    assert episode["best"]["telegram_message_link"]


def test_priorities_quality_first():
    versions = [
        {"quality": "720p", "quality_rank": 3, "language": "french", "subtitles": None, "file_size": 100, "created_at": "2026-01-01"},
        {"quality": "1080p", "quality_rank": 4, "language": "japanese", "subtitles": "french", "file_size": 100, "created_at": "2026-01-01"},
    ]
    assert best_version(versions)["quality"] == "1080p"


def test_priorities_language_preference():
    versions = [
        {"quality": "1080p", "quality_rank": 4, "language": "japanese", "subtitles": "french", "file_size": 100, "created_at": "2026-01-01"},
        {"quality": "1080p", "quality_rank": 4, "language": "french", "subtitles": None, "file_size": 100, "created_at": "2026-01-01"},
    ]
    assert best_version(versions)["language"] == "french"  # VF préférée


def test_manual_patch_marks_manually_edited(fresh_analyzer_db):
    store = CatalogStore()
    anime = store.find_anime_by_key_or_alias("solo leveling")
    updated = store.update_anime_metadata(
        anime["id"], {"display_title": "Solo Leveling (2024)", "manually_edited": True}
    )
    assert updated["display_title"] == "Solo Leveling (2024)"
    assert updated["manually_edited"] is True


def test_duplicates_detected_on_similar_title(fresh_analyzer_db):
    store = CatalogStore()
    first, _ = store.find_or_create_anime("twin show", "Twin Show")
    second, created = store.find_or_create_anime("twin show!", "Twin Show!")
    assert created
    duplicates = store.list_duplicates(status="review_required")
    assert any(
        {d["anime_a_id"], d["anime_b_id"]} == {first["id"], second["id"]}
        for d in duplicates
    ), "fiches quasi identiques → DUPLICATE_REVIEW_REQUIRED"


def test_duplicates_not_merged_automatically(fresh_analyzer_db):
    store = CatalogStore()
    store.find_or_create_anime("twin a", "Twin A")
    store.find_or_create_anime("twin a 2", "Twin A 2")
    # Les deux fiches existent toujours : aucune fusion silencieuse.
    assert store.find_anime_by_key_or_alias("twin a") is not None
    assert store.find_anime_by_key_or_alias("twin a 2") is not None


def test_merge_manual_moves_content(fresh_analyzer_db):
    store = CatalogStore()
    target, _ = store.find_or_create_anime("merge-cible", "Merge Cible")
    source, _ = store.find_or_create_anime("merge-source", "Merge Source")
    # Un signalement de doublon existe entre les deux fiches (simulé).
    duplicate = store.add_duplicate(target["id"], source["id"], "similar_title", 0.95)
    assert duplicate is not None
    season = store.find_or_create_season(source["id"], 1)
    store.find_or_create_episode(season["id"], 3, "regular", None)
    detail = store.merge_anime(target["id"], source["id"])
    assert detail is not None
    # L'épisode a migré vers la cible.
    numbers = [e["number"] for s in detail["seasons"] for e in s["episodes"]]
    assert 3 in numbers
    # La fiche source a disparu, son ancien titre devient un alias.
    assert store.find_anime_by_key_or_alias("merge-source")["id"] == target["id"]
    # Le signalement de doublon est résolu (les autres signalements
    # éventuels de la base partagée ne sont pas concernés).
    assert not any(
        d["id"] == duplicate["id"] and d["status"] == "review_required"
        for d in store.list_duplicates(status=None)
    )
    assert any(
        d["id"] == duplicate["id"] and d["status"] == "resolved_merged"
        for d in store.list_duplicates(status=None)
    )


def test_traceability_two_sources_one_episode(fresh_analyzer_db):
    store = CatalogStore()
    _ingest(
        store,
        [
            {"text": "Solo Leveling S02E08 1080p", "media_type": "video", "file_name": "a.mkv", "file_size": 1000, "message_id": 11, "link": "https://t.me/sourcea/11", "telegram_channel_id": "chanA", "telegram_channel_username": "sourcea"},
            {"text": "Solo Leveling S02E08 480p", "media_type": "video", "file_name": "b.mkv", "file_size": 500, "message_id": 21, "link": "https://t.me/sourceb/21", "telegram_channel_id": "chanB", "telegram_channel_username": "sourceb"},
        ],
    )
    anime = store.find_anime_by_key_or_alias("solo leveling")
    detail = store.anime_detail(anime["id"])
    assert len(detail["seasons"]) == 1
    episodes = detail["seasons"][0]["episodes"]
    assert len(episodes) == 1  # un seul épisode, pas deux fiches
    versions = episodes[0]["versions"]
    assert {v["quality"] for v in versions} == {"1080p", "480p"}
    assert {v["telegram_message_link"] for v in versions} == {
        "https://t.me/sourcea/11",
        "https://t.me/sourceb/21",
    }


def test_metadata_service_on_ingested_anime(fresh_analyzer_db):
    store = CatalogStore()
    _ingest(store, [{"text": "Demon Slayer S04E07 1080p VOSTFR", "media_type": "video", "file_name": "ds.mkv", "file_size": 100, "message_id": 1, "link": "https://t.me/c/1"}])
    anime = store.find_anime_by_key_or_alias("demon slayer")
    service = MetadataService([LocalMetadataProvider()])
    enriched = service.ensure_enriched(store.get_anime_public(anime["id"]))
    assert enriched["metadata_status"] == STATUS_FOUND
    assert enriched["original_title"] == "Kimetsu no Yaiba"
    assert "Action" in enriched["genres"]


def test_group_key_single_fiche_two_sources(fresh_analyzer_db):
    """Deux sources, même épisode : une seule clé de regroupement."""
    engine = RuleBasedAnalyzer()
    grouper = EpisodeGrouper()
    for text, channel in (("Solo Leveling S02E08 1080p", "A"), ("Solo Leveling S02E08 480p", "B")):
        result = engine.analyze({"text": text, "media_type": "video", "telegram_channel_id": channel})
        grouper.add(result)
    assert len(grouper) == 1
