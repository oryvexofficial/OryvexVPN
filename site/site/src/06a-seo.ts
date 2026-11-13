// ============================================================================
// SEO + CRAWLERS (v21)
// Canonical host, robots.txt, sitemap.xml, structured data, and a safe lane
// for real search engine crawlers so the anti-scrape layer never blocks them.
// ============================================================================

// Primary public address. Override with a SITE_URL var in wrangler.toml.
let SEO_ORIGIN = 'https://vexostream.bond';
function initSeoConfig(env) {
    const v = env && typeof env.SITE_URL === 'string' ? env.SITE_URL.trim().replace(/\/+$/, '') : '';
    if (/^https:\/\/[a-z0-9.-]+$/i.test(v)) SEO_ORIGIN = v;
}
function seoHost() { try { return new URL(SEO_ORIGIN).hostname; } catch (_) { return 'vexostream.bond'; } }

// Rewrites any absolute URL on this Worker to the canonical origin.
function seoUrl(u) {
    const s = String(u || '');
    if (!s) return SEO_ORIGIN + '/';
    if (s.startsWith('/')) return SEO_ORIGIN + s;
    try {
        const p = new URL(s);
        return SEO_ORIGIN + p.pathname + p.search;
    } catch (_) { return s; }
}

const SEO_DEFAULT_DESC = 'VexoStream is a free, ad-free 18+ video player. Paste a link or browse trending videos and stream every quality from 240p to 4K, straight from the edge.';
const SEO_INDEX = 'index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1';
const SEO_NOINDEX = 'noindex, follow';

// ---------------------------------------------------------------------------- crawlers
// Real search engines only: matching user agent AND (Cloudflare verified bot
// OR the crawler's own network). A spoofed "Googlebot" from a VPS is not trusted.
const SEARCH_BOT_UA = /(googlebot|google-inspectiontool|googleother|adsbot-google|mediapartners-google|storebot-google|bingbot|bingpreview|adidxbot|msnbot|duckduckbot|yandex(bot|images)|applebot)/i;
const SEARCH_BOT_ASNS = new Set([15169, 8075, 13238, 714, 6185]); // Google, Microsoft (Bing, DDG), Yandex, Apple
function isTrustedSearchBot(request) {
    const ua = String(request.headers.get('User-Agent') || '');
    if (!SEARCH_BOT_UA.test(ua)) return false;
    const cf = (request as any).cf || {};
    if (cf.verifiedBotCategory === 'Search Engine Crawler' || cf.verifiedBotCategory === 'Search Engine Optimization') return true;
    if (cf.botManagement && cf.botManagement.verifiedBot) return true;
    return SEARCH_BOT_ASNS.has(Number(cf.asn || 0));
}
// Read-only catalogue endpoints a crawler needs to render the card grids.
function isCrawlerReadablePath(path) {
    return path === '/api/posters' || path === '/proxy-image' || path.startsWith('/api/explore') || path === '/api/providers';
}

// ---------------------------------------------------------------------------- structured data
function jsonLd(obj) {
    return '<script type="application/ld+json">' + JSON.stringify(obj).replace(/</g, '\\u003c') + '</script>';
}

