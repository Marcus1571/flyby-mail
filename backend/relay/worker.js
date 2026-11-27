// FlyByMail relay (Cloudflare Worker). For a Mac whose DNS filter blocks the tunnel's domain: it reaches the claim service through a workers.dev address instead.
// Forwards only POST /claim and GET /health to env.ORIGIN, adding the Cloudflare Access service token (secrets env.CF_ID, env.CF_SECRET) as headers.
// The Mac's own bearer key is passed through untouched and is checked by the service itself. Variables: ORIGIN (plain text, https://<service hostname>), CF_ID, CF_SECRET (secrets).
export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const ok = (req.method === "POST" && url.pathname === "/claim") || (req.method === "GET" && url.pathname === "/health");
    if (!ok) return new Response("not found", { status: 404 });
    const body = req.method === "POST" ? await req.text() : undefined;
    if (body && body.length > 1024) return new Response("too large", { status: 413 });
    const headers = new Headers({ "CF-Access-Client-Id": env.CF_ID, "CF-Access-Client-Secret": env.CF_SECRET, "Content-Type": "application/json" });
    const auth = req.headers.get("Authorization");
    if (auth) headers.set("Authorization", auth);
    return fetch(env.ORIGIN + url.pathname, { method: req.method, headers, body });
  },
};
