// ============================================================================
// CHECK HOST: authorized ping / HTTP / TCP / DNS checks
// ----------------------------------------------------------------------------
// Regional probes use Check-Host.net's documented server-side API, with the
// Globalping API as a fallback. Both are called only by the Worker, so browser
// requests stay on VexoStream. The default allowlist is vexostream.bond and
// its subdomains; CHECK_HOST_ALLOWED_HOSTS can add explicitly authorized roots
// or exact IPs. Never use this as an unrestricted distributed scanner.
// ============================================================================
const CH_API = 'https://check-host.net';
const CH_UA = 'VexoStream-CheckHost/1.1 (+https://vexostream.bond/check-host)';
const CH_TYPES = ['ping', 'http', 'tcp', 'dns'];
const CH_COUNTRIES = [
    { cc: 'ir', name: 'Iran', max: 4 },
    { cc: 'us', name: 'United States', max: 3 },
    { cc: 'de', name: 'Germany', max: 2 },
    { cc: 'gb', name: 'United Kingdom', max: 1 },
    { cc: 'fr', name: 'France', max: 1 },
    { cc: 'nl', name: 'Netherlands', max: 2 }
];
const CH_CC = CH_COUNTRIES.map(c => c.cc);
// Used when the live node list can't be fetched (refreshed hourly otherwise).
const CH_FALLBACK_NODES = {
    'ir1.node.check-host.net': ['ir', 'Iran', 'Tehran', '185.105.238.209', 'AS47430'],
    'ir2.node.check-host.net': ['ir', 'Iran', 'Isfahan', '195.182.38.164', 'AS209279'],
    'ir3.node.check-host.net': ['ir', 'Iran', 'Shiraz', '77.104.108.3', 'AS213953'],
    'ir6.node.check-host.net': ['ir', 'Iran', 'Qom', '45.135.242.142', 'AS206596'],
    'us1.node.check-host.net': ['us', 'USA', 'Los Angeles', '38.145.202.12', 'AS18978'],
    'us2.node.check-host.net': ['us', 'USA', 'Dallas', '64.72.205.76', 'AS215703'],
    'us5.node.check-host.net': ['us', 'USA', 'New York', '162.217.248.181', 'AS213535'],
    'de1.node.check-host.net': ['de', 'Germany', 'Nuremberg', '142.132.174.167', 'AS24940'],
    'de4.node.check-host.net': ['de', 'Germany', 'Frankfurt', '185.37.147.117', 'AS34549'],
    'uk1.node.check-host.net': ['gb', 'UK', 'London', '107.181.134.162', 'AS213535'],
    'fr2.node.check-host.net': ['fr', 'France', 'Paris', '195.154.114.92', 'AS12876'],
    'nl1.node.check-host.net': ['nl', 'Netherlands', 'Amsterdam', '185.209.161.145', 'AS14576'],
    'nl2.node.check-host.net': ['nl', 'Netherlands', 'Meppel', '195.211.27.85', 'AS206446']
};

let __chNodes = { at: 0, nodes: null };
async function checkHostNodes() {
    if (__chNodes.nodes && Date.now() - __chNodes.at < 3600000) return __chNodes.nodes;
    try {
        const r = await timedFetch(CH_API + '/nodes/hosts', { headers: { 'Accept': 'application/json', 'User-Agent': CH_UA }, redirect: 'manual' }, 5000);
        if (r.ok) {
            const data: any = await r.json();
            const out = {};
            for (const [id, n] of Object.entries((data && data.nodes) || {}) as [string, any][]) {
                if (!/^[a-z0-9-]+\.node\.check-host\.net$/i.test(id)) continue;
                const loc = (n && n.location) || [];
                let cc = String(loc[0] || '').toLowerCase();
                if (cc === 'uk') cc = 'gb';
                if (!CH_CC.includes(cc)) continue;
                out[id] = [cc, String(loc[1] || ''), String(loc[2] || ''), String(n.ip || ''), String(n.asn || '').trim()];
            }
            if (Object.keys(out).length >= 4) { __chNodes = { at: Date.now(), nodes: out }; return out; }
        }
    } catch (_) {}
    __chNodes = { at: Date.now() - 3300000, nodes: CH_FALLBACK_NODES }; // retry in ~5 min
    return CH_FALLBACK_NODES;
}

// Spread picks across cities so 3 US nodes are LA / Dallas / New York, not 3x LA.
function pickCheckHostNodes(all, wanted) {
    const picked = [];
    for (const c of CH_COUNTRIES) {
        if (!wanted.includes(c.cc)) continue;
        const ids = Object.keys(all).filter(id => all[id][0] === c.cc).sort();
        const seen = new Set(), first = [], rest = [];
        for (const id of ids) { const city = all[id][2]; (seen.has(city) ? rest : first).push(id); seen.add(city); }
        picked.push(...first.concat(rest).slice(0, c.max));
    }
    return picked;
}

