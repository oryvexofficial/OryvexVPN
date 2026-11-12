// ============================================================================
// VEXOSTREAM: Cloudflare Edge Worker
// UI, native HLS player, embed engine, status page, admin panel, Telegram bot.
// Design: app shell (sidebar + top bar, tab bar on phones), Bricolage Grotesque + Inter,
// same light/dark palette, self-healing HLS player with resume + auto quality,
// dotted Natural Earth globe on canvas for the edge tile.
// Single-file deploy: `npx wrangler deploy` (see wrangler.toml).
// ============================================================================

// ----------------------------------------------------------------------------
// CONFIG
// Values can be supplied with Worker variables/secrets. The owner may override
// the Telegram token from the admin panel; that value is encrypted in D1 using
// STREAM_SIGN_SECRET. Signing secrets remain Worker-managed.
// ----------------------------------------------------------------------------
const DEFAULTS = {
    RAILWAY_URL: 'https://rhrh-development-zbxsf.lucity.app',
    TELEGRAM_BOT_TOKEN: '',
    STREAM_SIGN_SECRET: '',
    EDGE_TOKEN: '',
    ADMIN_PATH: '/adminpanel',
    // username -> sha256(password) hex. Override with ADMIN_USERS='{"name":"<sha256>"}'
    ADMIN_USERS: {},
    SITE_NAME: 'VexoStream',
    CREATOR: 'Muvixo'
};

let BACKEND_URL_BASE = DEFAULTS.RAILWAY_URL;
let RAILWAY_URL = DEFAULTS.RAILWAY_URL;
let TELEGRAM_WORKER_TOKEN = DEFAULTS.TELEGRAM_BOT_TOKEN;
let TELEGRAM_BOT_TOKEN = DEFAULTS.TELEGRAM_BOT_TOKEN;
let TELEGRAM_API = 'https://api.telegram.org/bot' + TELEGRAM_BOT_TOKEN;
let STREAM_SIGN_SECRET = DEFAULTS.STREAM_SIGN_SECRET;
let EDGE_TOKEN = DEFAULTS.EDGE_TOKEN;
let ADMIN_PATH = DEFAULTS.ADMIN_PATH;
let ADMIN_SESSION_SECRET = 'vx_admin_' + STREAM_SIGN_SECRET;
let ADMIN_USERS = DEFAULTS.ADMIN_USERS;

const TOKEN_TTL_SECONDS = 86400;
const ADMIN_SESSION_TTL = 60 * 60 * 12;
const ADMIN_COOKIE_NAME = 'vexo_admin_session';
const CACHE_TTL = { image: 86400, api: 300 };
const PROVIDERS = [
    { id: 'pornhub', name: 'Pornhub', domain: 'pornhub.com' },
    { id: 'xvideos', name: 'XVideos', domain: 'xvideos.com' },
    { id: 'xnxx', name: 'XNXX', domain: 'xnxx.com' },
    { id: 'redtube', name: 'RedTube', domain: 'redtube.com' },
    { id: 'youporn', name: 'YouPorn', domain: 'youporn.com' }
];
const PROVIDER_MODES = ['live', 'hidden', 'locked'];

