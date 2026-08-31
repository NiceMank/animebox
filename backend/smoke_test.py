"""Test de fumée du backend AnimeBox — à lancer CONTRE une instance qui tourne :

    TELEGRAM_MOCK=1 uvicorn app.main:app --port 8000 &
    python3 smoke_test.py

Vérifie le parcours complet sans identifiants réels : santé, connexion
(simulation), résolution/ajout/suppression de source, publications,
synchronisation et déconnexion. Aucun secret n'est utilisé.
"""
import json
import sys
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

print("7. Authentification requise")
status, anon = request("GET", "/api/sources")
check("sans jeton → 401", status == 401 and anon["error"]["code"] == "UNAUTHORIZED", str(anon))

print("8. Déconnexion")
status, logged_out = request("POST", "/api/telegram/logout", token=token)
check("logout → 200", status == 200, str(logged_out))
status, after = request("GET", "/api/telegram/status", token=token)
check("jeton révoqué → 401", status == 401, str(after))

print(f"\nSMOKE TEST OK — {PASSED} vérifications réussies.")
