"""Tests du système de correspondance des métadonnées (prompt §5, §6, §28)."""

from app.metadata.base import MetadataCandidate
from app.metadata.matching import (
    MATCH_CONFIDENT,
    MATCH_REVIEW,
    classify_match,
    score_candidate,
)


def _candidate(title: str, *, original: str | None = None, alts: tuple[str, ...] = (), year: int | None = None) -> MetadataCandidate:
    return MetadataCandidate(
        provider="fake",
        provider_id="1",
        title=title,
        original_title=original,
        alternative_titles=alts,
        year=year,
    )


def test_exact_title_confident():
    assert score_candidate("Solo Leveling", _candidate("Solo Leveling")) >= MATCH_CONFIDENT
    assert classify_match(score_candidate("Solo Leveling", _candidate("Solo Leveling"))) == "confident"


def test_original_title_match():
    score = score_candidate("Ore dake Level Up na Ken", _candidate("Solo Leveling", original="Ore dake Level Up na Ken"))
    assert score >= MATCH_CONFIDENT


def test_alternative_title_match():
    score = score_candidate("OP", _candidate("One Piece", alts=("OP",)))
    assert score >= MATCH_CONFIDENT


def test_suffix_variant_review_only():
    # « Solo Leveling Special » ne doit PAS être associé automatiquement.
    score = score_candidate("Solo Leveling", _candidate("Solo Leveling Special"))
    assert MATCH_REVIEW <= score < MATCH_CONFIDENT
    assert classify_match(score) == "review"


def test_false_positive_guard_one_piece():
    # « One Piece » ne doit pas être associé automatiquement au film.
    score = score_candidate("One Piece", _candidate("One Piece Film: Red"))
    assert score < MATCH_CONFIDENT
    assert classify_match(score) in ("review", "none")


def test_unrelated_title_none():
    score = score_candidate("Solo Leveling", _candidate("Naruto"))
    assert classify_match(score) == "none"


def test_year_match_bonus():
    base = score_candidate("Solo Leveling", _candidate("Solo Leveling", year=2024), known_year=2024)
    mismatch = score_candidate("Solo Leveling", _candidate("Solo Leveling", year=2019), known_year=2024)
    assert base > mismatch


def test_normalization_insensitive():
    exact = score_candidate("Solo Leveling", _candidate("Solo Leveling"))
    assert score_candidate("solo_leveling", _candidate("Solo Leveling")) >= exact - 0.05
    assert score_candidate("SOLO LEVELING", _candidate("Solo Leveling")) >= exact - 0.05


def test_matched_by_tracking():
    candidate = _candidate("Solo Leveling", original="Ore dake Level Up na Ken")
    score_candidate("Ore dake Level Up na Ken", candidate)
    assert candidate.matched_by in ("original_title", "title")
