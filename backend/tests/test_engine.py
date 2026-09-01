"""Tests du pipeline complet sur le corpus exigé + cas difficiles."""

from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str, **extra):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video", **extra})


def test_corpus_1():
    r = analyze("Solo Leveling S02E08 1080p VF")
    assert (r.title, r.season, r.episode, r.quality, r.language) == (
        "Solo Leveling", 2, 8, "1080p", "french",
    )
    assert r.confidence == 98
    assert r.status == "high"


def test_corpus_2():
    r = analyze("Solo.Leveling.S02E08.720p.VOSTFR")
    assert (r.title, r.season, r.episode, r.quality) == ("Solo Leveling", 2, 8, "720p")
    assert r.language == "japanese"
    assert r.subtitles == "french"
    assert r.status == "high"


def test_corpus_3():
    r = analyze("Solo_Leveling_S2_E8_480p")
    assert (r.title, r.season, r.episode, r.quality) == ("Solo Leveling", 2, 8, "480p")


def test_corpus_4():
    r = analyze("Solo Leveling 2x08 HD")
    assert (r.title, r.season, r.episode, r.quality) == ("Solo Leveling", 2, 8, "720p")


def test_corpus_5():
    r = analyze("Solo Leveling Episode 8 VF")
    assert (r.title, r.episode, r.language) == ("Solo Leveling", 8, "french")
    assert r.season is None


def test_corpus_6():
    r = analyze("Jujutsu Kaisen S02E15 1080p")
    assert (r.title, r.season, r.episode, r.quality) == ("Jujutsu Kaisen", 2, 15, "1080p")


def test_corpus_7():
    r = analyze("One Piece 1124 1080p")
    assert (r.title, r.episode, r.quality) == ("One Piece", 1124, "1080p")


def test_corpus_8():
    r = analyze("Demon Slayer S04E07 VOSTFR")
    assert (r.title, r.season, r.episode) == ("Demon Slayer", 4, 7)
    assert r.language == "japanese"
    assert r.subtitles == "french"


def test_hard_special_no_invented_episode():
    r = analyze("Solo Leveling - épisode spécial - 1080p")
    assert r.episode is None
    assert r.episode_kind == "special"
    assert r.quality == "1080p"


def test_hard_year_vs_episode():
    r = analyze("Solo Leveling 2024 S02E08 1080p")
    assert r.episode == 8
    assert r.year == 2024


def test_hard_alias_sl():
    r = analyze("SL S2 08 HD")
    assert (r.title, r.season, r.episode, r.quality) == ("Solo Leveling", 2, 8, "720p")
    assert r.title_matched and r.title_via_alias
    assert r.status == "medium"  # incertain → confirmation recommandée


def test_unknown_title_medium():
    r = analyze("My Fav Show S01E03 720p")
    assert r.title == "My Fav Show"
    assert not r.title_matched
    assert r.status in ("medium", "low")


def test_filename_priority_for_metadata():
    # La caption est vague, le nom de fichier porte l'information.
    r = analyze(
        "Nouvel épisode 🔥",
        file_name="Solo.Leveling.S02E08.1080p.WEB-DL.mkv",
    )
    assert (r.title, r.season, r.episode, r.quality) == ("Solo Leveling", 2, 8, "1080p")


def test_filename_priority_on_conflict():
    # Qualités contradictoires : le nom de fichier gagne (priorité configurable).
    r = analyze(
        "Solo Leveling S02E08 1080p VF",
        file_name="solo-leveling-s02e08-480p.mkv",
    )
    assert r.quality == "480p"
    assert any("contradictoire" in warning for warning in r.warnings)


def test_text_message_is_not_a_video():
    r = analyze("Épisode 08 disponible", media_type="text")
    assert r.episode == 8
    assert r.quality is None
    assert r.media_type == "text"


def test_media_type_refined_by_extension():
    r = analyze("Nouvel épisode", file_name="solo-s02e08.mp3", media_type="document")
    assert r.media_type == "audio"


def test_telegram_reference_kept():
    r = analyze(
        "Solo Leveling S02E08 1080p",
        telegram_message_id=123456,
        telegram_channel_id=42,
        telegram_channel_username="animefr",
        telegram_message_link="https://t.me/animefr/123456",
    )
    assert r.telegram_message_id == 123456
    assert r.telegram_message_link == "https://t.me/animefr/123456"
