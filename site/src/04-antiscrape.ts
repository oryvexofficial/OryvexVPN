// ============================================================================
// ANTI-SCRAPE LAYER
// 1. Per-visitor session tokens (IP + browser bound, short-lived) replace the
//    static EDGE_TOKEN in pages, so a copied token stops working elsewhere.
// 2. Browser fetch-metadata checks on the private APIs.
// 3. Per-IP rate limits with automatic temporary bans (per colo, via Cache API).
// 4. A honeypot link that only scrapers ignoring robots.txt will follow.
// ============================================================================
const SESSION_PLACEHOLDER = '__VX_SESSION_TOKEN__';
const SESSION_TTL_SECONDS = 6 * 3600;
const HONEYPOT_PATH = '/__vx/archive';
const BAN_PATH = '/__vx-ban/';
const __bans = new Map();

// requests per minute, per IP, per bucket
const RATE_LIMITS = {
    extract: 30,
    api: 120,
    image: 600,
    media: 4000,
    page: 150
};
const BAN_SECONDS = { flood: 15 * 60, honeypot: 30 * 60 };

const API_AUTOMATION_HINTS = ['headless', 'scrap', 'crawl', 'spider', 'bot/', 'java/', 'okhttp', 'undici', 'deno/', 'bun/', 'ruby', 'perl', 'php/', 'powershell', 'libcurl', 'insomnia', 'httpie'];

// IPv6 users rotate addresses inside their /64, so bind to the prefix.
function ipKeyOf(request) {
    const ip = clientIpOf(request);
    if (ip.includes(':')) return ip.split(':').slice(0, 4).join(':') + '::/64';
    return ip;
}

async function uaHashOf(request) {
    return (await sha256Hex(String(request.headers.get('User-Agent') || '').slice(0, 300))).slice(0, 16);
}

async function createSessionToken(request) {
    const exp = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
    const sig = await generateHmacSha256('sess:' + ipKeyOf(request) + ':' + (await uaHashOf(request)) + ':' + exp, STREAM_SIGN_SECRET);
    return 'v1.' + exp + '.' + sig.slice(0, 40);
}

async function verifySessionToken(request, token) {
    const m = /^v1\.(\d{9,11})\.([a-f0-9]{40})$/.exec(String(token || ''));
    if (!m) return false;
    const exp = parseInt(m[1], 10);
    if (Math.floor(Date.now() / 1000) > exp) return false;
    const sig = await generateHmacSha256('sess:' + ipKeyOf(request) + ':' + (await uaHashOf(request)) + ':' + exp, STREAM_SIGN_SECRET);
    return timingSafeEqual(sig.slice(0, 40), m[2]);
}

// Private endpoints: page token (browsers) or EDGE_TOKEN in the header (your own server tools).
async function isApiCallerAllowed(request, url) {
    // Googlebot renders pages from other IPs than the HTML fetch, so its page token
    // never matches. Let verified crawlers read the public catalogue (never streams).
    if (isCrawlerReadablePath(url.pathname) && isTrustedSearchBot(request)) return { ok: true, trusted: false };
    const headerToken = request.headers.get('X-Edge-Token') || '';
    if (headerToken && timingSafeEqual(headerToken, EDGE_TOKEN)) return { ok: true, trusted: true };
    const token = headerToken || url.searchParams.get('token') || '';
    if (!(await verifySessionToken(request, token))) return { ok: false, reason: 'Session expired. Refresh the page.', code: 'session' };

    const ua = String(request.headers.get('User-Agent') || '').toLowerCase();
    if (API_AUTOMATION_HINTS.some(h => ua.includes(h))) return { ok: false, reason: 'Automated clients are not allowed.' };

    const site = request.headers.get('Sec-Fetch-Site');
    if (site) {
        if (site !== 'same-origin') return { ok: false, reason: 'Cross-site API use is not allowed.' };
        if (request.headers.get('Sec-Fetch-Mode') === 'navigate' && url.pathname.startsWith('/api/')) return { ok: false, reason: 'Open the site to use this.' };
    } else if (!request.headers.get('Accept-Language')) {
        // Every real browser sends Accept-Language; bare HTTP clients usually don't.
        return { ok: false, reason: 'Security verification required.' };
    }
    return { ok: true, trusted: false };
}

// --------------------------------------------------------------------------- rate limit
const __rate = new Map();
function rateBucketFor(path) {
    if (path === '/api/extract' || path === '/api/v1/videos/extract') return 'extract';
    if (path === '/api/v1/image') return 'image';
    if (path === '/proxy-m3u8' || path === '/proxy-video') return 'media';
    if (path === '/proxy-image') return 'image';
    if (path.startsWith('/api/')) return 'api';
    return 'page';
}

