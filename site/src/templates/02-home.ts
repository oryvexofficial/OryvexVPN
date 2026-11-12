// ============================================================================
// PAGE: HOME
// ============================================================================
function listWords(names) {
    if (names.length <= 1) return names.join('');
    return names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
}
const NUM_WORDS = ['No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten'];



function searchFormHtml(q, provider, placeholder, autofocus) {
    return '<form class="search" action="/search" method="GET" role="search">' + ICONS.search +
        '<label for="exploreQuery" class="sr-only">Search</label>' +
        '<input type="search" id="exploreQuery" name="q" maxlength="100" value="' + escapeHtml(q || '') + '" placeholder="' + escapeHtml(placeholder || 'Search') + '" autocomplete="off" enterkeyhint="search"' + (autofocus ? ' autofocus' : '') + '>' +
        (provider ? '<input type="hidden" name="provider" value="' + escapeHtml(provider) + '">' : '') +
        '<button class="btn" type="submit">Search</button></form>';
}

function catalogUrl(kind, provider, q, page, defId) {
    if (kind === 'search') {
        const sp = new URLSearchParams();
        if (q) sp.set('q', q);
        if (provider && provider !== defId) sp.set('provider', provider);
        if (page > 1) sp.set('page', String(page));
        const qs = sp.toString();
        return '/search' + (qs ? '?' + qs : '');
    }
    return '/browse/' + provider + (page > 1 ? '?page=' + page : '');
}

// ---------------------------------------------------------------------------
// HOME  (/)
// ---------------------------------------------------------------------------
function renderHomeHtml(meta, cfg = normalizeProviderConfig(null)) {
    const live = browseProviders(cfg);
    const listed = listedProviders(cfg);
    const playable = playableProviders(cfg);
    const defId = defaultProviderOf(cfg);
    const srcs = live.map(p => '<a class="inline-flex h-9 items-center gap-2 rounded-full border border-line bg-surface ps-1.5 pe-3.5 text-sm font-medium text-fg no-underline transition hover:border-brand/50 hover:bg-surface-2 hover:no-underline active:scale-95" href="/browse/' + p.id + '"><span class="lib-dot size-6">' + escapeHtml(p.name.slice(0, 1)) + '<img src="/assets/providers/' + p.id + '-icon.png" alt="" loading="lazy" onerror="this.remove()"></span>' + escapeHtml(p.name) + '</a>').join('');
    const libs = listed.map((p, i) => '<a class="lib" href="/browse/' + p.id + '"><span class="lib-mono">' + escapeHtml(p.name.slice(0, 2)) + '<img src="/assets/providers/' + p.id + '-icon.png" alt="" loading="lazy" onerror="this.remove()"></span><span><b>' + escapeHtml(p.name) + '</b><small>' + (p.mode === 'live' ? escapeHtml(p.domain) : 'Currently unavailable') + '</small></span>' + (p.mode === 'live' ? '<span class="lib-state"><i></i><span>On air</span></span>' : '<span class="lib-state off"><i></i><span>Off air</span></span>') + '<span class="chev" aria-hidden="true"></span></a>').join('');
    const head = (id, title, sub, tools) => '<div class="section-head"><div><h2 class="section-title" id="' + id + '">' + title + '</h2>' + (sub ? '<p class="section-sub">' + sub + '</p>' : '') + '</div>' + (tools ? '<div class="head-tools">' + tools + '</div>' : '') + '</div>';
    const railNav = (rid) => '<div class="rail-nav" data-rail="' + rid + '"><button type="button" data-dir="-1" aria-label="Scroll left">&lsaquo;</button><button type="button" data-dir="1" aria-label="Scroll right">&rsaquo;</button></div>';
    return renderHead({ meta }) +
        '<body class="home">' +
        renderAgeGate() +
        renderNav('home') +
        '<main class="page"><div class="wrap-wide">' +
        '<section class="pt-10 pb-2 text-center tab:pt-20" aria-labelledby="heroTitle">' +
        '<p class="rise m-0 inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3.5 py-1.5 text-[13px] font-medium text-muted"><i class="size-1.5 rounded-full bg-ok shadow-[0_0_0_3px_color-mix(in_oklab,var(--green)_25%,transparent)]" aria-hidden="true"></i>Free, ad-free HD player</p>' +
        '<h1 class="rise mx-auto mt-7 mb-0 max-w-[14ch] text-5xl leading-[.95] font-semibold tracking-[-.055em] text-balance tab:text-7xl nav:text-[104px]" style="--d:1" id="heroTitle">Paste a link. <span class="text-brand">Press play.</span></h1>' +
        '<p class="rise mx-auto mt-6 mb-0 max-w-xl text-lg text-muted tab:text-xl" style="--d:2">Every quality, no ads, streamed straight from the edge.</p>' +
        '<div class="rise mx-auto mt-10 max-w-2xl" style="--d:3">' +
        '<div class="hero-paste flex h-14 items-center gap-2 rounded-full border border-line bg-surface ps-5 pe-1.5 tab:h-16 tab:pe-2">' +
        '<span class="hidden text-subtle tab:block [&>svg]:size-5" aria-hidden="true">' + ICONS.link + '</span>' +
        '<label for="targetUrl" class="sr-only">Video link or viewkey</label>' +
        '<input class="h-full min-w-0 flex-1 border-0 bg-transparent text-base text-fg outline-none placeholder:text-subtle tab:text-[17px]" type="text" id="targetUrl" inputmode="url" placeholder="Paste a link or viewkey" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="go">' +
        '<button class="btn h-11 px-6 text-[15px] tab:h-12 tab:px-7" id="extractBtn" type="button">' + ICONS.play + 'Play</button>' +
        '</div>' +
        '<p class="paste-hint" id="pasteHint">' + (playable.length ? 'Works with ' + escapeHtml(listWords(playable.map(p => p.name))) + '.' : 'Playback is paused right now.') + '</p>' +
        '<p class="live-line" data-live hidden><i aria-hidden="true"></i><span><b data-live-count>0</b> people watching right now</span></p>' +
        '</div>' +
        (srcs ? '<nav class="rise mt-8 flex flex-wrap justify-center gap-2" style="--d:4" aria-label="Libraries">' + srcs + '</nav>' : '') +
        '</section>' +
        '<section class="section" id="continueSec" hidden aria-labelledby="cwTitle">' + head('cwTitle', 'Continue watching', '', '<button class="cw-clear" type="button" id="cwClear">Clear</button>' + railNav('continueRail')) + '<div class="rail" id="continueRail"></div></section>' +
        (defId ? '<section class="section" id="trendSec" aria-labelledby="trendTitle">' + head('trendTitle', 'Trending on ' + escapeHtml(providerName(defId)), '', '<a class="see-all" href="/browse/' + defId + '">See all' + ICONS.arrow + '</a>' + railNav('trendRail')) + '<div class="rail" id="trendRail"></div></section>' : '') +
        (libs ? '<section class="section" aria-labelledby="libTitle">' + head('libTitle', 'Libraries', 'One clean player for every source.', '') + '<div class="libs">' + libs + '</div></section>' : '') +
        '<section class="section" aria-label="Features"><div class="grid gap-4 tab:grid-cols-3">' +
        '<article class="reveal feature flex flex-col rounded-2xl border border-line bg-surface p-6"><p class="m-0 text-sm font-medium text-brand">Quality</p><h3 class="mt-2 mb-0 text-xl font-semibold tracking-tight">Every quality.</h3><p class="mt-2 mb-0 text-[15px] text-muted">240p to 4K, HLS or MP4. Drops a notch by itself when your network dips.</p><div class="mt-auto flex flex-wrap gap-1.5 pt-6 font-mono text-xs"><span class="rounded-md border border-line px-2 py-1 text-muted">240</span><span class="rounded-md border border-line px-2 py-1 text-muted">480</span><span class="rounded-md border border-line px-2 py-1 text-muted">720</span><span class="rounded-md border border-line px-2 py-1 text-muted">1080</span><span class="rounded-md bg-brand px-2 py-1 text-white">4K</span></div></article>' +
        '<article class="reveal feature flex flex-col rounded-2xl border border-line bg-surface p-6"><p class="m-0 text-sm font-medium text-brand">For your site</p><h3 class="mt-2 mb-0 text-xl font-semibold tracking-tight">Embed anywhere.</h3><p class="mt-2 mb-0 text-[15px] text-muted">One line of code. Responsive by default.</p><div class="mt-auto pt-6"><code class="block truncate rounded-lg border border-line bg-bg px-3 py-2.5 font-mono text-[13px] text-muted">&lt;<span class="text-brand">vexo-player</span> viewkey="&hellip;"&gt;</code><a class="chev mt-3" href="/developers">Developer guide</a></div></article>' +
        '<article class="reveal feature flex flex-col rounded-2xl border border-line bg-surface p-6"><p class="m-0 text-sm font-medium text-brand">Gesture</p><h3 class="mt-2 mb-0 text-xl font-semibold tracking-tight">Hold to fly.</h3><p class="mt-2 mb-0 text-[15px] text-muted">Press and hold the picture for 2&times; speed.</p><div class="mt-auto pt-6"><span class="inline-flex items-center gap-2 rounded-lg border border-line px-3 py-2 font-mono text-sm text-fg [&>svg]:size-4 [&>svg]:text-brand">2&times; ' + ICONS.fast + '</span></div></article>' +
        '</div></section>' +
        '<section class="section max-w-3xl" aria-labelledby="aboutTitle"><h2 class="section-title" id="aboutTitle">What is VexoStream?</h2>' +
        '<p class="mt-3 mb-0 text-base leading-relaxed text-muted">VexoStream is a free, ad-free 18+ video player. Paste a link from a supported library or browse what&rsquo;s trending, and it streams in every quality from 240p to 4K through the edge, without storing a thing.</p></section>' +
        '</div></main>' +
        renderFooter() +
        clientConfigScript({ playable: playable.map(p => p.id), defaultProvider: defId, trend: defId ? { provider: defId, q: cfg.defaultQuery || 'trending' } : null }) +
        '<script>' + COMMON_JS + CARD_JS + HOME_JS + '</script>' +
        '</body></html>';
}

