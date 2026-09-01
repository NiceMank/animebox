"""Tests de détection d'épisode (étape 4 du pipeline).

L'épisode ne doit JAMAIS être confondu avec une année, une saison, une
résolution ou une taille de fichier.
"""

from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str, **extra):
    message = {"text": text, "media_type": "video", **extra}
    return RuleBasedAnalyzer().analyze(message)


def test_e01():
    assert analyze("Solo Leveling E01 1080p").episode == 1


def test_e1():
    assert analyze("Solo Leveling E1 1080p").episode == 1


def test_ep01():
    assert analyze("Solo Leveling EP01 1080p").episode == 1


def test_ep_space_number():
    assert analyze("Solo Leveling EP 01 1080p").episode == 1


def test_episode_word():
    assert analyze("Solo Leveling Episode 01 1080p").episode == 1


def test_episode_word_accent():
    assert analyze("Solo Leveling Épisode 01 1080p").episode == 1


def test_combined_s02e08():
    assert analyze("Solo Leveling S02E08 1080p").episode == 8


def test_combined_s2e8():
    assert analyze("Solo Leveling S2E8 1080p").episode == 8


def test_cross():
    assert analyze("Solo Leveling 2x08 1080p").episode == 8


def test_year_never_an_episode():
    result = analyze("Solo Leveling 2024 S02E08 1080p")
    assert result.episode == 8
    assert result.year == 2024


def test_resolution_never_an_episode():
    result = analyze("Solo Leveling 1080")
    assert result.episode is None
    assert result.quality == "1080p"


def test_bare_number_with_known_title():
    result = analyze("One Piece 1124 1080p")
    assert result.episode == 1124


def test_bare_two_digit_with_known_title():
    result = analyze("SOLO LEVELING 08 VOSTFR")
    assert result.episode == 8


def test_no_episode_alone():
    result = analyze("Solo Leveling 1080p VF")
    assert result.episode is None


def test_special_never_invents_an_episode():
    result = analyze("Solo Leveling - épisode spécial - 1080p")
    assert result.episode is None
    assert result.episode_kind == "special"
