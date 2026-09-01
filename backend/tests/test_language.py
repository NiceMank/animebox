"""Tests de détection de langue et de sous-titres (étapes 6 et 7)."""

from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video"})


def test_vf():
    result = analyze("Solo Leveling S02E08 1080p VF")
    assert result.language == "french"
    assert result.subtitles is None


def test_fr():
    result = analyze("Solo Leveling S02E08 1080p FR")
    assert result.language == "french"


def test_french_word():
    result = analyze("Solo Leveling S02E08 1080p FRENCH")
    assert result.language == "french"


def test_vo():
    result = analyze("Solo Leveling S02E08 1080p VO")
    assert result.language == "japanese"


def test_jap():
    result = analyze("Solo Leveling S02E08 1080p JAP")
    assert result.language == "japanese"


def test_japanese_word():
    result = analyze("Solo Leveling S02E08 1080p JAPANESE")
    assert result.language == "japanese"


def test_vostfr_splits_language_and_subtitles():
    result = analyze("Solo.Leveling.S02E08.720p.VOSTFR")
    assert result.language == "japanese"
    assert result.subtitles == "french"


def test_vost():
    result = analyze("Solo Leveling S02E08 1080p VOST")
    assert result.language == "japanese"
    assert result.subtitles == "unknown"


def test_sub():
    result = analyze("Solo Leveling S02E08 1080p SUB")
    assert result.language == "unknown"
    assert result.subtitles == "unknown"


def test_subbed():
    result = analyze("Solo Leveling S02E08 1080p SUBBED")
    assert result.subtitles == "unknown"


def test_sub_fr():
    result = analyze("Solo Leveling S02E08 1080p SUB FR")
    assert result.subtitles == "french"


def test_multi():
    result = analyze("Solo Leveling S02E08 1080p MULTI")
    assert result.language == "multi"


def test_unknown_when_absent():
    result = analyze("Solo Leveling S02E08 1080p")
    assert result.language == "unknown"
    assert result.subtitles is None