// ---------------------------------------------------------------------------
// BROWSE (/browse, /browse/:provider) + SEARCH (/search?q=)
// ---------------------------------------------------------------------------
function renderCatalogHtml(meta, cfg, opts) {
    const kind = opts.kind === 'search' ? 'search' : 'browse';
    const live = browseProviders(cfg);
    const defId = defaultProviderOf(cfg);
    const provider = opts.provider || defId;
    const page = opts.page > 0 ? opts.page : 1;
    const q = String(opts.q || '').slice(0, 100);
    const pname = providerName(provider);
    const hasQuery = kind === 'browse' || !!q;
    const tabs = live.map(p => '<a href="' + catalogUrl(kind, p.id, q, 1, defId) + '"' + (p.id === provider ? ' aria-current="page"' : '') + '>' + escapeHtml(p.name) + '</a>').join('');
    const title = kind === 'search' ? (q ? 'Results for \u201c' + escapeHtml(q) + '\u201d' : 'Search the catalogue.') : 'Browse ' + escapeHtml(pname) + '.';
    const sub = kind === 'search' ? (q ? 'On ' + escapeHtml(pname) + (page > 1 ? ', page ' + page : '') + '.' : 'Type a keyword, pick a library.') : 'Fresh picks from ' + escapeHtml(pname) + (page > 1 ? ', page ' + page : '') + '.';
    const crumbs = '<p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span>' + (kind === 'search' ? '<a href="/search">Search</a>' : '<a href="/browse">Browse</a>') + '</p>';
    const prevHref = page > 1 ? catalogUrl(kind, provider, q, page - 1, defId) : '#';
    const nextHref = catalogUrl(kind, provider, q, page + 1, defId);
    return renderHead({ meta }) +
        '<body>' + renderAgeGate() + renderNav(kind) +
        '<main class="page" id="browse"><div class="wrap-wide">' +
        '<header class="page-head">' + crumbs + '<div class="cat-head"><div><h1 class="headline">' + title + '</h1><p class="subhead">' + sub + '</p></div></div></header>' +
        '<div class="toolbar">' +
        (live.length ? '<nav class="segmented" aria-label="Provider" id="providerSeg">' + tabs + '</nav>' : '<p class="subhead" style="margin:0">The catalogue is paused right now.</p>') +
        searchFormHtml(q, provider !== defId ? provider : '', 'Search ' + (kind === 'browse' ? pname : 'videos'), kind === 'search' && !q) +
        '</div>' +
        '<div id="exploreGrid" class="vgrid" aria-live="polite">' + (hasQuery ? '' : '<div class="empty"><b>What are you in the mood for?</b>Search by keyword to see results.</div>') + '</div>' +
        (hasQuery ? '<div class="pager" id="paginationBar">' +
            '<a class="btn quiet sm' + (page > 1 ? '' : ' is-off') + '" id="prevPageBtn" href="' + prevHref + '"' + (page > 1 ? '' : ' aria-disabled="true" tabindex="-1"') + '>&lsaquo; Previous</a>' +
            '<span class="pager-label" id="pageIndicator">Page ' + page + '</span>' +
            '<a class="btn quiet sm is-off" id="nextPageBtn" href="' + nextHref + '" aria-disabled="true" tabindex="-1">Next &rsaquo;</a>' +
            '</div>' : '') +
        '</div></main>' + renderFooter() +
        clientConfigScript({ catalog: { kind, provider: live.some(p => p.id === provider) ? provider : '', q: kind === 'browse' ? (cfg.defaultQuery || 'trending') : q, page, active: hasQuery }, lockMessage: cfg.lockMessage }) +
        '<script>' + COMMON_JS + CARD_JS + CATALOG_JS + '</script>' +
        '</body></html>';
}

