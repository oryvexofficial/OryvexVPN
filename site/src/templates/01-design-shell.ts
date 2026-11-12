// ============================================================================
// DESIGN SYSTEM
// v25: Tailwind CSS only. Every style lives in src/styles/app.css, compiled
// by scripts/build.mjs and embedded as APP_CSS. Ink surfaces, pill controls,
// one signal blue, rack-focus motion, Geist + Geist Mono.
// ============================================================================
const FONT_CSS_URL = 'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap';
// Same fonts served from our own origin (/fonts/css2 -> Google Fonts CSS,
// /fonts/gstatic/* -> font files). The Worker fetches and caches them, so the
// browser never leaves vexostream.bond. Used by pages with sameOriginOnly.
const FONT_LOCAL_CSS_URL = '/fonts/css2' + FONT_CSS_URL.slice(FONT_CSS_URL.indexOf('?'));
const FONT_RTL_QUERY = '?family=Vazirmatn:wght@400;500;600;700;800&display=swap';
const FONT_LINKS_LOCAL =
    '<link rel="preload" as="style" href="' + FONT_LOCAL_CSS_URL + '">' +
    '<link rel="stylesheet" href="' + FONT_LOCAL_CSS_URL + '" media="print" onload="this.media=\'all\'">' +
    '<noscript><link rel="stylesheet" href="' + FONT_LOCAL_CSS_URL + '"></noscript>';
