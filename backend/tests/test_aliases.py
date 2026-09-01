"""Tests du catalogue de titres et des alias (étapes 9 et 10)."""

from app.analyzer.aliases import AliasRegistry
from app.analyzer.engine import RuleBasedAnalyzer


def test_alias_solo_leveling(registry):
    assert registry.resolve("ore dake level up na ken").title == "Solo Leveling"
    assert registry.resolve("sl").title == "Solo Leveling"


def test_alias_one_piece(registry):
    assert registry.resolve("op").title == "One Piece"


def test_alias_jjk(registry):
    assert registry.resolve("jjk").title == "Jujutsu Kaisen"


def test_alias_original_title(registry):
    assert registry.resolve("shingeki no kyojin").title == "Attack on Titan"


def test_canonical_exact(registry):
    resolved = registry.resolve_exact("solo leveling")
    assert resolved is not None and resolved.title == "Solo Leveling"
    assert registry.resolve_exact("sl") is None  # alias ≠ canonique


def test_resolution_insensible_au_format():
    engine = RuleBasedAnalyzer()
    for text in (
        "SOLO LEVELING 08 VOSTFR",
        "Solo.Leveling.S02E08.720p",
        "Solo_Leveling_S2_E8_480p",
        "solo leveling s2e8 1080p",
    ):
        assert engine.analyze({"text": text, "media_type": "video"}).title == "Solo Leveling"


def test_digits_in_title_preserved():
    engine = RuleBasedAnalyzer()
    result = engine.analyze({"text": "86 Eighty-Six S01E05", "media_type": "video"})
    assert result.title == "86 Eighty-Six"


def test_custom_alias():
    registry = AliasRegistry()
    registry.register_aliases(registry.resolve_exact("solo leveling"), ("slv",))
    assert registry.resolve("slv").title == "Solo Leveling"
