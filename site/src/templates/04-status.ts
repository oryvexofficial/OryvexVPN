// ============================================================================
// STATUS
// ============================================================================
const STATUS_COMPONENTS = [
    { id: 'edge', name: 'Edge API', desc: 'Cloudflare Workers, global edge' },
    { id: 'extract', name: 'Extraction Core', desc: 'Backend video parsing' },
    { id: 'proxy', name: 'Media Proxy', desc: 'HLS and MP4 stream gateway' },
    { id: 'telegram', name: 'Telegram Bot', desc: 'Webhook and commands' },
    { id: 'admin', name: 'Admin Panel', desc: 'Sessions and maintenance control' }
];
const STATUS_KEYS = STATUS_COMPONENTS.map(c => c.id);
const STATUS_LABELS = {
    operational: 'Operational',
    degraded: 'Degraded performance',
    partial_outage: 'Partial outage',
    major_outage: 'Major outage'
};
const SEVERITY = { operational: 0, degraded: 1, partial_outage: 2, major_outage: 3 };

let __statusCache = { at: 0, data: null };
let __lastStoredAt = 0;

async function runStatusChecks(env) {
    if (__statusCache.data && Date.now() - __statusCache.at < 30000) return __statusCache.data;
    await resolveTelegramSettings(env, '', true);
    const out = { edge: 'operational', extract: 'operational', proxy: 'operational', telegram: 'operational', admin: 'operational', checked_at: Date.now() };

    const backend = (async () => {
        try {
            const r = await timedFetch(RAILWAY_URL + '/', { method: 'GET', redirect: 'follow' }, 5000);
            if (!r.ok) out.extract = r.status >= 500 ? 'major_outage' : 'degraded';
        } catch (_) {
            out.extract = 'major_outage';
        }
    })();
    const tg = (async () => {
        try {
            const r = await timedFetch(TELEGRAM_API + '/getMe', {}, 4000);
            if (!r.ok) out.telegram = r.status === 401 || r.status === 404 ? 'major_outage' : 'degraded';
        } catch (_) {
            out.telegram = 'degraded';
        }
    })();
    const db = (async () => {
        if (!env || !env.DB) { out.admin = 'degraded'; return; }
        try { await env.DB.prepare('SELECT 1').first(); } catch (_) { out.admin = 'partial_outage'; }
    })();
    await Promise.all([backend, tg, db]);

    if (out.extract === 'major_outage') out.proxy = 'degraded';
    __statusCache = { at: Date.now(), data: out };
    return out;
}

function statusOverall(checks) {
    let worst = 'operational';
    for (const k of STATUS_KEYS) if ((SEVERITY[checks[k]] || 0) > SEVERITY[worst]) worst = checks[k];
    return worst;
}

async function storeStatus(env, checks) {
    if (!env || !env.STATUS) return;
    try {
        const overall = statusOverall(checks);
        const row = await env.STATUS.prepare('SELECT id FROM statuses WHERE code = ?').bind(overall).first();
        await env.STATUS.prepare('INSERT INTO status_history (status_id, status_code, note) VALUES (?, ?, ?)')
            .bind(row ? row.id : null, overall, JSON.stringify(checks)).run();
        __lastStoredAt = Date.now();
    } catch (err) {
        console.error('STATUS write failed:', err && err.message);
    }
}

// Cron always stores. Page views store at most once every 5 minutes per isolate.
let __statusMemo = { at: 0, checks: null };
async function runStatusChecksAndStore(env, force = false) {
    if (!force && __statusMemo.checks && Date.now() - __statusMemo.at < 60000) return __statusMemo.checks;
    const checks = await runStatusChecks(env);
    __statusMemo = { at: Date.now(), checks };
    if (force || Date.now() - __lastStoredAt > 5 * 60 * 1000) await storeStatus(env, checks);
    return checks;
}

async function getRealStatusHistory(env, currentChecks) {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const days = [];
    const map = {};
    for (let i = 89; i >= 0; i--) {
        const iso = new Date(today.getTime() - i * 86400000).toISOString().slice(0, 10);
        days.push(iso);
        map[iso] = {};
        for (const k of STATUS_KEYS) map[iso][k] = 'operational';
    }
    const incidents = [];
    let tracked = 0;
    if (env && env.STATUS) {
        try {
            const { results } = await env.STATUS.prepare(
                "SELECT date(created_at) AS dt, status_code, note, created_at FROM status_history WHERE created_at >= date('now', '-90 days') ORDER BY created_at ASC"
            ).all();
            tracked = results.length;
            for (let i = results.length - 1; i >= 0 && incidents.length < 5; i--) {
                if (results[i].status_code !== 'operational') incidents.push(results[i]);
            }
            for (const row of results) {
                if (!row.note || !map[row.dt]) continue;
                try {
                    const parsed = JSON.parse(row.note);
                    for (const k of STATUS_KEYS) {
                        if (parsed[k] && (SEVERITY[parsed[k]] || 0) > (SEVERITY[map[row.dt][k]] || 0)) map[row.dt][k] = parsed[k];
                    }
                } catch (_) {}
            }
        } catch (err) {
            console.error('STATUS read failed:', err && err.message);
        }
    }
    const todayIso = today.toISOString().slice(0, 10);
    for (const k of STATUS_KEYS) {
        if (currentChecks[k] && (SEVERITY[currentChecks[k]] || 0) > (SEVERITY[map[todayIso][k]] || 0)) map[todayIso][k] = currentChecks[k];
    }
    const bars = {};
    for (const k of STATUS_KEYS) bars[k] = days.map(d => ({ date: d, status: map[d][k] }));
    return { bars, incidents, tracked };
}