// ---------------------------------------------------------------------------
// DEVELOPERS (/developers)
// ---------------------------------------------------------------------------
function renderDevelopersHtml(meta, origin) {
    const o = escapeHtml(origin);
    return renderHead({ meta }) +
        '<body>' + renderNav('developers') +
        '<main class="page">' +
        '<section class="page-head"><div class="wrap-wide"><p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span><span>Developers</span></p>' +
        '<h1 class="headline">Embed anywhere.</h1><p class="subhead">One line drops the full player into any page.</p></div></section>' +
        '<section class="section alt" style="padding-top:clamp(32px,4vw,48px)"><div class="wrap-wide"><div class="dev-grid">' +
        '<article class="dev-card"><h3>Web component</h3><p>Responsive, themed, and self-sizing.</p><pre>&lt;script src="' + o + '/embed.js"&gt;&lt;/script&gt;\n&lt;vexo-player viewkey="VIEWKEY"&gt;&lt;/vexo-player&gt;</pre></article>' +
        '<article class="dev-card"><h3>Plain iframe</h3><p>Works on any site or CMS.</p><pre>&lt;iframe src="' + o + '/embed?viewkey=VIEWKEY"\n  width="640" height="360"\n  allow="fullscreen; picture-in-picture"\n  frameborder="0"&gt;&lt;/iframe&gt;</pre></article>' +
        '<article class="dev-card"><h3>Any supported link</h3><p>Pass a full URL instead of a viewkey.</p><pre>' + o + '/embed?url=https%3A%2F%2F...</pre></article>' +
        '<article class="dev-card"><h3>Public endpoints</h3><p>Read-only and cache-friendly.</p><ul>' +
        '<li><code>/api/status</code><span>Service and provider health</span></li>' +
        '<li><code>/api/providers</code><span>Available libraries</span></li>' +
        '<li><code>/status</code><span>Status page</span></li></ul></article>' +
        '</div></div></section>' +
        '</main>' + renderFooter() + '<script>' + COMMON_JS + '</script></body></html>';
}

function renderModelsHtml(meta, slug = '') {
    const cleanSlug = String(slug || '').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 120);
    const crumbsList = '<p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span><span>OnlyFans Models</span></p>';
    const crumbsProfile = '<p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span><a href="/models">OnlyFans Models</a></p>';
    const genders = [['Female', 'Women'], ['Female,Male', 'Both'], ['Male', 'Men']];
    const seg = '<div class="segmented" role="group" aria-label="Gender" id="modelGender">' +
        genders.map(g => '<button type="button" data-gender="' + g[0] + '" aria-pressed="' + (g[0] === 'Female' ? 'true' : 'false') + '">' + g[1] + '</button>').join('') + '</div>';
    const search = '<form class="search models-search" id="modelSearch" role="search">' + ICONS.search +
        '<label for="modelQuery" class="sr-only">Search models</label>' +
        '<input type="search" id="modelQuery" name="q" maxlength="80" placeholder="Search models" autocomplete="off" enterkeyhint="search">' +
        '<button class="btn" type="submit">Search</button></form>';
    const listBody =
        '<section class="page-head"><div class="wrap-wide">' + crumbsList +
        '<h1 class="headline">OnlyFans Models</h1><p class="subhead">The most popular profiles right now.</p></div></section>' +
        '<section class="section alt models-section"><div class="wrap-wide">' +
        '<div class="models-toolbar">' + seg + search + '</div>' +
        '<p class="models-count" id="modelsCount" aria-live="polite"></p>' +
        '<div id="modelsGrid" class="models-grid" aria-live="polite"></div>' +
        '<div class="models-pager"><button class="btn quiet sm" id="modelsPrev" type="button" disabled>&lsaquo; Previous</button><span class="pager-label" id="modelsPage">Page 1</span><button class="btn quiet sm" id="modelsNext" type="button" disabled>Next &rsaquo;</button></div>' +
        '</div></section>';
    const profileBody =
        '<section class="page-head" style="padding-bottom:0"><div class="wrap-wide">' + crumbsProfile + '</div></section>' +
        '<section class="section models-section" style="padding-top:clamp(12px,2vw,20px)"><div class="wrap-wide">' +
        '<div class="mprofile">' +
        '<div class="mgallery"><div class="mstage" id="mStage">' +
        '<button class="mnav prev" id="mPrev" type="button" aria-label="Previous photo" hidden>&lsaquo;</button>' +
        '<button class="mnav next" id="mNext" type="button" aria-label="Next photo" hidden>&rsaquo;</button>' +
        '<span class="mcounter" id="mCounter" hidden></span></div>' +
        '<div class="mthumbs" id="mThumbs" role="group" aria-label="Photos"></div></div>' +
        '<div><div class="mhead"><h1 class="headline" id="modelName">Loading&hellip;</h1><p class="mcountry" id="modelCountry"></p></div>' +
        '<div class="mdetails" id="modelDetails" aria-live="polite"></div></div>' +
        '</div></div></section>';
    return renderHead({ meta }) +
        '<body>' + renderAgeGate() + renderNav('models') +
        '<main class="page">' + (cleanSlug ? profileBody : listBody) + '</main>' +
        renderFooter() +
        clientConfigScript({}) +
        '<script>' + COMMON_JS + MODELS_JS(cleanSlug) + '</script></body></html>';
}

