"""Test de fumée du backend AnimeBox — à lancer CONTRE une instance qui tourne :

    TELEGRAM_MOCK=1 uvicorn app.main:app --port 8000 &
    python3 smoke_test.py

Vérifie le parcours complet sans identifiants réels : santé, connexion
(simulation), résolution/ajout/suppression de source, publications,
synchronisation, moteur d'analyse (analyse, regroupement, catalogue) et
déconnexion. Aucun secret n'est utilisé.
"""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"
PASSED = 0


def request(method: str, path: str, body=None, token=None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


def check(label: str, condition: bool, detail: str = "") -> None:
    global PASSED
    if condition:
        PASSED += 1
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label} {detail}")
        sys.exit(1)


print("1. Santé")
status, health = request("GET", "/health")
check("GET /health → 200", status == 200, str(health))
check("mode simulé", health.get("mode") == "mock", str(health))

print("2. Connexion Telegram (simulation)")
status, sent = request("POST", "/api/telegram/send-code", {"phone": "+22901020304"})
check("send-code → 200", status == 200 and sent.get("sent") is True, str(sent))

status, verified = request("POST", "/api/telegram/verify-code", {"phone": "+22901020304", "code": "12345"})
check("verify-code → 200", status == 200, str(verified))
check("jeton émis", bool(verified.get("token")), "jeton absent")
check("utilisateur renvoyé", verified.get("user", {}).get("username") == "animebox_demo", str(verified))
token = verified["token"]

status, wrong = request("POST", "/api/telegram/verify-code", {"phone": "+22901020304", "code": "12"})
check("code incorrect refusé (422)", status == 422, str(wrong))

status, status_resp = request("GET", "/api/telegram/status", token=token)
check("statut connecté", status == 200 and status_resp.get("connected") is True, str(status_resp))

print("3. Résolution et ajout d'une source")
status, resolved = request("POST", "/api/sources/resolve", {"input": "https://t.me/animechannel1"}, token=token)
check("resolve lien t.me → 200", status == 200, str(resolved))
check("titre du canal", resolved.get("channel", {}).get("title") == "Animechannel1", str(resolved))

status, missing = request("POST", "/api/sources/resolve", {"input": "@introuvable"}, token=token)
check("source introuvable → 404", status == 404 and missing["error"]["code"] == "SOURCE_NOT_FOUND", str(missing))

status, private = request("POST", "/api/sources/resolve", {"input": "@prive"}, token=token)
check("source inaccessible → 403", status == 403 and private["error"]["code"] == "SOURCE_INACCESSIBLE", str(private))

status, added = request("POST", "/api/sources", {"input": "@animechannel1", "name": "Anime Channel 1"}, token=token)
check("ajout source → 200", status == 200, str(added))
source_id = added["source"]["id"]
check("access_hash jamais exposé", "access_hash" not in added["source"])

print("4. Publications récentes")
status, messages = request("GET", f"/api/sources/{source_id}/messages?limit=8", token=token)
msgs = messages.get("messages", [])
check("8 publications", status == 200 and len(msgs) == 8, str(messages))
check("IDs de messages présents", all(isinstance(m.get("message_id"), int) for m in msgs))
check("liens t.me valides", any(m.get("link", "").startswith("https://t.me/") for m in msgs))
check("cas sans lien géré", any(m.get("link") is None for m in msgs))

print("5. Synchronisation")
status, synced = request("POST", f"/api/sources/{source_id}/sync", token=token)
check("sync source → 200", status == 200 and synced.get("messages_fetched", 0) > 0, str(synced))

status, all_synced = request("POST", "/api/sync", token=token)
check("sync globale → 200", status == 200, str(all_synced))
check("statistiques cohérentes", all_synced.get("stats", {}).get("analyzed_posts", 0) > 0, str(all_synced))

status, stats_resp = request("GET", "/api/stats", token=token)
check("historique non vide", status == 200 and len(stats_resp.get("history", [])) >= 2, str(stats_resp))

print("6. Activation/désactivation + suppression")
status, patched = request("PATCH", f"/api/sources/{source_id}", {"sync_enabled": False}, token=token)
check("désactivation → 200", status == 200 and patched["source"]["sync_enabled"] is False, str(patched))

