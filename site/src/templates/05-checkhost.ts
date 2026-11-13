
function renderCheckHostHtml(meta, init: any = {}) {
    const type = CH_TYPES.includes(init.type) ? init.type : 'http';
    const types = [['ping', 'Ping'], ['http', 'HTTP'], ['tcp', 'TCP port'], ['dns', 'DNS']];
    const flag = (cc, name) => '<img src="/assets/flags/' + cc + '.svg" alt="" width="24" height="16" loading="eager" decoding="async">';
    return renderHead({ meta, sameOriginOnly: true }) +
        '<body>' + renderNav('checkhost', { sameOriginOnly: true }) +
        '<main><div class="wrap">' +
        '<header class="ch-head"><p class="crumbs"><a href="/">Home</a><span aria-hidden="true">/</span><a href="/status">Status</a><span aria-hidden="true">/</span><span>Check host</span></p>' +
        '<h1 class="headline">Check host.</h1><p class="subhead">Ping, HTTP, TCP and DNS for VexoStream hosts, from real servers in six countries.</p></header>' +
        '<div class="ch-form" role="search">' +
        '<div class="ch-row">' +
        '<label for="chHost" class="sr-only">Domain, IP or URL</label>' +
        '<input class="ch-input" id="chHost" type="text" inputmode="url" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="300" placeholder="vexostream.bond" value="' + escapeHtml(init.host || '') + '">' +
        '<label for="chPort" class="sr-only">Port</label>' +
        '<input class="ch-input ch-port" id="chPort" type="text" inputmode="numeric" maxlength="5" placeholder="443" value="' + escapeHtml(init.port || '') + '"' + (type === 'tcp' ? '' : ' hidden') + '>' +
        '<button class="btn ch-go" id="chGo" type="button">Check</button>' +
        '</div>' +
        '<div class="ch-row" style="justify-content:space-between">' +
        '<div class="ch-types" role="group" aria-label="Check type">' +
        types.map(t => '<button class="ch-type" type="button" data-type="' + t[0] + '" aria-pressed="' + (t[0] === type) + '">' + t[1] + '</button>').join('') +
        '</div>' +
        '<div class="ch-ccs" role="group" aria-label="Countries"><span class="ch-ccs-l">From</span>' +
        CH_COUNTRIES.map(c => '<button class="ch-cc" type="button" data-cc="' + c.cc + '" aria-pressed="' + (!init.cc || init.cc.includes(c.cc)) + '" title="' + c.name + '">' + flag(c.cc, c.name) + '<span>' + c.cc.toUpperCase() + '</span></button>').join('') +
        '</div></div>' +
        '<p class="ch-err" id="chErr" role="alert"></p><p class="ch-info" id="chInfo" role="status"></p>' +
        '</div>' +
        '<div class="ch-beacons" id="chBeacons" aria-live="polite">' +
        CH_COUNTRIES.map(c => '<div class="ch-bc" data-cc="' + c.cc + '" data-s="idle"><span class="ch-bc-flag"><img src="/assets/flags/' + c.cc + '.svg" alt="' + c.name + ' flag" width="56" height="38"></span><b>' + c.name + '</b><small data-bc-txt>&nbsp;</small></div>').join('') +
        '</div>' +
        '<div class="ch-sum" id="chSum" hidden><span id="chSumTxt"></span></div>' +
        '<div class="ch-table-wrap"><table class="ch-table" id="chTable"><thead id="chThead"></thead><tbody id="chBody">' +
        '<tr><td colspan="4"><div class="ch-empty"><b>Where does it answer from?</b>Enter an authorized VexoStream host. Results stream in as each country replies.</div></td></tr>' +
        '</tbody></table></div>' +
        '<p class="ch-note">Regional probes come from Check-Host.net, with Globalping as a fallback. VexoStream does not run those servers; our Worker calls their public APIs, so your browser stays on vexostream.bond. Only VexoStream-owned or authorized hosts can be checked. The edge row can\u2019t run ping or raw TCP.</p>' +
        '<div style="height:96px"></div></div></main>' + renderFooter({ sameOriginOnly: true }) +
        '<script>window.CH_COUNTRIES=' + jsonForScript(CH_COUNTRIES.map(c => ({ cc: c.cc, name: c.name }))) + ';window.CH_AUTO=' + (init.host ? 'true' : 'false') + ';</script>' +
        '<script>' + COMMON_JS.replace("window.location.href = 'https://www.google.com';", "window.location.href = '/'") + CHECK_JS + '</script></body></html>';
}