const FONT_PROXY_QUERIES = new Set([FONT_CSS_URL.slice(FONT_CSS_URL.indexOf('?')), FONT_RTL_QUERY]);
const FONT_PROXY_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
async function handleFontProxy(request, url, ctx) {
    const isCss = url.pathname === '/fonts/css2';
    if (request.method !== 'GET' && request.method !== 'HEAD') return new Response('Method not allowed', { status: 405 });
    let upstream;
    if (isCss) {
        // Only the exact font sets this site uses; never an open proxy.
        if (!FONT_PROXY_QUERIES.has(decodeURIComponent(url.search))) return new Response('Not found', { status: 404, headers: { 'Cache-Control': 'no-store' } });
        upstream = 'https://fonts.googleapis.com/css2' + url.search;
    } else {
        const rest = url.pathname.slice('/fonts/gstatic'.length);
        if (!/^\/s\/[a-z0-9]+\/v\d+\/[A-Za-z0-9_\-.]+\.(woff2|woff|ttf)$/.test(rest)) return new Response('Not found', { status: 404, headers: { 'Cache-Control': 'no-store' } });
        upstream = 'https://fonts.gstatic.com' + rest;
    }
    let cache = null;
    try { cache = (caches as any).default; } catch (_) {}
    const key = new Request(url.origin + url.pathname + url.search, { method: 'GET' });
    if (cache) { try { const hit = await cache.match(key); if (hit) return hit; } catch (_) {} }
    let r;
    try { r = await timedFetch(upstream, { headers: { 'User-Agent': FONT_PROXY_UA, 'Accept': isCss ? 'text/css,*/*;q=0.1' : '*/*' }, redirect: 'manual' }, 8000); } catch (_) { r = null; }
    if (!r || !r.ok) return new Response(isCss ? '/* fonts unavailable */' : '', { status: 502, headers: { 'Content-Type': isCss ? 'text/css;charset=UTF-8' : 'text/plain', 'Cache-Control': 'no-store' } });
    const headers = { 'Cache-Control': isCss ? 'public, max-age=86400' : 'public, max-age=31536000, immutable', 'X-Content-Type-Options': 'nosniff', 'Access-Control-Allow-Origin': url.origin, 'X-Robots-Tag': 'noindex' };
    let out;
    if (isCss) {
        const css = (await r.text()).replace(/https:\/\/fonts\.gstatic\.com\//g, '/fonts/gstatic/');
        out = new Response(css, { headers: { ...headers, 'Content-Type': 'text/css;charset=UTF-8' } });
    } else {
        out = new Response(r.body, { headers: { ...headers, 'Content-Type': r.headers.get('Content-Type') || 'font/woff2' } });
    }
    if (cache) { const put = cache.put(key, out.clone()).catch(() => {}); if (ctx && ctx.waitUntil) ctx.waitUntil(put); }
    return out;
}
const FONT_LINKS =
    '<link rel="preconnect" href="https://fonts.googleapis.com">' +
    '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
    '<link rel="preload" as="style" href="' + FONT_CSS_URL + '">' +
    '<link rel="stylesheet" href="' + FONT_CSS_URL + '" media="print" onload="this.media=\'all\'">' +
    '<noscript><link rel="stylesheet" href="' + FONT_CSS_URL + '"></noscript>';








// ============================================================================
// ICONS
// ============================================================================
const ICONS = {
    home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 10.5 12 3.8l8.5 6.7V19a1.5 1.5 0 0 1-1.5 1.5h-4.2v-6h-5.6v6H5A1.5 1.5 0 0 1 3.5 19z"/></svg>',
    grid: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/></svg>',
    users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="9" cy="8" r="3.5"/><path d="M2.8 20a6.2 6.2 0 0 1 12.4 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8"/><path d="M18.4 14.2A6.2 6.2 0 0 1 21.2 20"/></svg>',
    pulse: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12h4l2.5-6 5 12 2.5-6h4"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
    theater: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="6" width="20" height="12" rx="2.5"/></svg>',
    history: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l3 2"/></svg>',
    arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>',
    play: '<svg class="ic-play" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 4.8c0-.78.86-1.26 1.53-.84l12 7.2a.98.98 0 0 1 0 1.68l-12 7.2A.98.98 0 0 1 6 19.2z"/></svg>',
    pause: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="4.5" width="4" height="15" rx="1.2"/><rect x="14" y="4.5" width="4" height="15" rx="1.2"/></svg>',
    volume: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4V5z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M18.5 5.5a9 9 0 0 1 0 13"/></svg>',
    mute: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4V5z" fill="currentColor"/><path d="m22 9-6 6"/><path d="m16 9 6 6"/></svg>',
    fullscreen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/></svg>',
    exitFullscreen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3v3a2 2 0 0 1-2 2H3"/><path d="M21 8h-3a2 2 0 0 1-2-2V3"/><path d="M3 16h3a2 2 0 0 1 2 2v3"/><path d="M16 21v-3a2 2 0 0 1 2-2h3"/></svg>',
    pip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="4" width="20" height="16" rx="2.5"/><rect x="12" y="11" width="7" height="6" rx="1" fill="currentColor"/></svg>',
    settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h10"/><path d="M18 7h2"/><circle cx="16" cy="7" r="2"/><path d="M4 17h2"/><path d="M10 17h10"/><circle cx="8" cy="17" r="2"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
    link: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
    code: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="12" height="12" rx="2.5"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
    sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    moon: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.5 14.6A8.5 8.5 0 0 1 9.4 3.5a8.5 8.5 0 1 0 11.1 11.1z"/></svg>',
    menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 9h16"/><path d="M4 15h16"/></svg>',
    burger: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 6.5h16"/><path d="M4 12h16"/><path d="M4 17.5h10"/></svg>',
    share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="18" cy="5.5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="18.5" r="2.5"/><path d="m8.2 10.8 7.6-4.1"/><path d="m8.2 13.2 7.6 4.1"/></svg>',
    fast: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5.5v13l9-6.5-9-6.5zm9 0v13l9-6.5-9-6.5z"/></svg>',
    lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg>',
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 15 6-6 6 6"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>',
    crown: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11.56 3.27a.5.5 0 0 1 .88 0l2.95 5.6a1 1 0 0 0 1.52.29l4.27-3.66a.5.5 0 0 1 .8.52l-2.83 10.25a1 1 0 0 1-.96.73H5.81a1 1 0 0 1-.96-.73L2.02 6.02a.5.5 0 0 1 .8-.52l4.27 3.66a1 1 0 0 0 1.52-.29z"/><path d="M5 21h14"/></svg>',
    globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18z"/></svg>',
    wrench: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>'
};

const FAVICON_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs><linearGradient id="vxg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2f8bff"/><stop offset="1" stop-color="#0047d6"/></linearGradient></defs><rect width="64" height="64" rx="16" fill="url(#vxg)"/><path d="M14 18H50L32 50Z" fill="#fff" stroke="#fff" stroke-width="3" stroke-linejoin="round"/><path d="M26 18L32 31L38 18Z" fill="#a9cbff" stroke="#a9cbff" stroke-width="3" stroke-linejoin="round"/></svg>';
const VX_GLYPH = '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M14 18H50L32 50Z" fill="currentColor" stroke="currentColor" stroke-width="3" stroke-linejoin="round"/><path d="M26 18L32 31L38 18Z" fill="#a9cbff" stroke="#a9cbff" stroke-width="3" stroke-linejoin="round"/></svg>';

// Detect browser-translated RTL text and apply direction/font fallbacks without forcing English pages RTL.
const DIRECTION_BOOT = String.raw`(function(){
  if(window.__vxDirectionBoot)return;window.__vxDirectionBoot=true;
  var timer=0;
  function detect(){
    var root=document.documentElement,body=document.body;if(!body)return;
    var text=String(body.innerText||body.textContent||'').slice(0,50000);
    var rtl=(text.match(/[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/g)||[]).length;
    var latin=(text.match(/[A-Za-z]/g)||[]).length;
    var dir=rtl>12&&rtl>=Math.max(8,latin*.15)?'rtl':'ltr';
    if(root.getAttribute('dir')!==dir)root.setAttribute('dir',dir);
    if(dir==='rtl'){
      if(!document.getElementById('vxRtlFont')){var l=document.createElement('link');l.id='vxRtlFont';l.rel='stylesheet';l.href='https://fonts.googleapis.com/css2?family=Vazirmatn:wght@400;500;600;700;800&display=swap';document.head.appendChild(l);}
      if(/[\u067E\u0686\u0698\u06A9\u06AF\u06CC\u06C0-\u06C3]/.test(text))root.setAttribute('lang','fa');
      else if(/[\u0590-\u05FF]/.test(text)&&!/[\u0600-\u08FF]/.test(text))root.setAttribute('lang','he');
      else root.setAttribute('lang','ar');
    }else if(/^(fa|ar|he)(-|$)/i.test(root.lang||''))root.setAttribute('lang','en');
    document.querySelectorAll('input[type="url"],#targetUrl').forEach(function(el){el.setAttribute('dir','ltr');});
    document.querySelectorAll('input[type="search"],input[type="text"],textarea').forEach(function(el){if(!el.hasAttribute('dir'))el.setAttribute('dir','auto');});
  }
  function queue(){clearTimeout(timer);timer=setTimeout(detect,220);}
  function start(){detect();if(!window.MutationObserver||!document.body)return;var observer=new MutationObserver(queue);observer.observe(document.body,{subtree:true,childList:true,characterData:true});}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();`;
// Same boot script, but the RTL font (Vazirmatn) comes from our own /fonts/ route.
const DIRECTION_BOOT_LOCAL = DIRECTION_BOOT.replace("'https://fonts.googleapis.com/css2?family=Vazirmatn", "'/fonts/css2?family=Vazirmatn");

// Runs before paint so the saved theme never flashes
const THEME_BOOT = "(function(){document.documentElement.classList.add('js');try{var t=localStorage.getItem('vexo_theme')||'dark';var d=t==='dark'||(t==='auto'&&window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches);if(d)document.documentElement.setAttribute('data-theme','dark');var m=document.querySelector('meta[name=theme-color]');if(m)m.setAttribute('content',d?'#0a0e17':'#f4f6fa');if(localStorage.getItem('vx_theater')==='1')document.documentElement.classList.add('pref-theater');}catch(e){}})();";

// ============================================================================
// SHELL  (sidebar + top bar on desktop, top bar + tab bar on phones)
// ============================================================================
function renderHead({ meta = '', title = 'VexoStream', css = '', theme = true, extraHead = '', sameOriginOnly = false } = {}) {
    return '<!DOCTYPE html><html lang="en" dir="ltr"><head>' +
        '<meta charset="UTF-8">' +
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' +
        '<meta name="theme-color" content="#0a0e17">' +
        '<meta name="color-scheme" content="light dark">' +
        '<link rel="icon" type="image/svg+xml" href="/favicon.svg">' +
        '<link rel="icon" type="image/png" sizes="512x512" href="/assets/brand/vexostream-mark-512.png">' +
        '<link rel="apple-touch-icon" href="/apple-touch-icon.png">' +
        '<link rel="manifest" href="/site.webmanifest">' +
        (meta || '<title>' + escapeHtml(title) + '</title>') +
        (sameOriginOnly ? '<meta name="vx-local-only" content="1">' : '') +
        (sameOriginOnly ? FONT_LINKS_LOCAL : FONT_LINKS) +
        '<script>try{window.VXM=' + MEMBER_PLACEHOLDER + '}catch(e){window.VXM={}}document.documentElement.classList.add(window.VXM&&window.VXM.in?"vx-in":"vx-out")</script>' +
        (theme ? '<script>' + THEME_BOOT + '</script>' : '') +
        '<script>' + (sameOriginOnly ? DIRECTION_BOOT_LOCAL : DIRECTION_BOOT) + '</script>' +
        '<style>' + APP_CSS + '</style>' +
        extraHead +
        '</head>';
}

const NAV_ITEMS = [
    { id: 'home', href: '/', label: 'Home', icon: 'home', tab: true },
    { id: 'browse', href: '/browse', label: 'Browse', icon: 'grid', tab: true },
    { id: 'search', href: '/search', label: 'Search', icon: 'search', tab: true },
    { id: 'models', href: '/models', label: 'OnlyFans Models', short: 'Models', icon: 'users', tab: true },
    { id: 'developers', href: '/developers', label: 'Developers', icon: 'code' },
    { id: 'status', href: '/status', label: 'Status', icon: 'pulse', tab: true },
    { id: 'social', href: '/social', label: 'Social', long: 'Social media', icon: 'share' },
    { id: 'checkhost', href: '/check-host', label: 'Check host', icon: 'globe', menuOnly: false }
];
// "Social" can be hidden from Admin > Social media
function navItems() {
    const showSocial = socialCached().showPage !== false;
    return NAV_ITEMS.filter(it => it.id !== 'social' || showSocial);
}

function renderNav(active, options: any = {}) {
    const cur = (it) => (active === it.id ? ' aria-current="page"' : '');
    const brand = '<a class="brand top-brand" href="/" aria-label="VexoStream home"><span class="brand-mark">' + VX_GLYPH + '</span><span class="brand-word">Vexo<b>Stream</b></span></a>';
    const label = (it) => it.id === 'models' ? '<span><span class="lbl-long">OnlyFans </span>Models</span>' : '<span>' + it.label + '</span>';
    const items = navItems();
    const burger = '<button class="icon-round burger-btn" type="button" data-drawer-open aria-controls="vxDrawer" aria-expanded="false" aria-label="Open menu">' + ICONS.burger + '</button>';
    const mast = '<ul class="mast-nav" aria-label="Primary">' + items.filter(it => !it.menuOnly).map(it => '<li class="nav-' + (it.id === 'developers' ? 'dev' : it.id) + '"><a class="mast-link" href="' + it.href + '"' + cur(it) + ' title="' + it.label + '">' + ICONS[it.icon] + label(it) + '</a></li>').join('') + '</ul>';
    // Account button: both states are rendered, html.vx-in / html.vx-out picks one (set before paint).
    const acct = '<a class="acct-btn acct-out" href="/login" data-acct-login>' + ICONS.users + '<span>Log in</span></a>' +
        '<span class="acct-wrap acct-in"><button class="acct-btn acct-in" type="button" data-drawer-open data-acct-toggle aria-controls="vxDrawer" aria-expanded="false" aria-label="Your account"><span class="acct-av" data-acct-initial>?</span><span class="acct-name" data-acct-name></span></button>' +
        '<span class="acct-pop" data-acct-pop role="menu" hidden><span class="acct-pop-who"><span class="acct-av" data-acct-initial>?</span><span><b data-acct-name></b><small data-acct-role>Member</small></span></span>' +
        '<a class="acct-pop-link" href="/adminpanel" data-acct-admin role="menuitem" hidden>Admin panel</a><a class="acct-pop-link" href="/logout" role="menuitem">Log out</a></span></span>';
    const top = '<header class="topbar"><div class="topbar-in"><div class="top-lead">' + burger + brand + '</div>' + mast +
        '<form class="top-search" action="/search" method="GET" role="search">' + ICONS.search +
        '<label for="topQuery" class="sr-only">Search videos</label>' +
        '<input type="search" id="topQuery" name="q" maxlength="100" placeholder="Search videos" autocomplete="off" enterkeyhint="search"><kbd aria-hidden="true">/</kbd></form>' +
        '<div class="top-tools">' +
        '<span class="live-pill" data-live hidden title="People watching right now"><i aria-hidden="true"></i><b data-live-count data-compact>0</b><span class="lp-l">watching</span></span>' +
        '<button class="icon-round top-search-btn" type="button" data-search-toggle aria-label="Search">' + ICONS.search + '</button>' +
        '<button class="icon-round top-theme" type="button" data-theme-toggle aria-label="Toggle appearance">' + ICONS.moon + '</button>' +
        acct +
        '</div></div></header>';
    const watch = items.filter(it => it.tab && it.id !== 'status');
    const more = items.filter(it => !(it.tab && it.id !== 'status'));
    const navLink = (it, i) => '<a href="' + it.href + '"' + cur(it) + ' style="--i:' + i + '">' + ICONS[it.icon] + '<span>' + (it.long || it.label) + '</span></a>';
    const account = '<div class="vxd-acct acct-out"><p class="vxd-acct-t">Log in to watch</p><p class="vxd-acct-s">Use a member or existing admin account.</p>' +
        '<div class="vxd-acct-b"><a class="btn sm" href="/login" data-acct-login>Log in</a><a class="btn quiet sm" href="/signup" data-acct-signup>Create account</a></div></div>' +
        '<div class="vxd-acct acct-in"><span class="acct-av" data-acct-initial>?</span><span class="vxd-acct-who"><b data-acct-name></b><small data-acct-role>Member</small></span><a class="btn quiet sm" href="/logout">Log out</a></div>';
    const drawer = '<div class="vxd" id="vxDrawer" aria-hidden="true" inert>' +
        '<div class="vxd-scrim" data-drawer-close></div>' +
        '<aside class="vxd-panel" role="dialog" aria-modal="true" aria-label="Menu">' +
        '<div class="vxd-head"><a class="brand" href="/" aria-label="VexoStream home"><span class="brand-mark">' + VX_GLYPH + '</span><span class="brand-word">Vexo<b>Stream</b></span></a>' +
        '<button class="icon-round" type="button" data-drawer-close aria-label="Close menu">' + ICONS.close + '</button></div>' +
        account +
        '<p class="vxd-label">Watch</p><nav class="vxd-nav" aria-label="Watch">' + watch.map(navLink).join('') + '</nav>' +
        '<p class="vxd-label">More</p><nav class="vxd-nav" aria-label="More">' + more.map((it, i) => navLink(it, i + watch.length)).join('') + '</nav>' +
        renderSocialDrawerBlock() +
        '<div class="vxd-foot"><span class="vxd-label">Appearance</span><div class="theme-switch" data-theme-switch></div></div>' +
        '</aside></div>';
    return '<div id="globalTopLoader"></div>' + top + drawer;
}

function renderFooter(options: any = {}) {
    const year = new Date().getUTCFullYear();
    const social = socialCached().showPage !== false;
    const col = (title, links) => '<div class="gfoot-col"><p class="gfoot-h">' + title + '</p>' + links.map(l => '<a href="' + l[0] + '">' + l[1] + '</a>').join('') + '</div>';
    return '<footer class="gfoot"><a class="vx-hp" href="' + HONEYPOT_PATH + '" rel="nofollow noindex" tabindex="-1" aria-hidden="true">Archive</a><div class="wrap-wide">' +
        '<div class="gfoot-top">' +
        '<div class="gfoot-brand"><a class="brand" href="/" aria-label="VexoStream home"><span class="brand-mark">' + VX_GLYPH + '</span><span class="brand-word">Vexo<b>Stream</b></span></a>' +
        '<p class="gfoot-tag">Every quality. No ads. Straight from the edge.</p>' + renderSocialFooterRow() + '</div>' +
        '<nav class="gfoot-cols" aria-label="Footer">' +
        col('Watch', [['/', 'Paste a link'], ['/browse', 'Browse'], ['/search', 'Search'], ['/models', 'Models']]) +
        col('Build', [['/developers', 'Embed player'], ['/api/providers', 'Providers API'], ['/status', 'System status'], ['/check-host', 'Check host']]) +
        col('Account', [['/login', 'Log in'], ['/signup', 'Create account']].concat(social ? [['/social', 'Social media']] : [])) +
        '</nav></div>' +
        '<div class="gfoot-bar"><span class="clocks"><span>Local <b id="footerClockLocal">--:--:--</b></span><span>UTC <b id="footerClockUtc">--:--:--</b></span></span><div class="theme-switch" data-theme-switch></div></div>' +
        '<p class="gfoot-note">VexoStream is an 18+ player. Videos are hosted by third-party providers and streamed through the edge without being stored. Stream links are signed for your connection and expire after 24 hours. &copy; <span id="footerYear">' + year + '</span> VexoStream. Created by ' + escapeHtml(DEFAULTS.CREATOR) + '.</p>' +
        '</div></footer>' +
        '<div class="toast" id="toast" role="status" aria-live="polite"></div>';
}

function renderAgeGate() {
    return '<div id="ageOverlay" class="age" role="dialog" aria-modal="true" aria-labelledby="ageTitle">' +
        '<div class="age-card">' +
        '<div class="age-badge">18+</div>' +
        '<h2 id="ageTitle">Adults only.</h2>' +
        '<p>VexoStream plays age-restricted content. Confirm you are 18 or older to continue.</p>' +
        '<button class="btn" id="btnAgePass" type="button">I&rsquo;m 18 or older</button>' +
        '<button class="age-leave" id="btnAgeExit" type="button">Leave</button>' +
        '</div></div>';
}

function clientConfigScript(extra = {}) {
    return '<script>window.VX=' + jsonForScript({ token: SESSION_PLACEHOLDER, ...extra }) + ';window.API_TOKEN=window.VX.token;</script>';
}

// ============================================================================
// CLIENT: COMMON (no backticks or template placeholders allowed in here)
// ============================================================================
const COMMON_JS = String.raw`
/* Expired or foreign session token: refresh once to get a new one. */
(function(){
  var f = window.fetch; if (!f) return;
  window.fetch = function(input){
    var u = typeof input === 'string' ? input : (input && input.url) || '';
    return f.apply(this, arguments).then(function(r){
      if (r.status === 403 && /(^|\/\/[^\/]+)\/api\//.test(u)) {
        r.clone().json().then(function(d){
          if (!d || d.code !== 'session') return;
          var k = 'vx_sess_reload', t = 0;
          try { t = +sessionStorage.getItem(k) || 0; } catch (e) {}
          if (Date.now() - t < 60000) return;
          try { sessionStorage.setItem(k, String(Date.now())); } catch (e) {}
          location.reload();
        }).catch(function(){});
      }
      return r;
    });
  };
})();

(function(){
  var root = document.documentElement;
  var ICON_SUN = ` + JSON.stringify(ICONS.sun) + String.raw`;
  var ICON_MOON = ` + JSON.stringify(ICONS.moon) + String.raw`;

  /* ---------- helpers ---------- */
  window.escapeHtml = function(text){
    if (text === null || text === undefined) return '';
    return String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  };
  window.b64url = function(str){
    var bytes = new TextEncoder().encode(String(str)), bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  };
  window.toast = function(msg){
    var t = document.getElementById('toast'); if (!t) return;
    t.textContent = msg; t.classList.add('show');
    clearTimeout(window.__toastT); window.__toastT = setTimeout(function(){ t.classList.remove('show'); }, 2200);
  };
  window.copyText = function(text){
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function(res, rej){
      try { var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0'; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); res(); } catch (e) { rej(e); }
    });
  };

  /* ---------- top loader ---------- */
  window.TopLoader = {
    start: function(){ var el = document.getElementById('globalTopLoader'); if (!el) return; el.style.opacity = '1'; el.style.width = '20%'; setTimeout(function(){ if (el.style.width === '20%') el.style.width = '70%'; }, 160); },
    done: function(){ var el = document.getElementById('globalTopLoader'); if (!el) return; el.style.width = '100%'; setTimeout(function(){ el.style.opacity = '0'; setTimeout(function(){ el.style.width = '0'; }, 300); }, 200); }
  };

  /* ---------- theme ---------- */
  function getPref(){ try { return localStorage.getItem('vexo_theme') || 'dark'; } catch (e) { return 'dark'; } }
  function isDark(pref){ return pref === 'dark' || (pref === 'auto' && window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches); }
  function applyTheme(pref){
    var dark = isDark(pref);
    if (dark) root.setAttribute('data-theme', 'dark'); else root.removeAttribute('data-theme');
    var tc = document.querySelector('meta[name="theme-color"]'); if (tc) tc.setAttribute('content', dark ? '#0a0e17' : '#f4f6fa');
    var wantSun = dark;
    document.querySelectorAll('[data-theme-toggle]').forEach(function(b){ if (b.getAttribute('data-icon') === String(wantSun)) return; b.setAttribute('data-icon', String(wantSun)); b.innerHTML = wantSun ? ICON_SUN : ICON_MOON; });
    document.querySelectorAll('[data-theme-toggle]').forEach(function(b){ b.setAttribute('aria-label', dark ? 'Switch to light appearance' : 'Switch to dark appearance'); });
    document.querySelectorAll('[data-theme-switch] button').forEach(function(b){ b.setAttribute('aria-pressed', String(b.dataset.v === pref)); });
  }
  var reduceMotion = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  function animateTheme(fn){
    if (reduceMotion) return fn();
    if (document.startViewTransition) { try { document.startViewTransition(fn); return; } catch (e) {} }
    root.classList.add('theme-anim'); fn();
    clearTimeout(window.__themeT); window.__themeT = setTimeout(function(){ root.classList.remove('theme-anim'); }, 500);
  }
  function setPref(pref){
    try { localStorage.setItem('vexo_theme', pref); } catch (e) {}
    if (isDark(pref) === (root.getAttribute('data-theme') === 'dark')) { applyTheme(pref); return; }
    animateTheme(function(){ applyTheme(pref); });
  }
  function initTheme(){
    document.querySelectorAll('[data-theme-switch]').forEach(function(box){
      box.innerHTML = '';
      [['light','Light'],['dark','Dark'],['auto','Auto']].forEach(function(o){
        var b = document.createElement('button'); b.type = 'button'; b.dataset.v = o[0]; b.textContent = o[1];
        b.addEventListener('click', function(){ setPref(o[0]); });
        box.appendChild(b);
      });
    });
    document.querySelectorAll('[data-theme-toggle]').forEach(function(b){
      b.addEventListener('click', function(){ setPref(isDark(getPref()) ? 'light' : 'dark'); });
    });
    if (window.matchMedia) {
      var mq = matchMedia('(prefers-color-scheme: dark)');
      var on = function(){ if (getPref() === 'auto') animateTheme(function(){ applyTheme('auto'); }); };
      if (mq.addEventListener) mq.addEventListener('change', on); else if (mq.addListener) mq.addListener(on);
    }
    applyTheme(getPref());
  }

  /* ---------- top search (phones: slide-in field) ---------- */
  function initTopSearch(){
    var input = document.getElementById('topQuery');
    var toggle = document.querySelector('[data-search-toggle]');
    if (!input) return;
    try { var q = new URLSearchParams(location.search).get('q'); if (q && location.pathname.indexOf('/search') === 0) input.value = q; } catch (e) {}
    var open = function(){ root.classList.add('search-open'); setTimeout(function(){ input.focus(); }, 30); };
    var close = function(){ root.classList.remove('search-open'); };
    if (toggle) toggle.addEventListener('click', function(e){ e.stopPropagation(); if (root.classList.contains('search-open')) close(); else open(); });
    input.addEventListener('blur', function(){ setTimeout(function(){ if (document.activeElement !== input) close(); }, 120); });
    input.form && input.form.addEventListener('submit', function(e){ if (!input.value.trim()) { e.preventDefault(); input.focus(); return; } if (window.TopLoader) TopLoader.start(); });
    document.addEventListener('keydown', function(e){
      var t = e.target, tag = t && t.tagName;
      if (e.key === 'Escape' && root.classList.contains('search-open')) { close(); input.blur(); return; }
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (t && t.isContentEditable)) return;
      e.preventDefault();
      var w = window.innerWidth; if (w < 720 || (w >= 1100 && w < 1280)) open(); else { input.focus(); input.select(); }
    });
  }

  /* ---------- sidebar libraries ---------- */
  function initLibraries(){
    var box = document.getElementById('sideLibs'), label = document.getElementById('sideLibsLabel');
    if (!box) return;
    var LOCK = ` + JSON.stringify(ICONS.lock) + String.raw`;
    function paint(list){
      if (!list || !list.length) return;
      var path = location.pathname;
      box.innerHTML = list.map(function(p){
        var href = '/browse/' + encodeURIComponent(p.id), on = path === href || path.indexOf(href + '/') === 0;
        return '<li><a class="side-link" href="' + href + '"' + (on ? ' aria-current="page"' : '') + '><span class="lib-dot">' + window.escapeHtml(String(p.name || p.id).charAt(0)) + '<img src="/assets/providers/' + encodeURIComponent(p.id) + '-icon.png" alt="" loading="lazy" onerror="this.remove()"></span><span>' + window.escapeHtml(p.name || p.id) + '</span>' + (p.status === 'locked' ? LOCK.replace('<svg', '<svg class="lib-lock"') : '') + '</a></li>';
      }).join('');
      if (label) label.hidden = false;
    }
    var cached = null;
    try { cached = JSON.parse(sessionStorage.getItem('vx_providers') || 'null'); } catch (e) {}
    if (cached && cached.at > Date.now() - 300000) { paint(cached.list); return; }
    fetch('/api/providers').then(function(r){ return r.ok ? r.json() : null; }).then(function(d){
      var list = d && Array.isArray(d.providers) ? d.providers : [];
      try { sessionStorage.setItem('vx_providers', JSON.stringify({ at: Date.now(), list: list })); } catch (e) {}
      paint(list);
    }).catch(function(){});
  }

  /* ---------- scrolled state for the top bar ---------- */
  function initScrolled(){
    var on = false;
    var check = function(){ var s = (window.scrollY || 0) > 4; if (s !== on) { on = s; root.classList.toggle('scrolled', s); } };
    window.addEventListener('scroll', check, { passive: true }); check();
  }

  /* ---------- age gate ---------- */
  function getCookie(name){ var m = document.cookie.match(new RegExp('(^| )' + name + '=([^;]+)')); return m ? m[2] : null; }
  function setCookie(name, val, days){ var d = new Date(); d.setTime(d.getTime() + days * 864e5); document.cookie = name + '=' + val + ';path=/;expires=' + d.toUTCString() + ';SameSite=Lax' + (location.protocol === 'https:' ? ';Secure' : ''); }
  function initAgeGate(){
    var overlay = document.getElementById('ageOverlay');
    if (!overlay) return;
    if (getCookie('vexo_age_verified') === 'true') return;
    overlay.classList.add('show');
    root.style.overflow = 'hidden';
    var pass = document.getElementById('btnAgePass');
    if (pass) { pass.focus(); pass.addEventListener('click', function(){ setCookie('vexo_age_verified', 'true', 30); overlay.classList.remove('show'); root.style.overflow = ''; }); }
    var exit = document.getElementById('btnAgeExit');
    if (exit) exit.addEventListener('click', function(){ window.location.href = 'https://www.google.com'; });
  }

  /* ---------- link loader ---------- */
  function initLinks(){
    document.addEventListener('click', function(e){
      var a = e.target.closest && e.target.closest('a');
      if (!a || e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || a.target === '_blank') return;
      var href = a.getAttribute('href') || '';
      if (!href || href.charAt(0) === '#' || href.indexOf('javascript:') === 0 || href.indexOf('mailto:') === 0) return;
      if (a.origin === location.origin && a.pathname !== location.pathname) window.TopLoader.start();
    });
    window.addEventListener('pageshow', function(){ window.TopLoader.done(); });
  }

  /* ---------- reveal ---------- */
  function initReveal(){
    var els = document.querySelectorAll('.reveal');
    if (!('IntersectionObserver' in window)) { els.forEach(function(el){ el.classList.add('in'); }); return; }
    var io = new IntersectionObserver(function(entries){ entries.forEach(function(en){ if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); } }); }, { rootMargin: '0px 0px -8% 0px' });
    els.forEach(function(el){ io.observe(el); });
  }

  /* ---------- footer clock ---------- */
  function pad2(n){ return (n < 10 ? '0' : '') + n; }
  function initClock(){
    var l = document.getElementById('footerClockLocal'), u = document.getElementById('footerClockUtc'), y = document.getElementById('footerYear');
    if (!l && !u) return;
    function tick(){
      var d = new Date();
      if (l) l.textContent = pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
      if (u) u.textContent = pad2(d.getUTCHours()) + ':' + pad2(d.getUTCMinutes()) + ':' + pad2(d.getUTCSeconds());
      if (y) { var cy = String(d.getUTCFullYear()); if (y.textContent !== cy) y.textContent = cy; }
    }
    tick();
    (function schedule(){ setTimeout(function(){ tick(); schedule(); }, 1000 - (Date.now() % 1000)); })();
  }

  /* ---------- protect media from drag / save ---------- */
  document.addEventListener('dragstart', function(e){ if (e.target && (e.target.tagName === 'IMG' || e.target.tagName === 'VIDEO')) e.preventDefault(); });
  document.addEventListener('contextmenu', function(e){ if (e.target && e.target.closest && e.target.closest('.vx-player, .vthumb')) e.preventDefault(); });

  /* ---------- duration formatting ---------- */
  window.vxDur = function(v){
    if (v === null || v === undefined || v === '') return '';
    var total = 0;
    if (typeof v === 'number' || /^[0-9]+(\.[0-9]+)?$/.test(String(v).trim())) total = Math.floor(Number(v));
    else {
      var parts = String(v).trim().split(':');
      if (parts.length < 2 || parts.length > 3) return String(v).trim();
      for (var i = 0; i < parts.length; i++) { var p = parseInt(parts[i], 10); if (isNaN(p)) return String(v).trim(); total = total * 60 + p; }
    }
    if (!total || total < 0) return '';
    var h = Math.floor(total / 3600), mi = Math.floor((total % 3600) / 60), se = total % 60;
    var p2 = function(x){ return (x < 10 ? '0' : '') + x; };
    return h ? h + ':' + p2(mi) + ':' + p2(se) : mi + ':' + p2(se);
  };

  /* ---------- burger menu ---------- */
  function initDrawer(){
    var d = document.getElementById('vxDrawer'); if (!d) return;
    var openers = document.querySelectorAll('[data-drawer-open]'), last = null;
    function set(open){
      d.classList.toggle('open', open);
      d.setAttribute('aria-hidden', String(!open));
      if (open) d.removeAttribute('inert'); else d.setAttribute('inert', '');
      root.classList.toggle('drawer-open', open);
      openers.forEach(function(b){ b.setAttribute('aria-expanded', String(open)); });
      if (open) { last = document.activeElement; var f = d.querySelector('.vxd-nav a[aria-current="page"]') || d.querySelector('.vxd-panel [data-drawer-close]'); setTimeout(function(){ f && f.focus({ preventScroll: true }); }, 60); }
      else if (last && last.focus) last.focus({ preventScroll: true });
    }
    openers.forEach(function(b){ b.addEventListener('click', function(e){ e.stopPropagation(); set(!d.classList.contains('open')); }); });
    d.querySelectorAll('[data-drawer-close]').forEach(function(b){ b.addEventListener('click', function(){ set(false); }); });
    d.querySelectorAll('a[href]').forEach(function(a){ a.addEventListener('click', function(){ if (a.target !== '_blank') set(false); }); });
    document.addEventListener('keydown', function(e){
      if (!d.classList.contains('open')) return;
      if (e.key === 'Escape') { e.preventDefault(); set(false); return; }
      if (e.key !== 'Tab') return;
      var f = d.querySelectorAll('.vxd-panel a[href], .vxd-panel button'); if (!f.length) return;
      var first = f[0], end = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); end.focus(); }
      else if (!e.shiftKey && document.activeElement === end) { e.preventDefault(); first.focus(); }
    });
  }

  /* ---------- member account + "Please log in first" ---------- */
  function vxState(){ return window.VXM || {}; }
  function initAccount(){
    var st = vxState(), here = location.pathname + location.search;
    var q = (here === '/' || /^\/(login|signup)/.test(location.pathname)) ? '' : '?next=' + encodeURIComponent(here);
    document.querySelectorAll('[data-acct-login]').forEach(function(a){ a.href = '/login' + q; });
    document.querySelectorAll('[data-acct-signup]').forEach(function(a){ a.href = '/signup' + q; });
    if (st.signup === false) document.querySelectorAll('[data-acct-signup]').forEach(function(a){ a.hidden = true; });
    if (!st.in) return;
    document.querySelectorAll('[data-acct-name]').forEach(function(el){ el.textContent = st.name || 'Member'; });
    document.querySelectorAll('[data-acct-initial]').forEach(function(el){ el.textContent = (st.name || 'M').charAt(0); });
    document.querySelectorAll('[data-acct-role]').forEach(function(el){ el.textContent = st.role || 'Member'; });
    if (st.admin) document.querySelectorAll('[data-acct-admin]').forEach(function(a){ a.href = st.admin; a.hidden = false; });
    // Desktop (no burger): the account button opens a small menu instead of the sidebar.
    var btn = document.querySelector('[data-acct-toggle]'), pop = document.querySelector('[data-acct-pop]');
    var wide = window.matchMedia ? window.matchMedia('(min-width:1100px)') : null;
    if (!btn || !pop) return;
    var popT = 0;
    function setPop(open){
      clearTimeout(popT);
      btn.setAttribute('aria-expanded', String(open));
      if (open) { pop.classList.remove('closing'); pop.hidden = false; pop.classList.add('open'); return; }
      if (pop.hidden) return;
      // play the exit (fade + scale + blur), then hide
      pop.classList.remove('open'); pop.classList.add('closing');
      popT = setTimeout(function(){ pop.hidden = true; pop.classList.remove('closing'); }, reduceMotion ? 0 : 160);
    }
    btn.addEventListener('click', function(e){
      if (!wide || !wide.matches) return;
      e.preventDefault(); e.stopImmediatePropagation();
      setPop(pop.hidden || pop.classList.contains('closing'));
    });
    document.addEventListener('click', function(e){ if (!pop.hidden && !pop.contains(e.target) && e.target !== btn && !btn.contains(e.target)) setPop(false); });
    document.addEventListener('keydown', function(e){ if (e.key === 'Escape' && !pop.hidden) { setPop(false); btn.focus(); } });
    if (wide && wide.addEventListener) wide.addEventListener('change', function(){ setPop(false); });
  }
  var loginBox = null, loginLast = null;
  function loginModal(next, kind){
    if (!loginBox) {
      loginBox = document.createElement('div');
      loginBox.className = 'vxl'; loginBox.setAttribute('role', 'dialog'); loginBox.setAttribute('aria-modal', 'true'); loginBox.setAttribute('aria-labelledby', 'vxlTitle');
      loginBox.innerHTML = '<div class="vxl-scrim" data-vxl-close></div><div class="vxl-card">' +
        '<button class="icon-round vxl-x" type="button" data-vxl-close aria-label="Close"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>' +
        '<div class="vxl-lock"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="11" width="16" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg></div>' +
        '<h2 id="vxlTitle">Please log in first.</h2><p>Use a member or existing admin account, or create a free member account.</p>' +
        '<div class="vxl-b"><a class="btn" data-vxl-login href="/login">Log in</a><a class="btn quiet" data-vxl-signup href="/signup">Create free account</a></div></div>';
      document.body.appendChild(loginBox);
      loginBox.querySelectorAll('[data-vxl-close]').forEach(function(b){ b.addEventListener('click', closeLogin); });
      document.addEventListener('keydown', function(e){ if (e.key === 'Escape' && loginBox.classList.contains('open')) closeLogin(); });
    }
    var q = '?next=' + encodeURIComponent(next || location.pathname);
    var lp = loginBox.querySelector('.vxl-card p'); if (lp) lp.textContent = kind === 'models' ? 'Models are for members. Log in, or create a free account in seconds.' : 'Use a member or existing admin account, or create a free member account.';
    loginBox.querySelector('[data-vxl-login]').href = '/login' + q;
    var su = loginBox.querySelector('[data-vxl-signup]'); su.href = '/signup' + q; su.hidden = vxState().signup === false;
    loginLast = document.activeElement;
    loginBox.classList.add('open');
    setTimeout(function(){ var f = loginBox.querySelector('[data-vxl-login]'); f && f.focus({ preventScroll: true }); }, 60);
  }
  function closeLogin(){ if (!loginBox) return; loginBox.classList.remove('open'); if (loginLast && loginLast.focus) loginLast.focus({ preventScroll: true }); }
  // true = blocked (popup shown). Used by cards, the paste box and any /video/ link.
  window.vxNeedsLogin = function(next){ var st = vxState(); if (!st.required || st.in) return false; loginModal(next); return true; };
  window.vxNeedsModelsLogin = function(next){ var st = vxState(); if (st.models === false || st.in) return false; loginModal(next, 'models'); return true; };
  function initVideoGate(){
    document.addEventListener('click', function(e){
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      var a = e.target && e.target.closest ? e.target.closest('a[href]') : null; if (!a) return;
      var u; try { u = new URL(a.href, location.href); } catch (err) { return; }
      if (u.origin !== location.origin) return;
      var isVideo = /^\/video\//.test(u.pathname), isModels = /^\/models(\/|$)/.test(u.pathname);
      if (!isVideo && !isModels) return;
      if (isModels ? window.vxNeedsModelsLogin(u.pathname + u.search) : window.vxNeedsLogin(u.pathname + u.search)) { e.preventDefault(); e.stopPropagation(); }
    }, true);
  }

  function boot(){ initAccount(); initVideoGate(); initDrawer(); initTheme(); initTopSearch(); initLibraries(); initScrolled(); initAgeGate(); initLinks(); initReveal(); initClock(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();

/* Watch history (local only): powers Continue watching + resume. */
(function(){
  var KEY = 'vx_history_v1', MAX = 40;
  function read(){ try { var l = JSON.parse(localStorage.getItem(KEY) || '[]'); return Array.isArray(l) ? l : []; } catch (e) { return []; } }
  function write(l){ try { localStorage.setItem(KEY, JSON.stringify(l.slice(0, MAX))); } catch (e) {} }
  window.VXHistory = {
    list: function(){ return read(); },
    get: function(u){ var l = read(); for (var i = 0; i < l.length; i++) if (l[i].u === u) return l[i]; return null; },
    save: function(entry){
      if (!entry || !entry.u) return;
      var l = read(), old = null;
      l = l.filter(function(x){ if (x.u === entry.u) { old = x; return false; } return true; });
      var merged = {}; var k;
      if (old) for (k in old) merged[k] = old[k];
      for (k in entry) if (entry[k] !== undefined && entry[k] !== '') merged[k] = entry[k];
      merged.at = Date.now();
      l.unshift(merged); write(l);
    },
    remove: function(u){ write(read().filter(function(x){ return x.u !== u; })); }
  };
})();

/* Live viewers: header pill + home line. The server sends a per-second series. */
(function(){
  var boxes = document.querySelectorAll('[data-live]');
  if (!boxes.length || !window.fetch) return;
  var nums = document.querySelectorAll('[data-live-count]');
  var full = new Intl.NumberFormat('en-US');
  var compact = new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 });
  var small = window.matchMedia ? window.matchMedia('all') : null;
  var calm = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)').matches : false;
  var sid = '';
  try { sid = localStorage.getItem('vx_live_sid') || ''; } catch (e) {}
  if (!/^[a-z0-9]{16,40}$/.test(sid)) {
    var abc = 'abcdefghijklmnopqrstuvwxyz0123456789', buf = new Uint8Array(24);
    if (window.crypto && crypto.getRandomValues) crypto.getRandomValues(buf); else for (var b = 0; b < 24; b++) buf[b] = Math.floor(Math.random() * 256);
    sid = '';
    for (var i = 0; i < 24; i++) sid += abc.charAt(buf[i] % 36);
    try { localStorage.setItem('vx_live_sid', sid); } catch (e) {}
  }
  var series = null, skew = 0, shown = null, raf = 0;
  function paint(v){
    nums.forEach(function(n){ n.textContent = (n.hasAttribute('data-compact') && small && small.matches && v >= 10000) ? compact.format(v) : full.format(v); });
  }
  function tween(to){
    if (shown === to) return;
    if (shown == null || calm) { shown = to; paint(to); return; }
    var from = shown, t0 = performance.now();
    if (raf) cancelAnimationFrame(raf);
    (function step(now){
      var p = Math.min(1, (now - t0) / 650); p = 1 - Math.pow(1 - p, 3);
      shown = Math.round(from + (to - from) * p); paint(shown);
      if (p < 1) raf = requestAnimationFrame(step);
    })(t0);
  }
  function tick(){
    if (!series) return;
    var i = Math.floor(Date.now() / 1000 + skew) - series.start;
    i = Math.max(0, Math.min(series.values.length - 1, i));
    tween(series.values[i]);
  }
  function show(on){ boxes.forEach(function(el){ el.hidden = !on; }); }
  function load(){
    fetch('/api/live?sid=' + sid, { credentials: 'same-origin', cache: 'no-store' }).then(function(r){ return r.ok ? r.json() : null; }).then(function(d){
      if (!d || !d.enabled || !d.values || !d.values.length) { series = null; show(false); return; }
      series = d; skew = d.start + 0.5 - Date.now() / 1000;
      show(true); tick();
    }).catch(function(){});
  }
  load();
  setInterval(tick, 1000);
  setInterval(function(){ if (document.visibilityState === 'visible') load(); }, 25000);
  document.addEventListener('visibilitychange', function(){ if (document.visibilityState === 'visible') load(); });
  if (small && small.addEventListener) small.addEventListener('change', function(){ if (shown != null) paint(shown); });
})();
`;