status, deleted = request("DELETE", f"/api/sources/{source_id}", token=token)
check("suppression → 200", status == 200 and deleted.get("ok") is True, str(deleted))

status, re_added = request("POST", "/api/sources", {"input": "@animechannel1"}, token=token)
check("ré-ajout → 200", status == 200, str(re_added))
source_id = re_added["source"]["id"]

print("7. Moteur d'analyse")
status, analyzer_status = request("GET", "/analyzer/status", token=token)
check("état du moteur → 200", status == 200 and analyzer_status["engine"]["name"] == "rule-based", str(analyzer_status))
check("aucune IA externe requise", analyzer_status["engine"]["external_ai"] is False, str(analyzer_status))

status, analysis = request(
    "POST", "/analyzer/analyze",
    {"text": "Solo Leveling S02E08 1080p VF", "media_type": "video", "telegram_message_id": 123456},
    token=token,
)
a = analysis.get("analysis", {})
check("analyse → titre/saison/épisode/qualité/langue",
      status == 200 and (a.get("title"), a.get("season"), a.get("episode"), a.get("quality"), a.get("language")) == ("Solo Leveling", 2, 8, "1080p", "french"), str(analysis))
check("score de confiance élevé", a.get("status") == "high" and a.get("confidence", 0) >= 85, str(a))
check("référence Telegram conservée", a.get("telegram", {}).get("message_id") == 123456, str(a))

status, batch = request(
    "POST", "/analyzer/analyze-batch",
    {"group": True, "messages": [
        {"text": "Solo Leveling S02E08 1080p", "media_type": "video"},
        {"text": "Solo Leveling S02E08 720p", "media_type": "video"},
        {"text": "Solo Leveling S02E08 480p", "media_type": "video"},
    ]},
    token=token,
)
groups = batch.get("groups", [])
check("regroupement → 1 épisode, 3 versions",
      status == 200 and len(groups) == 1 and groups[0]["version_count"] == 3 and groups[0]["best_quality"] == "1080p", str(batch))

status, started = request("POST", f"/api/sources/{source_id}/analyze", {"limit": 20, "force": True}, token=token)
check("analyse de source → 202", status == 202 and bool(started.get("job_id")), str(started))
job_id = started.get("job_id", "")
job = None
for _ in range(100):
    status, job_resp = request("GET", f"/analyzer/jobs/{job_id}", token=token)
    job = job_resp.get("job", {})
    if job.get("status") in ("done", "error"):
        break
    time.sleep(0.05)
check("tâche terminée", job.get("status") == "done", str(job))
check("8 publications traitées", job.get("processed") == 8, str(job))

status, catalog = request("GET", "/api/catalog/anime", token=token)
anime_list = catalog.get("anime", [])
solo = next((item for item in anime_list if item["key"] == "solo leveling"), None)
check("catalogue alimenté (Solo Leveling)", status == 200 and solo is not None and solo.get("version_count", 0) >= 4, str(catalog))

status, detail = request("GET", f"/api/catalog/anime/{solo['id']}", token=token)
episodes = [e for season in detail.get("anime", {}).get("seasons", []) for e in season.get("episodes", [])]
numbers = {e.get("number") for e in episodes}
check("épisodes S02E08 et S02E09 regroupés", numbers == {8, 9}, str(numbers))
versions = [v for e in episodes for v in e.get("versions", [])]
check("liens Telegram conservés", status == 200 and all(v.get("telegram_message_link") for v in versions), str(versions))

print("8. Authentification requise")
status, anon = request("GET", "/api/sources")
check("sans jeton → 401", status == 401 and anon["error"]["code"] == "UNAUTHORIZED", str(anon))
status, anon2 = request("GET", "/analyzer/status")
check("moteur sans jeton → 401", status == 401, str(anon2))

print("9. Déconnexion")
status, logged_out = request("POST", "/api/telegram/logout", token=token)
check("logout → 200", status == 200, str(logged_out))
status, after = request("GET", "/api/telegram/status", token=token)
check("jeton révoqué → 401", status == 401, str(after))

print(f"\nSMOKE TEST OK — {PASSED} vérifications réussies.")