let __configured = false;
function initConfig(env) {
    initSeoConfig(env);
    if (__configured || !env) return;
    __configured = true;
    const pick = (k) => (typeof env[k] === 'string' && env[k].trim()) ? env[k].trim() : null;
    BACKEND_URL_BASE = (pick('RAILWAY_URL') || pick('BACKEND_URL') || DEFAULTS.RAILWAY_URL).replace(/\/+$/, '');
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(BACKEND_URL_BASE)) BACKEND_URL_BASE = 'http://' + BACKEND_URL_BASE;
    BACKEND_IP_RESOLVER = pick('BACKEND_IP_RESOLVER') || 'sslip.io';
    RAILWAY_URL = fetchableBackendUrl(BACKEND_URL_BASE);
    TELEGRAM_WORKER_TOKEN = pick('TELEGRAM_BOT_TOKEN') || DEFAULTS.TELEGRAM_BOT_TOKEN;
    TELEGRAM_BOT_TOKEN = TELEGRAM_WORKER_TOKEN;
    TELEGRAM_API = 'https://api.telegram.org/bot' + TELEGRAM_BOT_TOKEN;
    STREAM_SIGN_SECRET = pick('STREAM_SIGN_SECRET') || DEFAULTS.STREAM_SIGN_SECRET;
    EDGE_TOKEN = pick('EDGE_TOKEN') || DEFAULTS.EDGE_TOKEN;
    ADMIN_PATH = '/' + (pick('ADMIN_PATH') || DEFAULTS.ADMIN_PATH).replace(/^\/+|\/+$/g, '');
    ADMIN_SESSION_SECRET = pick('ADMIN_SESSION_SECRET') || ('vx_admin_' + STREAM_SIGN_SECRET);
    const users = pick('ADMIN_USERS');
    if (users) {
        try {
            const parsed = JSON.parse(users);
            if (parsed && typeof parsed === 'object') ADMIN_USERS = parsed;
        } catch (_) { /* keep defaults */ }
    }
}

// ----------------------------------------------------------------------------
// SMALL HELPERS
// ----------------------------------------------------------------------------
function escapeHtml(text) {
    if (text === null || text === undefined) return '';
    return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// JSON that is safe to drop inside <script>...</script>
function jsonForScript(value) {
    return JSON.stringify(value)
        .replace(/</g, '\\u003c').replace(/>/g, '\\u003e')
        .replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

// Unicode-safe base64url (btoa alone throws on non-Latin1 characters)
function b64urlEncode(str) {
    const bytes = new TextEncoder().encode(String(str));
    let bin = '';
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(b64) {
    let s = String(b64).replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    const bin = atob(s);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder().decode(bytes);
}

function timingSafeEqual(a, b) {
    a = String(a || ''); b = String(b || '');
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return diff === 0;
}

function jsonResponse(data, status = 200, extra = {}) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { 'Content-Type': 'application/json;charset=UTF-8', 'Access-Control-Allow-Origin': '*', ...extra }
    });
}

async function timedFetch(url, init = {}, ms = 5000) {
    const ctrl = new AbortController();
    const id = setTimeout(() => ctrl.abort(), ms);
    try {
        return await fetch(url, { ...init, signal: ctrl.signal });
    } finally {
        clearTimeout(id);
    }
}

// ----------------------------------------------------------------------------
// SOCIAL CARDS
// ----------------------------------------------------------------------------
const SOCIAL_BOT_USER_AGENTS = [
    'bot', 'spider', 'crawler', 'discordbot', 'telegrambot', 'twitterbot',
    'facebookexternalhit', 'whatsapp', 'slackbot', 'vkshare', 'w3c_validator',
    'redditbot', 'applebot', 'bingbot', 'googlebot', 'yandexbot'
];

function isSocialEmbedBot(userAgent) {
    const ua = (userAgent || '').toLowerCase();
    return SOCIAL_BOT_USER_AGENTS.some(bot => ua.includes(bot));
}

