// OryvexVPN site: menu, copy buttons, docs table of contents, the GUI exit-picker demo.
// No network requests: the site works fully offline.
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  // Old one-page links (index.html#download) still land on the right page.
  var legacy = { about: 'about', how: 'guide', gui: 'app', docs: 'docs', creator: 'creator', download: 'download', tor: 'tor' };
  var page = document.body.getAttribute('data-page');
  if (page === 'home' && location.hash && legacy[location.hash.slice(1)]) {
    location.replace(legacy[location.hash.slice(1)]);
    return;
  }

  // Someone opened /download.html directly: show /download instead (GitHub Pages serves both).
  if (/^https?:$/.test(location.protocol) && /\.html$/.test(location.pathname) && page !== '404' && history.replaceState) {
    history.replaceState(null, '', location.pathname.replace(/(index)?\.html$/, '') + location.search + location.hash);
  }

  // Mobile menu
  var btn = $('#menu'), links = $('#nav-links');
  if (btn && links) {
    var setOpen = function (open) {
      links.classList.toggle('open', open);
      btn.setAttribute('aria-expanded', String(open));
      btn.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    };
    btn.addEventListener('click', function () { setOpen(btn.getAttribute('aria-expanded') !== 'true'); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setOpen(false); });
    $$('a', links).forEach(function (a) { a.addEventListener('click', function () { setOpen(false); }); });
    window.addEventListener('resize', function () { if (window.innerWidth > 940) setOpen(false); });
  }

  // Copy buttons: on every <pre> and on any [data-copy]
  var ICON_COPY = '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
  var ICON_OK = '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg>';
  function copyText(text, el) {
    var done = function () {
      el.innerHTML = ICON_OK + '<span>Copied</span>';
      setTimeout(function () { el.innerHTML = ICON_COPY + '<span>Copy</span>'; }, 1600);
    };
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, function () { fallback(text); done(); });
    } else { fallback(text); done(); }
  }
  function fallback(text) {
    var t = document.createElement('textarea');
    t.value = text; t.setAttribute('readonly', ''); t.style.position = 'fixed'; t.style.opacity = '0';
    document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(t);
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

  // Docs table of contents: highlight the section in view
  var toc = $$('.toc a');
  if (toc.length && 'IntersectionObserver' in window) {
    var map = {};
    toc.forEach(function (a) { map[a.getAttribute('href').slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting && map[en.target.id]) {
          toc.forEach(function (a) { a.classList.remove('on'); });
          map[en.target.id].classList.add('on');
        }
      });
    }, { rootMargin: '-30% 0px -60% 0px' });
    $$('.doc-body section[id]').forEach(function (s) { io.observe(s); });
  }

  // GUI demo: Tor exit picker
  var picker = $('#exit-picker');
  if (picker) {
    var exits = [['de', 'Germany'], ['nl', 'Netherlands'], ['us', 'United States'], ['fr', 'France'], ['se', 'Sweden'], ['ch', 'Switzerland']];
    var hints = {
      auto: 'Tor picks an exit itself, weighted by bandwidth.',
      fastest: 'Measures the best-served countries on connect and keeps the quickest.',
      country: 'Leaves from the country you pick.'
    };
    var cli = { auto: 'auto', fastest: 'fastest' };
    var chips = $('#chips', picker), hint = $('#hint', picker), flag = $('#flag', picker);
    var pick = 'de';
    var draw = function (mode) {
      $$('.seg button', picker).forEach(function (s) { s.setAttribute('aria-pressed', String(s.getAttribute('data-m') === mode)); });
      hint.textContent = hints[mode];
      if (flag) flag.textContent = 'oryvexcore --tor-only --tor-exit ' + (cli[mode] || pick);
      chips.innerHTML = mode !== 'country' ? '' : exits.map(function (e) {
        return '<button type="button" class="chip" data-c="' + e[0] + '" aria-pressed="' + (e[0] === pick) + '"><b>' + e[0].toUpperCase() + '</b><span>' + e[1] + '</span></button>';
      }).join('');
      $$('.chip', chips).forEach(function (el) {
        el.addEventListener('click', function () { pick = el.getAttribute('data-c'); draw('country'); });
      });
    };
    $$('.seg button', picker).forEach(function (s) { s.addEventListener('click', function () { draw(s.getAttribute('data-m')); }); });
    draw('country');
  }

  var y = $('#year');
  if (y) y.textContent = new Date().getFullYear();
})();
