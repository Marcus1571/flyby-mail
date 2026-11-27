"""FlyByMail claim service: lets several Macs share ONE answer to "who sends the reminder for this mail?".
Stores only SHA-256(message-id) + the device label + a time: no subjects, no addresses. stdlib only.
POST /claim {"id": "<64 hex>"} with "Authorization: Bearer <key>" -> {"won": true|false, "holder": "<label>", "done": true|false}
POST /claim {"id": ..., "done": true} -> the holder reports it sent the reminder: the claim never expires, every other Mac drops the mail
GET  /health -> ok (no auth, for a monitor)
Env: FLYBY_KEYS="label=sha256hex(key),label2=..."  FLYBY_DB=/data/claims.db  FLYBY_CLAIM_TTL=600  PORT=8787"""
import hashlib, hmac, json, os, re, sqlite3, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TTL = int(os.environ.get("FLYBY_CLAIM_TTL", "600"))   # a claim whose winner never came back frees itself after this
KEEP = 60 * 86400


def keys():
    return dict(p.split("=", 1) for p in os.environ.get("FLYBY_KEYS", "").split(",") if "=" in p)


def connect(path):
    c = sqlite3.connect(path, timeout=10, isolation_level=None)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("CREATE TABLE IF NOT EXISTS claims(id TEXT PRIMARY KEY, device TEXT NOT NULL, claimed_at INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0)")
    if "done" not in [r[1] for r in c.execute("PRAGMA table_info(claims)")]:   # databases made by 0.3.0
        c.execute("ALTER TABLE claims ADD COLUMN done INTEGER NOT NULL DEFAULT 0")
    return c


def claim(c, id_, device, now=None):
    """One atomic statement: wins if nobody holds it, the same device asks again, or the old claim expired; never once it is done."""
    now = int(now if now is not None else time.time())
    c.execute("DELETE FROM claims WHERE claimed_at < ?", (now - KEEP,))
    won = c.execute(
        "INSERT INTO claims(id,device,claimed_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE "
        "SET device=excluded.device, claimed_at=excluded.claimed_at WHERE claims.done=0 AND (claims.device=excluded.device OR claims.claimed_at < ?)",
        (id_, device, now, now - TTL)).rowcount == 1
    holder, done = c.execute("SELECT device, done FROM claims WHERE id=?", (id_,)).fetchone()
    return won, holder, bool(done)


def finish(c, id_, device):
    """The holder sent the reminder. Only the holder can finish; returns the claim as it now stands."""
    c.execute("UPDATE claims SET done=1 WHERE id=? AND device=?", (id_, device))
    row = c.execute("SELECT device, done FROM claims WHERE id=?", (id_,)).fetchone()
    return (row[0] == device and bool(row[1]), row[0], bool(row[1])) if row else (False, "", False)


def device_for(auth):
    token = auth[7:] if auth.startswith("Bearer ") else ""
    digest = hashlib.sha256(token.encode()).hexdigest()
    for label, h in keys().items():
        if hmac.compare_digest(digest, h): return label
    return None


class Handler(BaseHTTPRequestHandler):
    db_path = os.environ.get("FLYBY_DB", "/data/claims.db")

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        self.reply(200, {"ok": True}) if self.path == "/health" else self.reply(404, {"error": "not found"})

    def do_POST(self):
        device = device_for(self.headers.get("Authorization", ""))
        if not device: return self.reply(401, {"error": "bad key"})
        if self.path != "/claim": return self.reply(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(n, 1024)))
            id_, finished = body["id"], body.get("done") is True
            assert re.fullmatch(r"[0-9a-f]{64}", id_)
        except Exception:
            return self.reply(400, {"error": "expected {\"id\": 64 hex}"})
        c = connect(self.db_path)
        try: won, holder, done = finish(c, id_, device) if finished else claim(c, id_, device)
        finally: c.close()
        print(json.dumps({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "event": "done" if finished else "claim", "device": device, "id": id_[:8], "won": won, "holder": holder, "done": done}), flush=True)
        self.reply(200, {"won": won, "holder": holder, "done": done})

    def log_message(self, *a): pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8787"))), Handler).serve_forever()