function renderStatusHtml(checks, history, providerConfig = normalizeProviderConfig(null), meta = '') {
    const overall = statusOverall(checks);
    const headline = overall === 'operational' ? 'All systems operational.' : STATUS_LABELS[overall] + '.';
    let html = renderHead({ meta, title: 'System Status \u2014 VexoStream' }) +
        '<body>' + renderNav('status') +
        '<main><div class="wrap">' +
        '<header class="st-hero"><h1>System Status</h1><p>Live health of every part of VexoStream. <a href="/check-host?host=vexostream.bond">Check from 6 countries &rarr;</a></p></header>' +
        '<div class="st-banner s-' + overall + '"><div class="st-banner-l"><span class="st-dot s-' + overall + '"></span>' +
        '<div><b>' + headline + '</b><small>Checked <span id="statusChecked">just now</span> &middot; refreshes every 60 seconds</small></div></div>' +
        '<button class="btn quiet sm" id="statusRefresh" type="button">Refresh</button></div>' +
        '<div class="st-legend" style="margin-bottom:18px">' +
        Object.keys(STATUS_LABELS).map(k => '<span class="s-' + k + '"><i></i>' + STATUS_LABELS[k] + '</span>').join('') +
        '</div><div class="st-list">';

    for (const c of STATUS_COMPONENTS) {
        const st = checks[c.id] || 'operational';
        const bars = history.bars[c.id] || [];
        html += '<div class="st-row"><div class="st-row-head">' +
            '<div class="st-row-name"><span class="st-dot s-' + st + '"></span><div><b>' + c.name + '</b><small>' + c.desc + '</small></div></div>' +
            '<span class="st-state s-' + st + '">' + STATUS_LABELS[st] + '</span></div>' +
            '<div class="st-bars" role="img" aria-label="' + c.name + ' uptime, last 90 days">' +
            bars.map(b => '<span class="st-bar s-' + b.status + '" title="' + b.date + ' \u00b7 ' + STATUS_LABELS[b.status] + '"></span>').join('') +
            '</div><div class="st-axis"><span>90 days ago</span><span>Today</span></div></div>';
    }
    html += '</div><h2 class="st-h2">Provider availability</h2><div class="st-provider-grid">';
    for (const p of listedProviders(providerConfig)) {
        const label = p.mode === 'live' ? 'Live' : 'Currently unavailable';
        html += '<div class="st-provider" data-mode="' + p.mode + '"><b>' + escapeHtml(p.name) + '</b><span>' + label + '</span></div>';
    }
    if (!listedProviders(providerConfig).length) html += '<div class="st-empty">No providers are currently listed.</div>';
    html += '</div><h2 class="st-h2">Uptime, 90 days</h2><div class="st-grid">';
    for (const c of STATUS_COMPONENTS) {
        const bars = history.bars[c.id] || [];
        const ok = bars.filter(b => b.status === 'operational').length;
        const pct = bars.length ? (ok / bars.length * 100).toFixed(2) : '100.00';
        html += '<div class="st-up"><small>' + c.name + '</small><b>' + pct + '%</b></div>';
    }
    html += '</div><h2 class="st-h2">Recent incidents</h2>';
    if (history.incidents && history.incidents.length) {
        for (const inc of history.incidents) {
            const code = SEVERITY[inc.status_code] !== undefined ? inc.status_code : 'degraded';
            html += '<div class="st-inc"><span class="st-dot s-' + code + '"></span><div><b>' + escapeHtml(STATUS_LABELS[code]) + '</b>' +
                '<small data-utc="' + escapeHtml(inc.created_at) + '">' + escapeHtml(inc.created_at) + ' UTC</small></div></div>';
        }
    } else {
        html += '<div class="st-empty">No incidents in the past 90 days.</div>';
    }
    html += '<div style="height:96px"></div></div></main>' + renderFooter() +
        '<script>' + COMMON_JS + STATUS_JS + '</script></body></html>';
    return html;
}

const STATUS_JS = String.raw`
(function(){
  var btn = document.getElementById('statusRefresh'), el = document.getElementById('statusChecked'), last = Date.now();
  function label(){ if (!el) return; var s = Math.floor((Date.now() - last) / 1000); el.textContent = s < 5 ? 'just now' : s < 60 ? s + ' seconds ago' : Math.floor(s / 60) + ' min ago'; }
  function refresh(){
    if (document.hidden) return;
    if (btn) { btn.disabled = true; btn.textContent = 'Refreshing\u2026'; }
    fetch('/api/status', { cache: 'no-store' }).then(function(r){ if (r.ok) location.reload(); else throw 0; }).catch(function(){ if (btn) { btn.disabled = false; btn.textContent = 'Refresh'; } last = Date.now(); label(); });
  }
  if (btn) btn.addEventListener('click', refresh);
  document.querySelectorAll('[data-utc]').forEach(function(n){ var t = Date.parse(n.getAttribute('data-utc').replace(' ', 'T') + 'Z'); if (!isNaN(t)) n.textContent = new Date(t).toLocaleString(); });
  setInterval(label, 1000); setInterval(refresh, 60000); label();
})();
`;