function MODELS_JS(slug) {
    return String.raw`
(function(){
  var slug = ` + JSON.stringify(slug) + String.raw`;
  var TOKEN = (window.VX && window.VX.token) || '';
  var esc = window.escapeHtml || function(v){ return String(v == null ? '' : v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); };
  var FLAG_RE = /\uD83C[\uDDE6-\uDDFF]/g;
  function noFlag(t){ return String(t || '').replace(FLAG_RE, '').replace(/\s+/g, ' ').trim(); }
  function flagOf(t){ var m = String(t || '').match(/\uD83C[\uDDE6-\uDDFF]\uD83C[\uDDE6-\uDDFF]/); return m ? m[0] : ''; }
  function proxied(u){ return '/proxy-image?url=' + encodeURIComponent(u) + '&token=' + encodeURIComponent(TOKEN); }
  // Every image goes through the Worker proxy only (the source hosts are filtered on many networks).
  // One quiet retry through the proxy, then give up; fade in when ready.
  function loadImg(img, url, onFail){
    if (!url) { if (onFail) onFail(); return; }
    var retried = false;
    img.addEventListener('load', function(){ img.classList.add('ok'); });
    img.addEventListener('error', function(){
      if (!retried) { retried = true; setTimeout(function(){ img.src = proxied(url) + '&retry=1'; }, 700); return; }
      if (onFail) onFail();
    });
    img.decoding = 'async';
    img.src = proxied(url);
  }
  function countryHtml(flag, name){
    name = noFlag(name); flag = flag || '';
    if (!name && !flag) return '';
    return (flag ? '<span class="flag" aria-hidden="true">' + esc(flag) + '</span>' : '') + (name ? '<span>' + esc(name) + '</span>' : '');
  }
  function statusHtml(title, sub){ return '<div class="models-status"><b>' + esc(title) + '</b>' + (sub ? '<span>' + esc(sub) + '</span>' : '') + '</div>'; }

  /* ---------------- directory ---------------- */
  var grid = document.getElementById('modelsGrid');
  if (grid) {
    var seg = document.getElementById('modelGender');
    var form = document.getElementById('modelSearch');
    var input = document.getElementById('modelQuery');
    var prev = document.getElementById('modelsPrev');
    var next = document.getElementById('modelsNext');
    var pageLabel = document.getElementById('modelsPage');
    var countEl = document.getElementById('modelsCount');
    var GENDERS = { 'Female': 1, 'Male': 1, 'Female,Male': 1 };
    var sp = new URLSearchParams(location.search);
    var state = {
      gender: GENDERS[sp.get('gender')] ? sp.get('gender') : 'Female',
      q: (sp.get('q') || '').slice(0, 80),
      page: Math.max(1, Math.min(500, parseInt(sp.get('page') || '1', 10) || 1))
    };
    var reqId = 0;
    input.value = state.q;
    function syncSeg(){ seg.querySelectorAll('button').forEach(function(b){ b.setAttribute('aria-pressed', b.getAttribute('data-gender') === state.gender ? 'true' : 'false'); }); }
    function syncUrl(push){
      var u = new URLSearchParams();
      if (state.gender !== 'Female') u.set('gender', state.gender);
      if (state.q) u.set('q', state.q);
      if (state.page > 1) u.set('page', String(state.page));
      var url = '/models' + (u.toString() ? '?' + u.toString() : '');
      try { history[push ? 'pushState' : 'replaceState'](state, '', url); } catch (e) {}
    }
    function skeletons(n){
      var h = '';
      for (var i = 0; i < n; i++) h += '<div class="mcard skeleton" aria-hidden="true"><div class="mposter"></div><div class="sk-line" style="width:78%"></div><div class="sk-line" style="width:46%;height:11px"></div></div>';
      return h;
    }
    function card(m, i){
      var a = document.createElement('a');
      a.className = 'mcard';
      a.href = '/models/' + encodeURIComponent(m.slug || '');
      a.style.setProperty('--i', String(Math.min(i, 24)));
      a.innerHTML = '<div class="mposter"><img alt="' + esc(m.name) + '" loading="lazy"></div>' +
        '<h2>' + esc(m.name) + '</h2><div class="mcountry">' + countryHtml(m.country_flag, m.country_name) + '</div>';
      loadImg(a.querySelector('img'), m.image_url, function(){ var im = a.querySelector('img'); if (im) im.remove(); });
      a.addEventListener('click', function(){ if (window.TopLoader) TopLoader.start(); });
      return a;
    }
    function swap(render){
      // fade the old cards out, then drop the new ones in; returns the fade length
      if (!grid.children.length || grid.querySelector('.skeleton')) { render(); return 0; }
      grid.classList.add('leaving');
      setTimeout(function(){ grid.classList.remove('leaving'); render(); }, 200);
      return 200;
    }
    function load(push){
      var id = ++reqId;
      syncSeg(); if (push !== undefined) syncUrl(push);
      prev.disabled = true; next.disabled = true;
      pageLabel.textContent = 'Page ' + state.page;
      countEl.textContent = state.q ? 'Searching \u201c' + state.q + '\u201d\u2026' : '';
      var readyAt = Date.now() + swap(function(){ if (id === reqId) { grid.innerHTML = skeletons(12); grid.setAttribute('aria-busy', 'true'); } }) + 20;
      if (window.TopLoader) TopLoader.start();
      var qs = 'gender=' + encodeURIComponent(state.gender) + '&sort=popularity&page=' + state.page + (state.q ? '&search=' + encodeURIComponent(state.q) : '');
      fetch('/api/models?' + qs, { headers: { 'X-Edge-Token': TOKEN } })
        .then(function(r){ if (!r.ok) throw new Error('The directory answered ' + r.status + '.'); return r.json(); })
        .then(function(data){
          if (id !== reqId) return;
          var list = Array.isArray(data.models) ? data.models : [];
          setTimeout(function(){
            if (id !== reqId) return;
            if (!list.length) {
              grid.innerHTML = statusHtml(state.q ? 'No models match \u201c' + state.q + '\u201d.' : 'No profiles on this page.', 'Try another name or filter.');
              countEl.textContent = '';
              return;
            }
            var frag = document.createDocumentFragment();
            list.forEach(function(m, i){ frag.appendChild(card(m, i)); });
            grid.innerHTML = ''; grid.appendChild(frag);
            countEl.textContent = state.q ? 'Results for \u201c' + state.q + '\u201d' : 'Sorted by popularity';
            prev.disabled = state.page <= 1;
            next.disabled = !data.has_more;
          }, Math.max(40, readyAt - Date.now()));
        })
        .catch(function(err){
          if (id !== reqId) return;
          setTimeout(function(){
            if (id !== reqId) return;
            grid.innerHTML = statusHtml('Couldn\u2019t load the directory.', (err && err.message) || 'Check your connection and try again.');
            countEl.textContent = '';
            prev.disabled = state.page <= 1;
          }, Math.max(0, readyAt - Date.now()));
        })
        .then(function(){ if (id === reqId) { grid.removeAttribute('aria-busy'); if (window.TopLoader) TopLoader.done(); } });
    }
    seg.addEventListener('click', function(e){
      var b = e.target.closest('button[data-gender]'); if (!b) return;
      var g = b.getAttribute('data-gender'); if (g === state.gender) return;
      state.gender = g; state.page = 1; load(true);
    });
    form.addEventListener('submit', function(e){
      e.preventDefault();
      var q = (input.value || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      if (q === state.q && state.page === 1) return;
      state.q = q; state.page = 1; load(true);
    });
    input.addEventListener('search', function(){ if (!input.value && state.q) { state.q = ''; state.page = 1; load(true); } });
    prev.addEventListener('click', function(){ if (state.page > 1) { state.page--; load(true); window.scrollTo({ top: 0, behavior: 'smooth' }); } });
    next.addEventListener('click', function(){ state.page++; load(true); window.scrollTo({ top: 0, behavior: 'smooth' }); });
    window.addEventListener('popstate', function(e){
      var s = e.state; if (!s) return;
      state.gender = s.gender; state.q = s.q || ''; state.page = s.page || 1; input.value = state.q; load();
    });
    syncUrl(false);
    load();
    return;
  }

  /* ---------------- profile ---------------- */
  var stage = document.getElementById('mStage');
  if (!stage) return;
  var nameEl = document.getElementById('modelName');
  var countryEl = document.getElementById('modelCountry');
  var details = document.getElementById('modelDetails');
  var thumbs = document.getElementById('mThumbs');
  var btnPrev = document.getElementById('mPrev'), btnNext = document.getElementById('mNext'), counter = document.getElementById('mCounter');
  var images = [], cur = -1, current = null;
  var LABELS = { age: 'Age', gender: 'Gender', career: 'Career', country: 'Country', height: 'Height', hair_color: 'Hair Color', eye_color: 'Eye Color', ethnicity: 'Ethnicity', measurements: 'Measurements', breast_type: 'Breast Type', piercings: 'Piercings' };
  function show(i){
    if (!images.length) return;
    i = (i + images.length) % images.length;
    if (i === cur) return;
    cur = i;
    var old = current;
    var img = document.createElement('img');
    img.alt = (nameEl.textContent || '') + ' photo ' + (i + 1);
    stage.insertBefore(img, btnPrev);
    current = img;
    img.addEventListener('load', function(){
      if (old) { old.classList.add('out'); setTimeout(function(){ if (old.parentNode) old.remove(); }, 420); }
    });
    loadImg(img, images[i]);
    counter.textContent = (i + 1) + ' / ' + images.length;
    thumbs.querySelectorAll('button').forEach(function(b, j){
      b.setAttribute('aria-current', j === i ? 'true' : 'false');
      if (j === i && b.scrollIntoView) { try { b.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' }); } catch (e) {} }
    });
  }
  function rowsFor(src, keys){
    return keys.filter(function(k){ return src && src[k]; }).map(function(k){
      var v = noFlag(src[k]);
      if (k === 'age' && src.birth_date) v = esc(v) + '<small>Born ' + esc(noFlag(src.birth_date)) + '</small>';
      else v = esc(v);
      return '<div class="mrow"><dt>' + LABELS[k] + '</dt><dd>' + v + '</dd></div>';
    }).join('');
  }
  function group(title, rows, i){ return rows ? '<section class="mgroup" style="--i:' + i + '"><h2>' + title + '</h2><dl>' + rows + '</dl></section>' : ''; }
  if (window.TopLoader) TopLoader.start();
  fetch('/api/models/' + encodeURIComponent(slug), { headers: { 'X-Edge-Token': TOKEN } })
    .then(function(r){ if (!r.ok) throw new Error(r.status === 404 ? 'This profile doesn\u2019t exist.' : 'The profile answered ' + r.status + '.'); return r.json(); })
    .then(function(m){
      var p = m.personal_details || {}, a = m.physical_attributes || {};
      nameEl.textContent = m.name || 'Performer profile';
      document.title = (m.name || 'Profile') + ' \u2014 OnlyFans Models';
      var flag = m.country_flag || flagOf(p.country);
      countryEl.innerHTML = countryHtml(flag, m.country_name || p.country);
      details.innerHTML =
        group('Personal Details', rowsFor(p, ['age', 'gender', 'career', 'country']), 0) +
        group('Physical Attributes', rowsFor(a, ['height', 'hair_color', 'eye_color', 'ethnicity', 'measurements', 'breast_type', 'piercings']), 1) ||
        statusHtml('No details listed yet.', '');
      images = (Array.isArray(m.images) && m.images.length ? m.images : (m.image_url ? [m.image_url] : [])).filter(Boolean);
      if (images.length > 1) {
        btnPrev.hidden = false; btnNext.hidden = false; counter.hidden = false;
        thumbs.innerHTML = images.map(function(_, i){ return '<button type="button" aria-label="Photo ' + (i + 1) + '"><img alt="" loading="lazy"></button>'; }).join('');
        thumbs.querySelectorAll('button').forEach(function(b, i){
          loadImg(b.querySelector('img'), images[i]);
          b.addEventListener('click', function(){ show(i); });
        });
      }
      show(0);
    })
    .catch(function(err){
      nameEl.textContent = 'Profile unavailable';
      details.innerHTML = statusHtml('Couldn\u2019t load this profile.', (err && err.message) || 'Try again in a moment.');
    })
    .then(function(){ if (window.TopLoader) TopLoader.done(); });
  btnPrev.addEventListener('click', function(){ show(cur - 1); });
  btnNext.addEventListener('click', function(){ show(cur + 1); });
  document.addEventListener('keydown', function(e){
    if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
    if (e.key === 'ArrowLeft') show(cur - 1);
    if (e.key === 'ArrowRight') show(cur + 1);
  });
  var tx = 0;
  stage.addEventListener('touchstart', function(e){ tx = e.touches[0].clientX; }, { passive: true });
  stage.addEventListener('touchend', function(e){ var dx = e.changedTouches[0].clientX - tx; if (Math.abs(dx) > 40) show(cur + (dx < 0 ? 1 : -1)); });
})();
`;
}

