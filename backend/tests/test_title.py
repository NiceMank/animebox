"""Tests d'extraction de titre (étape 8 et titres complexes, étape 9)."""

from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str, **extra):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video", **extra})


def test_title_without_markers():
    result = analyze("Solo Leveling S02E08 1080p VF")
    assert result.title == "Solo Leveling"


def test_title_is_not_the_whole_line():
    result = analyze("Solo Leveling S02E08 1080p VF")
    assert result.title != "Solo Leveling S02E08 1080p VF"
    assert "s02e08" not in (result.title_key or "")


def test_title_with_digits_part_of_title():
    result = analyze("86 Eighty-Six S01E05")
    assert result.title == "86 Eighty-Six"
    assert result.title_matched


def test_title_with_part_suffix():
    result = analyze("JoJo's Bizarre Adventure Part 4 S01E01")
    assert "Part 4" in result.title
    assert result.episode == 1


def test_title_with_season_word():
    result = analyze("Classroom of the Elite S03E02")
    assert result.title == "Classroom of the Elite"


def test_title_unknown_kept():
    result = analyze("My Fav Show S01E03 720p")
    assert result.title == "My Fav Show"
    assert not result.title_matched


def test_leading_preposition_stripped():
    result = analyze("Saison 2 Episode 8 de Solo Leveling 720p VF")
    assert result.title == "Solo Leveling"


def test_special_keeps_clean_title():
    result = analyze("Solo Leveling - épisode spécial - 1080p")
    assert result.title == "Solo Leveling"
    assert result.episode_kind == "special"


def test_release_tags_stripped_from_filename():
    result = analyze(
        "Nouvel épisode",
        file_name="Solo.Leveling.S02E08.1080p.WEB-DL.x265.mkv",
    )
    assert result.title == "Solo Leveling"
    assert "web" not in (result.title_key or "")


def test_no_title_when_only_generic_words():
    result = analyze("Épisode 08 disponible", media_type="text")
    assert result.title is None
    assert result.status == "needs_review"
