"""Tests de détection de saison (étape 3 du pipeline)."""

from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video"})


def test_s01_compact():
    result = analyze("Solo Leveling S01E08 1080p")
    assert result.season == 1


def test_s1_short():
    result = analyze("Solo Leveling S1 E8 1080p")
    assert result.season == 1


def test_s_space_number():
    result = analyze("Solo Leveling S 01 1080p")
    assert result.season == 1


def test_season_word():
    result = analyze("Solo Leveling Season 1 1080p")
    assert result.season == 1


def test_saison_word():
    result = analyze("Solo Leveling Saison 1 1080p")
    assert result.season == 1


def test_s02e08():
    result = analyze("Solo Leveling S02E08 1080p")
    assert result.season == 2
    assert result.episode == 8


def test_cross_format():
    result = analyze("Solo Leveling 2x08 HD")
    assert result.season == 2
    assert result.episode == 8


def test_saison_word_episode_word():
    result = analyze("Saison 2 Episode 8 de Solo Leveling 720p VF")
    assert result.season == 2
    assert result.episode == 8


def test_s2_space_e8():
    result = analyze("Solo Leveling S2 E8 1080P")
    assert result.season == 2
    assert result.episode == 8


def test_s_space_number_episode():
    result = analyze("Solo Leveling S 02 E 08 1080p")
    assert result.season == 2
    assert result.episode == 8


def test_year_is_not_a_season():
    result = analyze("Solo Leveling 2024 S02E08 1080p")
    assert result.season == 2
    assert result.year == 2024