// Shared video card renderer (home rails, catalogue grid, watch page)
const CARD_JS = String.raw`
(function(){
  var PLAY = ` + JSON.stringify(ICONS.play) + String.raw`;
  var n = 0;
  window.vxThumbSrc = function(raw){ return '/proxy-image?url=' + encodeURIComponent(String(raw || '').trim()) + '&token=' + encodeURIComponent((window.VX && window.VX.token) || ''); };
  /* Real posters. Search pages hand out a random timeline frame; the watch
     page shows the video's own poster (og:image). A card stays in its loading
     state until that poster has fully loaded, then fades it in, so the random
     frame is never shown. The listing frame is only a last resort when the
     poster can't be found. Found posters are remembered across visits. */
  var POSTER_KEY = 'vx_posters_v3', POSTER_MAX = 600, posterMem = {};
  try { posterMem = JSON.parse(localStorage.getItem(POSTER_KEY) || '{}') || {}; } catch (_) { posterMem = {}; }
  try { sessionStorage.removeItem('vx_posters_v1'); sessionStorage.removeItem('vx_posters_v2'); } catch (_) {}
  var posterQueue = [], posterWait = {}, posterTimer = 0, posterSaveTimer = 0;
  function knownPoster(u){ return Object.prototype.hasOwnProperty.call(posterMem, u) ? String(posterMem[u] || '') : ''; }
  function savePosters(){
    clearTimeout(posterSaveTimer);
    posterSaveTimer = setTimeout(function(){
      try {
        var keys = Object.keys(posterMem);
        if (keys.length > POSTER_MAX) keys.slice(0, keys.length - POSTER_MAX).forEach(function(k){ delete posterMem[k]; });
        localStorage.setItem(POSTER_KEY, JSON.stringify(posterMem));
      } catch (_) {}
    }, 400);
  }
  function flushPosters(){
    posterTimer = 0;
    var batch = posterQueue.splice(0, 24);
    if (!batch.length) return;
    var qs = batch.map(function(u){ return 'u=' + encodeURIComponent(u); }).join('&');
    fetch('/api/posters?' + qs, { headers: { 'X-Edge-Token': (window.VX && window.VX.token) || '' }, cache: 'no-store' })
      .then(function(r){ return r.ok ? r.json() : null; })
      .catch(function(){ return null; })
      .then(function(d){
        var map = (d && d.posters) || {};
        /* "pending" = the API is still resolving it. An older API without the
           field, or a failed request, counts as pending until the deadline. */
        var pending = d && Array.isArray(d.pending) ? d.pending : null;
        batch.forEach(function(u){
          var p = String(map[u] || '').trim();
          var state = p ? 'ready' : (pending && pending.indexOf(u) < 0 ? 'none' : 'pending');
          if (p) posterMem[u] = p;
          var cbs = posterWait[u] || []; delete posterWait[u];
          cbs.forEach(function(cb){ try { cb(p, state); } catch (_) {} });
        });
        savePosters();
        if (posterQueue.length) posterTimer = setTimeout(flushPosters, 60);
      });
  }
  window.vxPosterFor = function(pageUrl, cb){
    if (!pageUrl) return cb('', 'none');
    var known = knownPoster(pageUrl);
    if (known) return cb(known, 'ready');
    if (posterWait[pageUrl]) { posterWait[pageUrl].push(cb); return; }
    posterWait[pageUrl] = [cb]; posterQueue.push(pageUrl);
    if (!posterTimer) posterTimer = setTimeout(flushPosters, 80);
  };
  var POSTER_DEADLINE = 9000, POSTER_POLL = [300, 400, 500, 600, 800, 1000, 1200];
  var thumbIO = 'IntersectionObserver' in window ? new IntersectionObserver(function(entries){
    entries.forEach(function(e){ if (!e.isIntersecting) return; thumbIO.unobserve(e.target); if (e.target.__vxStart) e.target.__vxStart(); });
  }, { rootMargin: '400px 0px' }) : null;
  /* Drives the one <img> inside a card's .vthumb.
     opts.trusted: item.thumbnail already is the real poster (watch history).
     opts.onFail:  nothing could be shown. */
  window.vxThumb = function(card, item, opts){
    opts = opts || {};
    var wrap = card.querySelector('.vthumb'), img = wrap && wrap.querySelector('img');
    if (!wrap || !img || !item) return;
    var listing = String(item.thumbnail || '').trim();
    var decided = false, started = 0, poll = 0, hard = 0, tries = 0;
    card.classList.add('is-loading');
    wrap.setAttribute('aria-busy', 'true');
    function stopTimers(){ clearTimeout(poll); clearTimeout(hard); }
    function finish(kind){
      card.classList.remove('is-loading'); card.classList.add(kind);
      wrap.removeAttribute('aria-busy');
    }
    function load(src, kind, onError){
      img.onload = function(){
        img.onload = img.onerror = null;
        var show = function(){ img.classList.add('ok'); finish(kind); };
        if (img.decode) img.decode().then(show, show); else show();
      };
      img.onerror = function(){ img.onload = img.onerror = null; onError(); };
      img.src = vxThumbSrc(src);
    }
    function failed(){ finish('thumb-failed'); if (opts.onFail) opts.onFail(); }
    function useListing(){
      if (decided) return; decided = true; stopTimers();
      if (listing) load(listing, 'thumb-listing', failed); else failed();
    }
    function useReal(p){
      if (decided) return; decided = true; stopTimers();
      load(p, 'thumb-real', function(){
        if (posterMem[item.url] === p) { delete posterMem[item.url]; savePosters(); }
        decided = false;
        if (p !== listing) useListing(); else failed();
      });
    }
    function ask(){
      vxPosterFor(item.url, function(p, state){
        if (decided) return;
        if (p) return useReal(p);
        var left = POSTER_DEADLINE - (Date.now() - started);
        if (state === 'none' || left <= 0) return useListing();
        poll = setTimeout(ask, Math.min(left, POSTER_POLL[Math.min(tries++, POSTER_POLL.length - 1)]));
      });
    }
    card.__vxStart = function(){
      if (started) return; started = Date.now();
      if (thumbIO) thumbIO.unobserve(card);
      if (opts.trusted && listing) {
        decided = true;
        load(listing, 'thumb-real', function(){ decided = false; started = Date.now(); hard = setTimeout(useListing, POSTER_DEADLINE + 800); ask(); });
        return;
      }
      if (!item.url) return useListing();
      hard = setTimeout(useListing, POSTER_DEADLINE + 800);
      ask();
    };
    if (thumbIO && !opts.now && !knownPoster(item.url)) thumbIO.observe(card); else card.__vxStart();
  };
  window.vxSkeletons = function(count){
    var html = '';
    for (var i = 0; i < count; i++) html += '<div class="vcard skeleton" aria-hidden="true"><div class="vthumb"></div><div><div class="sk-line" style="width:92%"></div><div class="sk-line" style="width:58%;margin-top:10px"></div></div></div>';
    return html;
  };
  window.vxCard = function(item, opts){
    opts = opts || {};
    var a = document.createElement('a');
    a.className = 'vcard';
    a.style.setProperty('--i', String(Math.min(24, n++ % 24)));
    a.href = '/video/' + b64url(item.url);
    var dur = vxDur(item.duration);
    var h = window.VXHistory ? VXHistory.get(item.url) : null;
    var pct = h && h.p && h.d ? Math.max(3, Math.min(100, h.p / h.d * 100)) : 0;
    a.innerHTML = '<div class="vthumb"><img loading="lazy" decoding="async" alt="">' +
      (dur ? '<span class="vdur">' + escapeHtml(dur) + '</span>' : '') +
      '<span class="vplay">' + PLAY + '</span>' +
      (pct ? '<span class="vwatched"><i style="width:' + pct.toFixed(1) + '%"></i></span>' : '') + '</div>' +
      '<div><h3 class="vtitle">' + escapeHtml(item.title || 'Untitled video') + '</h3><div class="vmeta"><span class="prov">' + escapeHtml(item.provider || '') + '</span>' +
      (opts.note ? '<i></i><span>' + escapeHtml(opts.note) + '</span>' : '') + '</div></div>';
    function gone(){ if (a.__gone) return; a.__gone = true; a.classList.add('gone'); setTimeout(function(){ a.remove(); if (opts.onGone) opts.onGone(); }, 230); }
    vxThumb(a, item, { trusted: !!opts.keepOnError, onFail: function(){ if (!opts.keepOnError) gone(); } });
    a.addEventListener('click', function(){ if (window.TopLoader) TopLoader.start(); });
    return a;
  };
  window.vxUsable = function(list){
    return Array.isArray(list) ? list.filter(function(it){ var t = String((it && it.thumbnail) || '').trim(); return it && it.url && t.length >= 8 && t.indexOf('blank.gif') < 0; }) : [];
  };
  window.vxProviderOf = function(u){
    var m = String(u || '').toLowerCase().match(/(pornhub|xvideos|xnxx|redtube|youporn)/);
    return m ? m[1] : '';
  };
  function railNav(){
    document.querySelectorAll('[data-rail]').forEach(function(nav){
      var rail = document.getElementById(nav.getAttribute('data-rail')); if (!rail) return;
      var btns = nav.querySelectorAll('button');
      var sync = function(){ btns[0].disabled = rail.scrollLeft < 8; btns[1].disabled = rail.scrollLeft + rail.clientWidth >= rail.scrollWidth - 8; };
      btns.forEach(function(b){ b.addEventListener('click', function(){ rail.scrollBy({ left: (+b.dataset.dir) * rail.clientWidth * 0.9, behavior: 'smooth' }); }); });
      rail.addEventListener('scroll', sync, { passive: true });
      window.addEventListener('resize', sync);
      rail.__sync = sync; sync();
    });
  }
  window.vxRailSync = function(){ document.querySelectorAll('.rail').forEach(function(r){ if (r.__sync) r.__sync(); }); };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', railNav); else railNav();
})();
`;