// No backticks or template placeholders in here.
const CHECK_JS = String.raw`
(function(){
  var $ = function(id){ return document.getElementById(id); };
  var host = $('chHost'), port = $('chPort'), go = $('chGo'), err = $('chErr'), info = $('chInfo');
  var body = $('chBody'), thead = $('chThead'), sum = $('chSum'), sumTxt = $('chSumTxt');
  var CC = window.CH_COUNTRIES || [];
  var NAMES = {}; CC.forEach(function(c){ NAMES[c.cc] = c.name; });
  var curType = document.querySelector('.ch-type[aria-pressed=true]');
  var type = curType ? curType.getAttribute('data-type') : 'http';
  var run = 0, nodes = [], results = {}, edge = null, pollTimer = null, provider = '', expected = 0, waitingNodes = false, shown = {};

  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]; }); }
  function ms(sec){ if (sec == null || isNaN(sec)) return ''; var v = sec * 1000; return (v < 10 ? v.toFixed(1) : Math.round(v)) + ' ms'; }
  function pressed(sel){ return Array.prototype.filter.call(document.querySelectorAll(sel), function(b){ return b.getAttribute('aria-pressed') === 'true'; }); }
  function chosenCc(){ return pressed('.ch-cc').map(function(b){ return b.getAttribute('data-cc'); }); }

  document.querySelectorAll('.ch-type').forEach(function(b){
    b.addEventListener('click', function(){
      document.querySelectorAll('.ch-type').forEach(function(x){ x.setAttribute('aria-pressed', String(x === b)); });
      type = b.getAttribute('data-type');
      port.hidden = type !== 'tcp';
      if (host.value.trim()) start();
    });
  });
  document.querySelectorAll('.ch-cc').forEach(function(b){
    b.addEventListener('click', function(){
      var on = b.getAttribute('aria-pressed') === 'true';
      if (on && chosenCc().length === 1) return;
      b.setAttribute('aria-pressed', String(!on));
      paintBeacons();
    });
  });
  go.addEventListener('click', start);
  host.addEventListener('keydown', function(e){ if (e.key === 'Enter') { e.preventDefault(); start(); } });
  port.addEventListener('keydown', function(e){ if (e.key === 'Enter') { e.preventDefault(); start(); } });

  function head(){
    var cols = { ping: ['Location', 'Result', 'rtt min / avg / max', 'IP address'], http: ['Location', 'Result', 'Time', 'Code / IP'], tcp: ['Location', 'Result', 'Time', 'IP address'], dns: ['Location', 'Result', 'Records', 'TTL'] }[type];
    thead.innerHTML = '<tr>' + cols.map(function(c){ return '<th>' + c + '</th>'; }).join('') + '</tr>';
    return cols;
  }

  function cells(r){
    if (r && r.supported === false) return ['<span class="ch-pill">Not at the edge</span>', '<span class="ch-dim ch-why">' + esc(r.error) + '</span>', ''];
    if (!r || !r.done) return ['<span class="ch-pill wait">Checking</span>', '<span class="ch-dim">&hellip;</span>', '<span class="ch-dim">&hellip;</span>'];
    if (r.error && !r.ok) return ['<span class="ch-pill bad">' + esc(r.error) + '</span>', '', ''];
    if (type === 'ping') {
      var dots = '<span class="ch-pings">' + (r.pings || []).map(function(p){ return '<i class="' + (p === 'OK' ? 'ok' : '') + '" title="' + esc(p) + '"></i>'; }).join('') + '</span>';
      var cls = r.recv === r.sent ? 'ok' : r.recv ? 'warn' : 'bad';
      return [dots + '<span class="ch-pill ' + cls + '">' + r.recv + ' / ' + r.sent + '</span>', r.recv ? '<span class="ch-mono">' + ms(r.min) + ' / ' + ms(r.avg) + ' / ' + ms(r.max) + '</span>' : '<span class="ch-dim">no reply</span>', '<span class="ch-mono">' + esc(r.ip || '') + '</span>'];
    }
    if (type === 'http') {
      var c = r.code, k = !c ? 'bad' : c < 300 ? 'ok' : c < 400 ? 'warn' : 'bad';
      var label = c ? c + ' ' + (r.message || '') : (r.message || r.error || 'Failed');
      return ['<span class="ch-pill ' + k + '">' + esc(label.trim()) + '</span>', '<span class="ch-mono">' + ms(r.time) + '</span>', '<span class="ch-mono">' + esc(r.ip || '') + '</span>'];
    }
    if (type === 'tcp') return ['<span class="ch-pill ok">Connected</span>', '<span class="ch-mono">' + ms(r.time) + '</span>', '<span class="ch-mono">' + esc(r.ip || '') + '</span>'];
    var recs = (r.A || []).concat(r.AAAA || []);
    return ['<span class="ch-pill ' + (recs.length ? 'ok' : 'bad') + '">' + (recs.length ? recs.length + ' found' : 'No records') + '</span>', '<span class="ch-mono">' + (recs.length ? recs.map(esc).join('<br>') : '<span class="ch-dim">&mdash;</span>') + '</span>', '<span class="ch-mono">' + (r.ttl == null ? '<span class="ch-dim">&mdash;</span>' : esc(r.ttl) + ' s') + '</span>'];
  }

  function verdict(r){
    if (!r || !r.done) return 'wait';
    if (!r.ok) return 'bad';
    if (type === 'ping' && r.recv < r.sent) return 'warn';
    if (type === 'http' && r.code >= 300 && r.code < 400) return 'warn';
    return 'ok';
  }

  function paintBeacons(){
    var on = chosenCc();
    document.querySelectorAll('.ch-bc').forEach(function(el){
      var cc = el.getAttribute('data-cc'), txt = el.querySelector('[data-bc-txt]');
      if (on.indexOf(cc) < 0) { el.setAttribute('data-s', 'off'); txt.innerHTML = 'off'; return; }
      var mine = nodes.filter(function(n){ return n.cc === cc; });
      if (run && !mine.length && waitingNodes) { el.setAttribute('data-s', 'wait'); txt.innerHTML = 'checking'; return; }
      if (!run || !mine.length) { el.setAttribute('data-s', run ? 'off' : 'idle'); txt.innerHTML = run ? (nodes.length ? 'no server' : 'unavailable') : '&nbsp;'; return; }
      var v = mine.map(function(n){ return verdict(results[n.id]); });
      var good = v.filter(function(x){ return x === 'ok' || x === 'warn'; }).length;
      var waiting = v.filter(function(x){ return x === 'wait'; }).length;
      var s = waiting ? 'wait' : good === v.length ? (v.indexOf('warn') >= 0 ? 'warn' : 'ok') : good ? 'warn' : 'bad';
      el.setAttribute('data-s', s);
      var times = mine.map(function(n){ var r = results[n.id]; return r && r.ok ? (type === 'ping' ? r.avg : r.time) : null; }).filter(function(x){ return x != null; });
      var best = times.length ? Math.min.apply(null, times) : null;
      txt.innerHTML = waiting && !good ? 'checking' : '<span>' + good + '/' + v.length + ' up</span>' + (best != null && type !== 'dns' ? '<span class="t"><i> \u00b7 </i>' + ms(best) + '</span>' : '');
    });
  }

  function paintTable(){
    head();
    var rows = nodes.map(function(n){
      var c = cells(results[n.id]);
      var fresh = !shown[n.id]; shown[n.id] = 1;
      return '<tr' + (fresh ? ' class="ch-new"' : '') + '><td><div class="ch-loc"><img src="/assets/flags/' + esc(n.cc) + '.svg" alt="" width="28" height="19"><span><b>' + esc(NAMES[n.cc] || n.country) + ', ' + esc(n.city) + '</b><small>' + esc(n.label || n.id.split('.')[0]) + (n.asn ? ' \u00b7 ' + esc(n.asn) : '') + '</small></span></div></td>' +
        '<td data-l="Result">' + c[0] + '</td><td data-l="' + (type === 'dns' ? 'Records' : 'Time') + '">' + c[1] + '</td><td data-l="' + (type === 'dns' ? 'TTL' : 'IP') + '">' + c[2] + '</td></tr>';
    });
    if (!nodes.length && waitingNodes) {
      for (var w = 0; w < Math.min(expected || 3, 6); w++) rows.push('<tr class="ch-ghost"><td><div class="ch-loc"><span class="ch-ghost-flag"></span><span><b>Assigning probe\u2026</b><small>' + esc(provider || 'Regional network') + '</small></span></div></td><td data-l="Result"><span class="ch-pill wait">Queued</span></td><td></td><td></td></tr>');
    }
    if (edge) {
      var c = cells(edge);
      var freshEdge = !shown.__edge; shown.__edge = 1;
      rows.push('<tr' + (freshEdge ? ' class="ch-new"' : '') + '><td><div class="ch-loc"><span class="ch-edge-ic"><img src="/assets/logos/cloudflare.svg" alt="Cloudflare" width="22" height="22"></span><span><b>VexoStream edge' + (edge.colo ? ', ' + esc(edge.colo) : '') + '</b><small>Cloudflare' + (edge.cc ? ' \u00b7 ' + esc(edge.cc.toUpperCase()) : '') + '</small></span></div></td>' +
        '<td data-l="Result">' + c[0] + '</td><td data-l="' + (type === 'dns' ? 'Records' : 'Time') + '">' + c[1] + '</td><td data-l="' + (type === 'dns' ? 'TTL' : 'IP') + '">' + c[2] + '</td></tr>');
    }
    body.innerHTML = rows.length ? rows.join('') : '<tr><td colspan="4"><div class="ch-empty"><b>No servers answered.</b>Try again in a minute.</div></td></tr>';
    var done = nodes.filter(function(n){ var r = results[n.id]; return r && r.done; }).length;
    var up = nodes.filter(function(n){ var v = verdict(results[n.id]); return v === 'ok' || v === 'warn'; }).length;
    var via = provider ? ' \u00b7 via ' + provider : '';
    if (nodes.length) sumTxt.textContent = (done < nodes.length ? 'Checking\u2026 ' + done + ' of ' + nodes.length + ' regional probes answered' : up + ' of ' + nodes.length + ' regional probes can reach it') + via;
    else if (waitingNodes) sumTxt.textContent = 'Waiting for regional probes' + via;
    else if (edge) sumTxt.textContent = edge.ok ? 'Regional probes unavailable. Showing the VexoStream edge result only.' : 'Regional probes unavailable. The edge result is shown below, but it did not succeed.';
    paintBeacons();
  }

  function share(target){
    try {
      var q = new URLSearchParams({ type: type, host: host.value.trim() });
      if (type === 'tcp' && port.value.trim()) q.set('port', port.value.trim());
      var cc = chosenCc(); if (cc.length < CC.length) q.set('cc', cc.join(','));
      history.replaceState(null, '', '/check-host?' + q.toString());
    } catch (e) {}
  }

  function start(){
    var h = host.value.trim();
    err.textContent = '';
    if (!h) { err.textContent = 'Type a domain, IP or URL.'; host.focus(); return; }
    if (type === 'tcp' && port.value.trim()) {
      if (!/^\d{1,5}$/.test(port.value.trim())) { err.textContent = 'Port must be 1 to 65535.'; port.focus(); return; }
      var p = Number(port.value.trim());
      if (!(p > 0 && p <= 65535)) { err.textContent = 'Port must be 1 to 65535.'; port.focus(); return; }
    }
    var my = ++run; nodes = []; results = {}; edge = null; provider = ''; expected = 0; waitingNodes = false;
    info.textContent = ''; shown = {};
    clearTimeout(pollTimer);
    go.disabled = true; go.textContent = 'Checking\u2026';
    document.querySelectorAll('.ch-bc').forEach(function(el){ if (el.getAttribute('data-s') !== 'off') { el.setAttribute('data-s', 'wait'); el.querySelector('[data-bc-txt]').textContent = 'checking'; } });
    head();
    body.innerHTML = '<tr><td colspan="4"><div class="ch-empty"><b>Sending probes\u2026</b>Checking only this authorized host from ' + chosenCc().length + ' selected regions.</div></td></tr>';
    share();
    var q = new URLSearchParams({ type: type, host: h, cc: chosenCc().join(',') });
    if (type === 'tcp' && port.value.trim()) q.set('port', port.value.trim());
    fetch('/api/check-host/start?' + q.toString(), { cache: 'no-store', credentials: 'same-origin' }).then(function(r){ return r.json().catch(function(){ return { ok: false, error: 'Unexpected reply (' + r.status + ').' }; }); }).then(function(j){
      if (my !== run) return;
      if (!j.ok) { fail(j.error || 'Check failed.'); return; }
      nodes = j.nodes || []; edge = j.edge || null; provider = j.providerName || ''; expected = j.expected || 0;
      waitingNodes = !!j.id && !nodes.length;
      if (j.error) err.textContent = j.error;
      if (j.notice) info.textContent = j.notice;
      sum.hidden = false;
      paintTable();
      if (j.id) poll(j.id, my, 0, 0); else finish();
    }).catch(function(){ if (my === run) fail('Network error. Try again.'); });
  }

  function endPending(message){
    if (waitingNodes) { waitingNodes = false; err.textContent = message; }
    nodes.forEach(function(nd){ if (!results[nd.id] || !results[nd.id].done) results[nd.id] = { done: true, ok: false, error: message }; });
    paintTable();
    finish();
  }

  function poll(id, my, n, failures){
    pollTimer = setTimeout(function(){
      if (my !== run) return;
      fetch('/api/check-host/result?id=' + encodeURIComponent(id) + '&type=' + type, { cache: 'no-store', credentials: 'same-origin' }).then(function(r){
        return r.json().catch(function(){ return { ok: false, error: 'Unexpected result reply (' + r.status + ').' }; }).then(function(j){ return { response: r, data: j }; });
      }).then(function(payload){
        if (my !== run) return;
        var j = payload.data;
        if (!payload.response.ok || !j || !j.ok) {
          var nextFailures = failures + 1;
          if (nextFailures >= 3 || n >= 18) return endPending('Regional results unavailable: ' + ((j && j.error) || 'request failed') + '.');
          return poll(id, my, n + 1, nextFailures);
        }
        if (j.nodes && j.nodes.length) { nodes = j.nodes; waitingNodes = false; }
        if (j && j.results) Object.keys(j.results).forEach(function(k){ results[k] = j.results[k]; });
        paintTable();
        var allDone = nodes.length > 0 && nodes.every(function(nd){ return results[nd.id] && results[nd.id].done; });
        if (j.done && allDone) return finish();
        if (j.done && !nodes.length) { waitingNodes = false; err.textContent = (provider || 'The regional network') + ' finished without assigning any probes. Showing the VexoStream edge result only.'; paintTable(); return finish(); }
        if (n >= 18) return endPending('Regional probe timed out before returning a result.');
        poll(id, my, n + 1, 0);
      }).catch(function(){
        if (my !== run) return;
        var nextFailures = failures + 1;
        if (nextFailures >= 3 || n >= 18) endPending('Regional results could not be loaded after repeated attempts.');
        else poll(id, my, n + 1, nextFailures);
      });
    }, n < 4 ? 800 : 1300);
  }

  function finish(){ go.disabled = false; go.textContent = 'Check again'; paintBeacons(); }
  function fail(msg){
    err.textContent = msg; go.disabled = false; go.textContent = 'Check';
    body.innerHTML = '<tr><td colspan="4"><div class="ch-empty"><b>Couldn\u2019t run that check.</b>' + esc(msg) + '</div></td></tr>';
    document.querySelectorAll('.ch-bc').forEach(function(el){ if (el.getAttribute('data-s') !== 'off') { el.setAttribute('data-s', 'idle'); el.querySelector('[data-bc-txt]').innerHTML = '&nbsp;'; } });
  }

  head(); paintBeacons();
  if (window.CH_AUTO) start(); else host.focus({ preventScroll: true });
})();
`;