// ---------------------------------------------------------------------------- input and authorization
function parseCheckHostV4(host) {
    if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return null;
    const bytes = host.split('.').map(Number);
    return bytes.every(n => n >= 0 && n <= 255) ? bytes : null;
}
function isPublicCheckHostV4(host) {
    const b = parseCheckHostV4(host);
    if (!b) return false;
    const [a, c, d] = b;
    if (a === 0 || a === 10 || a === 127 || a >= 224) return false;
    if (a === 100 && c >= 64 && c <= 127) return false;
    if (a === 169 && c === 254) return false;
    if (a === 172 && c >= 16 && c <= 31) return false;
    if (a === 192 && c === 168) return false;
    if (a === 192 && c === 0 && d === 0) return false;
    if (a === 192 && c === 0 && d === 2) return false;
    if (a === 192 && c === 88 && d === 99) return false;
    if (a === 198 && (c === 18 || c === 19)) return false;
    if (a === 198 && c === 51 && d === 100) return false;
    if (a === 203 && c === 0 && d === 113) return false;
    return true;
}
function parseCheckHostV6(host) {
    let s = String(host || '').toLowerCase();
    if (!s.includes(':') || s.includes('%')) return null;
    if (s.includes('.')) {
        const at = s.lastIndexOf(':');
        const v4 = parseCheckHostV4(s.slice(at + 1));
        if (!v4) return null;
        s = s.slice(0, at) + ':' + ((v4[0] << 8) | v4[1]).toString(16) + ':' + ((v4[2] << 8) | v4[3]).toString(16);
    }
    const halves = s.split('::');
    if (halves.length > 2) return null;
    const left = halves[0] ? halves[0].split(':') : [];
    const right = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
    if (left.concat(right).some(x => !/^[0-9a-f]{1,4}$/.test(x))) return null;
    const missing = 8 - left.length - right.length;
    if ((halves.length === 1 && missing !== 0) || (halves.length === 2 && missing < 1)) return null;
    const groups = left.map(x => parseInt(x, 16)).concat(Array(Math.max(0, missing)).fill(0), right.map(x => parseInt(x, 16)));
    if (groups.length !== 8) return null;
    return groups;
}
function checkHostV6Key(groups) {
    let bestStart = -1, bestLength = 1;
    for (let i = 0; i < groups.length;) {
        if (groups[i] !== 0) { i++; continue; }
        let j = i;
        while (j < groups.length && groups[j] === 0) j++;
        if (j - i > bestLength) { bestStart = i; bestLength = j - i; }
        i = j;
    }
    const h = groups.map(x => x.toString(16));
    if (bestStart < 0) return h.join(':');
    return h.slice(0, bestStart).join(':') + '::' + h.slice(bestStart + bestLength).join(':');
}
function isPublicCheckHostV6(groups) {
    if (!groups || (groups[0] & 0xe000) !== 0x2000) return false; // global unicast only
    if (groups[0] === 0x2001 && groups[1] <= 0x01ff) return false; // special-purpose 2001::/23
    if (groups[0] === 0x2001 && groups[1] === 0x0db8) return false; // documentation
    if (groups[0] === 0x2002) return false; // deprecated 6to4
    if (groups[0] === 0x3fff && groups[1] <= 0x000f) return false; // documentation
    if (groups[0] === 0x2620 && groups[1] === 0x004f && groups[2] === 0x8000) return false; // special-purpose
    const mapped = groups.slice(0, 5).every(x => x === 0) && groups[5] === 0xffff;
    if (mapped) {
        const v4 = [groups[6] >> 8, groups[6] & 255, groups[7] >> 8, groups[7] & 255].join('.');
        return isPublicCheckHostV4(v4);
    }
    return true;
}
function configuredCheckHostAllowlist(env) {
    const roots = ['vexostream.bond'];
    const raw = String(env && env.CHECK_HOST_ALLOWED_HOSTS || '');
    for (const entry of raw.split(/[,\s]+/).map(x => x.trim().toLowerCase()).filter(Boolean)) {
        const host = entry.replace(/^\*\./, '').replace(/^\./, '').replace(/\.$/, '');
        if (/^[a-z0-9.-]{1,253}$/.test(host) && !host.includes('..')) roots.push(host);
        else if (host.includes(':') && parseCheckHostV6(host)) roots.push(checkHostV6Key(parseCheckHostV6(host)));
        else if (parseCheckHostV4(host)) roots.push(host);
    }
    return Array.from(new Set(roots));
}
function checkHostIsAuthorized(host, isIp, env) {
    const allowed = configuredCheckHostAllowlist(env);
    if (isIp) {
        const normalized = host.includes(':') ? checkHostV6Key(parseCheckHostV6(host)) : host;
        return allowed.some(entry => entry.includes(':') ? entry === normalized : entry === host);
    }
    return allowed.some(root => !root.includes(':') && !parseCheckHostV4(root) && (host === root || host.endsWith('.' + root)));
}
function configuredCheckHostPorts(env) {
    const raw = String(env && env.CHECK_HOST_ALLOWED_PORTS || '');
    const values = raw ? raw.split(/[,\s]+/) : ['80', '443'];
    return new Set(values.map(x => Number(x.trim())).filter(x => Number.isInteger(x) && x >= 1 && x <= 65535));
}
function parseCheckTarget(raw, type, portOverride) {
    let s = String(raw || '').trim();
    if (!s || s.length > 300) return { ok: false, error: 'Type a domain, IP or URL.' };
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) {
        const colons = (s.match(/:/g) || []).length;
        if (colons > 1 && s.charAt(0) !== '[' && !s.includes('/')) s = '[' + s + ']';
        s = (type === 'http' || type === 'tcp' ? 'https://' : 'http://') + s;
    }
    let u;
    try { u = new URL(s); } catch (_) { return { ok: false, error: 'That doesn\u2019t look like a valid host.' }; }
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return { ok: false, error: 'Only http and https URLs are supported.' };
    if (u.username || u.password) return { ok: false, error: 'Remove the login from the URL.' };
    const host = u.hostname.replace(/^\[|\]$/g, '').replace(/\.$/, '').toLowerCase();
    const isV4 = !!parseCheckHostV4(host);
    const isV6 = host.includes(':');
    const v6 = isV6 ? parseCheckHostV6(host) : null;
    if (!isV4 && !isV6 && !/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$/.test(host)) return { ok: false, error: 'That doesn\u2019t look like a valid host.' };
    if ((isV4 && !isPublicCheckHostV4(host)) || (isV6 && !isPublicCheckHostV6(v6)) || (!isV4 && !isV6 && (host === 'localhost' || /\.(localhost|local|internal|home|test|example|invalid|onion)$/.test(host)))) {
        return { ok: false, error: 'Private, local, and reserved addresses can\u2019t be checked.' };
    }
    if (isV6 && !v6) return { ok: false, error: 'That doesn\u2019t look like a valid IPv6 address.' };
    const override = String(portOverride || '').trim();
    if (override && !/^\d{1,5}$/.test(override)) return { ok: false, error: 'Port must be a number from 1 to 65535.' };
    const port = type === 'tcp' && override ? override : (u.port || (u.protocol === 'https:' ? '443' : '80'));
    if ((type === 'tcp' || type === 'http') && (!Number(port) || Number(port) > 65535)) return { ok: false, error: 'Port must be from 1 to 65535.' };
    const shown = isV6 ? '[' + host + ']' : host;
    let target = host;
    if (type === 'http') target = u.protocol + '//' + shown + (u.port ? ':' + u.port : '') + u.pathname + u.search;
    if (type === 'tcp') target = shown + ':' + port;
    return { ok: true, target, host, url: type === 'http' ? target : '', port, isIp: isV4 || isV6, isV4, isV6 };
}

