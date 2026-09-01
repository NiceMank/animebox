"""Tests de regroupement (étapes 13, 14 et 27)."""

from app.analyzer.engine import RuleBasedAnalyzer
from app.analyzer.grouping import EpisodeGrouper


def analyze(text: str, **extra):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video", **extra})


def test_three_qualities_one_episode():
    grouper = EpisodeGrouper()
    for text in (
        "Solo Leveling S02E08 1080p",
        "Solo Leveling S02E08 720p",
        "Solo Leveling S02E08 480p",
    ):
        grouper.add(analyze(text))
    assert len(grouper) == 1
    group = grouper.groups()[0]
    assert group.title == "Solo Leveling"
    assert group.season == 2 and group.episode == 8
    assert [v.quality for v in group.versions] == ["1080p", "720p", "480p"]
    assert group.best_quality == "1080p"


def test_different_order_same_group():
    grouper = EpisodeGrouper()
    for text in (
        "Solo Leveling S02E08 480p",
        "Solo Leveling S02E08 1080p",
        "Solo Leveling S02E08 720p",
    ):
        grouper.add(analyze(text))
    assert len(grouper) == 1
    assert grouper.groups()[0].best_quality == "1080p"


def test_different_language_different_group():
    grouper = EpisodeGrouper()
    grouper.add(analyze("Solo Leveling S02E08 1080p VF"))
    grouper.add(analyze("Solo Leveling S02E08 1080p VOSTFR"))
    assert len(grouper) == 2


def test_same_quality_different_files_kept():
    grouper = EpisodeGrouper()
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        file_name="a.mkv", file_size=1000, telegram_message_id=1,
    ))
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        file_name="b.mkv", file_size=2000, telegram_message_id=2,
    ))
    assert len(grouper) == 1
    group = grouper.groups()[0]
    assert len(group.versions) == 2  # deux fichiers différents conservés


def test_same_file_duplicate():
    grouper = EpisodeGrouper()
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        file_name="a.mkv", file_size=1000, telegram_message_id=1,
    ))
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        file_name="a.mkv", file_size=1000, telegram_message_id=2,
    ))
    assert len(grouper.groups()[0].versions) == 1
    assert grouper.duplicates == 1


def test_same_message_twice_duplicate():
    grouper = EpisodeGrouper()
    message = {
        "text": "Solo Leveling S02E08 1080p",
        "media_type": "video",
        "file_name": "a.mkv",
        "telegram_message_id": 7,
        "telegram_channel_id": 1,
    }
    grouper.add(RuleBasedAnalyzer().analyze(message))
    grouper.add(RuleBasedAnalyzer().analyze(message))
    assert len(grouper.groups()[0].versions) == 1
    assert grouper.duplicates == 1


def test_different_sources_same_episode():
    grouper = EpisodeGrouper()
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        telegram_message_id=1, telegram_channel_id="chanA",
    ))
    grouper.add(analyze(
        "Solo Leveling S02E08 1080p",
        telegram_message_id=1, telegram_channel_id="chanB",
    ))
    assert len(grouper) == 1
    assert len(grouper.groups()[0].versions) == 2  # deux sources conservées


def test_group_serialization():
    grouper = EpisodeGrouper()
    grouper.add(analyze("Solo Leveling S02E08 1080p VF"))
    payload = grouper.to_dict()
    assert payload[0]["versions"][0]["quality"] == "1080p"
    assert payload[0]["versions"][0]["file"]["file_size"] is None
