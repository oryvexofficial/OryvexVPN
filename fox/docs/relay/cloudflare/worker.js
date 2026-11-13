const ALLOWED_HOSTS = [
  "mozilla.org",
  "mozilla.com",
  "firefox.com",
  "github.com",
  "githubusercontent.com",
  "jsdelivr.net",
];

const DROP_HEADERS = new Set([
  "host", "connection", "content-length", "keep-alive", "proxy-authenticate",
  "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade",
  "forwarded", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host",
  "x-real-ip", "true-client-ip",
]);
const METHODS = new Set(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]);
const MAX_REQUEST_BYTES = 1_048_576;
const MAX_RESPONSE_BYTES = 8_388_608;
const UPSTREAM_TIMEOUT_MS = 25_000;

const STATUS_PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<title>OryvexVPN Fox Relay</title>
<style>
:root{color-scheme:dark;--bg:#080e19;--panel:#101a2a;--line:#22334a;--text:#f3f7ff;--muted:#a9b7cb;--blue:#70aaff;--green:#78e0b4}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(ellipse at 50% 0%,#17345a 0,transparent 55%),var(--bg);font:16px/1.55 Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;color:var(--text)}
main{width:min(100%,560px);padding:36px;border:1px solid var(--line);border-radius:24px;background:linear-gradient(160deg,#142238,var(--panel) 54%);box-shadow:0 28px 90px #0007;text-align:center}
.mark{width:58px;height:58px;margin:0 auto 22px;border:1px solid #355780;border-radius:18px;display:grid;place-items:center;background:#142b48;color:var(--blue);font-size:28px;font-weight:800}
.pill{display:inline-flex;align-items:center;gap:8px;border:1px solid #285542;background:#102a22;color:var(--green);padding:5px 11px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase}
.dot{width:7px;height:7px;border-radius:50%;background:currentColor;box-shadow:0 0 12px currentColor}h1{margin:18px 0 10px;font-size:clamp(26px,7vw,36px);line-height:1.12;letter-spacing:-.035em}p{margin:0 auto;color:var(--muted);max-width:42ch}.note{margin-top:24px;padding-top:18px;border-top:1px solid var(--line);font-size:13px}.credit{margin-top:28px;color:#8393a9;font-size:12px}
</style>
</head>
<body><main><div class="mark" aria-hidden="true">O</div><span class="pill"><i class="dot" aria-hidden="true"></i> Relay ready</span><h1>OryvexVPN Relay for Fox connection was created</h1><p>Your private relay endpoint is ready for Fox account and service requests.</p><p class="note">This relay only forwards HTTPS requests to the Mozilla, Firefox, GitHub, and jsDelivr host allowlist. It does not carry your general VPN traffic.</p><div class="credit">Created by Muvixo</div></main></body></html>`;

function fail(status, reason) {
  return new Response(reason, {
    status,
    headers: {
      "X-Relay-Error": reason,
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
  });
}

function safeEqual(left, right) {
  if (typeof left !== "string" || left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < right.length; i++) mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
}

function allowedHost(host) {
  return ALLOWED_HOSTS.some((domain) => host === domain || host.endsWith(`.${domain}`));
}

function cleanHeaders(input) {
  const output = new Headers();
  for (const [name, value] of input) {
    const lower = name.toLowerCase();
    if (DROP_HEADERS.has(lower) || lower.startsWith("cf-")) continue;
    output.set(name, value);
  }
  return output;
}

async function readBodyLimited(request) {
  if (!request.body) return undefined;
  const length = Number(request.headers.get("content-length"));
  if (Number.isFinite(length) && length > MAX_REQUEST_BYTES) throw new Error("request body too large");
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_REQUEST_BYTES) {
        await reader.cancel();
        throw new Error("request body too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function limitResponse(stream, controller, timer, onFinish) {
  if (!stream) {
    clearTimeout(timer);
    return null;
  }
  const reader = stream.getReader();
  let size = 0;
  return new ReadableStream({
    async pull(out) {
      try {
        const { done, value } = await reader.read();
        if (done) {
          clearTimeout(timer);
          onFinish();
          out.close();
          return;
        }
        size += value.byteLength;
        if (size > MAX_RESPONSE_BYTES) {
          await reader.cancel();
          clearTimeout(timer);
          onFinish();
          out.error(new Error("upstream response too large"));
          return;
        }
        out.enqueue(value);
      } catch (error) {
        clearTimeout(timer);
        onFinish();
        out.error(error);
      }
    },
    async cancel(reason) {
      clearTimeout(timer);
      controller.abort(reason);
      onFinish();
      await reader.cancel(reason);
    },
  });
}

export default {
  async fetch(request, env = {}) {
    const here = new URL(request.url);
    const probe = here.searchParams.get("health") === "1";
    const hasTarget = here.searchParams.has("url");

    // A public status page is safe: it reveals no secret and helps identify the deployment.
    if (!hasTarget && !probe && request.method === "GET") {
      return new Response(STATUS_PAGE, {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
          "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
          "X-Content-Type-Options": "nosniff",
          "X-Frame-Options": "DENY",
          "Referrer-Policy": "no-referrer",
        },
      });
    }

    const secret = env.SECRET;
    if (typeof secret !== "string" || secret.length < 32) return fail(503, "no secret is set in the relay");
    if (!safeEqual(here.searchParams.get("secret"), secret)) return fail(403, "wrong secret");

    if (probe) {
      if (request.method !== "GET") return fail(405, "health requires GET");
      return new Response(JSON.stringify({ relay: "oryvex-vpn", version: 1, ready: true }), {
        status: 200,
        headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
      });
    }

    if (!METHODS.has(request.method)) return fail(405, "method not allowed");

    let target;
    try {
      target = new URL(here.searchParams.get("url") || "");
    } catch (_) {
      return fail(400, "url must be an https URL");
    }
    if (target.protocol !== "https:") return fail(400, "url must be an https URL");
    if (target.username || target.password || target.hash || (target.port && target.port !== "443")) {
      return fail(400, "target must not contain credentials, a fragment or a non-HTTPS port");
    }

    const host = target.hostname.toLowerCase();
    if (!allowedHost(host)) return fail(403, `host not allowed: ${host}`);

    let body;
    try {
      if (request.method !== "GET" && request.method !== "HEAD") body = await readBodyLimited(request);
    } catch (_) {
      return fail(413, "request body too large");
    }

    const aborter = new AbortController();
    const timer = setTimeout(() => aborter.abort("upstream timeout"), UPSTREAM_TIMEOUT_MS);
    let finished = false;
    const onFinish = () => { finished = true; };
    try {
      const upstream = await fetch(target, {
        method: request.method,
        headers: cleanHeaders(request.headers),
        body,
        redirect: "manual",
        signal: aborter.signal,
      });
      // Return redirects to the client without following them here. Each later
      // request through the relay is independently checked against the allowlist.
      const advertised = Number(upstream.headers.get("content-length"));
      if (Number.isFinite(advertised) && advertised > MAX_RESPONSE_BYTES) {
        clearTimeout(timer);
        await upstream.body?.cancel();
        return fail(502, "upstream response too large");
      }
      const responseHeaders = cleanHeaders(upstream.headers);
      responseHeaders.set("X-Oryvex-Relay", "1");
      responseHeaders.set("Cache-Control", "no-store");
      responseHeaders.set("X-Content-Type-Options", "nosniff");
      const responseBody = limitResponse(upstream.body, aborter, timer, onFinish);
      if (!responseBody) clearTimeout(timer);
      return new Response(responseBody, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: responseHeaders,
      });
    } catch (_) {
      clearTimeout(timer);
      if (!finished) aborter.abort();
      return fail(502, "upstream request failed");
    }
  },
};