function buildSocialCardMetaTags({ title, description, url, image, video, robots, canonical, jsonld, imageAlt }: any) {
    const safeTitle = escapeHtml(title || DEFAULTS.SITE_NAME);
    const safeDesc = escapeHtml(description || SEO_DEFAULT_DESC);
    const pageUrl = seoUrl(url || '/');
    const safeUrl = escapeHtml(pageUrl);
    const robotsValue = robots || SEO_INDEX;
    const indexable = !/noindex/i.test(robotsValue);
    let directImg = image || '';
    if (directImg && directImg.includes('/proxy-image')) {
        try {
            const parsed = new URL(directImg, pageUrl);
            const targetParam = parsed.searchParams.get('url');
            if (targetParam) directImg = targetParam;
        } catch (_) {}
    }
    const hasOwnImage = !!directImg;
    if (!directImg) directImg = SEO_ORIGIN + '/assets/brand/vexostream-mark-512.png';
    directImg = escapeHtml(directImg);
    const safeVid = escapeHtml(video || '');
    const safeAlt = escapeHtml(imageAlt || title || 'VexoStream');

    let meta = '<title>' + safeTitle + '</title>' +
        '<meta name="description" content="' + safeDesc + '">' +
        '<meta name="robots" content="' + escapeHtml(robotsValue) + '">' +
        // Adult-content labels: Google SafeSearch + RTA parental filters.
        '<meta name="rating" content="adult">' +
        '<meta name="RATING" content="RTA-5042-1996-1400-1577-RTA">' +
        (indexable && canonical !== false ? '<link rel="canonical" href="' + escapeHtml(canonical ? seoUrl(canonical) : pageUrl) + '">' : '') +
        '<meta property="og:site_name" content="VexoStream">' +
        '<meta property="og:locale" content="en_US">' +
        '<meta property="og:type" content="' + (safeVid ? 'video.other' : 'website') + '">' +
        '<meta property="og:url" content="' + safeUrl + '">' +
        '<meta property="og:title" content="' + safeTitle + '">' +
        '<meta property="og:description" content="' + safeDesc + '">' +
        '<meta property="og:image" content="' + directImg + '">' +
        '<meta property="og:image:alt" content="' + safeAlt + '">' +
        '<meta name="twitter:card" content="' + (hasOwnImage ? 'summary_large_image' : 'summary') + '">' +
        '<meta name="twitter:title" content="' + safeTitle + '">' +
        '<meta name="twitter:description" content="' + safeDesc + '">' +
        '<meta name="twitter:image" content="' + directImg + '">';
    if (hasOwnImage) {
        meta += '<meta property="og:image:secure_url" content="' + directImg + '">' +
            '<meta property="og:image:width" content="1280">' +
            '<meta property="og:image:height" content="720">';
    } else {
        meta += '<meta property="og:image:width" content="512"><meta property="og:image:height" content="512">';
    }
    if (safeVid) {
        meta += '<meta property="og:video" content="' + safeVid + '">' +
            '<meta property="og:video:secure_url" content="' + safeVid + '">' +
            '<meta property="og:video:type" content="text/html">' +
            '<meta property="og:video:width" content="1280">' +
            '<meta property="og:video:height" content="720">';
    }
    if (jsonld) meta += jsonld;
    return meta;
}

// ----------------------------------------------------------------------------
// SIGNED MEDIA TOKENS (HMAC-SHA256, bound to client IP)
// ----------------------------------------------------------------------------
const __hmacKeys = new Map();
async function generateHmacSha256(message, secret) {
    const enc = new TextEncoder();
    let key = __hmacKeys.get(secret);
    if (!key) {
        key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
        __hmacKeys.set(secret, key);
    }
    const signature = await crypto.subtle.sign('HMAC', key, enc.encode(message));
    return Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('');
}

async function sha256Hex(text) {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}

function clientIpOf(request) {
    return request.headers.get('CF-Connecting-IP') || '0.0.0.0';
}

async function createSignedMediaToken(clientIp) {
    const expires = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
    const sig = await generateHmacSha256(clientIp + ':' + expires, STREAM_SIGN_SECRET);
    return { exp: expires, token: sig };
}

async function verifyMediaToken(clientIp, expiresStr, providedSig) {
    if (!expiresStr || !providedSig) return false;
    const expires = parseInt(expiresStr, 10);
    if (isNaN(expires) || Math.floor(Date.now() / 1000) > expires) return false;
    const expectedSig = await generateHmacSha256(clientIp + ':' + expires, STREAM_SIGN_SECRET);
    return timingSafeEqual(expectedSig, providedSig);
}

async function telegramWebhookSecret() {
    return (await generateHmacSha256('telegram-webhook', STREAM_SIGN_SECRET)).slice(0, 48);
}