// Public DNS-over-HTTPS JSON resolvers, tried in order. Both are used only
// server-side, to make sure a host never resolves to a private address.
const CH_DOH_RESOLVERS = [
    { name: 'Cloudflare', url: 'https://cloudflare-dns.com/dns-query' },
    { name: 'Google', url: 'https://dns.google/resolve' }
];
async function askCheckHostDoh(resolver, host, rr) {
    const r = await timedFetch(resolver.url + '?name=' + encodeURIComponent(host) + '&type=' + rr, { headers: { 'Accept': 'application/dns-json' }, redirect: 'manual' }, 3500);
    if (!r.ok) throw new Error('resolver_http_' + r.status);
    const j = await r.json();
    const status = Number(j && j.Status);
    if (![0, 3].includes(status)) throw new Error('resolver_dns_status_' + status);
    return (j.Answer || []).filter(a => a && Number(a.type) === (rr === 'A' ? 1 : 28)).map(a => ({ data: String(a.data || ''), ttl: Number(a.TTL) }));
}
async function resolveCheckHostDns(host, isIp) {
    if (isIp) return { ok: true, A: parseCheckHostV4(host) ? [host] : [], AAAA: parseCheckHostV6(host) ? [host] : [], ttl: null, time: 0, resolver: '' };
    const started = Date.now();
    for (const resolver of CH_DOH_RESOLVERS) {
        let a, aaaa;
        try {
            [a, aaaa] = await Promise.all([askCheckHostDoh(resolver, host, 'A'), askCheckHostDoh(resolver, host, 'AAAA')]);
        } catch (_) {
            continue; // try the next resolver
        }
        const unsafe = a.some(x => !isPublicCheckHostV4(x.data)) || aaaa.some(x => !isPublicCheckHostV6(parseCheckHostV6(x.data)));
        if (unsafe) return { ok: false, blocked: true, error: 'This host resolves to a private or reserved address. No probes were sent.' };
        const ttl = a.concat(aaaa).reduce((m, x) => Number.isFinite(x.ttl) ? Math.min(m, x.ttl) : m, Infinity);
        return { ok: true, A: a.map(x => x.data), AAAA: aaaa.map(x => x.data), ttl: Number.isFinite(ttl) ? ttl : null, time: (Date.now() - started) / 1000, resolver: resolver.name };
    }
    return { ok: false, error: 'Could not verify public DNS for this host (Cloudflare and Google DNS did not answer). No probes were sent; try again shortly.' };
}

