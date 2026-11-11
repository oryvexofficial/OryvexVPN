// OryvexVPN site: the app shell (theme, number-key navigation, tab bar sheet), copy buttons,
// the docs contents bar, the screenshot viewer, the Tor exit picker.
// No network requests: the site works fully offline.
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var page = document.body.getAttribute('data-page');
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Old one-page links (index.html#download) still land on the right page.
  var legacy = { about: 'about.html', how: 'guide.html', gui: 'app.html', docs: 'docs.html', creator: 'creator.html', download: 'download.html', tor: 'tor.html' };
  if (page === 'home' && location.hash && legacy[location.hash.slice(1)]) {
    location.replace(legacy[location.hash.slice(1)]);
    return;
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

  var y = $('#year');
  if (y) y.textContent = new Date().getFullYear();
})();