// ----------------------------------------------------------------------------
// ANTI-SCRAPE + SSRF GUARD
// ----------------------------------------------------------------------------
const EXTENDED_BLOCKED_USER_AGENTS = [
    'httrack', 'webhttrack', 'offline explorer', 'teleport', 'teleportpro',
    'webcopier', 'sitecheck', 'sitechecker', 'grabber', 'extractor',
    'yt-dlp', 'youtube-dl', 'python-requests', 'python-urllib', 'aiohttp',
    'httpx', 'curl', 'wget', 'go-http-client', 'scrapy', 'postmanruntime',
    'axios', 'node-fetch', 'httpclient', 'phantomjs', 'selenium', 'puppeteer',
    'playwright', 'headlesschrome', 'urllib', 'libwww-perl', 'nikto',
    'sqlmap', 'nmap', 'masscan', 'zgrab', 'internet-measurement', 'archive.org_bot'
];

const SECURE_HTML_HEADERS = {
    'Content-Type': 'text/html;charset=UTF-8',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=()'
};

const EMBED_HTML_HEADERS = {
    'Content-Type': 'text/html;charset=UTF-8',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': 'frame-ancestors *',
    'Referrer-Policy': 'strict-origin-when-cross-origin'
};

function isPrivateHost(hostname) {
    const h = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '');
    if (!h) return true;
    if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || h === 'metadata.google.internal') return true;
    const v4 = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
    if (v4) {
        const a = +v4[1], b = +v4[2];
        if (a === 0 || a === 10 || a === 127) return true;
        if (a === 169 && b === 254) return true;
        if (a === 172 && b >= 16 && b <= 31) return true;
        if (a === 192 && b === 168) return true;
        if (a === 100 && b >= 64 && b <= 127) return true;
        if (a >= 224) return true;
        return false;
    }
    if (h.includes(':')) {
        if (h === '::' || h === '::1') return true;
        if (h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80')) return true;
        if (h.startsWith('::ffff:')) return isPrivateHost(h.slice(7));
    }
    return false;
}

async function isScraperOrAttack(request, url) {
    if (url.pathname === '/webhook') return { blocked: false };
    const userAgent = (request.headers.get('User-Agent') || '').trim().toLowerCase();

    const isPrivatePath = url.pathname.startsWith('/api/') || url.pathname.startsWith('/proxy-');
    if (!isPrivatePath && isSocialEmbedBot(userAgent)) return { blocked: false };

    if (!userAgent || userAgent.length < 12) {
        return { blocked: true, reason: 'Security verification required: missing or invalid client identity.' };
    }
    for (const signature of EXTENDED_BLOCKED_USER_AGENTS) {
        if (userAgent.includes(signature)) {
            return { blocked: true, reason: 'Automated scrapers and harvesting tools are not allowed.' };
        }
    }

    if (url.pathname === '/proxy-m3u8' || url.pathname === '/proxy-video') {
        const token = url.searchParams.get('sig');
        const exp = url.searchParams.get('exp');
        if (!token || !exp) return { blocked: true, reason: 'Missing stream signature.' };
        const isValid = await verifyMediaToken(clientIpOf(request), exp, token);
        if (!isValid) return { blocked: true, reason: 'Invalid or expired media token.' };
    }

    const target = url.searchParams.get('url');
    if (target) {
        try {
            const t = target.trim().startsWith('//') ? 'https:' + target.trim() : target.trim();
            const parsedTarget = new URL(t);
            if (parsedTarget.protocol !== 'http:' && parsedTarget.protocol !== 'https:') {
                return { blocked: true, reason: 'Unsupported protocol scheme.' };
            }
            if (isPrivateHost(parsedTarget.hostname)) {
                return { blocked: true, reason: 'Restricted network destination.' };
            }
        } catch (_) {
            return { blocked: true, reason: 'Malformed resource parameter.' };
        }
    }
    return { blocked: false };
}