function hitRate(ipKey, bucket) {
    const minute = Math.floor(Date.now() / 60000);
    const key = bucket + '|' + ipKey;
    let e = __rate.get(key);
    if (!e || e.m !== minute) { e = { m: minute, n: 0 }; __rate.set(key, e); }
    e.n++;
    if (__rate.size > 20000) {
        for (const [k, v] of __rate) if (v.m !== minute) __rate.delete(k);
    }
    return e.n;
}

async function isBanned(origin, ipKey) {
    const local = __bans.get(ipKey);
    if (local && local > Date.now()) return true;
    if (local) __bans.delete(ipKey);
    try { return !!(await caches.default.match(new Request(origin + BAN_PATH + encodeURIComponent(ipKey)))); } catch (_) { return false; }
}

async function banIp(origin, ipKey, seconds, reason, ctx) {
    __bans.set(ipKey, Date.now() + seconds * 1000);
    if (__bans.size > 5000) { const now = Date.now(); for (const [k, v] of __bans) if (v < now) __bans.delete(k); }
    // Cache API shares the ban with every isolate in this Cloudflare location (custom domains only).
    const p = caches.default.put(new Request(origin + BAN_PATH + encodeURIComponent(ipKey)), new Response(reason, { headers: { 'Cache-Control': 'public, max-age=' + seconds } })).catch(() => {});
    if (ctx && ctx.waitUntil) ctx.waitUntil(p); else await p;
}

function blockedResponse(path, status, message, retryAfter) {
    const headers = { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex, nofollow' };
    if (retryAfter) headers['Retry-After'] = String(retryAfter);
    if (path.startsWith('/api/') || path.startsWith('/proxy-')) return jsonResponse({ status: 'error', error: message }, status, headers);
    return new Response('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Slow down</title><body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#000;color:#f5f5f7;font:17px/1.5 -apple-system,system-ui,sans-serif;text-align:center;padding:24px"><div><b style="display:block;font-size:24px;margin-bottom:6px">' + escapeHtml(message) + '</b><span style="color:#a1a1a6">Try again in a few minutes.</span></div>', { status, headers: { ...headers, 'Content-Type': 'text/html;charset=UTF-8' } });
}

// Runs before routing. Returns a Response to stop the request, or null.
async function antiScrapeGate(request, url, env, ctx) {
    const path = url.pathname;
    if (path === '/webhook' || path === '/favicon.ico' || path === '/favicon.svg' || path === '/robots.txt') return null;
    // Verified search engines (Googlebot, Bingbot...) share IPs and crawl fast:
    // never rate-limit or ban them, or the site drops out of Google.
    if (isTrustedSearchBot(request)) {
        if (path === HONEYPOT_PATH || path.startsWith(HONEYPOT_PATH + '/') || path.startsWith(BAN_PATH)) return blockedResponse(path, 404, 'Not found.', 0);
        return null;
    }
    const ipKey = ipKeyOf(request);

    if (path === HONEYPOT_PATH || path.startsWith(HONEYPOT_PATH + '/')) {
        await banIp(url.origin, ipKey, BAN_SECONDS.honeypot, 'honeypot', ctx);
        return blockedResponse(path, 403, 'Access blocked.', BAN_SECONDS.honeypot);
    }
    if (path.startsWith(BAN_PATH)) return blockedResponse(path, 404, 'Not found.', 0);
    if (await isBanned(url.origin, ipKey)) return blockedResponse(path, 429, 'Too many requests.', 600);

    const bucket = rateBucketFor(path);
    let limited = false;
    // Optional Cloudflare rate-limit binding (shared across all isolates in a colo).
    if (env && env.RATE_LIMITER && typeof env.RATE_LIMITER.limit === 'function' && bucket !== 'media') {
        try { const r = await env.RATE_LIMITER.limit({ key: bucket + '|' + ipKey }); limited = !r.success; } catch (_) {}
    }
    const n = hitRate(ipKey, bucket);
    const limit = RATE_LIMITS[bucket];
    if (n > limit * 3) { await banIp(url.origin, ipKey, BAN_SECONDS.flood, 'flood', ctx); return blockedResponse(path, 429, 'Too many requests.', BAN_SECONDS.flood); }
    if (limited || n > limit) return blockedResponse(path, 429, 'Too many requests.', 60);
    return null;
}

// Swap the page placeholder for a token bound to this visitor.
async function injectSessionToken(response, request) {
    const type = response.headers.get('Content-Type') || '';
    if (!/text\/html/i.test(type) || !response.body) return response;
    const html = await response.text();
    if (!html.includes(SESSION_PLACEHOLDER)) return new Response(html, response);
    const token = await createSessionToken(request);
    const headers = new Headers(response.headers);
    headers.set('Cache-Control', 'private, no-store');
    headers.delete('Content-Length');
    return new Response(html.split(SESSION_PLACEHOLDER).join(token), { status: response.status, statusText: response.statusText, headers });
}
