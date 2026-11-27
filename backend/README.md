# FlyByMail claim service (optional)

Lets several Macs that run the FlyByMail engine on the same mailbox agree who sends a reminder, so two engines ticking at the same moment never send it twice.
Without it the app works on its own (one Mac, or several that merely rarely collide).

- **What it stores:** SHA-256 of a mail's Message-Id, the device label, a timestamp. No subjects, addresses or bodies. Rows older than 60 days are deleted.
- **API:** `POST /claim {"id": "<64 hex>"}` with `Authorization: Bearer <key>` returns `{"won": bool, "holder": label}`; `GET /health`. A claim lasts 10 minutes
  (so a Mac that won and then crashed frees it); the same device asking again wins again. After sending, the winner posts `{"id": ..., "done": true}`: the claim then never expires and the answer carries `"done": true`, so the other Macs drop the mail.
- **Run:** `docker compose up -d --build` (see `compose.yaml`, `.env.example`; add `-f compose.edge.yaml` to join a shared `edge` network for a tunnel container). Port is bound to 127.0.0.1 only: put a Cloudflare Tunnel with Access (service token) or a
  Tailscale Serve rule in front. Check: `python3 -m unittest test_server` here, and `scripts/check-engine.sh` in the repo root (real round trip against this server).
- **On each Mac:** `defaults write app.legba.flybymail backendURL "https://<your-door>"`, and the key into the Keychain:
  `security add-generic-password -s app.legba.flybymail.backend -a key -w` (it prompts for the key, so it never sits in shell history). Do this in a GUI session (the login keychain is locked over SSH); the app's first read shows a macOS Keychain dialog, answer it with the login password and **Always Allow**, or the engine waits on it. Behind Cloudflare Access also
  `-s app.legba.flybymail.backend.cfid` and `-s app.legba.flybymail.backend.cfsecret` (the service token's ID and secret, same way).
- **Behaviour in the engine:** won, send. Lost, wait (the next tick finds the winner's reminder in Sent and reuses it). Service unreachable, wait; an entry more than
  30 minutes late is sent anyway so a dead server cannot silence reminders for good. Done by another Mac, drop the mail. Log events: `claim-lost`, `claim-done`, `claim-unavailable`, `finish-failed`.
- **Relay (optional):** `relay/worker.js` is a Cloudflare Worker for Macs whose DNS filter blocks the tunnel's domain; see the comment at its top. The Macs then use the `workers.dev` address and only need their own key (no Cloudflare token).