// ============================================================================
// BACKEND FORWARDING (Railway / any host running VexoStream-Core)
// ============================================================================
function refererFor(target) {
    const t = String(target || '').toLowerCase();
    if (t.includes('xvideos')) return 'https://www.xvideos.com/';
    if (t.includes('xnxx')) return 'https://www.xnxx.com/';
    if (t.includes('redtube') || t.includes('rdtcdn')) return 'https://www.redtube.com/';
    if (t.includes('babewiki')) return 'https://babewiki.com/';
    if (t.includes('youporn') || t.includes('ypncdn')) return 'https://www.youporn.com/';
    return 'https://www.pornhub.com/';
}

async function forwardToRailway(request, ctx, signingRequest = request) {
    const url = new URL(request.url);
    const railwayTarget = RAILWAY_URL + url.pathname + url.search;
    const cache = caches.default;
    const isGet = request.method === 'GET';
    const noCache = url.pathname === '/api/extract' || url.pathname === '/api/posters' || url.pathname.startsWith('/api/explore');

    if (isGet && !noCache) {
        try {
            const cached = await cache.match(request);
            if (cached) return cached;
        } catch (_) {}
    }

    const headers = new Headers();
    headers.set('User-Agent', request.headers.get('User-Agent') || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    headers.set('Accept', 'application/json, text/plain, */*');
    headers.set('X-Edge-Token', EDGE_TOKEN);
    const targetParam = url.searchParams.get('url') || '';
    if (targetParam || url.pathname.includes('extract')) {
        const ref = refererFor(targetParam);
        headers.set('Referer', ref);
        headers.set('Origin', ref.replace(/\/$/, ''));
    }

    const init = { method: request.method, headers, redirect: 'follow' };
    if (request.method !== 'GET' && request.method !== 'HEAD' && request.body) init.body = request.body;

    try {
        if (url.pathname === '/api/extract') {
            const response = await timedFetch(railwayTarget, init, 60000);
            let data;
            try {
                data = await response.json();
            } catch (_) {
                return jsonResponse({ status: 'error', error: 'Backend returned an invalid response (' + response.status + ')' }, 502);
            }
            if (data && data.status === 'success' && data.streams) {
                // one signature per response: bind to the original client request IP + expiry
                const signed = await createSignedMediaToken(clientIpOf(signingRequest));
                for (const listName of ['qualities', 'fallback']) {
                    const list = Array.isArray(data.streams[listName]) ? data.streams[listName] : [];
                    for (const q of list) {
                        if (!q || !q.url) continue;
                        q.x_url = btoa(encodeURIComponent(q.url));
                        q.x_sig = signed.token;
                        q.x_exp = signed.exp;
                        delete q.url;
                    }
                }
            }
            return jsonResponse(data, 200, { 'Cache-Control': 'no-store' });
        }

        const response = await timedFetch(railwayTarget, init, 30000);
        const body = await response.arrayBuffer();
        const out = new Headers(response.headers);
        out.set('Access-Control-Allow-Origin', '*');
        out.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        out.set('Access-Control-Allow-Headers', '*');
        out.delete('set-cookie');
        out.delete('content-encoding');
        out.delete('content-length');
        if (isGet && response.status === 200) out.set('Cache-Control', 'public, max-age=' + CACHE_TTL.api);
        const finalResponse = new Response(body, { status: response.status, statusText: response.statusText, headers: out });
        if (isGet && !noCache && response.status === 200) ctx.waitUntil(cache.put(request, finalResponse.clone()).catch(() => {}));
        return finalResponse;
    } catch (err) {
        return jsonResponse({ status: 'error', error: 'Backend unreachable' }, 502);
    }
}

// ============================================================================
// IMAGE PROXY
// ============================================================================
async function handleImageProxy(request, ctx) {
    const reqUrl = new URL(request.url);
    let targetUrl = (reqUrl.searchParams.get('url') || '').trim();
    if (!targetUrl) return new Response('Missing URL', { status: 400 });
    if (targetUrl.startsWith('//')) targetUrl = 'https:' + targetUrl;
    try {
        const parsed = new URL(targetUrl);
        if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') || parsed.username || parsed.password || isPrivateHost(parsed.hostname)) {
            return new Response('Restricted image URL', { status: 400 });
        }
        if (/\.(webm|mp4|m3u8|ts|m4s)$/i.test(parsed.pathname)) return new Response('Invalid format', { status: 403 });
    } catch (_) {
        return new Response('Bad URL', { status: 400 });
    }

    const cache = caches.default;
    const cacheKey = new Request(reqUrl.origin + '/proxy-image?url=' + encodeURIComponent(targetUrl), { method: 'GET' });
    try {
        const cached = await cache.match(cacheKey);
        if (cached) return cached;
    } catch (_) {}

    try {
        const h = new Headers();
        h.set('User-Agent', request.headers.get('User-Agent') || 'Mozilla/5.0');
        h.set('Accept', 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8');
        h.set('Referer', refererFor(targetUrl));
        h.set('Sec-Fetch-Mode', 'no-cors');

        const isImage = (r) => !!(r && r.ok && /^image\//i.test(r.headers.get('content-type') || ''));
        let res = await timedFetch(targetUrl, { headers: h, redirect: 'follow' }, 12000).catch(() => null);
        if (!res || !res.ok) return new Response('CDN error', { status: res ? res.status : 502 });

        const contentType = (res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
        if (!/^image\//i.test(contentType)) return new Response('Not an image', { status: 415 });
        const size = Number(res.headers.get('content-length') || 0);
        if (size > 12 * 1024 * 1024) return new Response('Image too large', { status: 413 });
        const buf = await res.arrayBuffer();
        const out = new Headers();
        out.set('Content-Type', contentType);
        out.set('Access-Control-Allow-Origin', '*');
        out.set('Cache-Control', 'public, max-age=' + CACHE_TTL.image);
        const response = new Response(buf, { status: 200, headers: out });
        ctx.waitUntil(cache.put(cacheKey, response.clone()).catch(() => {}));
        return response;
    } catch (_) {
        return new Response('Image proxy failed', { status: 502 });
    }
}

// ============================================================================
// MEDIA PROXY  Browser -> Worker -> CDN directly.
// The backend only scrapes/extracts metadata and stream URLs; it never carries media.
// One signature per playlist keeps long VOD playlists under the CPU limit.
// ============================================================================
function signedWorkerMediaUrl(endpoint, mediaUrl, origin, signed) {
    const output = new URL(endpoint, origin);
    output.searchParams.set('url', mediaUrl);
    output.searchParams.set('sig', signed.token);
    output.searchParams.set('exp', String(signed.exp));
    return output.toString();
}

function mediaEndpointFor(absUrl) {
    return absUrl.split('#')[0].toLowerCase().includes('.m3u8') ? '/proxy-m3u8' : '/proxy-video';
}

function playlistUriToWorker(uri, playlistUrl, origin, signed) {
    let parsed;
    try { parsed = new URL(uri, playlistUrl); } catch (_) { return uri; }
    if ((parsed.pathname === '/proxy-m3u8' || parsed.pathname === '/proxy-video') && parsed.searchParams.get('url')) {
        return signedWorkerMediaUrl(parsed.pathname, parsed.searchParams.get('url'), origin, signed);
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return uri;
    let abs = parsed.toString();
    try {
        const pl = new URL(playlistUrl);
        // CDN tokens (validfrom/validto/hash) usually sit only on the playlist URL
        if (pl.search && !parsed.search && pl.pathname !== '/proxy-m3u8') abs += pl.search;
    } catch (_) {}
    return signedWorkerMediaUrl(mediaEndpointFor(abs), abs, origin, signed);
}

function rewritePlaylist(text, playlistUrl, origin, signed) {
    const out = [];
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim();
        if (!line) continue;
        if (line.startsWith('#')) {
            out.push(line.replace(/URI="([^"]+)"/g, (m, u) => 'URI="' + playlistUriToWorker(u, playlistUrl, origin, signed) + '"'));
        } else {
            out.push(playlistUriToWorker(line, playlistUrl, origin, signed));
        }
    }
    return out.join('\n') + '\n';
}

function cdnHeadersFor(target, request) {
    const h = new Headers();
    const ref = refererFor(target);
    h.set('Referer', ref);
    h.set('Origin', ref.replace(/\/$/, ''));
    h.set('User-Agent', request.headers.get('User-Agent') || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
    h.set('Accept', '*/*');
    for (const name of ['range', 'if-range']) {
        const v = request.headers.get(name);
        if (v) h.set(name, v);
    }
    return h;
}

function mediaResponseHeaders(src) {
    const h = new Headers();
    for (const name of ['content-type', 'content-length', 'content-range', 'accept-ranges', 'last-modified', 'etag']) {
        const v = src.get(name);
        if (v) h.set(name, v);
    }
    if (!h.get('accept-ranges')) h.set('Accept-Ranges', 'bytes');
    h.set('Access-Control-Allow-Origin', '*');
    h.set('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length, Content-Type');
    return h;
}

async function playlistResponse(res, playlistUrl, request, url) {
    const text = await res.text();
    if (!text.includes('#EXTM3U')) return null;
    const signed = await createSignedMediaToken(clientIpOf(request));
    return new Response(rewritePlaylist(text, playlistUrl, url.origin, signed), {
        status: 200,
        headers: {
            'Content-Type': 'application/vnd.apple.mpegurl; charset=utf-8',
            'Cache-Control': 'no-store',
            'Access-Control-Allow-Origin': '*'
        }
    });
}

// One quiet retry for transient CDN failures (5xx, 429, dropped connections),
// so a single hiccup never reaches the player as a playback error.
async function fetchUpstreamMedia(target, request, isPlaylist) {
    const init: RequestInit = { method: request.method === 'HEAD' ? 'HEAD' : 'GET', headers: cdnHeadersFor(target, request), redirect: 'follow' };
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            const res = await timedFetch(target, init, isPlaylist ? 15000 : 25000);
            if (attempt === 0 && (res.status >= 500 || res.status === 429)) {
                try { if (res.body) await res.body.cancel(); } catch (_) {}
                await new Promise(r => setTimeout(r, 300));
                continue;
            }
            return res;
        } catch (err) {
            if (attempt === 1) throw err;
            await new Promise(r => setTimeout(r, 300));
        }
    }
    throw new Error('unreachable');
}

async function handleWorkerStreamProxy(request, url) {
    const mediaUrl = (url.searchParams.get('url') || '').trim();
    if (!mediaUrl) return new Response('Missing url', { status: 400, headers: { 'Access-Control-Allow-Origin': '*' } });
    const isPlaylist = url.pathname === '/proxy-m3u8';
    let target;
    try {
        target = new URL(mediaUrl);
        if (target.protocol !== 'http:' && target.protocol !== 'https:') throw new Error('unsupported protocol');
        if (isPrivateHost(target.hostname)) throw new Error('restricted destination');
    } catch (_) {
        return new Response('Invalid media URL', { status: 400, headers: { 'Access-Control-Allow-Origin': '*' } });
    }

    // Fetch all HLS playlists, segments, keys, and direct media from the Worker.
    // Do not send playback traffic through the scraping backend.
    try {
        const res = await fetchUpstreamMedia(target.toString(), request, isPlaylist);
        if (res.ok || res.status === 206) {
            if (isPlaylist) {
                const r = await playlistResponse(res, res.url || target.toString(), request, url);
                if (r) return r;
            } else {
                const h = mediaResponseHeaders(res.headers);
                // segments never change: let the browser keep them for back-seeks
                h.set('Cache-Control', 'private, max-age=900');
                return new Response(res.body, { status: res.status, headers: h });
            }
        }
        return new Response('Upstream refused the stream (' + res.status + ')', {
            status: res.status >= 400 ? res.status : 502,
            headers: { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store', 'X-Vexo-Upstream': String(res.status) }
        });
    } catch (_) {
        return new Response('Worker could not fetch the media stream', {
            status: 502,
            headers: { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
        });
    }
}

