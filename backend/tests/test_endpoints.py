"""Tests des routes HTTP du moteur (étapes 22 et 29)."""

import time

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as test_client:
        yield test_client


def _token(client: TestClient) -> str:
    response = client.post(
        "/api/telegram/verify-code",
        json={"phone": "+22912345678", "code": "12345"},
    )
    assert response.status_code == 200, response.text
    return response.json()["token"]


@pytest.fixture()
def auth(client):
    return {"Authorization": f"Bearer {_token(client)}"}


def test_requires_auth(client):
    response = client.get("/analyzer/status")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_status(client, auth):
    response = client.get("/analyzer/status", headers=auth)
    assert response.status_code == 200
    data = response.json()
    assert data["engine"]["name"] == "rule-based"
    assert data["engine"]["external_ai"] is False
    assert data["mode"] == "mock"
    assert "1080p" in data["supported_qualities"]
    assert data["catalog"]["anime"] >= 30


def test_analyze(client, auth):
    response = client.post(
        "/analyzer/analyze",
        headers=auth,
        json={
            "text": "Solo Leveling S02E08 1080p VF",
            "media_type": "video",
            "telegram_message_id": 123456,
            "telegram_message_link": "https://t.me/animefr/123456",
        },
    )
    assert response.status_code == 200
    analysis = response.json()["analysis"]
    assert analysis["title"] == "Solo Leveling"
    assert analysis["season"] == 2
    assert analysis["episode"] == 8
    assert analysis["quality"] == "1080p"
    assert analysis["language"] == "french"
    assert analysis["confidence"] == 98
    assert analysis["status"] == "high"
    assert analysis["telegram"]["message_id"] == 123456


def test_analyze_batch_groups(client, auth):
    response = client.post(
        "/analyzer/analyze-batch",
        headers=auth,
        json={
            "group": True,
            "messages": [
                {"text": "Solo Leveling S02E08 1080p", "media_type": "video"},
                {"text": "Solo Leveling S02E08 720p", "media_type": "video"},
                {"text": "Solo Leveling S02E08 480p", "media_type": "video"},
            ],
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["count"] == 3
    assert len(data["groups"]) == 1
    group = data["groups"][0]
    assert group["version_count"] == 3
    assert group["best_quality"] == "1080p"
    assert [v["quality"] for v in group["versions"]] == ["1080p", "720p", "480p"]


def test_group_endpoint(client, auth):
    analyses = [
        {
            "title": "Solo Leveling",
            "title_key": "solo leveling",
            "anime_key": "solo leveling",
            "season": 2,
            "episode": 8,
            "language": "french",
            "quality": "1080p",
            "quality_rank": 4,
            "media_type": "video",
            "status": "high",
            "confidence": 95,
            "telegram": {"message_id": 1, "channel_id": "a"},
        },
        {
            "title": "Solo Leveling",
            "title_key": "solo leveling",
            "anime_key": "solo leveling",
            "season": 2,
            "episode": 8,
            "language": "french",
            "quality": "720p",
            "quality_rank": 3,
            "media_type": "video",
            "status": "high",
            "confidence": 95,
            "telegram": {"message_id": 2, "channel_id": "a"},
        },
    ]
    response = client.post("/analyzer/group", headers=auth, json={"analyses": analyses})
    assert response.status_code == 200
    data = response.json()
    assert data["grouped_episodes"] == 1
    assert data["groups"][0]["version_count"] == 2


def test_source_analyze_job_and_catalog(client, auth, fresh_analyzer_db):
    added = client.post(
        "/api/sources", headers=auth, json={"input": "@animefr"}
    ).json()["source"]
    response = client.post(
        f"/api/sources/{added['id']}/analyze",
        headers=auth,
        json={"limit": 20, "force": True},
    )
    assert response.status_code == 202
    job_id = response.json()["job_id"]

    job = None
    for _ in range(100):  # la tâche de fond est exécutée après la réponse
        job = client.get(f"/analyzer/jobs/{job_id}", headers=auth).json()["job"]
        if job["status"] in ("done", "error"):
            break
        time.sleep(0.05)
    assert job["status"] == "done", job
    assert job["processed"] == 8
    assert job["new_episodes"] == 6
    assert job["new_versions"] == 8
    assert job["duplicates"] == 0

    # Catalogue alimenté et exposé pour l'application.
    catalog = client.get("/api/catalog/anime", headers=auth).json()["anime"]
    solo = next(a for a in catalog if a["key"] == "solo leveling")
    assert solo["version_count"] == 4  # E08 : 3 versions + E09 : 1 version
    detail = client.get(
        f"/api/catalog/anime/{solo['id']}", headers=auth
    ).json()["anime"]
    numbers = {e["number"] for s in detail["seasons"] for e in s["episodes"]}
    assert numbers == {8, 9}
    versions = [v for s in detail["seasons"] for e in s["episodes"] for v in e["versions"]]
    assert {v["quality"] for v in versions} == {"1080p", "720p", "480p"}
    assert all(v["telegram_message_link"] for v in versions)

    # La source reflète l'analyse.
    sources = client.get("/api/sources", headers=auth).json()["sources"]
    updated = next(s for s in sources if s["id"] == added["id"])
    assert updated["analyzed_posts"] == 8
    assert updated["detected_episodes"] == 6


def test_source_analyze_unknown_source(client, auth):
    response = client.post("/api/sources/nope/analyze", headers=auth)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "SOURCE_NOT_FOUND"


def test_job_not_found(client, auth):
    response = client.get("/analyzer/jobs/inconnu", headers=auth)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "JOB_NOT_FOUND"


def test_catalog_anime_not_found(client, auth):
    response = client.get("/api/catalog/anime/999999", headers=auth)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "ANIME_NOT_FOUND"
