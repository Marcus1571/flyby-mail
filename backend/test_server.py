import hashlib, json, os, tempfile, threading, unittest, urllib.error, urllib.request
os.environ["FLYBY_KEYS"] = "mac=" + hashlib.sha256(b"k1").hexdigest() + ",macai=" + hashlib.sha256(b"k2").hexdigest()
os.environ["FLYBY_CLAIM_TTL"] = "600"
import server

ID = "a" * 64


class T(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(); self.path = os.path.join(self.dir, "c.db")

    def test_one_winner_among_many_simultaneous_claims(self):
        server.connect(self.path).close()
        wins = []
        def go(dev):
            c = server.connect(self.path); wins.append(server.claim(c, ID, dev)[0]); c.close()
        ts = [threading.Thread(target=go, args=(f"d{i}",)) for i in range(20)]
        [t.start() for t in ts]; [t.join() for t in ts]
        self.assertEqual(sum(wins), 1)

    def test_same_device_again_wins_other_loses_until_ttl(self):
        c = server.connect(self.path)
        self.assertEqual(server.claim(c, ID, "mac", now=1000), (True, "mac", False))
        self.assertEqual(server.claim(c, ID, "mac", now=1010), (True, "mac", False))
        self.assertEqual(server.claim(c, ID, "macai", now=1020), (False, "mac", False))
        self.assertEqual(server.claim(c, ID, "macai", now=1010 + 599), (False, "mac", False))
        self.assertEqual(server.claim(c, ID, "macai", now=1010 + 601), (True, "macai", False))

    def test_done_claim_never_expires_and_only_holder_finishes(self):
        c = server.connect(self.path)
        server.claim(c, ID, "mac", now=1000)
        self.assertEqual(server.finish(c, ID, "macai"), (False, "mac", False))   # not the holder: nothing changes
        self.assertEqual(server.finish(c, ID, "mac"), (True, "mac", True))
        self.assertEqual(server.claim(c, ID, "macai", now=1000 + 10**6), (False, "mac", True))
        self.assertEqual(server.claim(c, ID, "mac", now=1000 + 10**6), (False, "mac", True))
        self.assertEqual(server.finish(c, "b" * 64, "mac"), (False, "", False))   # unknown id

    def test_old_database_gets_done_column(self):
        import sqlite3
        old = sqlite3.connect(self.path, isolation_level=None)
        old.execute("CREATE TABLE claims(id TEXT PRIMARY KEY, device TEXT NOT NULL, claimed_at INTEGER NOT NULL)")
        old.execute("INSERT INTO claims VALUES(?,?,?)", (ID, "mac", 1000)); old.close()
        c = server.connect(self.path)
        self.assertEqual(server.claim(c, ID, "macai", now=1100), (False, "mac", False))

    def test_http_auth_and_validation(self):
        srv = server.ThreadingHTTPServer(("127.0.0.1", 0), type("H", (server.Handler,), {"db_path": self.path}))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{srv.server_port}/claim"
        def post(key, body):
            r = urllib.request.Request(url, json.dumps(body).encode(), {"Authorization": f"Bearer {key}"})
            try: return json.load(urllib.request.urlopen(r))
            except urllib.error.HTTPError as e: return e.code
        self.assertEqual(post("wrong", {"id": ID}), 401)
        self.assertEqual(post("k1", {"id": "nothex"}), 400)
        self.assertEqual(post("k1", {"id": ID}), {"won": True, "holder": "mac", "done": False})
        self.assertEqual(post("k2", {"id": ID}), {"won": False, "holder": "mac", "done": False})
        self.assertEqual(post("k1", {"id": ID, "done": True}), {"won": True, "holder": "mac", "done": True})
        self.assertEqual(post("k2", {"id": ID}), {"won": False, "holder": "mac", "done": True})
        srv.shutdown()


if __name__ == "__main__": unittest.main()