// Home page: paste a link, continue watching, trending rail
const HOME_JS = String.raw`
(function(){
  var target = document.getElementById('targetUrl');
  var hint = document.getElementById('pasteHint');
  var HINT_DEFAULT = hint ? hint.textContent : '';
  function setHint(msg, isErr){ if (!hint) return; hint.textContent = msg; hint.classList.toggle('err', !!isErr); }
  function play(){
    var val = (target.value || '').trim();
    if (!val) { setHint('Paste a link or a viewkey first.', true); target.focus(); return; }
    var finalUrl = val;
    if (!/^https?:\/\//i.test(val)) {
      var m = val.match(/viewkey=([a-zA-Z0-9]+)/) || val.match(/^([a-zA-Z0-9]{8,24})$/);
      if (!m) { setHint('That doesn\u2019t look like a link or a viewkey.', true); return; }
      finalUrl = 'https://www.pornhub.com/view_video.php?viewkey=' + encodeURIComponent(m[1]);
    }
    var dest = '/video/' + b64url(finalUrl);
    if (window.vxNeedsLogin && window.vxNeedsLogin(dest)) return;
    setHint('Opening the player\u2026', false);
    if (window.TopLoader) TopLoader.start();
    location.href = dest;
  }
  var eb = document.getElementById('extractBtn');
  if (eb) eb.addEventListener('click', play);
  if (target) {
    target.addEventListener('keydown', function(e){ if (e.key === 'Enter') { e.preventDefault(); play(); } });
    target.addEventListener('input', function(){ if (hint && hint.classList.contains('err')) setHint(HINT_DEFAULT, false); });
    target.addEventListener('paste', function(){ setTimeout(function(){ if (/^https?:\/\/\S+$/i.test((target.value || '').trim())) play(); }, 30); });
  }

  /* hero timecode: hours:minutes:seconds:frames since the page opened (25 fps) */
  var tc = document.getElementById('heroTc');
  if (tc) {
    var t0 = Date.now(), p2 = function(x){ return (x < 10 ? '0' : '') + x; }, still = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches, last = '';
    var draw = function(){
      var ms = Date.now() - t0, s = Math.floor(ms / 1000), f = still ? 0 : Math.floor((ms % 1000) / 40);
      var txt = p2(Math.floor(s / 3600)) + ':' + p2(Math.floor(s / 60) % 60) + ':' + p2(s % 60) + ':' + p2(f);
      if (txt !== last) { tc.textContent = txt; last = txt; }
      if (still) setTimeout(draw, 1000); else requestAnimationFrame(draw);
    };
    draw();
  }

  /* continue watching */
  var cwSec = document.getElementById('continueSec'), cwRail = document.getElementById('continueRail');
  function renderContinue(){
    if (!cwSec || !cwRail || !window.VXHistory) return;
    var list = VXHistory.list().filter(function(h){ return h.u && h.p > 5 && (!h.d || h.p < h.d - 8); }).slice(0, 16);
    cwRail.innerHTML = '';
    if (!list.length) { cwSec.hidden = true; return; }
    list.forEach(function(h){
      var left = h.d ? Math.max(0, Math.round((h.d - h.p) / 60)) : 0;
      cwRail.appendChild(vxCard({ url: h.u, title: h.t, thumbnail: h.th, duration: h.d, provider: h.pv || vxProviderOf(h.u) }, { keepOnError: true, note: left ? left + ' min left' : 'Resume' }));
    });
    cwSec.hidden = false;
    vxRailSync();
  }
  renderContinue();
  var clr = document.getElementById('cwClear');
  if (clr) clr.addEventListener('click', function(){ try { localStorage.removeItem('vx_history_v1'); } catch (e) {} renderContinue(); toast('History cleared'); });

  /* trending rail */
  var tr = window.VX && window.VX.trend, rail = document.getElementById('trendRail'), sec = document.getElementById('trendSec');
  if (tr && rail) {
    rail.innerHTML = vxSkeletons(6);
    fetch('/api/explore?q=' + encodeURIComponent(tr.q) + '&page=1&provider=' + encodeURIComponent(tr.provider), { headers: { 'X-Edge-Token': window.VX.token } })
      .then(function(r){ if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(function(list){
        var items = vxUsable(list).slice(0, 16);
        if (!items.length) { sec.hidden = true; return; }
        rail.innerHTML = '';
        items.forEach(function(it){ rail.appendChild(vxCard(it)); });
        vxRailSync();
      })
      .catch(function(){ if (sec) sec.hidden = true; });
  }
})();
`;

