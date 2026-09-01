"""Tests de détection de qualité (étape 5 du pipeline)."""

from app.analyzer.quality import infer_from_resolution, rank_of
from app.analyzer.engine import RuleBasedAnalyzer


def analyze(text: str, **extra):
    return RuleBasedAnalyzer().analyze({"text": text, "media_type": "video", **extra})


def test_values():
    cases = {
        "2160p": "2160p",
        "4K": "2160p",
        "1440p": "1440p",
        "1080p": "1080p",
        "1080": "1080p",
        "FHD": "1080p",
        "720p": "720p",
        "720": "720p",
        "HD": "720p",
        "480p": "480p",
        "480": "480p",
        "360p": "360p",
        "360": "360p",
    }
    for token, expected in cases.items():
        result = analyze(f"Solo Leveling S02E08 {token}")
        assert result.quality == expected, f"{token} → {result.quality} (attendu {expected})"


def test_original_value_kept():
    result = analyze("Solo Leveling S02E08 FHD")
    assert result.quality == "1080p"
    assert result.quality_original == "fhd"


def test_higher_quality_wins_on_conflict():
    result = analyze("Solo Leveling S02E08 1080p 720p")
    assert result.quality == "1080p"
    assert any("plusieurs qualités" in warning for warning in result.warnings)


def test_ranking():
    ranks = ["360p", "480p", "720p", "1080p", "1440p", "2160p"]
    for lower, higher in zip(ranks, ranks[1:]):
        assert rank_of(higher) > rank_of(lower)


def test_metadata_inference():
    assert infer_from_resolution(1920, 1080) == "1080p"
    assert infer_from_resolution(1280, 720) == "720p"
    assert infer_from_resolution(3840, 2160) == "2160p"
    assert infer_from_resolution(None, None) is None


def test_metadata_quality_source():
    result = analyze("One Piece 1124", width=1920, height=1080)
    assert result.quality == "1080p"
    assert result.quality_source == "metadata"


def test_no_quality():
    result = analyze("Solo Leveling S02E08 VF")
    assert result.quality is None
