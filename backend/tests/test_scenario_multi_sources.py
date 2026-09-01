"""Scénario complet du prompt §29 : deux sources Telegram, un seul épisode.

    SOURCE A : Solo.Leveling.S02E08.1080p.VF.mkv  +  720p VF
    SOURCE B : Solo Leveling S02E08 480p VOSTFR

    Résultat attendu :
        - UNE seule fiche anime (Solo Leveling) ;
        - UNE seule fiche épisode (Saison 2, Épisode 8) ;
        - TROIS versions (1080p VF, 720p VF, 480p VOSTFR) ;
        - publications Telegram d'origine toutes conservées (liens, canaux).
"""

import time

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as test_client:
        yield test_client


def _auth_headers(client: TestClient) -> dict:
    response = client.post(
        "/api/telegram/verify-code",
        json={"phone": "+22912345678", "code": "12345"},
    )
    return {"Authorization": f"Bearer {response.json()['token']}"}


def _add_source(client: TestClient, headers: dict, username: str) -> dict:
    # Nettoyage : supprime les éventuelles sources du même nom (re-exécutions).
    for source in client.get("/api/sources", headers=headers).json()["sources"]:
        if source["username"] == username:
            client.delete(f"/api/sources/{source['id']}", headers=headers)
    response = client.post("/api/sources", headers=headers, json={"input": f"@{username}"})
    assert response.status_code == 200, response.text
    return response.json()["source"]


def _analyze_and_wait(client: TestClient, headers: dict, source_id: str) -> dict:
    response = client.post(
        f"/api/sources/{source_id}/analyze", headers=headers, json={"limit": 10, "force": True}
    )
    assert response.status_code == 202
    job = None
    for _ in range(100):
        job = client.get(
            f"/analyzer/jobs/{response.json()['job_id']}", headers=headers
        ).json()["job"]
        if job["status"] in ("done", "error"):
            break
        time.sleep(0.05)
    assert job["status"] == "done", job
    return job


def test_full_scenario_two_sources(client, fresh_analyzer_db):
    headers = _auth_headers(client)

    source_a = _add_source(client, headers, "sourcea")
    source_b = _add_source(client, headers, "sourceb")

    _analyze_and_wait(client, headers, source_a["id"])
    _analyze_and_wait(client, headers, source_b["id"])

    catalog = client.get("/api/catalog/anime", headers=headers).json()["anime"]
    solo = next((a for a in catalog if a["key"] == "solo leveling"), None)
    assert solo is not None, "la fiche Solo Leveling doit exister"

    # Une seule fiche anime.
    assert sum(1 for a in catalog if a["canonical_title"] == "Solo Leveling") == 1

    detail = client.get(f"/api/catalog/anime/{solo['id']}", headers=headers).json()["anime"]
    # Une seule saison 2, un seul épisode 8.
    season2 = next(s for s in detail["seasons"] if s["number"] == 2)
    assert len(detail["seasons"]) == 1
    episode8 = next(e for e in season2["episodes"] if e["number"] == 8)
    assert len(season2["episodes"]) == 1

    # Trois versions regroupées.
    versions = episode8["versions"]
    assert len(versions) == 3
    assert {v["quality"] for v in versions} == {"1080p", "720p", "480p"}
    by_quality = {v["quality"]: v for v in versions}
    assert by_quality["1080p"]["language"] == "french"
    assert by_quality["720p"]["language"] == "french"
    assert by_quality["480p"]["language"] == "japanese"
    assert by_quality["480p"]["subtitles"] == "french"

    # Les deux publications d'origine sont conservées (source A et source B).
    channels = {v["source"]["channel_username"] for v in versions}
    assert channels == {"sourcea", "sourceb"}
    # Chaque version garde sa référence Telegram (message id + canal) ;
    # le lien t.me n'est présent que lorsqu'il est constructible (jamais inventé).
    assert all(v["telegram_message_id"] is not None for v in versions)
    assert sum(1 for v in versions if v["telegram_message_link"]) >= 1

    # Meilleure version proposée (1080p VF) — les autres restent disponibles.
    assert episode8["best_version"]["quality"] == "1080p"
    assert episode8["version_count"] == 3

    # Métadonnées enrichies (fournisseur local en mode simulation).
    assert detail["metadata_status"] == "found"
    assert "Action" in detail["genres"]

    # La recherche retrouve l'animé par titre original et alias.
    assert client.get("/api/catalog/search", headers=headers, params={"q": "Ore dake Level Up na Ken"}).json()["results"][0]["key"] == "solo leveling"
    alias_hits = client.get("/api/catalog/search", headers=headers, params={"q": "SL"}).json()["results"]
    assert any(hit["key"] == "solo leveling" for hit in alias_hits)

    # Les épisodes récents alimentent l'accueil.
    recent = client.get("/api/catalog/recent", headers=headers).json()["recent"]
    assert any(
        r["anime_title"] == "Solo Leveling" and r["season_number"] == 2 and r["number"] == 8
        for r in recent
    )
