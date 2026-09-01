"""Tests de persistance : catalogue, cache d'analyse, travaux (étapes 21, 24)."""

from app.analyzer.aliases import AnimeTitle
from app.analyzer.batch import BatchAnalyzer
from app.analyzer.engine import RuleBasedAnalyzer
from app.analyzer.storage import (
    AnalysisCache,
    CatalogStore,
    JobStore,
    message_fingerprint,
)


def _messages():
    return [
        {
            "text": "Solo Leveling S02E08 1080p VF",
            "media_type": "video",
            "file_name": "solo-s02e08-1080p.mkv",
            "file_size": 1288490188,
            "message_id": 101,
            "link": "https://t.me/animefr/101",
        },
        {
            "text": "Solo Leveling S02E08 720p VF",
            "media_type": "video",
            "file_name": "solo-s02e08-720p.mkv",
            "file_size": 697932185,
            "message_id": 102,
            "link": "https://t.me/animefr/102",
        },
        {
            "text": "Solo Leveling S02E08 480p VOSTFR",
            "media_type": "video",
            "file_name": "solo-s02e08-480p.mkv",
            "file_size": 375809638,
            "message_id": 103,
            "link": "https://t.me/animefr/103",
        },
    ]


def test_catalog_ingest_and_reuse(fresh_analyzer_db):
    engine = RuleBasedAnalyzer()
    store = CatalogStore()
    batch = BatchAnalyzer(engine, cache=AnalysisCache(), store=store)
    source = {"id": "src1", "username": "animefr", "channel_id": "7"}

    first = batch.run(_messages(), source=source)
    assert first.new_episodes == 1
    assert first.new_versions == 3
    # Deux groupes : VF (1080p + 720p) et VOSTFR (480p).
    assert first.grouped_episodes == 2

    anime = store.find_anime_by_key_or_alias("solo leveling")
    assert anime is not None
    detail = store.anime_detail(anime["id"])
    assert len(detail["seasons"]) == 1
    assert detail["seasons"][0]["number"] == 2
    episodes = detail["seasons"][0]["episodes"]
    assert len(episodes) == 1
    assert episodes[0]["number"] == 8
    qualities = {v["quality"] for v in episodes[0]["versions"]}
    assert qualities == {"1080p", "720p", "480p"}
    assert all(v["telegram_message_link"] for v in episodes[0]["versions"])

    # Deuxième passage : tout est servi par le cache, aucune duplication.
    second = batch.run(_messages(), source=source)
    assert second.from_cache == 3
    assert second.new_versions == 0
    detail = store.anime_detail(anime["id"])
    assert len(detail["seasons"][0]["episodes"][0]["versions"]) == 3


def test_cache_fingerprint_changes(fresh_analyzer_db):
    engine = RuleBasedAnalyzer()
    cache = AnalysisCache()
    message = _messages()[0]
    fingerprint = message_fingerprint(message)
    result = engine.analyze(message)
    cache.put("7", 101, fingerprint, result.to_dict())
    hit = cache.get("7", 101)
    assert hit is not None and hit["fingerprint"] == fingerprint
    # Contenu modifié → empreinte différente.
    changed = dict(message, text="Solo Leveling S02E08 720p VF")
    assert message_fingerprint(changed) != fingerprint
    assert cache.stats()["entries"] == 1


def test_force_reanalyzes(fresh_analyzer_db):
    engine = RuleBasedAnalyzer()
    batch = BatchAnalyzer(engine, cache=AnalysisCache(), store=CatalogStore())
    batch.run(_messages(), source={"id": "s", "channel_id": "7"})
    forced = BatchAnalyzer(
        engine, cache=AnalysisCache(), store=CatalogStore(), force=True
    )
    rerun = forced.run(_messages(), source={"id": "s", "channel_id": "7"})
    assert rerun.analyzed == 3
    assert rerun.new_versions == 0  # versions déjà présentes, pas de doublon


def test_alias_persistence(fresh_analyzer_db):
    store = CatalogStore()
    anime = store.add_alias("solo leveling", "slv2")
    assert anime is not None
    assert store.find_anime_by_key_or_alias("slv2")["title"] == "Solo Leveling"


def test_anime_not_coupled_to_telegram(fresh_analyzer_db):
    store = CatalogStore()
    store.find_or_create_anime("my original", "My Original")
    anime, created = store.find_or_create_anime("my original", "My Original")
    assert not created
    assert set(anime) >= {"id", "key", "title", "release_year"}


def test_register_custom_title():
    from app.analyzer.aliases import AliasRegistry

    registry = AliasRegistry()
    registry.register(AnimeTitle("my show", "My Show", None, 2025))
    assert registry.resolve("my show").title == "My Show"


def test_jobs(fresh_analyzer_db):
    jobs = JobStore()
    jobs.create("job1", "src1", total=10)
    assert jobs.get("job1")["status"] == "running"
    assert jobs.running_count() == 1
    jobs.update("job1", status="done", processed=10, new_versions=3)
    job = jobs.get("job1")
    assert job["status"] == "done" and job["new_versions"] == 3
    assert jobs.running_count() == 0


def test_catalog_counts(fresh_analyzer_db):
    store = CatalogStore()
    counts = store.counts()
    assert counts["anime"] >= 30  # catalogue intégré seedé
    assert counts["anime_alias"] > 0


def test_duplicate_same_file_not_overwritten(fresh_analyzer_db):
    engine = RuleBasedAnalyzer()
    batch = BatchAnalyzer(engine, cache=AnalysisCache(), store=CatalogStore())
    messages = [
        {
            "text": "Solo Leveling S02E08 1080p",
            "media_type": "video",
            "file_name": "x.mkv",
            "file_size": 500,
            "message_id": 1,
        },
        {
            "text": "Solo Leveling S02E08 1080p",
            "media_type": "video",
            "file_name": "x.mkv",
            "file_size": 500,
            "message_id": 2,
        },
    ]
    result = batch.run(messages, source={"id": "s", "channel_id": "7"})
    assert result.duplicates == 1
    store = CatalogStore()
    anime = store.find_anime_by_key_or_alias("solo leveling")
    detail = store.anime_detail(anime["id"])
    versions = detail["seasons"][0]["episodes"][0]["versions"]
    assert len(versions) == 1  # jamais écrasé, mais pas dupliqué non plus
