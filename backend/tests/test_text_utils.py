"""Tests de normalisation (étape 2 du pipeline)."""

from app.analyzer.text_utils import normalize, titlecase


def test_case_and_spaces():
    assert normalize("SOLO LEVELING 08 VOSTFR") == "solo leveling 08 vostfr"


def test_underscores():
    assert normalize("Solo_Leveling_S02_E08_1080p") == "solo leveling s02 e08 1080p"


def test_dots():
    assert normalize("Solo.Leveling.S02E08.1080p") == "solo leveling s02e08 1080p"


def test_dashes_and_brackets():
    assert normalize("Solo Leveling - Episode 08 - 720p") == "solo leveling episode 08 720p"
    assert normalize("[AnimeVOSTFR] Solo (2024) S01E02") == "animevostfr solo 2024 s01e02"


def test_accents():
    assert normalize("Épisode 08 VF") == "épisode 08 vf"


def test_unicode_nfkc():
    assert normalize("One Ｐiece 1124") == "one piece 1124"
    assert normalize("ＨＤ") == "hd"


def test_apostrophes_and_colons():
    assert normalize("JoJo's Bizarre Adventure Part 4") == "jojo s bizarre adventure part 4"
    assert normalize("Re:Zero S02E01") == "re zero s02e01"


def test_titlecase_display():
    assert titlecase("solo leveling") == "Solo Leveling"
    assert titlecase("one piece") == "One Piece"
    assert titlecase("jojo s bizarre adventure") == "Jojo s Bizarre Adventure"
