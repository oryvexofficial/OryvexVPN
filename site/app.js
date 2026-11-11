// OryvexVPN site: the app shell (theme, number-key navigation, tab bar sheet), copy buttons,
// the docs contents bar, the screenshot viewer, the Tor exit picker, and the Connect demo.
// No network requests: the site works fully offline, and the demo connects nothing.
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var page = document.body.getAttribute('data-page');
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Old one-page links (index.html#download) still land on the right page.
  var legacy = { about: 'about', how: 'guide', gui: 'app', docs: 'docs', creator: 'creator', download: 'download', tor: 'tor' };
  if (page === 'home' && location.hash && legacy[location.hash.slice(1)]) {
    location.replace(legacy[location.hash.slice(1)]);
    return;
  }
  // Someone opened /download.html directly: show /download instead (GitHub Pages serves both).
  if (/^https?:$/.test(location.protocol) && /\.html$/.test(location.pathname) && page !== '404' && history.replaceState) {
    history.replaceState(null, '', location.pathname.replace(/(index)?\.html$/, '') + location.search + location.hash);
  }

  var store = {
    get: function (k, s) { try { return (s || localStorage).getItem(k); } catch (e) { return null; } },
    set: function (k, v, s) { try { (s || localStorage).setItem(k, v); } catch (e) {} },
    del: function (k, s) { try { (s || localStorage).removeItem(k); } catch (e) {} }
  };
  var session = (function () { try { return sessionStorage; } catch (e) { return null; } })();

  // ------------------------------------------------------------ appearance: ink or paper
  var root = document.documentElement;
  $$('.theme-btn').forEach(function (b) {
    b.addEventListener('click', function () {
      var light = root.getAttribute('data-theme') !== 'light';
      var apply = function () {
        if (light) root.setAttribute('data-theme', 'light'); else root.removeAttribute('data-theme');
      };
      if (document.startViewTransition && !reduce) document.startViewTransition(apply); else apply();
      store.set('ox-theme', light ? 'light' : 'dark');
    });
  });

  // ------------------------------------------------------------ number keys jump between pages, like Ctrl+1..3 in the app
  var navLinks = $$('.side .nav a');
  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
    var t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    var n = parseInt(e.key, 10);
    if (n >= 1 && n <= navLinks.length && navLinks[n - 1].getAttribute('aria-current') !== 'page') {
      location.href = navLinks[n - 1].href;
    }
  });

  // ------------------------------------------------------------ "More" sheet on phones
  var sheet = $('#sheet'), more = $('#more');
  if (sheet && more) {
    var setSheet = function (open) {
      sheet.classList.toggle('open', open);
      more.setAttribute('aria-expanded', String(open));
      if (open) $('.sheet-in', sheet).focus({ preventScroll: true }); else more.focus({ preventScroll: true });
    };
    more.addEventListener('click', function () { setSheet(!sheet.classList.contains('open')); });
    sheet.addEventListener('click', function (e) { if (e.target === sheet) setSheet(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && sheet.classList.contains('open')) setSheet(false); });
  }

  // ------------------------------------------------------------ copy buttons: on every <pre> and on any [data-copy]
  var ICON_COPY = '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
  var ICON_OK = '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg>';
  function fallbackCopy(text) {
    var t = document.createElement('textarea');
    t.value = text; t.setAttribute('readonly', ''); t.style.position = 'fixed'; t.style.opacity = '0';
    document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(t);
  }
  function copyText(text, el) {
    var done = function () {
      el.innerHTML = ICON_OK + '<span>Copied</span>';
      setTimeout(function () { el.innerHTML = ICON_COPY + '<span>Copy</span>'; }, 1600);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text); done(); });
    } else { fallbackCopy(text); done(); }
  }
  $$('pre').forEach(function (pre) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'copy'; b.innerHTML = ICON_COPY + '<span>Copy</span>';
    b.setAttribute('aria-label', 'Copy code');
    b.addEventListener('click', function () {
      var code = pre.querySelector('code') || pre;
      var text = code.innerText.split('\n').map(function (l) { return l.replace(/\s+#.*$/, ''); }).join('\n').trim();
      copyText(text, b);
    });
    pre.appendChild(b);
  });
  $$('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () { copyText(b.getAttribute('data-copy'), b); });
  });

  // ------------------------------------------------------------ docs: highlight the section in view
  var tocBar = $('.toc'), toc = $$('.toc a');
  if (toc.length && 'IntersectionObserver' in window) {
    var map = {};
    toc.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        var a = map[en.target.id];
        if (en.isIntersecting && a) {
          toc.forEach(function (x) { x.classList.remove('on'); });
          a.classList.add('on');
          if (tocBar.scrollWidth > tocBar.clientWidth) tocBar.scrollTo({ left: a.offsetLeft - 24, behavior: reduce ? 'auto' : 'smooth' });
        }
      });
    }, { rootMargin: '-25% 0px -65% 0px' });
    $$('.doc-sec[id]').forEach(function (s) { io.observe(s); });
  }

  // ------------------------------------------------------------ app page: the screenshot viewer
  var shots = $('#shots');
  if (shots) {
    var frame = $('#shot', shots), cap = $('#shot-cap', shots);
    $$('[data-shot]', shots).forEach(function (b) {
      if (b.tagName !== 'BUTTON') return;
      b.addEventListener('click', function () {
        var k = b.getAttribute('data-shot');
        var tpl = $('template[data-shot="' + k + '"]', shots);
        if (!tpl) return;
        $$('button[data-shot]', shots).forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
        frame.innerHTML = '';
        frame.appendChild(document.importNode(tpl.content, true));
        frame.classList.toggle('phone', k === 'phone');
        cap.innerHTML = tpl.getAttribute('data-cap');
      });
    });
  }

  // ------------------------------------------------------------ tor page: the exit picker from the app
  var picker = $('#exit-picker');
  if (picker) {
    var hints = {
      auto: 'Let Tor choose an exit, weighted by bandwidth, as Tor Browser does.',
      fastest: 'Measure exits in the best-served countries each time you connect, then use the quickest.',
      country: 'Choose the exit country. Tor identifies each relay using its built-in GeoIP data.'
    };
    var mode = 'country', pick = 'de', strict = false, all = false;
    var hint = $('#exit-hint'), cmd = $('#exit-cmd'), box = $('#exit-country'), sw = $('#strict'), allBtn = $('#flags-all');
    var flags = $$('.flag', picker);
    var draw = function () {
      $$('.seg button', picker).forEach(function (s) { s.setAttribute('aria-pressed', String(s.getAttribute('data-m') === mode)); });
      hint.textContent = hints[mode];
      box.hidden = mode !== 'country';
      flags.forEach(function (f) {
        var c = f.getAttribute('data-c');
        f.setAttribute('aria-pressed', String(c === pick));
        f.hidden = !all && f.hasAttribute('data-extra') && c !== pick;
      });
      allBtn.firstChild.nodeValue = all ? 'Show fewer ' : 'Show all ' + flags.length + ' countries ';
      var useStrict = strict && mode === 'country';
      sw.setAttribute('aria-checked', String(useStrict));
      sw.disabled = mode !== 'country';
      sw.style.opacity = mode === 'country' ? '' : '.4';
      cmd.textContent = 'oryvexcore --tor-only --tor-exit ' + (mode === 'country' ? pick : mode) + (useStrict ? ' --tor-exit-strict' : '');
    };
    $$('.seg button', picker).forEach(function (s) { s.addEventListener('click', function () { mode = s.getAttribute('data-m'); draw(); }); });
    flags.forEach(function (f) { f.addEventListener('click', function () { pick = f.getAttribute('data-c'); draw(); }); });
    allBtn.addEventListener('click', function () { all = !all; draw(); });
    sw.addEventListener('click', function () { strict = !strict; draw(); });
    draw();
  }

  // ------------------------------------------------------------ the sidebar status card
  var KEY = 'ox-demo';
  var pad = function (n) { return (n < 10 ? '0' : '') + n; };
  var clock = function (ms) { var s = Math.max(0, Math.floor(ms / 1000)); return pad(Math.floor(s / 3600)) + ':' + pad(Math.floor(s / 60) % 60) + ':' + pad(s % 60); };
  var NAMES = { auto: 'Auto', wg: 'WireGuard', masque: 'MASQUE', mim: 'MASQUE\u00b2', gool: 'Gool', tor: 'Tor', bypass: 'Bypass' };
  var saved = function () { try { return JSON.parse(store.get(KEY, session) || 'null'); } catch (e) { return null; } };
  var sidePill = $('#side-pill'), sideLine = $('#side-line'), sideBtn = $('#side-btn');
  var side = function (s, line, btn) {
    if (!sidePill) return;
    sidePill.setAttribute('data-s', s);
    sidePill.textContent = { off: 'Off', busy: 'Connecting', on: 'Connected', stop: 'Stopping' }[s];
    sideLine.textContent = line;
    sideBtn.textContent = btn;
    sideBtn.classList.toggle('quiet', s !== 'off' || page !== 'home');
  };

  if (page !== 'home' && sidePill) {
    var tick = null;
    var showSaved = function () {
      var d = saved();
      clearInterval(tick);
      if (!d) { side('off', 'Auto \u00b7 live demo', 'Try the demo'); return; }
      var upd = function () { side('on', clock(Date.now() - d.since) + ' \u00b7 ' + NAMES[d.proto === 'auto' ? 'wg' : d.proto], 'Disconnect'); };
      upd(); tick = setInterval(upd, 1000);
    };
    sideBtn.addEventListener('click', function (e) {
      if (saved()) { e.preventDefault(); store.del(KEY, session); showSaved(); }
    });
    showSaved();
  }

  // ------------------------------------------------------------ home: the Connect page, as a demo
  var panel = $('#panel');
  if (panel) {
    var el = {
      pill: $('#p-pill'), chip: $('#p-chip'), eyebrow: $('#p-eyebrow'), head: $('#p-head'), sub: $('#p-sub'),
      orb: $('#orb'), cta: $('#cta'), note: $('#p-note'), prog: $('.prog', panel),
      steps: $('#steps'), list: $('#step-list'), pct: $('#pct'), dirty: $('#dirty'),
      down: $('#s-down'), downT: $('#s-down-t'), up: $('#s-up'), upT: $('#s-up-t'),
      time: $('#s-time'), timeS: $('#s-time-s'), gw: $('#s-gw'), gwS: $('#s-gw-s'),
      log: $('#log'), routeHint: $('#route-hint'), carrierBox: $('#carrier-box'), cmd: $('#route-cmd')
    };
    var HINTS = {
      auto: 'Try WireGuard, MASQUE, MASQUE\u00b2, and Gool in order. Keep the first route that connects.',
      wg: 'Use WireGuard for speed when UDP traffic is allowed.',
      masque: 'Use an HTTP/3 or HTTP/2 tunnel that blends in with regular HTTPS traffic.',
      mim: 'Carry MASQUE inside MASQUE to use a different exit address.',
      gool: 'Carry WireGuard inside MASQUE to use a different exit address.',
      bypass: 'Go out directly and reshape the first packets of each connection so filters cannot read the site name. Your address does not change.',
      tor: 'Connect directly to Tor, using bridges when needed. Pick an exit country on the Tor page.'
    };
    var GW = { auto: '162.159.192.7:2408', wg: '162.159.192.7:2408', masque: '162.159.198.1:443', mim: '162.159.198.2:443', gool: '162.159.198.1:443', tor: '3 hops \u00b7 auto exit', bypass: 'Direct \u00b7 no tunnel' };
    var carried = function (p) { return p === 'masque' || p === 'mim' || p === 'gool'; };
    var want = { proto: 'auto', carrier: 'h2' }, live = null;
    var state = 'off', timers = [], since = 0, loop = null;
    var hist = { down: [], up: [] }, tot = { down: 0, up: 0 }, rate = { down: 0, up: 0 }, ticks = 0;

    var later = function (ms, f) { timers.push(setTimeout(f, reduce ? Math.min(ms, 120) : ms)); };
    var clearTimers = function () { timers.forEach(clearTimeout); timers = []; };

    // ---- the log
    var now = function () { var d = new Date(); return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()); };
    var esc = function (s) { return s.replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); };
    var first = true;
    var log = function (kind, text) {
      if (first) { el.log.innerHTML = ''; first = false; }
      var warn = kind === '!';
      var cls = kind === '+' ? 'ok' : warn ? 'warn' : kind === '=' ? 'dim' : '';
      var row = document.createElement('div');
      if (warn) row.className = 'w';
      row.innerHTML = '<span class="t">' + now() + '</span><span class="l' + (warn ? ' warn' : '') + '">' + (warn ? 'WARN' : 'INFO') + '</span><span class="' + cls + '">[' + kind + '] ' + esc(text) + '</span>';
      el.log.appendChild(row);
      while (el.log.children.length > 200) el.log.removeChild(el.log.firstChild);
      el.log.scrollTop = el.log.scrollHeight;
      emptyCheck();
    };
    var logFilter = 'core';
    var empty = document.createElement('div');
    empty.className = 'w'; empty.innerHTML = '<span class="dim">No problems so far.</span>';
    var emptyCheck = function () {
      var has = $$('.w', el.log).some(function (r) { return r !== empty; });
      if (logFilter === 'problems' && !has) { if (!empty.parentNode) el.log.appendChild(empty); }
      else if (empty.parentNode) empty.parentNode.removeChild(empty);
    };
    $$('#log-tabs button').forEach(function (b) {
      b.addEventListener('click', function () {
        logFilter = b.getAttribute('data-f');
        $$('#log-tabs button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
        el.log.classList.toggle('problems', logFilter === 'problems');
        emptyCheck();
      });
    });

    // ---- the plan for a route: stages, what each says, what the core logs
    var plan = function (p, c) {
      var h = c === 'h3' ? 'HTTP/3' : 'HTTP/2', gw = GW[p];
      var ident = { t: 'Set up identity', idle: 'Saved identity', done: 'Saved identity', logs: [['*', 'loaded existing WARP identity']] };
      var proxy = { t: 'Proxy ready', idle: 'SOCKS5 on port 1819', done: 'SOCKS5 on port 1819', logs: [['+', 'socks5 server listening on 127.0.0.1:1819']] };
      if (p === 'tor') return [
        { t: 'Start Tor', idle: 'Bootstrapping\u2026', done: 'Bootstrapped 100%', logs: [['*', 'starting Arti (tor-only)'], ['*', 'bootstrap 40%: loading directory'], ['+', 'bootstrap 100%: done']] },
        { t: 'Pick an exit', idle: 'Auto', done: 'Tor\u2019s own pick', logs: [['*', 'tor exit: auto, weighted by bandwidth']] },
        { t: 'Verify the route', idle: 'Checking HTTPS\u2026', done: 'HTTPS 200 \u00b7 640 ms', logs: [['+', 'route validated in 640 ms']] },
        proxy];
      if (p === 'bypass') return [
        { t: 'Start the bypass engine', idle: 'Launching\u2026', done: 'Engine running', logs: [['*', 'starting the bypass engine from oryvex-bypass']] },
        { t: 'Choose a technique', idle: 'Trying per site\u2026', done: 'fake(ttl=4), split(sni)', logs: [['*', 'resolving names with the engine\u2019s own DoH resolver'], ['+', 'strategy kept: fake(ttl=4), split(sni)']] },
        { t: 'Proxy ready', idle: 'SOCKS5 on port 1819', done: 'SOCKS5 on port 1819', logs: [['+', 'bypass is ready; 127.0.0.1:1819 reaches the internet directly']] }];
      var scan = { t: 'Find an endpoint', idle: 'Scanning\u2026', logs: [] };
      if (p === 'auto' || p === 'wg') {
        scan.done = '162.159.192.7 \u00b7 48 ms';
        scan.logs = [['*', 'hunting for a WireGuard endpoint (balanced scan)'], ['+', 'candidate ok 162.159.192.7:2408 rtt=48ms'], ['+', 'candidate ok 162.159.195.12:500 rtt=63ms'], ['*', 'selected WireGuard endpoint 162.159.192.7:2408']];
        return [ident, scan, { t: 'Verify the tunnel', idle: 'Checking handshake\u2026', done: 'HTTPS 200 \u00b7 412 ms', logs: [['*', 'validating wireguard handshake and data path'], ['+', 'tunnel validated in 412 ms']] }, proxy];
      }
      scan.done = gw.replace(/:\d+$/, '') + ' \u00b7 37 ms';
      scan.logs = [['*', 'hunting for a MASQUE endpoint (balanced scan)'], ['+', 'candidate ok ' + gw + ' rtt=37ms'], ['*', 'selected MASQUE endpoint ' + gw]];
      var outer = { t: p === 'masque' ? 'Open the tunnel' : p === 'mim' ? 'Open the outer tunnel' : 'Open MASQUE', idle: 'MASQUE over ' + h, done: h + ' \u00b7 380 ms', logs: [['*', 'opening MASQUE over ' + c + ' (firewall profile)'], ['+', 'CONNECT-UDP accepted, tunnel up in 380 ms']] };
      if (p === 'masque') return [ident, scan, outer, proxy];
      var inner = p === 'mim'
        ? { t: 'Open the inner tunnel', idle: 'MASQUE inside MASQUE', done: 'Inner MASQUE up', logs: [['*', 'dialling inner MASQUE through the outer tunnel'], ['+', 'inner tunnel up, new exit address']] }
        : { t: 'WireGuard inside', idle: 'Handshake inside MASQUE', done: 'WireGuard up', logs: [['*', 'wireguard handshake inside MASQUE'], ['+', 'inner WireGuard up, new exit address']] };
      return [ident, scan, outer, inner, proxy];
    };
    var routeText = function (p, c) {
      var h = c === 'h3' ? 'HTTP/3' : 'HTTP/2';
      if (p === 'auto') return 'Auto \u00b7 WireGuard (1 of 4)';
      if (p === 'tor') return 'Tor \u00b7 auto exit';
      if (p === 'bypass') return 'Bypass \u00b7 direct, packets reshaped';
      return NAMES[p] + (carried(p) ? ' over ' + h : '');
    };
    var restText = function (p, c) {
      if (p === 'auto') return panel.clientWidth < 480 ? 'Auto: four routes, in order' : 'Auto: WireGuard \u203a MASQUE \u203a MASQUE\u00b2 \u203a Gool';
      if (p === 'tor') return 'Tor \u00b7 auto exit \u00b7 bridges when needed';
      if (p === 'bypass') return 'Bypass \u00b7 direct, packets reshaped';
      return routeText(p, c) + '  \u00b7  Balanced scan';
    };

    // ---- the panel text, with the app's blur-swap
    var put = function (node, text) {
      if (node.textContent === text) return;
      node.textContent = text;
      if (!reduce) { node.classList.remove('swap'); void node.offsetWidth; node.classList.add('swap'); }
    };
    var steps = [], cur = -1;
    var drawSteps = function () {
      el.list.innerHTML = steps.map(function (s, i) {
        var cls = i < cur ? 'done' : i === cur ? 'now' : '';
        var d = i < cur ? s.done : s.idle;
        return '<li class="' + cls + '"><span class="dot"><svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg></span><span class="s-t">' + s.t + '</span><span class="s-d">' + d + '</span></li>';
      }).join('');
      var p = steps.length ? Math.round(((cur < 0 ? 0 : cur) + (state === 'on' ? 0 : 0.5)) / steps.length * 100) : 0;
      if (state === 'on') p = 100;
      el.pct.textContent = p + '%';
      el.prog.style.strokeDasharray = (state === 'busy' ? Math.max(4, p) : 0) + ' 100';
    };
    var draw = function () {
      var p = (live || want).proto, c = (live || want).carrier;
      panel.setAttribute('data-state', state === 'stop' ? 'off' : state);
      el.pill.setAttribute('data-s', state);
      el.pill.textContent = { off: 'Off', busy: 'Connecting', on: 'Connected', stop: 'Stopping' }[state];
      var head = { off: 'A way out.', busy: 'Finding a Route.', on: 'Connected.', stop: 'Disconnecting.' }[state];
      var eyebrow = { off: 'Private by Design', busy: steps[cur] ? steps[cur].t : 'Getting Ready', on: 'Tunnel connected', stop: 'Closing the tunnel' }[state];
      var sub = state === 'off' ? restText(want.proto, want.carrier)
        : state === 'on' ? (panel.clientWidth > 520 && p !== 'tor' ? 'Via ' + GW[p] + '  \u00b7  ' : '') + routeText(p, c)
        : state === 'stop' ? 'Disconnecting securely\u2026' : routeText(p, c);
      put(el.eyebrow, eyebrow); put(el.head, head); put(el.sub, sub);
      var label = { off: 'Connect', busy: 'Cancel connection', on: 'Disconnect', stop: 'Disconnecting' }[state];
      el.cta.textContent = label;
      el.cta.classList.toggle('quiet', state !== 'off');
      el.cta.disabled = state === 'stop';
      el.orb.setAttribute('aria-label', label + ' (demo)');
      el.note.innerHTML = state === 'on'
        ? 'Demo connected. The real one is a download away. <a href="download">Get the app</a>'
        : 'Live demo: it runs in this page and connects nothing. <a href="download">Get the real app</a>';
      el.steps.hidden = state !== 'busy';
      $('.bento').classList.toggle('idle', state !== 'on');
      drawSteps();
      side(state, state === 'off' ? NAMES[want.proto] + ' \u00b7 live demo' : (state === 'on' ? clock(Date.now() - since) + ' \u00b7 ' + NAMES[p === 'auto' ? 'wg' : p] : routeText(p, c)), label);
    };

    // ---- the chosen route, the chip and the command line
    var drawRoute = function () {
      var p = want.proto, c = want.carrier;
      $$('#routes .choice').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-p') === p)); });
      $$('#carrier button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-c') === c)); });
      el.carrierBox.hidden = !carried(p);
      el.routeHint.textContent = HINTS[p];
      var shown = live ? live.proto : p;
      el.chip.innerHTML = '<img class="proto" src="assets/protocols/' + shown + '.svg" alt="" width="20" height="20"><span>' + NAMES[shown] + '</span>';
      el.cmd.textContent = p === 'tor' ? 'oryvexcore --tor-only --tor-exit auto' : p === 'bypass' ? 'oryvexcore --bypass' : 'oryvexcore --protocol ' + p + ' --scan balanced' + (carried(p) ? (c === 'h3' ? ' --h3' : ' --h2') : '');
      el.dirty.hidden = !(live && (live.proto !== p || live.carrier !== c) && state !== 'off');
      if (state === 'off') draw();
    };

    // ---- the numbers
    var fmtRate = function (b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + ' MB/s' : Math.round(b / 1e3) + ' KB/s'; };
    var fmtTot = function (b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + ' MiB total' : Math.round(b / 1024) + ' KiB total'; };
    var spark = function (id, arr) {
      var line = $('#' + id + '-l'), area = $('#' + id + '-a');
      if (!line) return;
      var max = Math.max.apply(null, arr.concat([1]));
      var pts = arr.map(function (v, i) { return (i * 120 / 23).toFixed(1) + ' ' + (28 - v / max * 24).toFixed(1); });
      while (pts.length < 2) pts.unshift('0 28');
      var d = 'M' + pts.join('L');
      line.setAttribute('d', d);
      area.setAttribute('d', d + 'L120 30L0 30Z');
    };
    var zero = function () {
      hist = { down: [], up: [] }; tot = { down: 0, up: 0 }; rate = { down: 0, up: 0 };
      el.down.textContent = '0 B/s'; el.up.textContent = '0 B/s';
      el.downT.textContent = '0 B total'; el.upT.textContent = '0 B total';
      el.time.textContent = '00:00:00'; el.timeS.textContent = 'Not started';
      el.gw.textContent = '\u2013'; el.gwS.textContent = 'Found by the scan';
      $('#s-down-l').setAttribute('d', 'M0 29H120'); $('#s-down-a').setAttribute('d', 'M0 29H120V30H0Z');
      $('#s-up-l').setAttribute('d', 'M0 29H120'); $('#s-up-a').setAttribute('d', 'M0 29H120V30H0Z');
    };
    var step = function () {
      var walk = function (v, lo, hi) { return Math.min(hi, Math.max(lo, v + (Math.random() - 0.5) * (hi - lo) * 0.45)); };
      rate.down = walk(rate.down || 2.2e6, 0.7e6, 3.6e6);
      rate.up = walk(rate.up || 4e5, 1.4e5, 6.5e5);
      ['down', 'up'].forEach(function (k) {
        tot[k] += rate[k];
        if (!hist[k].length) for (var i = 0; i < 23; i++) hist[k].push(rate[k] * (0.55 + Math.random() * 0.5));
        hist[k].push(rate[k]); if (hist[k].length > 24) hist[k].shift();
      });
      el.down.textContent = fmtRate(rate.down); el.up.textContent = fmtRate(rate.up);
      el.downT.textContent = fmtTot(tot.down); el.upT.textContent = fmtTot(tot.up);
      spark('s-down', hist.down); spark('s-up', hist.up);
      el.time.textContent = clock(Date.now() - since);
      ticks++;
      if (ticks === 18) log('!', 'keepalive missed once, retrying');
      if (ticks === 19) log('+', 'keepalive restored (rtt=51ms)');
      if (ticks % 30 === 0) log('=', 'up ' + (tot.up / 1048576).toFixed(1) + ' MiB down ' + (tot.down / 1048576).toFixed(1) + ' MiB uptime ' + clock(Date.now() - since));
      draw();
    };

    // ---- the state machine
    var connected = function (restored) {
      state = 'on'; cur = steps.length;
      if (!restored) since = Date.now();
      el.gw.textContent = GW[live.proto];
      el.gwS.textContent = NAMES[live.proto === 'auto' ? 'wg' : live.proto];
      el.timeS.textContent = 'Tunnel up';
      store.set(KEY, JSON.stringify({ proto: live.proto, carrier: live.carrier, since: since }), session);
      clearInterval(loop); loop = setInterval(step, 1000); step();
      draw(); drawRoute();
    };
    var connect = function () {
      if (state !== 'off') return;
      live = { proto: want.proto, carrier: want.carrier };
      steps = plan(live.proto, live.carrier); cur = 0; state = 'busy';
      zero();
      log('*', 'OryvexCore starting (' + (live.proto === 'auto' ? 'auto: wireguard first' : live.proto === 'tor' ? 'tor-only' : NAMES[live.proto].toLowerCase()) + ')');
      draw(); drawRoute();
      var t = 500;
      steps.forEach(function (s, i) {
        s.logs.forEach(function (l, j) { later(t + j * 260, function () { log(l[0], l[1]); }); });
        t += 420 + s.logs.length * 260;
        later(t, function () { cur = i + 1; if (cur < steps.length) draw(); });
      });
      later(t + 200, function () { connected(false); });
    };
    var disconnect = function (thenConnect) {
      if (state === 'off' || state === 'stop') return;
      var wasBusy = state === 'busy';
      clearTimers(); clearInterval(loop);
      state = 'stop'; draw();
      log('*', wasBusy ? 'cancelled, closing what was opened' : 'closing the tunnel');
      store.del(KEY, session);
      later(700, function () {
        state = 'off'; live = null; steps = []; cur = -1;
        log('*', 'stopped');
        zero(); draw(); drawRoute();
        if (thenConnect) later(250, connect);
      });
    };
    var toggle = function () { if (state === 'off') connect(); else disconnect(false); };

    el.cta.addEventListener('click', toggle);
    el.orb.addEventListener('click', toggle);
    if (sideBtn) sideBtn.addEventListener('click', function (e) { e.preventDefault(); toggle(); });
    $('#reapply').addEventListener('click', function () { disconnect(true); });
    $$('#routes .choice').forEach(function (b) { b.addEventListener('click', function () { want.proto = b.getAttribute('data-p'); drawRoute(); }); });
    $$('#carrier button').forEach(function (b) { b.addEventListener('click', function () { want.carrier = b.getAttribute('data-c'); drawRoute(); }); });
    window.addEventListener('resize', function () { if (state === 'on') draw(); });

    // a session left running on another page picks up where it was
    var d = saved();
    if (d && NAMES[d.proto]) {
      want = { proto: d.proto, carrier: d.carrier || 'h2' };
      live = { proto: d.proto, carrier: want.carrier };
      steps = plan(live.proto, live.carrier); since = d.since;
      first = true; log('*', 'session restored, tunnel up for ' + clock(Date.now() - since));
      connected(true);
    } else {
      drawRoute(); draw();
    }
    if (location.hash === '#connect' && state === 'off') {
      later(450, connect);
    }
  }

  var y = $('#year');
  if (y) y.textContent = new Date().getFullYear();
})();