// Browse + search pages: fetch one page of results into the grid
const CATALOG_JS = String.raw`
(function(){
  var cfg = (window.VX && window.VX.catalog) || {};
  var grid = document.getElementById('exploreGrid');
  var nextBtn = document.getElementById('nextPageBtn');
  var seg = document.getElementById('providerSeg');
  if (seg) { var cur = seg.querySelector('[aria-current="page"]'); if (cur && seg.scrollWidth > seg.clientWidth) seg.scrollLeft = Math.max(0, cur.offsetLeft - (seg.clientWidth - cur.offsetWidth) / 2); }
  document.querySelectorAll('.segmented a, .pager a').forEach(function(a){ a.addEventListener('click', function(){ if (window.TopLoader) TopLoader.start(); }); });
  if (!grid || !cfg.active) return;
  function message(title, sub){ grid.innerHTML = '<div class="empty"><b>' + escapeHtml(title) + '</b>' + escapeHtml(sub || '') + '</div>'; }
  function enableNext(on){
    if (!nextBtn) return;
    nextBtn.classList.toggle('is-off', !on);
    if (on) { nextBtn.removeAttribute('aria-disabled'); nextBtn.removeAttribute('tabindex'); }
    else { nextBtn.setAttribute('aria-disabled', 'true'); nextBtn.setAttribute('tabindex', '-1'); }
  }
  if (!cfg.provider) { message('The catalogue is paused.', 'Paste a link on the home page to watch something.'); return; }
  grid.innerHTML = vxSkeletons(12);
  grid.setAttribute('aria-busy', 'true');
  if (window.TopLoader) TopLoader.start();
  fetch('/api/explore?q=' + encodeURIComponent(cfg.q || 'trending') + '&page=' + (cfg.page || 1) + '&provider=' + encodeURIComponent(cfg.provider), { headers: { 'X-Edge-Token': window.VX.token } })
    .then(function(res){
      if (res.status === 423) return res.json().catch(function(){ return {}; }).then(function(d){ var e = new Error((d && d.error) || window.VX.lockMessage || 'This provider is currently unavailable.'); e.locked = true; throw e; });
      if (!res.ok) throw new Error('The server answered ' + res.status + '.');
      return res.json();
    })
    .then(function(list){
      grid.innerHTML = '';
      var items = vxUsable(list);
      if (!items.length) { message('No videos on page ' + (cfg.page || 1) + '.', 'Try another search or provider.'); enableNext(false); return; }
      var frag = document.createDocumentFragment();
      var gone = function(){ if (!grid.querySelector('.vcard')) message('Nothing to show here.', 'Try another search or provider.'); };
      items.forEach(function(it){ if (!it.provider) it.provider = cfg.provider; frag.appendChild(vxCard(it, { onGone: gone })); });
      grid.appendChild(frag);
      enableNext(true);
    })
    .catch(function(err){
      if (err && err.locked) message('Currently unavailable.', err.message);
      else message('Couldn\u2019t load the catalogue.', (err && err.message) || 'Check your connection and try again.');
      enableNext(false);
    })
    .then(function(){ grid.removeAttribute('aria-busy'); if (window.TopLoader) TopLoader.done(); });
})();
`;

// ============================================================================
// EDGE GLOBE (home tile)
// Land mask: Natural Earth 1:50m countries sampled on a 1.5 degree
// equal-area grid (rows from 89.25N to 59.25S), packed 1 bit per cell.