function seoSameAs() {
    try {
        const cfg = socialCached();
        const out = Object.values(cfg.links || {}).filter(v => typeof v === 'string' && /^https:\/\//.test(v));
        const join = channelJoinUrl(cfg);
        if (join && !out.includes(join)) out.push(join);
        return out.slice(0, 12);
    } catch (_) { return []; }
}

function seoHomeJsonLd() {
    const org = {
        '@type': 'Organization',
        '@id': SEO_ORIGIN + '/#organization',
        name: 'VexoStream',
        alternateName: ['Vexo Stream', 'Vexostream'],
        url: SEO_ORIGIN + '/',
        logo: { '@type': 'ImageObject', url: SEO_ORIGIN + '/assets/brand/vexostream-mark-512.png', width: 512, height: 512 }
    };
    const same = seoSameAs();
    if (same.length) org['sameAs'] = same;
    return jsonLd({
        '@context': 'https://schema.org',
        '@graph': [
            org,
            {
                '@type': 'WebSite',
                '@id': SEO_ORIGIN + '/#website',
                name: 'VexoStream',
                alternateName: ['Vexo Stream', 'Vexostream'],
                url: SEO_ORIGIN + '/',
                inLanguage: 'en',
                publisher: { '@id': SEO_ORIGIN + '/#organization' },
                potentialAction: {
                    '@type': 'SearchAction',
                    target: { '@type': 'EntryPoint', urlTemplate: SEO_ORIGIN + '/search?q={search_term_string}' },
                    'query-input': 'required name=search_term_string'
                }
            }
        ]
    });
}

function seoBreadcrumbs(items) {
    return jsonLd({
        '@context': 'https://schema.org',
        '@type': 'BreadcrumbList',
        itemListElement: items.map((it, i) => ({ '@type': 'ListItem', position: i + 1, name: it[0], item: seoUrl(it[1]) }))
    });
}

// ---------------------------------------------------------------------------- robots + sitemap
function renderRobotsTxt() {
    return [
        'User-agent: *',
        'Allow: /',
        'Allow: /api/explore',
        'Allow: /api/posters',
        'Allow: /api/providers',
        'Allow: /proxy-image',
        'Disallow: ' + ADMIN_PATH,
        'Disallow: /api/',
        'Disallow: /proxy-m3u8',
        'Disallow: /proxy-video',
        'Disallow: /embed',
        'Disallow: /account/',
        'Disallow: /logout',
        'Disallow: /__vx/',
        'Disallow: /__vx-ban/',
        '',
        'Sitemap: ' + SEO_ORIGIN + '/sitemap.xml',
        ''
    ].join('\n');
}

function renderSitemapXml(cfg) {
    const today = new Date().toISOString().slice(0, 10);
    const urls = [['/', 'daily', '1.0']];
    for (const p of browseProviders(cfg)) urls.push(['/browse/' + p.id, 'daily', '0.8']);
    urls.push(['/developers', 'monthly', '0.5'], ['/status', 'daily', '0.4'], ['/check-host', 'monthly', '0.4']);
    if (socialCached().showPage !== false) urls.push(['/social', 'weekly', '0.5']);
    if (!membersCached().modelsLogin) urls.push(['/models', 'daily', '0.6']);
    return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
        urls.map(u => '  <url><loc>' + escapeHtml(SEO_ORIGIN + u[0]) + '</loc><lastmod>' + today + '</lastmod><changefreq>' + u[1] + '</changefreq><priority>' + u[2] + '</priority></url>').join('\n') +
        '\n</urlset>\n';
}

function renderWebManifest() {
    return JSON.stringify({
        name: 'VexoStream',
        short_name: 'VexoStream',
        start_url: '/',
        display: 'standalone',
        background_color: '#0a0e17',
        theme_color: '#0a0e17',
        icons: [
            { src: '/assets/brand/vexostream-mark-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
            { src: '/favicon.svg', sizes: 'any', type: 'image/svg+xml' }
        ]
    });
}

// ---------------------------------------------------------------------------- response polish
// Public pages: private, revalidated each time (keeps the per-visitor token
// fresh) but no longer "no-store", so browsers can use the back/forward cache.
const SEO_PRIVATE_PATHS = /^\/(adminpanel|login|signup|register|logout|account)(\/|$)/;
function finalizeSeoHeaders(response, request) {
    let url;
    try { url = new URL(request.url); } catch (_) { return response; }
    const path = url.pathname;
    const type = response.headers.get('Content-Type') || '';
    const headers = new Headers(response.headers);
    let changed = false;
    if ((path.startsWith('/api/') || path.startsWith('/proxy-')) && !headers.has('X-Robots-Tag')) {
        headers.set('X-Robots-Tag', 'noindex');
        changed = true;
    }
    if (/text\/html/i.test(type)) {
        const isAdmin = path === ADMIN_PATH || path.startsWith(ADMIN_PATH + '/');
        if (!isAdmin && !SEO_PRIVATE_PATHS.test(path) && response.status === 200 && /no-store/.test(headers.get('Cache-Control') || '')) {
            headers.set('Cache-Control', 'private, no-cache');
            changed = true;
        }
        // Preview / workers.dev hosts must never compete with the real domain.
        if (url.hostname !== seoHost() && !headers.has('X-Robots-Tag')) {
            headers.set('X-Robots-Tag', 'noindex');
            changed = true;
        }
    }
    return changed ? new Response(response.body, { status: response.status, statusText: response.statusText, headers }) : response;
}
