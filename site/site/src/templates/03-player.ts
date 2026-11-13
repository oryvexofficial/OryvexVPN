// ============================================================================
const LAND_ROWS = 100;
const LAND_B64 = 'AAAAAAAAACAAAMA9EAAA7AeEAADwPwAAAAAA/wAAAgCACH4AEBwCAATADwAEDwAA8BH+AAD0PwAB4HT4AwDk/3sAPnRh/AE40P//Z/n/9IwfAL7+////w///5/wA8Pf3////8v//Z3gw4O7/////D/z/vzAcCHD//////z/4//9BgAEA5///////H/j+/4MDBAC8///////nAA7+/8AFAAB4/v////+hAMCA/x/4AAAQjP//////wAAgAP//8AMAwCD//////wccAADg///9AwCggP//////H2AAAAD4/9//AAA8////////fzCAAADw/3//AQDQ/f///////w8CAAAA/v//JwAAAP////////8XAgAAAPD//38GAAD+/////////wcAAAAA+P//vwwAAPj/////////AwAAAACA////FwAAAP8/ff7/////AAAAAACA////BQAAAL7+4P3/////RwAAAAAA+P//HwAAAPBhPnD8/////yAAAAAAAPD//z8AAADAB/Kc5/////8HAQAAAAAA/v//AwAAAPAAyP/z////vwIBAAAAAAD4//8PAAAAwAfI/p//////MRAAAAAAAAD///8BAAAAwHhA9e//////MwwAAAAAAAD+//8BAAAAAPwBgf//////D3kAAAAAAACA//8fAAAAAOB/AOD//////w8aAAAAAAAAAP7/HwAAAADg/8fA//////9/EAAAAAAAAADA//8AAAAAAP7//f///////w8AAAAAAAAAAPB/QAAAAAAA/v///fP/////HwAAAAAAAAAAYP8AAwAAAAD+///fP///////AAAAAAAAAAAA6A9AAAAAAMD////3D/7///8/AAAAAAAAAAAAyA8AAAAAAMD////PPwH///9/AQAAAAAAAAAAAD4AAAAAAAD+/////H/g////EwAAAAAAAAAAAIAPgAEAAADA////f/4f8P/+PwAAAAAAAAAAAACADwMDAAAAwP/////8H8B/+AcAAAAAAAAAAAAAED4GcAAAAAD/////8z8A/8CfAAAAAAAAAAAAAADAPwAAAAAA8P///3/+A+AH+AMIAAAAAAAAAAAAAEA/AAAAAAD8////Pz8A8AD4AwYAAAAAAAAAAAAAAH4AAAAAAPz///9/DwDgAPAHAAAAAAAAAAAAAAAA4AAAAAAA+P////8HAIADQB8AAAAAAAAAAAAAAAAAAw8AAADA/////x8DABwAcEABAAAAAAAAAAAAAAAw2A8AAADw/////z8AgAEgBCAAAAAAAAAAAAAAAADQ/wcAAAD+/////wcAgAAIADgAAAAAAAAAAAAAAADg/wMAAAD//////wEAIAAEIAQAAAAAAAAAAAAAAAD4/wcAAAA3/P//fwAAAAAGOAAAAAAAAAAAAAAAAAD8/w8AAAAA8P//HwAAAEADDgAAAAAAAAAAAAAAAAD+/wcAAAAA8P//BwAAAMCCDwQAAAAAAAAAAAAAAAD//wcAAAAA+P//AwAAAIDB7wQAAAAAAAAAAAAAAID//z8AAAAA+P//AQAAAADDB6QAAAAAAAAAAAAAAID//38AAAAA+P//AAAAAIDHNyADAAAAAAAAAAAAAID///8HAAAA8P9/AAAAAAAHIOEPAAAAAAAAAAAAAMD///8PAAAA8P8fAAAAAAACEIAPAAAAAAAAAAAAAOD///8HAAAA/P8PAAAAAAALAMAHAgAAAAAAAAAAAPD///8BAAAA/v8DAAAAAAAMBGgCAgAAAAAAAAAAAPz//z8AAADA//8AAAAAAACQAIAAAAAAAAAAAAAAgP///wEAAAD4/w8AAAAAAAAAQAAAAAAAAAAAAAAA/P//BwAAAPD/PwAAAAAAAAAeAQAAAAAAAAAAAADw//8PAAAA4P//MAAAAAAAgB4GAAAAAAAAAAAAAMD//x8AAADg/38YAAAAAADgHwcAAAAAAAAAAAAAwP//BwAAAPj/DwcAAAAAAP7vAAAAAAAAAAAAAAD4/z8AAACA/z94AAAAAADw/w8AAAAAAAAAAAAAwP//AAAAAPx/4CAAAAAA8P8/AAAAAAAAAAAAAMD//wAAAAD8f3AAAAAAAP7/PwABAAAAAAAAAADw/w8AAAAA/x8cAAAAAOD//w8AAAAAAAAAAAAA/z8AAAAA8P/AAAAAAAD//38AAAAAAAAAAAAA/n8AAAAA8H8AAAAAAID//38AAAAAAAAAAACA/w8AAAAA/A8AAAAAAPD//wcAAAAAAAAAAAD8fwAAAADgPwAAAAAAwP//HwAAAAAAAAAAAPw/AAAAAOAPAAAAAADg//8HAAAAAAAAAACA/wMAAAAA/AAAAAAAAH74PwAAAAAAAAAAAP4GAAAAAHgAAAAAAAA+0B8AAAAAAAAAAAD/AAAAAAAAAAAAAAAAAPwBIAAAAAAAAAD8BwAAAAAAAAAAAAAAAPABAAAAAAAAAAD+AQAAAAAAAAAAAAAAAA4ADAAAAAAAAPADAAAAAAAAAAAAAAAACAAIAAAAAAAAeAAAAAAAAAAAAAAAAAADwAAAAAAAAMADAAAAAAAAAAAAAAAAAkAAAAAAAADgAQAAAAAAAAAAAAAAAAADAAAAAACAAwAAAAAAAAAAAAAAAIABAAAAAADgAQAAAAAAAAAAAAAAAAAAAAAAAMADAAAAAAAAAAAAAAAAAAAAAAAAHAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAAAAAAAAAAAAAAAAAAIABAAAAAAAAAAAAAAAAAAAAAMAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const GLOBE_JS = 'var LAND = ' + JSON.stringify(LAND_B64) + ', LAND_ROWS = ' + LAND_ROWS + ';' + String.raw`
(function(){
  var box = document.getElementById('edgeGlobe');
  if (!box) return;
  var cv = box.querySelector('canvas');
  var ctx = cv && cv.getContext && cv.getContext('2d');
  if (!ctx) return;
  var D = Math.PI / 180, STEP = 1.5;
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- land dots (Natural Earth, 1.5 degree equal-area grid) ---------- */
  var bin = atob(LAND), xs = [], ys = [], zs = [], idx = 0, lat = 90 - STEP / 2;
  for (var r = 0; r < LAND_ROWS; r++) {
    var n = Math.max(1, Math.floor(Math.cos(lat * D) * 360 / STEP + 0.5));
    for (var k = 0; k < n; k++) {
      if (bin.charCodeAt(idx >> 3) & (1 << (idx & 7))) {
        var lon = -180 + (k + 0.5) * 360 / n, cl = Math.cos(lat * D);
        xs.push(cl * Math.sin(lon * D)); ys.push(Math.sin(lat * D)); zs.push(cl * Math.cos(lon * D));
      }
      idx++;
    }
    lat -= STEP;
  }
  var N = xs.length;
  function vec(la, lo){ var c = Math.cos(la * D); return [c * Math.sin(lo * D), Math.sin(la * D), c * Math.cos(lo * D)]; }

  /* ---------- edge locations + routes ---------- */
  var POPS = [
    ['San Francisco', 37.77, -122.42], ['New York', 40.71, -74.0], ['Toronto', 43.65, -79.38], ['S\u00e3o Paulo', -23.55, -46.63],
    ['London', 51.5, -0.12], ['Frankfurt', 50.11, 8.68], ['Abidjan', 5.36, -4.0], ['Lagos', 6.52, 3.38],
    ['Johannesburg', -26.2, 28.05], ['Dubai', 25.2, 55.27], ['Mumbai', 19.08, 72.88], ['Singapore', 1.35, 103.82],
    ['Tokyo', 35.68, 139.69], ['Sydney', -33.87, 151.2]
  ].map(function(p){ return { name: p[0], v: vec(p[1], p[2]), ph: Math.random() * 6.28 }; });
  var ROUTES = [[0,1],[1,4],[4,5],[5,9],[9,10],[10,11],[11,12],[12,0],[11,13],[4,6],[6,7],[7,8],[8,9],[1,3],[3,6],[2,4],[5,11],[0,13]];
  function slerp(a, b, t){
    var d = Math.max(-1, Math.min(1, a[0]*b[0] + a[1]*b[1] + a[2]*b[2])), w = Math.acos(d);
    if (w < 1e-4) return a.slice();
    var s = Math.sin(w), p = Math.sin((1 - t) * w) / s, q = Math.sin(t * w) / s;
    return [a[0]*p + b[0]*q, a[1]*p + b[1]*q, a[2]*p + b[2]*q];
  }
  var ARCS = ROUTES.map(function(rt, i){
    var a = POPS[rt[0]].v, b = POPS[rt[1]].v, w = Math.acos(Math.max(-1, Math.min(1, a[0]*b[0] + a[1]*b[1] + a[2]*b[2])));
    var h = 0.03 + w * 0.09, seg = 56, pts = [];
    for (var j = 0; j <= seg; j++) { var t = j / seg, p = slerp(a, b, t), m = 1 + h * Math.sin(Math.PI * t); pts.push([p[0]*m, p[1]*m, p[2]*m]); }
    return { pts: pts, dur: 2.2 + w * 1.4, delay: i * 0.37 };
  });

  /* ---------- theme ---------- */
  var C = {};
  function readTheme(){
    var cs = getComputedStyle(box);
    ['dot','sea-1','sea-2','rim','glow','arc','arc-2','pop'].forEach(function(k){ C[k] = cs.getPropertyValue('--globe-' + k).trim() || '#888'; });
  }
  readTheme();
  new MutationObserver(function(){ readTheme(); draw(); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

  /* ---------- sizing ---------- */
  var W = 0, H = 0, R = 0, cx = 0, cy = 0, dpr = 1;
  function size(){
    var rect = box.getBoundingClientRect();
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = Math.max(1, rect.width); H = Math.max(1, rect.height);
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    R = Math.min(W, H) * 0.4; cx = W / 2; cy = H / 2;
    draw();
  }

  /* ---------- camera ---------- */
  var yaw = 20 * D, tilt = -18 * D, spin = reduce ? 0 : 0.11, vel = reduce ? 0 : 1.6;
  var cosT, sinT, cosY, sinY;
  function cam(){ cosY = Math.cos(yaw); sinY = Math.sin(yaw); cosT = Math.cos(tilt); sinT = Math.sin(tilt); }
  function rot(x, y, z, out){
    var X = x * cosY - z * sinY, Z1 = x * sinY + z * cosY;
    out[0] = X; out[1] = y * cosT - Z1 * sinT; out[2] = y * sinT + Z1 * cosT;
    return out;
  }
  var P = [0, 0, 0];

  /* ---------- draw ---------- */
  var time = 0, buckets = [[], [], [], []];
  function draw(){
    if (!W) return;
    cam();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    var g = ctx.createRadialGradient(cx, cy, R * 0.92, cx, cy, R * 1.22);
    g.addColorStop(0, C.glow); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.globalAlpha = 0.55; ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

    ctx.globalAlpha = 1;
    var s = ctx.createRadialGradient(cx - R * 0.35, cy - R * 0.4, R * 0.1, cx, cy, R);
    s.addColorStop(0, C['sea-1']); s.addColorStop(1, C['sea-2']);
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, 6.2832); ctx.fillStyle = s; ctx.fill();
    ctx.lineWidth = 1; ctx.strokeStyle = C.rim; ctx.globalAlpha = 0.6; ctx.stroke();

    for (var b = 0; b < 4; b++) buckets[b].length = 0;
    for (var i = 0; i < N; i++) {
      rot(xs[i], ys[i], zs[i], P);
      if (P[2] <= 0.02) continue;
      var bi = P[2] > 0.75 ? 3 : P[2] > 0.5 ? 2 : P[2] > 0.25 ? 1 : 0;
      buckets[bi].push(cx + P[0] * R, cy - P[1] * R);
    }
    var ds = Math.max(1.3, R / 130);
    ctx.fillStyle = C.dot;
    for (b = 0; b < 4; b++) {
      var arr = buckets[b], sz = ds * (0.6 + b * 0.16), hs = sz / 2;
      ctx.globalAlpha = 0.28 + b * 0.24;
      ctx.beginPath();
      for (var j = 0; j < arr.length; j += 2) ctx.rect(arr[j] - hs, arr[j + 1] - hs, sz, sz);
      ctx.fill();
    }

    ctx.lineCap = 'round';
    for (var a = 0; a < ARCS.length; a++) drawArc(ARCS[a]);

    for (var p = 0; p < POPS.length; p++) {
      var v = POPS[p].v; rot(v[0], v[1], v[2], P);
      if (P[2] <= 0.05) continue;
      var x = cx + P[0] * R, y = cy - P[1] * R, k2 = (Math.sin(time * 2.2 + POPS[p].ph) + 1) / 2;
      ctx.globalAlpha = (0.35 * (1 - k2)) * P[2];
      ctx.fillStyle = C.pop; ctx.beginPath(); ctx.arc(x, y, ds * (2.4 + 3.6 * k2), 0, 6.2832); ctx.fill();
      ctx.globalAlpha = Math.min(1, 0.4 + P[2]);
      ctx.beginPath(); ctx.arc(x, y, ds * 1.7, 0, 6.2832); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  var Q = [0, 0, 0];
  function visible(q){ return q[2] > 0 || (q[0] * q[0] + q[1] * q[1]) > 1; }
  function drawArc(arc){
    var pts = arc.pts, n = pts.length - 1;
    var cyc = arc.dur + 1.6, t = ((time + arc.delay) % cyc) / arc.dur;
    var head = Math.min(1, t), tail = Math.max(0, t - 0.42);
    var fade = t > 1 ? Math.max(0, 1 - (t - 1) * arc.dur / 1.6) : 1;
    ctx.lineWidth = Math.max(1, R / 220);
    ctx.strokeStyle = C['arc-2']; ctx.globalAlpha = 0.22;
    strokeRange(pts, 0, n);
    if (fade <= 0) return;
    ctx.strokeStyle = C.arc; ctx.globalAlpha = 0.95 * fade; ctx.lineWidth = Math.max(1.4, R / 150);
    strokeRange(pts, Math.floor(tail * n), Math.ceil(head * n));
  }
  function strokeRange(pts, from, to){
    var open = false;
    ctx.beginPath();
    for (var j = from; j <= to; j++) {
      var p = pts[j]; rot(p[0], p[1], p[2], Q);
      if (!visible(Q)) { open = false; continue; }
      var x = cx + Q[0] * R, y = cy - Q[1] * R;
      if (!open) { ctx.moveTo(x, y); open = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }

  /* ---------- loop ---------- */
  var running = false, last = 0, onScreen = false, dragging = false;
  function frame(ts){
    if (!running) return;
    var dt = Math.min(0.05, (ts - (last || ts)) / 1000); last = ts;
    if (!dragging) { vel += (spin - vel) * Math.min(1, dt * 1.6); yaw += vel * dt; }
    if (!reduce) time += dt;
    draw();
    requestAnimationFrame(frame);
  }
  function update(){
    var want = onScreen && !document.hidden;
    if (want && !running) { running = true; last = 0; requestAnimationFrame(frame); }
    else if (!want) running = false;
  }
  if ('IntersectionObserver' in window) new IntersectionObserver(function(e){ onScreen = e[0].isIntersecting; update(); }, { rootMargin: '80px' }).observe(box);
  else { onScreen = true; update(); }
  document.addEventListener('visibilitychange', update);
  if ('ResizeObserver' in window) new ResizeObserver(size).observe(box); else window.addEventListener('resize', size);
  size();

  /* ---------- drag to spin (horizontal only so the page still scrolls) ---------- */
  var px = 0, py = 0, lx = 0, lt = 0;
  box.addEventListener('pointerdown', function(e){ dragging = true; px = lx = e.clientX; py = e.clientY; lt = performance.now(); box.classList.add('grabbing'); try { box.setPointerCapture(e.pointerId); } catch (_) {} });
  box.addEventListener('pointermove', function(e){
    if (!dragging) return;
    var dx = e.clientX - lx, now = performance.now();
    yaw += dx / R * 0.9; tilt = Math.max(-40 * D, Math.min(10 * D, tilt + (e.clientY - py) / R * 0.4));
    py = e.clientY; vel = (dx / R * 0.9) / Math.max(0.008, (now - lt) / 1000); lx = e.clientX; lt = now;
    if (!running) draw();
  });
  function end(){ if (!dragging) return; dragging = false; box.classList.remove('grabbing'); vel = Math.max(-6, Math.min(6, vel)); }
  box.addEventListener('pointerup', end); box.addEventListener('pointercancel', end); box.addEventListener('lostpointercapture', end);
})();
`;

// ============================================================================
// PLAYER (shared by /video and /embed)
// ============================================================================
const HLS_SRC = 'https://cdnjs.cloudflare.com/ajax/libs/hls.js/1.6.15/hls.min.js';
const HLS_FALLBACK_SRC = 'https://cdn.jsdelivr.net/npm/hls.js@1.6.15/dist/hls.min.js';
const HLS_SCRIPT = '<link rel="preconnect" href="https://cdnjs.cloudflare.com" crossorigin>' +
    '<script id="hlsjs" src="' + HLS_SRC + '" defer onload="window.__hlsState=\'ok\'" onerror="window.__hlsState=\'err\'"></script>';
const ICON_BACK10 = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><text x="12" y="15.5" fill="currentColor" stroke="none" font-size="7.5" font-weight="700" text-anchor="middle" font-family="Inter,Arial">10</text></svg>';
const ICON_FWD10 = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/><text x="12" y="15.5" fill="currentColor" stroke="none" font-size="7.5" font-weight="700" text-anchor="middle" font-family="Inter,Arial">10</text></svg>';

function proxiedThumb(thumb) {
    const raw = normalizeThumbnailUrl(thumb);
    if (!raw) return '';
    return '/proxy-image?url=' + encodeURIComponent(raw) + '&token=' + SESSION_PLACEHOLDER;
}

function renderPlayerMarkup(mode, thumb) {
    const speeds = [0.5, 0.75, 1, 1.25, 1.5, 2].map(s => '<button type="button" role="menuitemradio" data-speed="' + s + '"' + (s === 1 ? ' class="on"' : '') + '>' + (s === 1 ? '1&times;' : s + '&times;') + '</button>').join('');
    const posterUrl = proxiedThumb(thumb);
    const posterStyle = posterUrl ? ' style="background-image:url(\'' + escapeHtml(posterUrl) + '\')"' : '';
    return '<div class="vx-player loading" id="vx" tabindex="0" data-mode="' + mode + '" aria-label="Video player">' +
        '<video id="vxVideo" playsinline webkit-playsinline preload="auto"></video>' +
        '<div class="vx-poster" id="vxPoster"' + posterStyle + '></div>' +
        '<div class="vx-hit" id="vxHit"></div>' +
        '<div class="vx-mark">VexoStream</div>' +
        '<div class="vx-net" id="vxNet" role="status" aria-live="polite"><i></i><span id="vxNetText"></span></div>' +
        '<div class="vx-badge" id="vxBadge">2&times; ' + ICONS.fast + '</div>' +
        '<div class="vx-ripple l" id="vxRipL">&minus;10s</div><div class="vx-ripple r" id="vxRipR">+10s</div>' +
        '<button class="vx-center" id="vxCenter" type="button" aria-label="Play">' + ICONS.play + '</button>' +
        '<div class="vx-spin" aria-hidden="true"></div>' +
        '<div class="vx-msg" id="vxMsg">Finding streams&hellip;</div>' +
        '<div class="vx-resume" id="vxResume"><span id="vxResumeText"></span><button type="button" id="vxRestart">Start over</button></div>' +
        '<div class="vx-error" role="alert"><span class="vx-error-ic" aria-hidden="true">!</span><b>This video won&rsquo;t play right now.</b><p id="vxErrText">No working stream was found.</p><button class="btn" id="vxRetry" type="button">Try again</button></div>' +
        '<div class="vx-chrome" id="vxChrome">' +
        '<div class="vx-track" id="vxTrack" role="slider" tabindex="0" aria-label="Seek" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0">' +
        '<div class="vx-rail"><div class="vx-buf" id="vxBuf"></div><div class="vx-prog" id="vxProg"></div></div>' +
        '<div class="vx-hover" id="vxHover" aria-hidden="true"><div class="vx-thumb" id="vxThumb"><canvas id="vxThumbCanvas"></canvas></div><span class="vx-hover-time" id="vxHoverTime">0:00</span></div></div>' +
        '<div class="vx-ctrls">' +
        '<div class="vx-group">' +
        '<button class="vx-btn" id="vxPlay" type="button" aria-label="Play">' + ICONS.play + '</button>' +
        '<button class="vx-btn vx-hide-sm" id="vxBack" type="button" aria-label="Back 10 seconds">' + ICON_BACK10 + '</button>' +
        '<button class="vx-btn vx-hide-sm" id="vxFwd" type="button" aria-label="Forward 10 seconds">' + ICON_FWD10 + '</button>' +
        '<div class="vx-vol"><button class="vx-btn" id="vxMute" type="button" aria-label="Mute">' + ICONS.volume + '</button>' +
        '<input type="range" id="vxVol" min="0" max="1" step="0.05" value="1" aria-label="Volume"></div>' +
        '<span class="vx-time"><b id="vxCur">0:00</b><span class="vx-dur-wrap"> / <span id="vxDur">--:--</span></span></span>' +
        '</div>' +
        '<div class="vx-group">' +
        '<span class="vx-qtag" id="vxQTag">Auto</span>' +
        '<div class="vx-wrap-menu"><button class="vx-btn" id="vxSetBtn" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Settings">' + ICONS.gear + '</button>' +
        '<div class="vx-menu" id="vxSetMenu" role="menu">' +
        '<h5>Quality <span id="vxQualMode">Auto</span></h5><div class="vx-qopts" id="vxQualMenu"></div>' +
        '<h5>Speed</h5><div class="vx-sopts" id="vxSpeedMenu">' + speeds + '</div>' +
        '</div></div>' +
        '<button class="vx-btn vx-hide-sm" id="vxPip" type="button" aria-label="Picture in picture" hidden>' + ICONS.pip + '</button>' +
        (mode === 'watch' ? '<button class="vx-btn vx-hide-sm btn-theater" id="vxTheater" type="button" aria-label="Theater mode" aria-pressed="false">' + ICONS.theater + '</button>' : '') +
        '<button class="vx-btn" id="vxFs" type="button" aria-label="Full screen">' + ICONS.fullscreen + '</button>' +
        '</div></div></div>' +
        '</div>';
}

function renderWatchHtml(targetUrl, meta, initial = {}) {
    const enc = b64urlEncode(targetUrl);
    const vexoEmbedUrl = vexoEmbedUrlForVideo(targetUrl);
    return renderHead({ meta, extraHead: HLS_SCRIPT }) +
        '<body class="watch">' +
        '<script>if(document.documentElement.classList.contains("pref-theater"))document.body.classList.add("theater");</script>' +
        renderAgeGate() +
        renderNav('') +
        '<main class="watch-page"><div class="wrap-wide watch-grid">' +
        '<section class="watch-main">' +
        '<div class="stage">' + renderPlayerMarkup('watch', initial.thumb) + '</div>' +
        '<div class="watch-head"><div>' +
        '<h1 class="watch-title pending" id="videoTitle">' + escapeHtml(initial.title || 'Loading title\u2026') + '</h1>' +
        '<div class="watch-meta" id="videoMeta"></div></div>' +
        '<div class="watch-actions">' +
        '<button class="btn quiet sm" id="btnCopyLink" type="button">' + ICONS.link + 'Copy link</button>' +
        '<button class="btn sm" id="btnOpenEmbed" type="button">' + ICONS.code + 'Embed</button>' +
        '</div></div>' +
        '</section>' +
        '<aside class="watch-side" aria-label="Video details">' +
        '<div class="side-card"><h2>Streams <span class="health" id="vxHealth" data-s="busy"><i></i><span>Connecting</span></span></h2>' +
        '<div class="qual-list" id="qualityButtonsGrid"><span>Resolving streams&hellip;</span></div></div>' +
        '<div class="side-card" id="upNextCard"><h2>More like this</h2><div class="upnext" id="upNext"><div class="sk"></div><div class="sk"></div><div class="sk"></div></div></div>' +
        '<div class="side-card kbd-card"><h2>Shortcuts</h2><div class="kbd-help"><span><kbd>K</kbd>Play / pause</span><span><kbd>F</kbd>Full screen</span><span><kbd>&larr;</kbd><kbd>&rarr;</kbd>5 seconds</span><span><kbd>J</kbd><kbd>L</kbd>10 seconds</span><span><kbd>M</kbd>Mute</span><span><kbd>T</kbd>Theater</span></div></div>' +
        '</aside>' +
        '</div></main>' +
        '<div class="sheet" id="embedModal" role="dialog" aria-modal="true" aria-labelledby="embedTitle">' +
        '<div class="sheet-card">' +
        '<div class="sheet-head"><h3 id="embedTitle">Embed this video</h3><button class="sheet-x" id="btnCloseEmbed" type="button" aria-label="Close">' + ICONS.close + '</button></div>' +
        '<div class="segmented" role="group" aria-label="Embed type"><button type="button" id="tabIframe" aria-pressed="true">iframe</button><button type="button" id="tabSdk" aria-pressed="false">Web component</button></div>' +
        '<div class="code" id="embedCodeText"></div>' +
        '<section class="vexo-embed-option" aria-labelledby="vexoEmbedTitle">' +
        '<h4 id="vexoEmbedTitle">VexoStream embed link</h4>' +
        (vexoEmbedUrl
            ? '<p>This link opens the video in VexoStream’s own embedded player. Provider playback rules and availability still apply.</p>' +
              '<a class="vexo-embed-link" id="vexoEmbedLink" href="' + escapeHtml(vexoEmbedUrl) + '" target="_blank" rel="noopener noreferrer">Open VexoStream embed <span aria-hidden="true">↗</span></a>' +
              '<div class="code vexo-embed-url" id="vexoEmbedUrlText">' + escapeHtml(vexoEmbedUrl) + '</div>' +
              '<button class="btn quiet sm" id="btnCopyVexoEmbed" type="button">' + ICONS.copy + '<span id="copyVexoEmbedLabel">Copy VexoStream embed link</span></button>'
            : '<p id="vexoEmbedUnavailable">This source does not match a supported provider video URL, so VexoStream cannot create an embed link for it.</p>') +
        '</section>' +
        '<div class="sheet-foot"><a class="chev" id="embedDirectPreview" href="/embed/' + enc + '" target="_blank" rel="noopener">Preview VexoStream embed</a>' +
        '<button class="btn" id="btnCopyEmbed" type="button">' + ICONS.copy + '<span id="copyBtnLabel">Copy code</span></button></div>' +
        '</div></div>' +
        renderFooter() +
        clientConfigScript({ player: { mode: 'watch', targetUrl, enc, vexoEmbedUrl, thumb: initial.thumb || '', hlsFallback: HLS_FALLBACK_SRC } }) +
        '<script>' + COMMON_JS + CARD_JS + PLAYER_JS + WATCH_JS + '</script>' +
        '</body></html>';
}

function renderEmbedHtml(targetUrl, meta, thumb = '', appGrant = '') {
    const stripAppGrant = appGrant
        ? '<script>try{var u=new URL(location.href);u.searchParams.delete("app_grant");history.replaceState(null,"",u.pathname+u.search+u.hash)}catch(e){}</script>'
        : '';
    return '<!DOCTYPE html><html lang="en" class="embed" data-theme="dark"><head>' +
        '<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' +
        '<meta name="robots" content="noindex">' +
        stripAppGrant +
        '<link rel="icon" type="image/svg+xml" href="/favicon.svg">' +
        (meta || '<title>VexoStream Player</title>') +
        FONT_LINKS +
        '<script>' + DIRECTION_BOOT + '</script>' +
        '<style>' + APP_CSS + '</style>' + HLS_SCRIPT +
        '</head><body>' +
        renderPlayerMarkup('embed', thumb) +
        clientConfigScript({ player: { mode: 'embed', targetUrl, thumb, appGrant, hlsFallback: HLS_FALLBACK_SRC } }) +
        '<script>' + PLAYER_JS + '</script>' +
        '</body></html>';
}

const PLAYER_JS = String.raw`
(function(){
  var cfg = (window.VX && window.VX.player) || {};
  var TOKEN = (window.VX && window.VX.token) || '';
  var root = document.getElementById('vx');
  var video = document.getElementById('vxVideo');
  if (!root || !video) return;
  var $ = function(id){ return document.getElementById(id); };
  var esc = window.escapeHtml || function(t){ return String(t == null ? '' : t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); };
  var poster = $('vxPoster'), hit = $('vxHit'), center = $('vxCenter'), msg = $('vxMsg');
  var btnPlay = $('vxPlay'), btnMute = $('vxMute'), vol = $('vxVol'), btnFs = $('vxFs'), btnPip = $('vxPip'), btnTheater = $('vxTheater');
  var track = $('vxTrack'), prog = $('vxProg'), buf = $('vxBuf'), hover = $('vxHover'), curEl = $('vxCur'), durEl = $('vxDur');
  var setBtn = $('vxSetBtn'), setMenu = $('vxSetMenu'), qualMenu = $('vxQualMenu'), speedMenu = $('vxSpeedMenu'), qualMode = $('vxQualMode'), qtag = $('vxQTag');
  var netEl = $('vxNet'), netText = $('vxNetText'), resumeEl = $('vxResume'), resumeText = $('vxResumeText');
  var hoverTime = $('vxHoverTime'), thumbBox = $('vxThumb'), thumbCanvas = $('vxThumbCanvas');
  var I_PLAY = ` + JSON.stringify(ICONS.play) + String.raw`;
  var I_PAUSE = ` + JSON.stringify(ICONS.pause) + String.raw`;
  var I_VOL = ` + JSON.stringify(ICONS.volume) + String.raw`;
  var I_MUTE = ` + JSON.stringify(ICONS.mute) + String.raw`;
  var I_FS = ` + JSON.stringify(ICONS.fullscreen) + String.raw`;
  var I_FS_EXIT = ` + JSON.stringify(ICONS.exitFullscreen) + String.raw`;

  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var nativeHls = false; try { nativeHls = !!video.canPlayType('application/vnd.apple.mpegurl'); } catch (e) {}
  var conn = navigator.connection || {};
  var lowData = !!conn.saveData || /(^|-)2g$/.test(String(conn.effectiveType || ''));

  /* ---------------------------------------------------------------- state */
  var queue = [], idx = -1, hls = null, gen = 0, tried = {};
  var wantPlay = false, ready = false, started = false, failedNow = false, refreshing = false, lockedMsg = '';
  var autoQ = true, prefLabel = 'auto';
  try { var sp = localStorage.getItem('vx_qpref'); if (sp) { prefLabel = sp; autoQ = sp === 'auto'; } } catch (e) {}
  var apiDuration = 0, hlsDuration = 0, resumeAt = 0, pendingSeek = 0;
  var refreshLog = [], netFails = 0, mediaFails = 0, nativeFails = {}, authHits = 0;
  var lastT = -1, lastProgressAt = Date.now(), attachedAt = Date.now(), stallStep = 0, recovering = false, playedOk = false, needFresh = false, autoShifted = false;
  var waitStart = 0, slowLog = [], waitTimer = null;
  var userRate = 1, holding = false, holdTimer = null, suppressClick = false;
  var scrubbing = false, scrubTime = 0, idleTimer = null;
  var title = '', provider = '', thumbRaw = cfg.thumb || '';
  var posterLoadedRank = 0, posterAttempted = {};

  window.VXPlayer = {
    video: video,
    queue: function(){ return queue; },
    current: function(){ return idx; },
    isAuto: function(){ return autoQ; },
    select: function(i){ choose(i); },
    auto: function(){ chooseAuto(); },
    refresh: function(){ refresh('manual'); },
    debug: function(){ return { resumeAt: resumeAt, idx: idx, refreshes: refreshLog.length, ready: ready, gen: gen, stallStep: stallStep }; }
  };

  /* ---------------------------------------------------------------- ui helpers */
  function emit(name, detail){ try { document.dispatchEvent(new CustomEvent('vx:' + name, { detail: detail })); } catch (e) {} }
  function setLoading(on, text){ root.classList.toggle('loading', !!on); if (msg) msg.textContent = on ? (text || '') : ''; }
  var netTimer = null;
  function net(text, kind, ms){
    clearTimeout(netTimer);
    if (!netEl) return;
    if (!text) { netEl.classList.remove('show'); return; }
    netText.textContent = text;
    netEl.className = 'vx-net show' + (kind === 'ok' ? ' ok' : kind === 'off' ? ' off' : '');
    if (ms) netTimer = setTimeout(function(){ netEl.classList.remove('show'); }, ms);
  }
  function health(s, text){ emit('health', { state: s, text: text }); }
  function fail(text){
    failedNow = true; wantPlay = false; destroyHls();
    setLoading(false); net('');
    root.classList.add('failed');
    var t = $('vxErrText'); if (t && text) t.textContent = text;
    health('bad', 'Unavailable');
    emit('failed', {});
  }
  function fmt(s){
    if (!isFinite(s) || isNaN(s) || s < 0) s = 0;
    s = Math.floor(s);
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return (h ? h + ':' + (m < 10 ? '0' : '') + m : m) + ':' + (x < 10 ? '0' : '') + x;
  }
  function parseDur(v){
    if (v == null || v === '') return 0;
    if (typeof v === 'number' || /^[0-9]+(\.[0-9]+)?$/.test(String(v).trim())) return Number(v) || 0;
    var parts = String(v).trim().split(':'), t = 0;
    for (var i = 0; i < parts.length; i++) { var p = parseInt(parts[i], 10); if (isNaN(p)) return 0; t = t * 60 + p; }
    return t;
  }
  function duration(){ var d = video.duration; if (d && isFinite(d) && d > 0) return d; return hlsDuration || apiDuration || 0; }
  function renderTime(){
    var d = duration(), c = scrubbing ? scrubTime : (video.currentTime || 0);
    if (!scrubbing && c < 0.5 && resumeAt > 1 && !playedOk) c = resumeAt;
    if (curEl) curEl.textContent = fmt(c);
    if (durEl) durEl.textContent = d ? fmt(d) : '--:--';
    if (d && prog) prog.style.width = Math.min(100, (c / d) * 100) + '%';
    if (track && d) track.setAttribute('aria-valuenow', String(Math.round((c / d) * 100)));
  }
  function renderBuffer(){
    var d = duration(); if (!d || !buf || !video.buffered || !video.buffered.length) return;
    var c = video.currentTime;
    for (var i = 0; i < video.buffered.length; i++) {
      if (video.buffered.start(i) <= c + 0.5 && c <= video.buffered.end(i)) { buf.style.width = Math.min(100, video.buffered.end(i) / d * 100) + '%'; return; }
    }
  }
  function bufferedAhead(){
    var c = video.currentTime, b = video.buffered;
    for (var i = 0; b && i < b.length; i++) if (b.start(i) <= c + 0.1 && c < b.end(i)) return b.end(i) - c;
    return 0;
  }
  function syncPlayIcons(){
    var playing = !video.paused && !video.ended;
    root.classList.toggle('playing', playing);
    if (btnPlay) { btnPlay.innerHTML = playing ? I_PAUSE : I_PLAY; btnPlay.setAttribute('aria-label', playing ? 'Pause' : 'Play'); }
    if (center) { center.innerHTML = playing ? I_PAUSE : I_PLAY; center.classList.toggle('is-pause', playing); center.setAttribute('aria-label', playing ? 'Pause' : 'Play'); }
  }
  function syncVolume(){
    var muted = video.muted || video.volume === 0;
    if (btnMute) { btnMute.innerHTML = muted ? I_MUTE : I_VOL; btnMute.setAttribute('aria-label', muted ? 'Unmute' : 'Mute'); }
    if (vol) vol.value = muted ? 0 : video.volume;
  }

  /* ---------------------------------------------------------------- hls.js loader (with CDN fallback) */
  var hlsPromise = null;
  function whenHls(){
    if (hlsPromise) return hlsPromise;
    hlsPromise = new Promise(function(resolve){
      function inject(src, cb){ var s = document.createElement('script'); s.src = src; s.async = true; s.onload = function(){ cb(true); }; s.onerror = function(){ cb(false); }; document.head.appendChild(s); }
      function done(){ if (window.Hls) return resolve(window.Hls); if (cfg.hlsFallback) inject(cfg.hlsFallback, function(){ resolve(window.Hls || null); }); else resolve(null); }
      if (window.Hls) return resolve(window.Hls);
      if (window.__hlsState === 'err') return done();
      if (window.__hlsState === 'ok') return resolve(window.Hls || null);
      var s = document.getElementById('hlsjs');
      if (!s) return done();
      var settled = false, once = function(){ if (settled) return; settled = true; done(); };
      s.addEventListener('load', once); s.addEventListener('error', once);
      setTimeout(once, 9000);
    });
    return hlsPromise;
  }

  /* ---------------------------------------------------------------- extraction */
  function waitOnline(){
    return new Promise(function(resolve){
      if (navigator.onLine !== false) return resolve();
      var on = function(){ window.removeEventListener('online', on); resolve(); };
      window.addEventListener('online', on);
    });
  }
  function extract(max, label){
    var attempt = 0;
    return new Promise(function(resolve){
      function once(){
        attempt++;
        if (label) setLoading(true, attempt > 1 ? label + ' (' + attempt + '/' + max + ')' : label);
        waitOnline().then(function(){
          var requestHeaders = { 'X-Edge-Token': TOKEN };
          if (cfg.appGrant) requestHeaders['X-Vexo-Embed-Grant'] = cfg.appGrant;
          return fetch('/api/extract?url=' + encodeURIComponent(cfg.targetUrl) + '&token=' + encodeURIComponent(TOKEN), { headers: requestHeaders, cache: 'no-store' });
        }).then(function(r){
          if (r.status === 429) { var ra = parseInt(r.headers.get('Retry-After') || '5', 10) || 5; var e = new Error('busy'); e.wait = Math.min(20, ra) * 1000; throw e; }
          return r.json();
        }).then(function(data){
          if (data && data.status === 'success' && data.streams && Array.isArray(data.streams.qualities) && data.streams.qualities.length) return resolve(data);
          if (data && data.locked) { lockedMsg = data.error || 'This provider is currently unavailable.'; return resolve(null); }
          if (data && data.code === 'session') return resolve(null);
          retry();
        }).catch(function(e){ retry(e && e.wait); });
      }
      function retry(wait){ if (attempt >= max) return resolve(null); setTimeout(once, wait || Math.min(8000, 900 * Math.pow(1.7, attempt - 1))); }
      once();
    });
  }

  function decodeUrl(x){ try { return decodeURIComponent(atob(x)); } catch (e) { return ''; } }
  function heightOf(q){ var m = String(q || '').match(/\d+/); var n = m ? parseInt(m[0], 10) : 0; if (/4k/i.test(String(q))) n = 2160; return n; }
  function proxyUrl(raw, isHls, item){
    return location.origin + (isHls ? '/proxy-m3u8' : '/proxy-video') + '?url=' + encodeURIComponent(raw) + '&sig=' + encodeURIComponent(item.x_sig || '') + '&exp=' + encodeURIComponent(item.x_exp || '');
  }
  function buildQueue(data){
    queue = []; tried = {};
    var seen = {};
    (data.streams.qualities || []).slice().sort(function(a, b){ return heightOf(b.quality) - heightOf(a.quality); }).forEach(function(q){
      var label = String(q.quality || '').replace(/[\[\]]/g, '').trim();
      if (!label || /^(source|auto)$/i.test(label) || !q.x_url) return;
      var raw = decodeUrl(q.x_url); if (!raw) return;
      var isHls = q.type === 'hls' || raw.indexOf('.m3u8') >= 0;
      var key = label + '|' + (isHls ? 'h' : 'm');
      if (seen[key]) return; seen[key] = 1;
      queue.push({ url: proxyUrl(raw, isHls, q), isHls: isHls, label: label, h: heightOf(label), visible: true });
    });
    (Array.isArray(data.streams.fallback) ? data.streams.fallback : []).forEach(function(f){
      if (!f || !f.x_url) return;
      var raw = decodeUrl(f.x_url); if (!raw) return;
      queue.push({ url: proxyUrl(raw, raw.indexOf('.m3u8') >= 0, f), isHls: raw.indexOf('.m3u8') >= 0, label: String(f.quality || 'MP4').trim(), h: heightOf(f.quality), visible: false });
    });
  }
  function capHeight(){
    if (lowData) return 480;
    var px = Math.max(screen.width || 0, screen.height || 0) * Math.min(2, window.devicePixelRatio || 1);
    /* Conservative default prevents startup flapping on high-bitrate direct MP4s. */
    return 720;
  }
  function autoIndex(){
    var cap = capHeight(), best = -1, lowest = -1;
    for (var i = 0; i < queue.length; i++) {
      var e = queue[i]; if (!e.visible) continue;
      lowest = i;
      if (best < 0 && (!e.h || e.h <= cap)) best = i;
    }
    if (best < 0) best = lowest;
    return best < 0 ? 0 : best;
  }
  function indexForLabel(label){
    for (var i = 0; i < queue.length; i++) if (queue[i].visible && queue[i].label === label) return i;
    return -1;
  }
  function startIndex(){
    if (!autoQ) { var i = indexForLabel(prefLabel); if (i >= 0) return i; }
    return autoIndex();
  }

  /* ---------------------------------------------------------------- quality ui */
  function renderQualityMenu(){
    if (qualMenu) {
      var html = '<button type="button" role="menuitemradio" data-i="auto">Auto<small id="vxAutoLbl"></small></button>';
      queue.forEach(function(e, i){ if (e.visible) html += '<button type="button" role="menuitemradio" data-i="' + i + '">' + esc(e.label) + '<small>' + (e.isHls ? 'HLS' : 'MP4') + '</small></button>'; });
      qualMenu.innerHTML = html;
      qualMenu.querySelectorAll('button').forEach(function(b){
        b.addEventListener('click', function(ev){ ev.stopPropagation(); closeMenus(); if (b.dataset.i === 'auto') chooseAuto(); else choose(+b.dataset.i); });
      });
    }
    emit('qualities', { queue: queue });
  }
  function markActive(){
    var e = queue[idx]; if (!e) return;
    if (qtag) { qtag.textContent = e.visible ? e.label : 'SD'; qtag.classList.toggle('hd', e.h >= 720); }
    if (qualMode) qualMode.textContent = autoQ ? 'Auto' : e.label;
    var al = $('vxAutoLbl'); if (al) al.textContent = autoQ ? e.label : '';
    if (qualMenu) qualMenu.querySelectorAll('button').forEach(function(b){ b.classList.toggle('on', autoQ ? b.dataset.i === 'auto' : b.dataset.i === String(idx)); });
    emit('active', { index: idx, entry: e, auto: autoQ });
  }
  function choose(i){
    if (!queue[i]) return;
    autoQ = false; prefLabel = queue[i].label;
    try { localStorage.setItem('vx_qpref', prefLabel); } catch (e) {}
    if (i === idx && !failedNow) { markActive(); return; }
    switchTo(i, 'Switching to ' + queue[i].label + '\u2026');
  }
  function chooseAuto(){
    autoQ = true; prefLabel = 'auto'; autoShifted = false;
    try { localStorage.setItem('vx_qpref', 'auto'); } catch (e) {}
    var i = autoIndex();
    if (i === idx) { markActive(); return; }
    switchTo(i, 'Switching to ' + (queue[i] ? queue[i].label : 'Auto') + '\u2026');
  }
  function switchTo(i, note){
    var at = pos() > 0 ? pos() : 0;
    if (!video.paused) wantPlay = true;
    if (note) net(note, 'busy', 2500);
    attach(i, at);
  }

  /* ---------------------------------------------------------------- attach a source */
  function destroyHls(){ if (hls) { var h = hls; hls = null; try { h.destroy(); } catch (e) {} } }
  function attach(i, at){
    var my = ++gen;
    destroyHls();
    failedNow = false; root.classList.remove('failed');
    ready = false; netFails = 0; mediaFails = 0; authHits = 0; stallStep = 0; playedOk = false; needFresh = false;
    attachedAt = Date.now(); lastProgressAt = attachedAt; lastT = -1;
    idx = i; tried[i] = true; markActive();
    var entry = queue[i];
    if (!entry) { refresh('empty'); return; }
    if (wantPlay) setLoading(true, '');
    (entry.isHls ? whenHls() : Promise.resolve(null)).then(function(Hls){
      if (my !== gen) return;
      var useJs = entry.isHls && Hls && Hls.isSupported() && !(isIOS && nativeHls);
      if (useJs) {
        video.removeAttribute('src');
        try { video.load(); } catch (e) {}
        var h = new Hls({
          enableWorker: true, lowLatencyMode: false, startPosition: at > 0 ? at : -1,
          maxBufferLength: 30, maxMaxBufferLength: 90, backBufferLength: 30, maxBufferHole: 0.5,
          nudgeMaxRetry: 6, startFragPrefetch: true, capLevelToPlayerSize: true,
          manifestLoadingTimeOut: 20000, manifestLoadingMaxRetry: 5, manifestLoadingRetryDelay: 1500,
          levelLoadingTimeOut: 20000, levelLoadingMaxRetry: 5, levelLoadingRetryDelay: 1500,
          fragLoadingTimeOut: 25000, fragLoadingMaxRetry: 8, fragLoadingRetryDelay: 1000, fragLoadingMaxRetryTimeout: 12000
        });
        hls = h;
        h.on(Hls.Events.MEDIA_ATTACHED, function(){ if (my === gen) h.loadSource(entry.url); });
        h.on(Hls.Events.MANIFEST_PARSED, function(){ if (my === gen) onReady(my); });
        h.on(Hls.Events.LEVEL_LOADED, function(ev, data){ if (my === gen && data && data.details && data.details.totalduration) { hlsDuration = data.details.totalduration; renderTime(); } });
        h.on(Hls.Events.FRAG_LOADED, function(){ if (my === gen) { netFails = 0; authHits = 0; needFresh = false; } });
        h.on(Hls.Events.ERROR, function(ev, data){ onHlsError(my, data, Hls); });
        h.attachMedia(video);
      } else if (entry.isHls && !nativeHls) {
        skip(my, 'unsupported');
      } else {
        pendingSeek = at > 0 ? at : 0;
        video.src = entry.url;
        try { video.load(); } catch (e) {}
        var meta = function(){
          video.removeEventListener('loadedmetadata', meta);
          if (my !== gen) return;
          if (pendingSeek > 0) { try { video.currentTime = pendingSeek; } catch (e) {} pendingSeek = 0; }
          onReady(my);
        };
        video.addEventListener('loadedmetadata', meta);
        if (isIOS && !wantPlay) { ready = true; setLoading(false); }
      }
    });
  }
  function onReady(my){
    if (my !== gen) return;
    ready = true;
    attachedAt = Date.now(); lastProgressAt = attachedAt; lastT = video.currentTime || 0; stallStep = 0;
    renderTime();
    emit('source-ready', { index: idx });
    if (wantPlay) doPlay(); else setLoading(false);
    if (!recovering) health('ok', 'Healthy');
  }

  /* ---------------------------------------------------------------- recovery ladder */
  function onHlsError(my, d, Hls){
    if (my !== gen || !d || !hls) return;
    var code = d.response && d.response.code;
    var D = Hls.ErrorDetails;
    var isManifest = d.details === D.MANIFEST_LOAD_ERROR || d.details === D.MANIFEST_LOAD_TIMEOUT || d.details === D.MANIFEST_PARSING_ERROR || d.details === D.LEVEL_LOAD_ERROR || d.details === D.LEVEL_LOAD_TIMEOUT;
    if (!d.fatal) {
      /* links expired while we still have buffer: fetch fresh ones once the buffer runs low */
      if (code === 401 || code === 403 || code === 410) { authHits++; if (authHits >= 2) needFresh = true; }
      return;
    }
    if (d.type === Hls.ErrorTypes.NETWORK_ERROR) {
      if (navigator.onLine === false) { offline(); return; }
      if (code === 401 || code === 403 || code === 410) { if (playedOk || started) refresh('expired'); else skip(my, 'auth'); return; }
      if (code === 404 && isManifest) { skip(my, 'gone'); return; }
      if (netFails < 5) {
        netFails++;
        recovering = true; net('Reconnecting\u2026', 'busy'); health('busy', 'Reconnecting');
        setTimeout(function(){ if (my === gen && hls) { try { hls.startLoad(pos()); } catch (e) { skip(my, 'restart'); } } }, Math.min(8000, 1800 * netFails));
        return;
      }
      if (playedOk) refresh('network'); else skip(my, 'network');
    } else if (d.type === Hls.ErrorTypes.MEDIA_ERROR) {
      if (mediaFails === 0) { mediaFails++; try { hls.recoverMediaError(); } catch (e) { skip(my, 'media'); } }
      else if (mediaFails === 1) { mediaFails++; try { hls.swapAudioCodec(); hls.recoverMediaError(); } catch (e) { skip(my, 'media'); } }
      else skip(my, 'media');
    } else {
      skip(my, 'other');
    }
  }
  /* This source is broken: try the next one (lower quality first, then MP4 fallbacks). */
  function skip(my, why){
    if (my !== gen) return;
    if (!autoQ && queue[idx]) {
      recovering = true;
      net('Reconnecting at ' + queue[idx].label + '\u2026', 'busy');
      health('busy', 'Reconnecting');
      refresh('manual-' + why);
      return;
    }
    var at = pos() > 0 ? pos() : 0;
    var next = -1, i;
    for (i = idx + 1; i < queue.length; i++) if (!tried[i]) { next = i; break; }
    if (next < 0) for (i = 0; i < queue.length; i++) if (!tried[i]) { next = i; break; }
    if (next < 0) { refresh('exhausted'); return; }
    recovering = true;
    net('Trying ' + queue[next].label + '\u2026', 'busy', 3000); health('busy', 'Switching source');
    attach(next, at);
  }
  /* Ask the backend for fresh links (they expire), keep the position and quality. */
  function refresh(reason){
    if (refreshing) return;
    if (lockedMsg) { fail(lockedMsg); return; }
    var now = Date.now();
    refreshLog = refreshLog.filter(function(t){ return now - t < 180000; });
    if (refreshLog.length >= 6) { giveUp(); return; }
    refreshLog.push(now);
    refreshing = true; recovering = true;
    var at = pos() > 0 ? pos() : 0, keep = queue[idx] && queue[idx].label;
    if (at > 0) resumeAt = at;
    gen++; destroyHls();
    setLoading(true, ''); net('Reconnecting\u2026', 'busy'); health('busy', 'Reconnecting');
    var delay = refreshLog.length === 1 ? 150 : Math.min(8000, 1300 * (refreshLog.length - 1));
    setTimeout(function(){
      extract(3).then(function(data){
        refreshing = false;
        if (!data) { if (lockedMsg) { fail(lockedMsg); return; } refresh(reason); return; }
        if (data.duration) apiDuration = parseDur(data.duration) || apiDuration;
        buildQueue(data); renderQualityMenu();
        if (!queue.length) { refresh(reason); return; }
        var i = keep ? indexForLabel(keep) : -1;
        if (keep && !autoQ && i < 0) {
          fail('The selected quality (' + keep + ') is no longer available. Choose Auto or another quality.');
          return;
        }
        if (i < 0) i = startIndex();
        attach(i, resumeAt);
      });
    }, delay);
  }
  function giveUp(){
    fail('Could not reconnect after several attempts. Check your connection and the video source, then tap Try again.');
  }
  function offline(){ net('You\u2019re offline. Waiting for connection\u2026', 'off'); health('bad', 'Offline'); }
  window.addEventListener('offline', offline);
  window.addEventListener('online', function(){
    net('Back online', 'ok', 1600); health('ok', 'Healthy');
    lastProgressAt = Date.now(); stallStep = 0;
    if (hls && wantPlay) { try { hls.startLoad(pos()); } catch (e) {} }
    else if (!hls && wantPlay && idx >= 0 && !refreshing) attach(idx, video.currentTime || resumeAt);
  });

  /* Native <video> (MP4, Safari HLS) errors */
  video.addEventListener('error', function(){
    if (hls || idx < 0 || !queue.length || !video.getAttribute('src')) return;
    var code = video.error && video.error.code, my = gen;
    var n = nativeFails[idx] = (nativeFails[idx] || 0) + 1;
    if (navigator.onLine === false) { offline(); return; }
    if (code === 2 && n <= 3) { recovering = true; net('Reconnecting\u2026', 'busy'); var t = video.currentTime || resumeAt; setTimeout(function(){ if (my === gen) attach(idx, t); }, Math.min(6000, 1800 * n)); return; }
    if (playedOk) refresh('native'); else skip(my, 'native');
  });

  /* Stall watchdog: nudge, reload, step quality down, then fetch fresh links. */
  function lowerIndex(){
    var cur = queue[idx]; if (!cur) return -1;
    for (var i = idx + 1; i < queue.length; i++) if (queue[i].visible && queue[i].h && cur.h && queue[i].h < cur.h) return i;
    return -1;
  }
  function downshift(why){
    var j = lowerIndex(); if (j < 0 || autoShifted) return false;
    autoShifted = true;
    net('Switching to ' + queue[j].label + ' for smoother playback', 'busy', 3200);
    attach(j, pos() > 0 ? pos() : 0);
    return true;
  }
  function gapJump(){
    var c = video.currentTime, b = video.buffered;
    for (var i = 0; b && i < b.length; i++) {
      if (b.start(i) > c && b.start(i) - c < 3) { try { video.currentTime = b.start(i) + 0.05; } catch (e) {} return; }
    }
    if (bufferedAhead() > 0.5) { try { video.currentTime = c + 0.01; } catch (e) {} }
  }
  function pos(){ return video.currentTime > 0.5 ? video.currentTime : (resumeAt > 0 ? resumeAt : -1); }
  function kick(){
    var t = pos(); if (t < 0) t = 0;
    if (hls) { try { hls.stopLoad(); hls.startLoad(t); } catch (e) {} }
    else if (idx >= 0) attach(idx, t);
  }
  setInterval(function(){
    if (!ready || !wantPlay || video.paused || video.ended || scrubbing || failedNow || refreshing || video.seeking && Date.now() - lastProgressAt < 8000) { if (!wantPlay || video.paused) lastProgressAt = Date.now(); return; }
    var t = video.currentTime;
    if (needFresh && bufferedAhead() < 6 && !refreshing) { needFresh = false; refresh('expired'); return; }
    if (lastT < 0) { lastT = t; lastProgressAt = Date.now(); return; }
    if (Math.abs(t - lastT) > 0.01) {
      lastT = t; lastProgressAt = Date.now();
      if (stallStep || recovering) { stallStep = 0; if (recovering) { recovering = false; net('Reconnected', 'ok', 1400); health('ok', 'Healthy'); } }
      return;
    }
    if (navigator.onLine === false) { offline(); lastProgressAt = Date.now(); return; }
    var stuck = Date.now() - lastProgressAt;
    /* Don't punish a slow manifest/startup: begin recovery only after playback had time to settle. */
    if (Date.now() - attachedAt < 12000) return;
    if (stuck > 6000 && stallStep < 1) { stallStep = 1; gapJump(); }
    else if (stuck > 12000 && stallStep < 2) { stallStep = 2; recovering = true; net('Reconnecting\u2026', 'busy'); health('busy', 'Reconnecting'); kick(); }
    else if (stuck > 30000 && stallStep < 3) { stallStep = 3; if (!(autoQ && downshift('stall'))) refresh('stall'); }
    else if (stuck > 45000 && stallStep < 4) { stallStep = 4; refresh('stall'); }
  }, 1000);

  /* ---------------------------------------------------------------- play / pause */
  function doPlay(){
    wantPlay = true;
    if (failedNow) return;
    if (!ready && !(isIOS && video.getAttribute('src'))) { setLoading(true, ''); return; }
    var p;
    try { p = video.play(); } catch (e) { p = null; }
    if (p && p.catch) p.catch(function(err){
      var name = err && err.name;
      if (name === 'AbortError') return;
      if (name === 'NotAllowedError') {
        if (!video.muted) {
          video.muted = true; syncVolume();
          video.play().then(function(){ net('Playing muted. Tap the speaker to unmute.', 'ok', 3500); }).catch(function(){ wantPlay = false; setLoading(false); syncPlayIcons(); });
        } else { wantPlay = false; setLoading(false); syncPlayIcons(); }
        return;
      }
      if (name === 'NotSupportedError') skip(gen, 'notsupported');
    });
  }
  function toggle(){
    if (failedNow) return;
    if (video.paused || video.ended) doPlay(); else { wantPlay = false; video.pause(); }
  }
  function seekBy(s){ var d = duration(); if (!d) return; video.currentTime = Math.max(0, Math.min(d - 0.2, (video.currentTime || 0) + s)); renderTime(); wake(); }
  function ripple(side){ var el = $(side < 0 ? 'vxRipL' : 'vxRipR'); if (!el) return; el.classList.remove('go'); void el.offsetWidth; el.classList.add('go'); }

  video.addEventListener('play', function(){ started = true; root.classList.add('started'); syncPlayIcons(); wake(); });
  video.addEventListener('pause', function(){ syncPlayIcons(); wake(); saveProgress(true); });
  video.addEventListener('ended', function(){ wantPlay = false; syncPlayIcons(); wake(); saveProgress(true); });
  video.addEventListener('waiting', function(){
    if (!wantPlay) return;
    waitStart = Date.now();
    clearTimeout(waitTimer); waitTimer = setTimeout(function(){ if (wantPlay && video.readyState < 3) setLoading(true, ''); }, 350);
  });
  video.addEventListener('playing', function(){
    clearTimeout(waitTimer);
    try { sessionStorage.removeItem('vx_reload_' + location.pathname + location.search); } catch (e) {}
    playedOk = true; setLoading(false); syncPlayIcons();
    if (waitStart) {
      var dur = Date.now() - waitStart; waitStart = 0;
      lastProgressAt = Date.now(); lastT = video.currentTime || 0;
      if (dur > 2500 && started) {
        var now = Date.now(); slowLog = slowLog.filter(function(t){ return now - t < 60000; }); slowLog.push(now);
        if (slowLog.length >= 4 && autoQ && lowerIndex() >= 0) { slowLog = []; downshift('buffering'); }
      }
    }
  });
  video.addEventListener('canplay', function(){ if (wantPlay && video.paused && ready && !failedNow) doPlay(); else if (!wantPlay) setLoading(false); });
  video.addEventListener('timeupdate', function(){ if (ready && video.currentTime > 0.5 && !video.seeking) resumeAt = video.currentTime; if (!scrubbing) renderTime(); renderBuffer(); if (root.classList.contains('loading') && !video.paused && bufferedAhead() > 0.3) setLoading(false); saveProgress(false); });
  video.addEventListener('progress', renderBuffer);
  video.addEventListener('durationchange', renderTime);
  video.addEventListener('loadedmetadata', renderTime);
  video.addEventListener('volumechange', function(){ syncVolume(); try { localStorage.setItem('vx_vol', String(video.volume)); localStorage.setItem('vx_muted', video.muted ? '1' : '0'); } catch (e) {} });

  if (center) center.addEventListener('click', function(e){ e.stopPropagation(); center.classList.remove('tap'); void center.offsetWidth; center.classList.add('tap'); toggle(); });
  if (btnPlay) btnPlay.addEventListener('click', function(e){ e.stopPropagation(); toggle(); });
  var back = $('vxBack'), fwd = $('vxFwd');
  if (back) back.addEventListener('click', function(e){ e.stopPropagation(); seekBy(-10); ripple(-1); });
  if (fwd) fwd.addEventListener('click', function(e){ e.stopPropagation(); seekBy(10); ripple(1); });
  var retryBtn = $('vxRetry');
  if (retryBtn) retryBtn.addEventListener('click', function(){
    lockedMsg = ''; refreshLog = []; failedNow = false; wantPlay = true;
    root.classList.remove('failed');
    try { sessionStorage.removeItem('vx_reload_' + location.pathname + location.search); } catch (e) {}
    if (!queue.length) boot(); else refresh('retry');
  });

  /* ---------------------------------------------------------------- history + resume */
  var lastSave = 0;
  function saveProgress(force){
    if (cfg.mode !== 'watch' || !window.VXHistory || !started) return;
    var now = Date.now(); if (!force && now - lastSave < 5000) return; lastSave = now;
    var t = video.currentTime || 0, d = duration();
    VXHistory.save({ u: cfg.targetUrl, e: cfg.enc, p: Math.floor(t), d: Math.floor(d || 0), t: title, th: thumbRaw, pv: provider });
  }
  window.addEventListener('pagehide', function(){ saveProgress(true); });
  function initResume(){
    try { if (sessionStorage.getItem('vx_autoplay_' + location.pathname) === '1') { sessionStorage.removeItem('vx_autoplay_' + location.pathname); wantPlay = true; } } catch (e) {}
    try { var rs = parseFloat(sessionStorage.getItem('vx_resume_' + location.pathname) || ''); if (rs > 0) { resumeAt = rs; sessionStorage.removeItem('vx_resume_' + location.pathname); return; } } catch (e) {}
    if (cfg.mode !== 'watch' || !window.VXHistory) return;
    var h = VXHistory.get(cfg.targetUrl);
    if (h && h.p > 10 && (!h.d || h.p < h.d - 15)) {
      resumeAt = h.p;
      if (resumeEl) {
        resumeText.textContent = 'Resuming at ' + fmt(h.p);
        resumeEl.classList.add('show');
        setTimeout(function(){ resumeEl.classList.remove('show'); }, 7000);
        $('vxRestart').addEventListener('click', function(e){ e.stopPropagation(); resumeAt = 0; resumeEl.classList.remove('show'); try { video.currentTime = 0.01; } catch (x) {} pendingSeek = 0; renderTime(); });
      }
    }
  }

  /* ---------------------------------------------------------------- picture area */
  var lastTap = 0, tapTimer = null;
  if (hit) {
    hit.addEventListener('pointerdown', function(e){
      if (e.button && e.button !== 0) return;
      suppressClick = false;
      clearTimeout(holdTimer);
      holdTimer = setTimeout(function(){
        if (video.paused) return;
        holding = true; suppressClick = true;
        video.playbackRate = 2; root.classList.add('fast');
      }, 380);
    });
    var endHold = function(){ clearTimeout(holdTimer); if (holding) { holding = false; video.playbackRate = userRate; root.classList.remove('fast'); } };
    hit.addEventListener('pointerup', endHold);
    hit.addEventListener('pointercancel', endHold);
    hit.addEventListener('pointerleave', endHold);
    hit.addEventListener('click', function(e){
      if (suppressClick) { suppressClick = false; return; }
      if (closeMenus()) return;
      var touch = e.pointerType === 'touch' || (window.matchMedia && matchMedia('(hover: none)').matches);
      if (!touch) { toggle(); return; }
      var now = Date.now(), rect = root.getBoundingClientRect(), x = (e.clientX - rect.left) / rect.width;
      if (now - lastTap < 300 && started) {
        clearTimeout(tapTimer); lastTap = 0;
        if (x < 0.4) { seekBy(-10); ripple(-1); } else if (x > 0.6) { seekBy(10); ripple(1); } else toggle();
        return;
      }
      lastTap = now;
      tapTimer = setTimeout(function(){
        if (!started) toggle();
        else if (root.classList.contains('idle')) wake(); else root.classList.add('idle');
      }, 260);
    });
    hit.addEventListener('dblclick', function(){ if (window.matchMedia && matchMedia('(hover: none)').matches) return; toggleFs(); });
  }

  function wake(){
    root.classList.remove('idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(function(){ if (!video.paused && !scrubbing && !root.querySelector('.vx-menu.open')) root.classList.add('idle'); }, 2800);
  }
  root.addEventListener('pointermove', function(e){ if (e.pointerType !== 'touch') wake(); });
  root.addEventListener('focusin', wake);

  /* ---------------------------------------------------------------- seek preview (desktop hover only) */
  function placeHover(p){
    if (!hover || !track) return;
    var tw = track.clientWidth || 1, hw = hover.offsetWidth || 0;
    var x = p * tw, half = hw / 2;
    if (hw && tw > hw) x = Math.max(half, Math.min(tw - half, x));
    hover.style.left = x + 'px';
  }
  var finePointer = !!(window.matchMedia && matchMedia('(hover: hover) and (pointer: fine)').matches);
  var preview = (function(){
    var pv = null, pvHls = null, state = 'idle', entry = null;
    var busy = false, pending = -1, lastBucket = -1, wantBucket = -1, cache = {}, order = [], MAX = 160;
    var ctx = thumbCanvas && thumbCanvas.getContext ? thumbCanvas.getContext('2d') : null;
    var painted = false;
    function enabled(){ return !!(finePointer && ctx && thumbBox && !lowData && state !== 'dead' && playedOk); }
    function stepFor(d){ return d > 3600 ? 10 : d > 900 ? 5 : d > 240 ? 2 : 1; }
    function sizeCanvas(){
      if (!pv || !pv.videoWidth) return;
      var w = 168, ar = pv.videoHeight / pv.videoWidth;
      var h = Math.round(Math.max(0.42, Math.min(1.78, ar)) * w);
      var dpr = Math.min(2, window.devicePixelRatio || 1);
      thumbCanvas.width = Math.round(w * dpr); thumbCanvas.height = Math.round(h * dpr);
      thumbBox.style.width = w + 'px'; thumbBox.style.height = h + 'px';
    }
    function pickEntry(){
      var best = null;
      queue.forEach(function(e){
        if (!e || !e.url) return;
        if (e.isHls && !(window.Hls && window.Hls.isSupported())) return;
        var h = e.h || 9999;
        if (!best || h < best.h || (h === best.h && !e.isHls && best.e.isHls)) best = { e: e, h: h };
      });
      return best ? best.e : null;
    }
    function kill(){
      if (pvHls) { try { pvHls.destroy(); } catch (e) {} pvHls = null; }
      if (pv) { try { pv.removeAttribute('src'); pv.load(); pv.remove(); } catch (e) {} pv = null; }
    }
    function die(){ state = 'dead'; kill(); root.classList.remove('vx-has-thumb'); }
    function warm(){
      if (!enabled() || state !== 'idle' || !queue.length) return;
      entry = pickEntry(); if (!entry) return die();
      state = 'loading';
      pv = document.createElement('video');
      pv.muted = true; pv.defaultMuted = true; pv.playsInline = true; pv.preload = 'auto';
      pv.setAttribute('muted', ''); pv.setAttribute('playsinline', ''); pv.setAttribute('aria-hidden', 'true'); pv.tabIndex = -1;
      pv.className = 'vx-pv';
      root.appendChild(pv);
      pv.addEventListener('loadeddata', function(){ if (state !== 'loading') return; state = 'ready'; sizeCanvas(); if (wantBucket >= 0) request(wantBucket); });
      pv.addEventListener('seeked', onSeeked);
      pv.addEventListener('error', function(){ if (!pvHls) die(); });
      var Hls = window.Hls;
      if (entry.isHls && Hls && Hls.isSupported()) {
        pvHls = new Hls({ enableWorker: true, startLevel: 0, autoStartLoad: true, capLevelToPlayerSize: false, maxBufferLength: 2, maxMaxBufferLength: 4, maxBufferSize: 4000000, backBufferLength: 0, fragLoadingMaxRetry: 1, manifestLoadingMaxRetry: 1, levelLoadingMaxRetry: 1 });
        pvHls.on(Hls.Events.MANIFEST_PARSED, function(){ try { pvHls.currentLevel = 0; pvHls.autoLevelCapping = 0; } catch (e) {} });
        pvHls.on(Hls.Events.ERROR, function(ev, data){ if (data && data.fatal) die(); });
        pvHls.loadSource(entry.url);
        pvHls.attachMedia(pv);
      } else { pv.src = entry.url; try { pv.load(); } catch (e) {} }
      setTimeout(function(){ if (state === 'loading') die(); }, 20000);
    }
    function remember(b){
      if (cache[b]) return;
      try {
        var c = document.createElement('canvas'); c.width = thumbCanvas.width; c.height = thumbCanvas.height;
        c.getContext('2d').drawImage(pv, 0, 0, c.width, c.height);
        cache[b] = c; order.push(b);
        if (order.length > MAX) delete cache[order.shift()];
      } catch (e) { die(); }
    }
    function paint(src){
      try { ctx.drawImage(src, 0, 0, thumbCanvas.width, thumbCanvas.height); painted = true; root.classList.add('vx-has-thumb'); thumbBox.classList.remove('stale'); }
      catch (e) { die(); }
    }
    function request(b){
      if (state !== 'ready' || !pv) return;
      if (busy) { pending = b; return; }
      var d = duration(); if (!d) return;
      busy = true; pending = -1;
      var t = Math.min(Math.max(0, d - 0.3), b * stepFor(d) + 0.05);
      try { pv.currentTime = t; } catch (e) { busy = false; }
      pv.__bucket = b;
      clearTimeout(pv.__guard);
      pv.__guard = setTimeout(function(){ busy = false; if (pending >= 0) request(pending); }, 4000);
    }
    function onSeeked(){
      if (!pv) return;
      clearTimeout(pv.__guard);
      busy = false;
      var b = pv.__bucket;
      if (!thumbCanvas.width) sizeCanvas();
      if (b >= 0) { remember(b); if (b === wantBucket && cache[b]) paint(cache[b]); }
      if (pending >= 0 && pending !== b) { var n = pending; pending = -1; request(n); }
    }
    function show(t){
      if (!enabled()) return;
      if (state === 'idle') warm();
      if (state === 'dead') return;
      var d = duration(); if (!d) return;
      var b = Math.floor(t / stepFor(d));
      wantBucket = b;
      if (b === lastBucket) return;
      lastBucket = b;
      if (cache[b]) { paint(cache[b]); return; }
      if (painted) thumbBox.classList.add('stale');
      request(b);
    }
    function hide(){ wantBucket = -1; lastBucket = -1; pending = -1; }
    window.addEventListener('resize', function(){ if (state === 'ready') { cache = {}; order = []; sizeCanvas(); lastBucket = -1; } });
    window.addEventListener('pagehide', kill);
    document.addEventListener('vx:failed', die);
    return { show: show, hide: hide };
  })();

  /* ---------------------------------------------------------------- scrubbing */
  function pctFromEvent(e){ var r = track.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); }
  if (track) {
    track.addEventListener('pointerdown', function(e){
      var d = duration(); if (!d) return;
      scrubbing = true; track.classList.add('drag');
      try { track.setPointerCapture(e.pointerId); } catch (x) {}
      scrubTime = pctFromEvent(e) * d; renderTime();
    });
    track.addEventListener('pointermove', function(e){
      var d = duration(); if (!d) return;
      var p = pctFromEvent(e);
      if (hoverTime) hoverTime.textContent = fmt(p * d);
      if (e.pointerType !== 'touch') preview.show(p * d);
      placeHover(p);
      if (scrubbing) { scrubTime = p * d; renderTime(); }
    });
    track.addEventListener('pointerleave', function(){ preview.hide(); });
    var endScrub = function(){ if (!scrubbing) return; scrubbing = false; track.classList.remove('drag'); try { video.currentTime = scrubTime; } catch (x) {} lastProgressAt = Date.now(); renderTime(); wake(); };
    track.addEventListener('pointerup', endScrub);
    track.addEventListener('pointercancel', endScrub);
    track.addEventListener('keydown', function(e){
      if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); seekBy(-5); }
      if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); seekBy(5); }
    });
  }
  video.addEventListener('seeking', function(){ lastProgressAt = Date.now(); });

  /* ---------------------------------------------------------------- volume */
  try {
    var sv = parseFloat(localStorage.getItem('vx_vol'));
    if (!isNaN(sv) && sv >= 0 && sv <= 1) video.volume = sv;
    if (localStorage.getItem('vx_muted') === '1') video.muted = true;
  } catch (e) {}
  syncVolume();
  var lastVol = video.volume || 1;
  if (btnMute) btnMute.addEventListener('click', function(e){
    e.stopPropagation();
    if (video.muted || video.volume === 0) { video.muted = false; if (video.volume === 0) video.volume = lastVol || 1; }
    else { lastVol = video.volume; video.muted = true; }
  });
  if (vol) vol.addEventListener('input', function(){ var v = parseFloat(vol.value); video.volume = v; video.muted = v === 0; if (v > 0) lastVol = v; });

  /* ---------------------------------------------------------------- settings menu */
  function closeMenus(){
    if (setMenu && setMenu.classList.contains('open')) { setMenu.classList.remove('open'); if (setBtn) setBtn.setAttribute('aria-expanded', 'false'); return true; }
    return false;
  }
  if (setBtn && setMenu) setBtn.addEventListener('click', function(e){
    e.stopPropagation();
    var open = !setMenu.classList.contains('open');
    closeMenus();
    if (open) { setMenu.classList.add('open'); setBtn.setAttribute('aria-expanded', 'true'); wake(); }
  });
  if (qtag) { qtag.style.cursor = 'pointer'; qtag.addEventListener('click', function(e){ e.stopPropagation(); if (setBtn) setBtn.click(); }); }
  if (speedMenu) speedMenu.querySelectorAll('button[data-speed]').forEach(function(b){
    b.addEventListener('click', function(e){
      e.stopPropagation();
      userRate = parseFloat(b.dataset.speed) || 1;
      video.playbackRate = userRate;
      speedMenu.querySelectorAll('button').forEach(function(x){ x.classList.toggle('on', x === b); });
    });
  });
  document.addEventListener('click', function(e){ if (!e.target.closest || !e.target.closest('.vx-wrap-menu')) closeMenus(); });

  /* ---------------------------------------------------------------- fullscreen, pip, theater */
  function fsEl(){ return document.fullscreenElement || document.webkitFullscreenElement; }
  function toggleFs(){
    if (fsEl()) { (document.exitFullscreen || document.webkitExitFullscreen).call(document); return; }
    var req = root.requestFullscreen || root.webkitRequestFullscreen;
    if (req) { var r = req.call(root); if (r && r.catch) r.catch(function(){}); try { if (screen.orientation && screen.orientation.lock && video.videoWidth > video.videoHeight) screen.orientation.lock('landscape').catch(function(){}); } catch (e) {} }
    else if (video.webkitEnterFullscreen) video.webkitEnterFullscreen();
  }
  if (btnFs) btnFs.addEventListener('click', function(e){ e.stopPropagation(); toggleFs(); });
  var onFs = function(){ var on = !!fsEl(); if (btnFs) { btnFs.innerHTML = on ? I_FS_EXIT : I_FS; btnFs.setAttribute('aria-label', on ? 'Exit full screen' : 'Full screen'); } };
  document.addEventListener('fullscreenchange', onFs);
  document.addEventListener('webkitfullscreenchange', onFs);
  if (btnPip && document.pictureInPictureEnabled) {
    btnPip.hidden = false;
    btnPip.addEventListener('click', function(e){
      e.stopPropagation();
      if (document.pictureInPictureElement) document.exitPictureInPicture().catch(function(){});
      else video.requestPictureInPicture().catch(function(){});
    });
  }
  function setTheater(on){
    document.body.classList.toggle('theater', on);
    if (btnTheater) btnTheater.setAttribute('aria-pressed', String(on));
    try { localStorage.setItem('vx_theater', on ? '1' : '0'); } catch (e) {}
  }
  if (btnTheater) {
    btnTheater.setAttribute('aria-pressed', String(document.body.classList.contains('theater')));
    btnTheater.addEventListener('click', function(e){ e.stopPropagation(); setTheater(!document.body.classList.contains('theater')); });
  }

  /* ---------------------------------------------------------------- keyboard */
  document.addEventListener('keydown', function(e){
    var t = e.target, tag = t && t.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (t && t.isContentEditable)) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (document.querySelector('.sheet.open, .age.show')) return;
    var k = e.key.toLowerCase(), handled = true;
    if (k === ' ' || k === 'k') { if (tag === 'BUTTON' && k === ' ') return; toggle(); }
    else if (k === 'arrowleft') seekBy(-5);
    else if (k === 'arrowright') seekBy(5);
    else if (k === 'j') { seekBy(-10); ripple(-1); }
    else if (k === 'l') { seekBy(10); ripple(1); }
    else if (k === 'arrowup') { video.muted = false; video.volume = Math.min(1, video.volume + 0.1); }
    else if (k === 'arrowdown') { video.volume = Math.max(0, video.volume - 0.1); }
    else if (k === 'm') { if (btnMute) btnMute.click(); }
    else if (k === 'f') toggleFs();
    else if (k === 't' && btnTheater) setTheater(!document.body.classList.contains('theater'));
    else if (k === 'escape') { if (!closeMenus()) handled = false; }
    else handled = false;
    if (handled) { e.preventDefault(); wake(); }
  });

  /* ---------------------------------------------------------------- boot */
  function imageCandidates(value, out, seen, depth){
    out = out || []; seen = seen || {}; depth = depth || 0;
    if (depth > 3 || value == null) return out;
    if (Array.isArray(value)) { value.slice(0, 12).forEach(function(v){ imageCandidates(v, out, seen, depth + 1); }); return out; }
    if (typeof value === 'object') {
      ['url','src','image','image_url','thumbnail','thumbnail_url','thumb','thumb_url','thumbs','poster','poster_url','default_thumb','cover_image','preview_image'].forEach(function(k){
        if (value[k] != null) imageCandidates(value[k], out, seen, depth + 1);
      });
      return out;
    }
    var raw = String(value).trim();
    if (!raw || raw.length > 2048 || /(?:blank|placeholder|default)\.gif(?:[?#]|$)/i.test(raw)) return out;
    if (raw.indexOf('//') === 0) raw = 'https:' + raw;
    try {
      var u = new URL(raw, location.href);
      if ((u.protocol !== 'http:' && u.protocol !== 'https:') || !u.hostname || u.username || u.password) return out;
      if (/\.(?:mp4|m3u8|webm|m4s|ts)(?:$|[?#])/i.test(u.pathname)) return out;
      raw = u.toString();
      if (!seen[raw]) { seen[raw] = true; out.push(raw); }
    } catch (_) {}
    return out;
  }
  function thumbnailCandidates(data){
    var out = [], seen = {};
    if (typeof data === 'string' || Array.isArray(data)) return imageCandidates(data, out, seen);
    if (!data || typeof data !== 'object') return out;
    ['thumbnail','thumbnail_url','thumb','thumb_url','poster','poster_url','image','image_url','default_thumb','cover','cover_image','preview','preview_image','images','thumbnails','thumbs']
      .forEach(function(k){ if (data[k] != null) imageCandidates(data[k], out, seen); });
    return out.slice(0, 8);
  }
  function setPoster(values, rank){
    if (!poster) return;
    var list = thumbnailCandidates(values);
    if (!list.length || rank < posterLoadedRank) return;
    list.forEach(function(raw){
      if (posterAttempted[raw]) return;
      posterAttempted[raw] = true;
      var src = '/proxy-image?url=' + encodeURIComponent(raw) + '&token=' + encodeURIComponent(TOKEN);
      var img = new Image();
      img.onload = function(){
        if (rank < posterLoadedRank) return;
        posterLoadedRank = rank;
        poster.style.backgroundImage = 'url("' + src + '")';
        if ('mediaSession' in navigator) cfg.artwork = location.origin + src;
      };
      img.onerror = function(){};
      img.src = src;
    });
  }
  function resolvePosterFromSite(){
    if (!cfg.targetUrl) return;
    var url = '/api/posters?u=' + encodeURIComponent(cfg.targetUrl) + '&token=' + encodeURIComponent(TOKEN);
    fetch(url, { headers: { 'X-Edge-Token': TOKEN }, cache: 'no-store' })
      .then(function(r){ return r.ok ? r.json() : null; })
      .then(function(data){
        if (!data) return;
        var posters = data.posters || {};
        setPoster(posters[cfg.targetUrl] || data.thumbnail || data.poster || '', 2);
      })
      .catch(function(){});
  }
  function mediaSession(t){
    if (!('mediaSession' in navigator)) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({ title: t || 'VexoStream', artist: 'VexoStream', artwork: cfg.artwork ? [{ src: cfg.artwork, sizes: '1280x720', type: 'image/jpeg' }] : [] });
      navigator.mediaSession.setActionHandler('play', doPlay);
      navigator.mediaSession.setActionHandler('pause', function(){ wantPlay = false; video.pause(); });
      navigator.mediaSession.setActionHandler('seekbackward', function(){ seekBy(-10); });
      navigator.mediaSession.setActionHandler('seekforward', function(){ seekBy(10); });
    } catch (e) {}
  }
  function boot(){
    setLoading(true, 'Finding streams\u2026'); health('busy', 'Connecting');
    whenHls();
    setPoster(thumbRaw, 3);
    resolvePosterFromSite();
    extract(5, 'Finding streams\u2026').then(function(data){
      if (!data) { fail(lockedMsg || 'The source didn\u2019t return any streams. Check that the video is public.'); emit('meta', null); return; }
      if (data.duration) { apiDuration = parseDur(data.duration); renderTime(); }
      title = data.title || ''; provider = String(data.provider || '');
      var extractedThumbs = thumbnailCandidates(data);
      if (!thumbRaw && extractedThumbs.length) thumbRaw = extractedThumbs[0];
      setPoster(extractedThumbs, 1);
      mediaSession(data.title);
      buildQueue(data);
      renderQualityMenu();
      emit('meta', data);
      if (!queue.length) { fail('No playable streams were found for this video.'); return; }
      if (/[?&]autoplay=1/.test(location.search)) { video.muted = true; wantPlay = true; }
      attach(startIndex(), resumeAt);
      if (!wantPlay) setLoading(false);
    });
  }
  syncPlayIcons();
  if (!cfg.targetUrl) { fail('No video link was given.'); return; }
  initResume();
  boot();
})();
`;

const WATCH_JS = String.raw`
(function(){
  var cfg = window.VX.player;
  var titleEl = document.getElementById('videoTitle');
  var metaEl = document.getElementById('videoMeta');
  var grid = document.getElementById('qualityButtonsGrid');
  var healthEl = document.getElementById('vxHealth');
  var modal = document.getElementById('embedModal');
  var codeEl = document.getElementById('embedCodeText');
  var upNext = document.getElementById('upNext'), upCard = document.getElementById('upNextCard');
  var snippet = 'iframe';

  document.addEventListener('vx:health', function(e){
    if (!healthEl || !e.detail) return;
    healthEl.setAttribute('data-s', e.detail.state);
    healthEl.querySelector('span').textContent = e.detail.text || '';
  });
  document.addEventListener('vx:meta', function(e){
    var d = e.detail;
    if (!d) {
      if (titleEl) { titleEl.textContent = 'Video unavailable'; titleEl.classList.remove('pending'); }
      if (grid) grid.innerHTML = '<span>No streams available.</span>';
      if (upCard) upCard.hidden = true;
      return;
    }
    var title = d.title || 'Untitled video';
    if (titleEl) { titleEl.textContent = title; titleEl.classList.remove('pending'); }
    document.title = title + ' \u2014 VexoStream';
    var prov = String(d.provider || vxProviderOf(cfg.targetUrl) || '');
    if (metaEl) {
      var bits = [];
      if (prov) bits.push('<a class="tag" href="/browse/' + encodeURIComponent(vxProviderOf(prov) || prov.toLowerCase()) + '">' + escapeHtml(prov) + '</a>');
      var dur = vxDur(d.duration); if (dur) bits.push('<span class="tag">' + escapeHtml(dur) + '</span>');
      metaEl.innerHTML = bits.join('');
    }
    loadUpNext(title, vxProviderOf(prov) || vxProviderOf(cfg.targetUrl));
  });
  function paintQualities(){
    if (!grid || !window.VXPlayer) return;
    var q = VXPlayer.queue(), cur = VXPlayer.current(), auto = VXPlayer.isAuto();
    grid.innerHTML = '';
    var a = document.createElement('button');
    a.type = 'button'; a.className = 'qbtn' + (auto ? ' on' : ''); a.innerHTML = 'Auto <small>' + (auto && q[cur] ? escapeHtml(q[cur].label) : 'ABR') + '</small>';
    a.addEventListener('click', function(){ VXPlayer.auto(); });
    grid.appendChild(a);
    q.forEach(function(entry, i){
      if (!entry.visible) return;
      var b = document.createElement('button');
      b.type = 'button'; b.className = 'qbtn' + (!auto && i === cur ? ' on' : '');
      b.innerHTML = escapeHtml(entry.label) + ' <small>' + (entry.isHls ? 'HLS' : 'MP4') + '</small>';
      b.addEventListener('click', function(){ VXPlayer.select(i); });
      grid.appendChild(b);
    });
  }
  document.addEventListener('vx:qualities', paintQualities);
  document.addEventListener('vx:active', paintQualities);
  document.addEventListener('vx:failed', function(){
    if (titleEl && titleEl.classList.contains('pending')) { titleEl.textContent = 'Video unavailable'; titleEl.classList.remove('pending'); }
  });

  /* ---------- more like this ---------- */
  function loadUpNext(title, provider){
    if (!upNext || !provider) { if (upCard) upCard.hidden = true; return; }
    var words = String(title || '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter(function(w){ return w.length > 3; }).slice(0, 3).join(' ');
    var q = words || 'trending';
    fetch('/api/explore?q=' + encodeURIComponent(q) + '&page=1&provider=' + encodeURIComponent(provider), { headers: { 'X-Edge-Token': window.VX.token } })
      .then(function(r){ if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(function(list){
        var items = vxUsable(list).filter(function(it){ return it.url !== cfg.targetUrl; }).slice(0, 8);
        if (!items.length) { upCard.hidden = true; return; }
        upNext.innerHTML = '';
        items.forEach(function(it){
          var a = document.createElement('a');
          a.className = 'unext'; a.href = '/video/' + b64url(it.url);
          var dur = vxDur(it.duration);
          a.innerHTML = '<div class="vthumb"><img loading="lazy" decoding="async" alt="">' + (dur ? '<span class="vdur">' + escapeHtml(dur) + '</span>' : '') + '</div><div><b>' + escapeHtml(it.title || 'Untitled video') + '</b><small>' + escapeHtml(it.provider || provider) + '</small></div>';
          vxThumb(a, it);
          a.addEventListener('click', function(){ if (window.TopLoader) TopLoader.start(); });
          upNext.appendChild(a);
        });
      })
      .catch(function(){ if (upCard) upCard.hidden = true; });
  }

  /* ---------- share + embed ---------- */
  function embedUrl(){ return location.origin + '/embed/' + cfg.enc; }
  function renderCode(){
    var code = snippet === 'iframe'
      ? '<div style="position:relative;padding-top:56.25%">\n  <iframe src="' + embedUrl() + '" style="position:absolute;inset:0;width:100%;height:100%;border:0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>\n</div>'
      : '<script src="' + location.origin + '/embed.js"><\/script>\n<vexo-player src="' + cfg.targetUrl.replace(/"/g, '&quot;') + '"></vexo-player>';
    if (codeEl) codeEl.textContent = code;
    document.getElementById('tabIframe').setAttribute('aria-pressed', String(snippet === 'iframe'));
    document.getElementById('tabSdk').setAttribute('aria-pressed', String(snippet !== 'iframe'));
  }
  function open(){ renderCode(); modal.classList.add('open'); var x = document.getElementById('btnCloseEmbed'); if (x) x.focus(); }
  function close(){ modal.classList.remove('open'); var b = document.getElementById('btnOpenEmbed'); if (b) b.focus(); }
  document.getElementById('btnOpenEmbed').addEventListener('click', open);
  document.getElementById('btnCloseEmbed').addEventListener('click', close);
  modal.addEventListener('click', function(e){ if (e.target === modal) close(); });
  document.addEventListener('keydown', function(e){ if (e.key === 'Escape' && modal.classList.contains('open')) close(); });
  document.getElementById('tabIframe').addEventListener('click', function(){ snippet = 'iframe'; renderCode(); });
  document.getElementById('tabSdk').addEventListener('click', function(){ snippet = 'sdk'; renderCode(); });
  document.getElementById('btnCopyEmbed').addEventListener('click', function(){
    copyText(codeEl.textContent).then(function(){ toast('Embed code copied'); var l = document.getElementById('copyBtnLabel'); l.textContent = 'Copied'; setTimeout(function(){ l.textContent = 'Copy code'; }, 1800); }, function(){ toast('Copy failed. Select the code instead.'); });
  });
  var copyVexoEmbed = document.getElementById('btnCopyVexoEmbed');
  if (copyVexoEmbed) copyVexoEmbed.addEventListener('click', function(){
    copyText(cfg.vexoEmbedUrl || '').then(function(){
      toast('VexoStream embed link copied');
      var l = document.getElementById('copyVexoEmbedLabel');
      if (l) { l.textContent = 'Copied'; setTimeout(function(){ l.textContent = 'Copy VexoStream embed link'; }, 1800); }
    }, function(){ toast('Copy failed. Select the URL instead.'); });
  });
  document.getElementById('btnCopyLink').addEventListener('click', function(){
    copyText(location.origin + location.pathname).then(function(){ toast('Link copied'); }, function(){ toast('Copy failed'); });
  });
})();
`;

function renderEmbedSdk(origin) {
    return String.raw`(function(){
  var ORIGIN = ` + JSON.stringify(origin) + String.raw`;
  function b64url(str){ var bytes = new TextEncoder().encode(String(str)), bin = ''; for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]); return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''); }
  if (window.customElements && !customElements.get('vexo-player')) {
    customElements.define('vexo-player', class extends HTMLElement {
      static get observedAttributes(){ return ['src', 'viewkey']; }
      connectedCallback(){ this.render(); }
      attributeChangedCallback(){ if (this.isConnected) this.render(); }
      render(){
        var src = this.getAttribute('src') || '', vk = this.getAttribute('viewkey') || '';
        var url = src ? ORIGIN + '/embed/' + b64url(src) : (vk ? ORIGIN + '/embed?viewkey=' + encodeURIComponent(vk) : '');
        if (!url) { this.innerHTML = ''; return; }
        if (this.getAttribute('autoplay') !== null) url += (url.indexOf('?') >= 0 ? '&' : '?') + 'autoplay=1';
        this.style.display = 'block';
        this.innerHTML = '<div style="position:relative;width:100%;padding-top:56.25%;border-radius:' + (this.getAttribute('radius') || '18') + 'px;overflow:hidden;background:#000">' +
          '<iframe src="' + url + '" title="VexoStream player" style="position:absolute;inset:0;width:100%;height:100%;border:0" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen loading="lazy"></iframe></div>';
      }
    });
  }
})();`;
}