// Per-visitor: 10 new checks a minute is plenty for a human, stops floods
// from burning the shared check-host.net quota.
const __chHits = new Map();
function checkHostThrottled(ip) {
    const now = Date.now();
    const list = (__chHits.get(ip) || []).filter(t => now - t < 60000);
    list.push(now);
    __chHits.set(ip, list);
    if (__chHits.size > 5000) for (const k of __chHits.keys()) { __chHits.delete(k); if (__chHits.size < 2500) break; }
    return list.length > 10;
}

// ---------------------------------------------------------------------------- our own edge probe
async function edgeProbe(request, type, t, dnsCheck) {
    const cf = (request && request.cf) || {};
    const where = { colo: String(cf.colo || ''), cc: String(cf.country || '').toLowerCase() };
    const started = Date.now();
    try {
        if (type === 'http') {
            const r = await timedFetch(t.url, { method: 'GET', redirect: 'manual', headers: { 'User-Agent': CH_UA, 'Accept': '*/*' } }, 8000);
            try { r.body && r.body.cancel(); } catch (_) {}
            const ms = Date.now() - started;
            return { ...where, done: true, ok: r.status > 0 && r.status < 400, time: ms / 1000, code: r.status, message: r.statusText || httpStatusText(r.status) };
        }
        if (type === 'dns') {
            return { ...where, done: true, ok: !!(dnsCheck && dnsCheck.ok && (dnsCheck.A.length + dnsCheck.AAAA.length)), A: (dnsCheck && dnsCheck.A) || [], AAAA: (dnsCheck && dnsCheck.AAAA) || [], ttl: dnsCheck ? dnsCheck.ttl : null, time: dnsCheck && Number.isFinite(dnsCheck.time) ? dnsCheck.time : (Date.now() - started) / 1000, error: dnsCheck && !dnsCheck.ok ? dnsCheck.error : '' };
        }
    } catch (e) {
        return { ...where, done: true, ok: false, time: (Date.now() - started) / 1000, error: e && e.name === 'AbortError' ? 'Timed out' : 'Connection failed' };
    }
    if (type === 'ping') return { ...where, done: true, ok: false, supported: false, error: 'ICMP ping is not available from the Cloudflare Worker edge.' };
    if (type === 'tcp') return { ...where, done: true, ok: false, supported: false, error: 'Raw TCP checks are not available from the Cloudflare Worker edge.' };
    return null;
}
function httpStatusText(code) {
    return ({ 200: 'OK', 201: 'Created', 204: 'No Content', 301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified', 307: 'Temporary Redirect', 308: 'Permanent Redirect', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 429: 'Too Many Requests', 500: 'Internal Server Error', 502: 'Bad Gateway', 503: 'Service Unavailable', 504: 'Gateway Timeout', 520: 'Web Server Error', 521: 'Web Server Down', 522: 'Connection Timed Out', 523: 'Origin Unreachable', 524: 'A Timeout Occurred', 525: 'SSL Handshake Failed', 526: 'Invalid SSL Certificate' })[code] || '';
}

// ---------------------------------------------------------------------------- result parsing
function normalizeCheckResult(type, raw) {
    if (raw === null || raw === undefined) return { done: false };
    const first = Array.isArray(raw) ? raw[0] : raw;
    if (type === 'ping') {
        const pings = Array.isArray(first) ? first : [];
        if (!pings.length || pings[0] === null) return { done: true, ok: false, error: 'Could not resolve host', pings: [] };
        const list = pings.map(p => Array.isArray(p) ? { s: String(p[0] || ''), t: Number(p[1]) || 0 } : { s: 'TIMEOUT', t: 0 });
        const good = list.filter(p => p.s === 'OK').map(p => p.t);
        const ip = (pings.find(p => Array.isArray(p) && p[2]) || [])[2] || '';
        return {
            done: true, ok: good.length > 0, ip, sent: list.length, recv: good.length,
            pings: list.map(p => p.s),
            min: good.length ? Math.min(...good) : null, avg: good.length ? good.reduce((a, b) => a + b, 0) / good.length : null, max: good.length ? Math.max(...good) : null
        };
    }
    if (type === 'http') {
        if (!Array.isArray(first)) return { done: true, ok: false, error: 'No answer' };
        const code = first[3] === null || first[3] === undefined ? null : Number(first[3]);
        return { done: true, ok: Number(first[0]) === 1, time: Number(first[1]) || 0, message: String(first[2] || ''), code, ip: String(first[4] || '') };
    }
    if (type === 'tcp') {
        if (!first || typeof first !== 'object') return { done: true, ok: false, error: 'No answer' };
        if (first.error) return { done: true, ok: false, error: String(first.error) };
        return { done: true, ok: true, time: Number(first.time) || 0, ip: String(first.address || '') };
    }
    if (type === 'dns') {
        if (!first || typeof first !== 'object') return { done: true, ok: false, error: 'No answer', A: [], AAAA: [] };
        const A = Array.isArray(first.A) ? first.A.map(String) : [];
        const AAAA = Array.isArray(first.AAAA) ? first.AAAA.map(String) : [];
        return { done: true, ok: A.length + AAAA.length > 0, A, AAAA, ttl: first.TTL === null || first.TTL === undefined ? null : Number(first.TTL) };
    }
    return { done: true, ok: false };
}

// ---------------------------------------------------------------------------- regional providers
// Two documented public APIs, both called only from the Worker:
//   Check-Host.net  https://check-host.net/about/api   (primary)
//   Globalping      https://globalping.io/docs/api.globalping.io (fallback)
// Neither is operated by VexoStream. CHECK_HOST_PROVIDER picks the mode:
// auto (default: Check-Host.net, then Globalping), check-host, globalping, edge.
const CH_JSON_HEADERS = { 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' };
const GP_API = 'https://api.globalping.io/v1/measurements';
const CH_PROVIDER_NAMES = { 'check-host': 'Check-Host.net', 'globalping': 'Globalping' };

function checkHostProviderMode(env) {
    const v = String(env && env.CHECK_HOST_PROVIDER || 'auto').trim().toLowerCase();
    return ['auto', 'check-host', 'globalping', 'edge'].includes(v) ? v : 'auto';
}
function checkHostProviderOrder(env) {
    const mode = checkHostProviderMode(env);
    if (mode === 'edge') return [];
    if (mode === 'auto') return ['check-host', 'globalping'];
    return [mode];
}
function providerReason(name, status, payload, invalid = false) {
    const code = String(payload && (payload.error && (payload.error.type || payload.error.message || payload.error) || payload.code) || '').toLowerCase();
    if (status === 429 || code === 'limit_exceeded' || code.includes('rate limit')) return name + ' rate-limited the request (HTTP ' + status + ')';
    if (status === 401 || status === 403) return name + ' denied the request (HTTP ' + status + ')';
    if (status === 422) return name + ' has no probes available in the selected countries';
    if (status >= 500) return name + ' is temporarily unavailable (HTTP ' + status + ')';
    if (status >= 300 && status < 400) return name + ' answered with an unexpected redirect (HTTP ' + status + ')';
    if (invalid) return name + ' returned an invalid response (HTTP ' + status + ')';
    return name + ' did not accept the request (HTTP ' + status + ')';
}
// Kept for backwards compatibility with older callers/tests.
function checkHostProviderError(status, payload, invalid = false) {
    return providerReason('Check-Host.net', status, payload, invalid) + '. Showing the VexoStream edge result only.';
}

// ---- Check-Host.net
async function startCheckHostNet(type, t, wanted) {
    const all = await checkHostNodes();
    const ids = pickCheckHostNodes(all, wanted);
    if (!ids.length) return { reason: 'Check-Host.net has no probes in the selected countries' };
    const q = new URLSearchParams({ host: t.target, max_nodes: String(ids.length) });
    ids.forEach(id => q.append('node', id));
    try {
        const r = await timedFetch(CH_API + '/check-' + type + '?' + q.toString(), { headers: { 'Accept': 'application/json', 'User-Agent': CH_UA }, redirect: 'manual' }, 8000);
        const text = await r.text();
        let j = null;
        try { j = JSON.parse(text); } catch (_) {}
        if (!r.ok) return { reason: providerReason('Check-Host.net', r.status, j), status: r.status };
        if (!j || !j.ok || !j.request_id || !/^[a-z0-9]{1,40}$/i.test(String(j.request_id))) return { reason: providerReason('Check-Host.net', r.status, j, true), status: r.status };
        const meta = j.nodes && typeof j.nodes === 'object' ? j.nodes : {};
        const nodeIds = Object.keys(meta).length ? Object.keys(meta) : ids;
        const nodes = nodeIds.filter(id => /^[a-z0-9-]+\.node\.check-host\.net$/i.test(id)).map(id => {
            const m = meta[id] || all[id] || [];
            let cc = String(m[0] || '').toLowerCase();
            if (cc === 'uk') cc = 'gb';
            return { id, cc, country: (CH_COUNTRIES.find(c => c.cc === cc) || {}).name || String(m[1] || ''), city: String(m[2] || ''), ip: String(m[3] || ''), asn: String(m[4] || '').trim(), label: id.split('.')[0] };
        }).sort((a, b) => CH_CC.indexOf(a.cc) - CH_CC.indexOf(b.cc) || a.city.localeCompare(b.city));
        return { id: 'ch.' + String(j.request_id), provider: 'check-host', nodes };
    } catch (_) {
        return { reason: 'Check-Host.net could not be reached within 8 seconds' };
    }
}
async function pollCheckHostNet(id, type) {
    try {
        const r = await timedFetch(CH_API + '/check-result/' + id, { headers: { 'Accept': 'application/json', 'User-Agent': CH_UA }, redirect: 'manual' }, 5000);
        if (!r.ok) return { status: 502, body: { ok: false, error: 'Check-Host.net could not return this result (HTTP ' + r.status + ').' } };
        const j = await r.json().catch(() => null);
        if (!j || typeof j !== 'object' || Array.isArray(j)) return { status: 502, body: { ok: false, error: 'Check-Host.net returned an invalid result.' } };
        const rawResults = j.results && typeof j.results === 'object' ? j.results : j;
        const results = {};
        const entries = Object.entries(rawResults).filter(([node]) => /^[a-z0-9.-]+\.node\.check-host\.net$/i.test(node));
        let done = entries.length > 0;
        for (const [node, raw] of entries) {
            const n = normalizeCheckResult(type, raw);
            results[node] = n;
            if (!n.done) done = false;
        }
        return { status: 200, body: { ok: true, provider: 'check-host', done, results } };
    } catch (_) {
        return { status: 504, body: { ok: false, error: 'Check-Host.net result polling timed out after 5 seconds.' } };
    }
}

// ---- Globalping
function globalpingHeaders(env, json) {
    const h = { 'Accept': 'application/json', 'User-Agent': CH_UA };
    if (json) h['Content-Type'] = 'application/json';
    const tok = env && typeof env.GLOBALPING_TOKEN === 'string' ? env.GLOBALPING_TOKEN.trim() : '';
    if (tok) h['Authorization'] = 'Bearer ' + tok;
    return h;
}
function globalpingBody(type, t, wanted) {
    const locations = CH_COUNTRIES.filter(c => wanted.includes(c.cc)).map(c => ({ country: c.cc.toUpperCase(), limit: Math.min(c.max, 2) }));
    const body: any = { type: type === 'tcp' ? 'ping' : type, target: t.host, locations, inProgressUpdates: true };
    if (type === 'ping') body.measurementOptions = { packets: 4 };
    if (type === 'tcp') body.measurementOptions = { packets: 3, protocol: 'TCP', port: Number(t.port) };
    if (type === 'dns') body.measurementOptions = { query: { type: 'A' } };
    if (type === 'http') {
        const u = new URL(t.url);
        const request: any = { method: 'GET', path: u.pathname || '/' };
        if (u.search && u.search.length > 1) request.query = u.search.slice(1);
        body.measurementOptions = { protocol: u.protocol === 'https:' ? 'HTTPS' : 'HTTP', port: Number(t.port), request };
    }
    return body;
}
async function startGlobalping(env, type, t, wanted) {
    const send = async (cc) => {
        const r = await timedFetch(GP_API, { method: 'POST', headers: globalpingHeaders(env, true), body: JSON.stringify(globalpingBody(type, t, cc)), redirect: 'manual' }, 8000);
        const text = await r.text();
        let j = null;
        try { j = JSON.parse(text); } catch (_) {}
        return { r, j };
    };
    try {
        let { r, j } = await send(wanted);
        let skipped = [];
        // Globalping has few or no probes in some countries (often Iran). Retry once without them.
        if (r.status === 422 && wanted.includes('ir') && wanted.length > 1) {
            skipped = ['ir'];
            ({ r, j } = await send(wanted.filter(c => c !== 'ir')));
        }
        if (r.status !== 200 && r.status !== 202) return { reason: providerReason('Globalping', r.status, j), status: r.status };
        if (!j || !j.id || !/^[A-Za-z0-9]{1,64}$/.test(String(j.id))) return { reason: providerReason('Globalping', r.status, j, true), status: r.status };
        return { id: 'gp.' + String(j.id), provider: 'globalping', nodes: [], skipped, expected: Number(j.probesCount) || 0 };
    } catch (_) {
        return { reason: 'Globalping could not be reached within 8 seconds' };
    }
}
function gpLastLine(raw) {
    const lines = String(raw || '').trim().split(/\r?\n/).filter(Boolean);
    return (lines[lines.length - 1] || 'Probe failed').slice(0, 120);
}
function normalizeGlobalpingResult(type, res) {
    const st = String(res && res.status || '');
    if (!res || st === 'in-progress' || !st) return { done: false };
    if (st === 'offline') return { done: true, ok: false, error: 'Probe went offline' };
    if (type === 'ping' || type === 'tcp') {
        const stats = res.stats || {};
        const timings = Array.isArray(res.timings) ? res.timings : [];
        const total = Number(stats.total) || timings.length || 0;
        const recv = Number.isFinite(Number(stats.rcv)) ? Number(stats.rcv) : timings.length;
        if (st === 'failed' && !recv) return { done: true, ok: false, error: type === 'tcp' ? 'Connection failed' : gpLastLine(res.rawOutput), pings: [] };
        const sec = (v) => Number.isFinite(Number(v)) && v !== null ? Number(v) / 1000 : null;
        if (type === 'tcp') return { done: true, ok: recv > 0, time: sec(stats.avg), ip: String(res.resolvedAddress || ''), error: recv > 0 ? '' : 'Connection failed' };
        const pings = timings.map(() => 'OK').concat(Array(Math.max(0, total - timings.length)).fill('TIMEOUT'));
        return { done: true, ok: recv > 0, ip: String(res.resolvedAddress || ''), sent: total, recv, pings, min: sec(stats.min), avg: sec(stats.avg), max: sec(stats.max) };
    }
    if (type === 'http') {
        if (st === 'failed' && !res.statusCode) return { done: true, ok: false, error: gpLastLine(res.rawOutput) };
        const code = Number(res.statusCode) || null;
        const total = res.timings && Number.isFinite(Number(res.timings.total)) ? Number(res.timings.total) / 1000 : null;
        return { done: true, ok: !!code, code, message: String(res.statusCodeName || httpStatusText(code) || ''), time: total, ip: String(res.resolvedAddress || '') };
    }
    if (type === 'dns') {
        if (st === 'failed') return { done: true, ok: false, error: gpLastLine(res.rawOutput), A: [], AAAA: [] };
        const answers = Array.isArray(res.answers) ? res.answers : [];
        const A = answers.filter(a => a && a.type === 'A').map(a => String(a.value));
        const AAAA = answers.filter(a => a && a.type === 'AAAA').map(a => String(a.value));
        const ttl = answers.reduce((m, a) => Number.isFinite(Number(a && a.ttl)) ? Math.min(m, Number(a.ttl)) : m, Infinity);
        return { done: true, ok: A.length + AAAA.length > 0, A, AAAA, ttl: Number.isFinite(ttl) ? ttl : null };
    }
    return { done: true, ok: false };
}
async function pollGlobalping(env, id, type) {
    try {
        const r = await timedFetch(GP_API + '/' + id, { headers: globalpingHeaders(env, false), redirect: 'manual' }, 5000);
        if (!r.ok) return { status: 502, body: { ok: false, error: 'Globalping could not return this result (HTTP ' + r.status + ').' } };
        const j = await r.json().catch(() => null);
        if (!j || typeof j !== 'object' || !Array.isArray(j.results)) return { status: 502, body: { ok: false, error: 'Globalping returned an invalid result.' } };
        const nodes = [], results = {};
        j.results.forEach((row, i) => {
            const probe = (row && row.probe) || {};
            let cc = String(probe.country || '').toLowerCase();
            if (cc === 'uk') cc = 'gb';
            const id2 = 'gp' + i;
            nodes.push({ id: id2, cc, country: (CH_COUNTRIES.find(c => c.cc === cc) || {}).name || cc.toUpperCase(), city: String(probe.city || ''), asn: probe.asn ? 'AS' + String(probe.asn).replace(/^AS/i, '') : '', label: String(probe.network || 'Globalping probe').slice(0, 60) });
            results[id2] = normalizeGlobalpingResult(type, row && row.result);
        });
        nodes.sort((a, b) => CH_CC.indexOf(a.cc) - CH_CC.indexOf(b.cc) || a.city.localeCompare(b.city));
        const allDone = nodes.length > 0 && nodes.every(n => results[n.id].done);
        return { status: 200, body: { ok: true, provider: 'globalping', done: j.status === 'finished' || allDone, results, nodes } };
    } catch (_) {
        return { status: 504, body: { ok: false, error: 'Globalping result polling timed out after 5 seconds.' } };
    }
}

// ---------------------------------------------------------------------------- API handlers
async function handleCheckHostStart(request, url, env) {
    const type = String(url.searchParams.get('type') || 'http').toLowerCase();
    if (!CH_TYPES.includes(type)) return jsonResponse({ ok: false, error: 'Unknown check type.' }, 400, CH_JSON_HEADERS);
    const t = parseCheckTarget(url.searchParams.get('host'), type, type === 'tcp' ? url.searchParams.get('port') : '');
    if (!t.ok) return jsonResponse({ ok: false, error: t.error }, 400, CH_JSON_HEADERS);
    if (!checkHostIsAuthorized(t.host, t.isIp, env)) return jsonResponse({ ok: false, error: 'Checks are limited to VexoStream-owned or explicitly authorized hosts.' }, 403, CH_JSON_HEADERS);
    const allowedPorts = configuredCheckHostPorts(env);
    if ((type === 'tcp' || type === 'http') && !allowedPorts.has(Number(t.port))) {
        return jsonResponse({ ok: false, error: 'That port is not authorized. Allowed ports: ' + Array.from(allowedPorts).join(', ') + '.' }, 403, CH_JSON_HEADERS);
    }
    if (checkHostThrottled(clientIpOf(request))) return jsonResponse({ ok: false, error: 'Easy there. Max 10 checks a minute, try again shortly.' }, 429, { ...CH_JSON_HEADERS, 'Retry-After': '60' });

    const dnsCheck = await resolveCheckHostDns(t.host, t.isIp);
    if (!dnsCheck.ok) return jsonResponse({ ok: false, error: dnsCheck.error }, dnsCheck.blocked ? 403 : 503, CH_JSON_HEADERS);
    if (type !== 'dns' && !t.isIp && !dnsCheck.A.length && !dnsCheck.AAAA.length) {
        return jsonResponse({ ok: false, error: 'This authorized host has no public A or AAAA records. No probes were sent.' }, 422, CH_JSON_HEADERS);
    }

    const askedCc = String(url.searchParams.get('cc') || '').toLowerCase().split(',').map(s => s.trim()).filter(c => CH_CC.includes(c));
    const wanted = askedCc.length ? askedCc : CH_CC;

    const regional = (async (): Promise<any> => {
        const reasons = [];
        for (const provider of checkHostProviderOrder(env)) {
            const res = provider === 'check-host' ? await startCheckHostNet(type, t, wanted) : await startGlobalping(env, type, t, wanted);
            if (res.id) return { ...res, reasons };
            reasons.push(res.reason);
        }
        return { reasons };
    })();
    const [rem, edgeResult]: [any, any] = await Promise.all([regional, edgeProbe(request, type, t, dnsCheck)]);

    let notice = null, error = null;
    if (rem.id && rem.reasons.length) notice = rem.reasons.join('. ') + '. Using ' + CH_PROVIDER_NAMES[rem.provider] + ' instead.';
    if (rem.id && rem.skipped && rem.skipped.length) notice = (notice ? notice + ' ' : '') + 'Globalping has no probes in Iran right now, so Iran was skipped.';
    if (!rem.id) error = rem.reasons.length
        ? 'Regional probes unavailable: ' + rem.reasons.join('; ') + '. Showing the VexoStream edge result only.'
        : 'Regional probes are turned off (CHECK_HOST_PROVIDER=edge). Showing the VexoStream edge result only.';

    return jsonResponse({
        ok: !!rem.id || !!(edgeResult && edgeResult.supported !== false),
        type, target: t.target, host: t.host,
        id: rem.id || null, provider: rem.provider || null, providerName: rem.provider ? CH_PROVIDER_NAMES[rem.provider] : null,
        expected: rem.expected || (rem.nodes ? rem.nodes.length : 0),
        error, notice,
        nodes: rem.nodes || [], edge: edgeResult
    }, 200, CH_JSON_HEADERS);
}

async function handleCheckHostResult(url, env) {
    const raw = String(url.searchParams.get('id') || '');
    const type = String(url.searchParams.get('type') || '').toLowerCase();
    if (!CH_TYPES.includes(type)) return jsonResponse({ ok: false, error: 'Bad request.' }, 400, CH_JSON_HEADERS);
    let out;
    if (/^gp\.[A-Za-z0-9]{1,64}$/.test(raw)) out = await pollGlobalping(env, raw.slice(3), type);
    else if (/^(ch\.)?[a-z0-9]{1,40}$/i.test(raw)) out = await pollCheckHostNet(raw.replace(/^ch\./, ''), type);
    else return jsonResponse({ ok: false, error: 'Bad request.' }, 400, CH_JSON_HEADERS);
    return jsonResponse(out.body, out.status, CH_JSON_HEADERS);
}
