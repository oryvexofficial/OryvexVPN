import test from 'node:test';
import assert from 'node:assert/strict';

const worker = (await import('../dist/worker.js')).default;
const realFetch = globalThis.fetch;

const nodeRows = [
  ['us1.node.check-host.net', ['us', 'USA', 'Los Angeles', '38.145.202.12', 'AS18978']],
  ['ir1.node.check-host.net', ['ir', 'Iran', 'Tehran', '185.105.238.209', 'AS47430']],
  ['de1.node.check-host.net', ['de', 'Germany', 'Nuremberg', '142.132.174.167', 'AS24940']],
  ['gb1.node.check-host.net', ['gb', 'United Kingdom', 'London', '107.181.134.162', 'AS213535']],
  ['fr1.node.check-host.net', ['fr', 'France', 'Paris', '195.154.114.92', 'AS12876']],
  ['nl1.node.check-host.net', ['nl', 'Netherlands', 'Amsterdam', '185.209.161.145', 'AS14576']]
];
const nodeMeta = Object.fromEntries(nodeRows.map(([id, values]) => [id, {
  location: values.slice(0, 3),
  ip: values[3],
  asn: values[4]
}]));
const nodeValues = Object.fromEntries(nodeRows);
let behavior;
let nextId = 0;
const pollCounts = new Map();
const startedTypes = new Map();
const seenProbeUrls = [];
const seenOrigins = new Set();
const gpBodies = [];
const gpTypes = new Map();
const gpPolls = new Map();

function responseJson(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}

function setBehavior(overrides = {}) {
  behavior = {
    regional: 'ok',
    edge: 'ok',
    dns: 'public',
    result: 'done',
    gp: 'ok',
    gpResult: 'done',
    ...overrides
  };
  globalThis.fetch = async (input, init = {}) => {
    // Same rule as the Cloudflare Workers runtime: only "follow" and "manual" exist.
    if (init.redirect !== undefined && !['follow', 'manual'].includes(init.redirect)) {
      throw new TypeError('Invalid redirect value, must be one of "follow" or "manual"');
    }
    const u = new URL(typeof input === 'string' ? input : input.url);
    seenOrigins.add(u.origin);

    if (u.origin === 'https://cloudflare-dns.com' || u.origin === 'https://dns.google') {
      if (behavior.dns === 'unavailable') return responseJson({ error: 'resolver unavailable' }, 503);
      if (behavior.dns === 'cloudflare-down' && u.origin === 'https://cloudflare-dns.com') return responseJson({ error: 'down' }, 503);
      const rr = u.searchParams.get('type');
      const records = behavior.dns === 'private'
        ? (rr === 'A' ? [{ type: 1, data: '10.1.2.3', TTL: 60 }] : [])
        : (rr === 'A'
          ? [{ type: 1, data: '93.184.216.34', TTL: 180 }]
          : [{ type: 28, data: '2606:2800:220:1:248:1893:25c8:1946', TTL: 180 }]);
      return responseJson({ Status: 0, Answer: records });
    }

    if (u.origin === 'https://check-host.net') {
      if (u.pathname === '/nodes/hosts') return responseJson({ nodes: nodeMeta });
      if (u.pathname.startsWith('/check-result/')) {
        if (behavior.result === 'timeout') throw new DOMException('simulated timeout', 'AbortError');
        if (behavior.result === 'unavailable') return responseJson({ error: 'unavailable' }, 503);
        const id = u.pathname.split('/').pop();
        const type = startedTypes.get(id) || 'http';
        if (behavior.result === 'pending-once' && !pollCounts.has(id)) {
          pollCounts.set(id, 1);
          return responseJson({ 'us1.node.check-host.net': null });
        }
        return responseJson(resultPayload(type));
      }
      const m = /^\/check-(ping|http|tcp|dns)$/.exec(u.pathname);
      if (m) {
        seenProbeUrls.push(u);
        if (behavior.regional === 'timeout') throw new DOMException('simulated timeout', 'AbortError');
        if (behavior.regional === 'forbidden') return responseJson({ error: 'forbidden' }, 403);
        if (behavior.regional === 'limited') return responseJson({ error: 'limit_exceeded' }, 429);
        if (behavior.regional === 'unavailable') return responseJson({ error: 'maintenance' }, 503);
        if (behavior.regional === 'malformed') return new Response('not json', { status: 200 });
        const type = m[1];
        const id = 'test' + (++nextId);
        startedTypes.set(id, type);
        const selected = u.searchParams.getAll('node');
        const selectedNodes = Object.fromEntries(selected.filter(n => nodeValues[n]).map(n => [n, nodeValues[n]]));
        return responseJson({ ok: 1, request_id: id, nodes: selectedNodes });
      }
    }

    if (u.origin === 'https://api.globalping.io') {
      if (init.method === 'POST') {
        const body = JSON.parse(init.body);
        gpBodies.push(body);
        if (behavior.gp === 'limited') return responseJson({ error: { type: 'rate_limit_exceeded', message: 'API rate limit exceeded.' } }, 429);
        if (behavior.gp === 'no-iran' && body.locations.some(l => l.country === 'IR')) return responseJson({ error: { type: 'no_probes_found', message: 'No suitable probes found.' } }, 422);
        if (behavior.gp === 'down') return responseJson({ error: { type: 'api_error' } }, 503);
        const id = 'Gp' + (++nextId);
        gpTypes.set(id, body);
        return responseJson({ id, probesCount: body.locations.length }, 202);
      }
      if (behavior.gpResult === 'unavailable') return responseJson({}, 500);
      const id = u.pathname.split('/').pop();
      const body = gpTypes.get(id) || { type: 'http', measurementOptions: {} };
      const n = (gpPolls.get(id) || 0) + 1; gpPolls.set(id, n);
      const pending = behavior.gpResult === 'pending-once' && n === 1;
      return responseJson({ id, type: body.type, status: pending ? 'in-progress' : 'finished', results: [
        { probe: { country: 'US', city: 'Ashburn', asn: 16509, network: 'Amazon' }, result: pending ? { status: 'in-progress' } : gpResult(body) }
      ] });
    }

    if (u.origin === 'https://vexostream.bond') {
      if (behavior.edge === 'timeout') throw new DOMException('simulated timeout', 'AbortError');
      if (behavior.edge === 'failure') return new Response('', { status: 522, statusText: 'Connection Timed Out' });
      return new Response('', { status: 200, statusText: 'OK' });
    }

    throw new Error('Unexpected outbound request: ' + u.origin + u.pathname);
  };
}

function gpResult(body) {
  if (body.type === 'ping') return { status: 'finished', resolvedAddress: '93.184.216.34', timings: [{ rtt: 10 }, { rtt: 12 }], stats: { min: 10, avg: 11, max: 12, total: body.measurementOptions.packets, rcv: 2, loss: 33 } };
  if (body.type === 'http') return { status: 'finished', statusCode: 200, statusCodeName: 'OK', resolvedAddress: '93.184.216.34', timings: { total: 87 } };
  return { status: 'finished', answers: [{ name: 'vexostream.bond.', type: 'A', ttl: 300, value: '93.184.216.34' }], timings: { total: 9 } };
}

function resultPayload(type) {
  const node = 'us1.node.check-host.net';
  if (type === 'ping') return { [node]: [[['OK', 0.042, '93.184.216.34'], ['TIMEOUT', 3.0]]] };
  if (type === 'http') return { [node]: [[1, 0.12, 'OK', '200', '93.184.216.34']] };
  if (type === 'tcp') return { [node]: [{ address: '93.184.216.34', time: 0.03 }] };
  return { [node]: [{ A: ['93.184.216.34'], AAAA: ['2606:2800:220:1:248:1893:25c8:1946'], TTL: 180 }] };
}

let requestSeq = 0;
async function call(path, env = {}) {
  const request = new Request('https://vexostream.bond' + path, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
      'CF-Connecting-IP': '198.51.100.' + (++requestSeq % 200 + 1)
    }
  });
  return worker.fetch(request, {
    STREAM_SIGN_SECRET: 'unit-test-only',
    EDGE_TOKEN: 'unit-test-only',
    ...env
  }, { waitUntil() {} });
}

async function start(type = 'http', host = 'vexostream.bond', extra = '', env = {}) {
  const q = new URLSearchParams({ type, host, cc: 'us' });
  if (extra) new URLSearchParams(extra).forEach((v, k) => q.set(k, v));
  const response = await call('/api/check-host/start?' + q.toString(), env);
  return { response, body: await response.json() };
}

test('rejects invalid, private, local, reserved, and unauthorized targets before any probe request', async () => {
  setBehavior();
  const probesBefore = seenProbeUrls.length;
  const cases = [
    ['http', '10.0.0.1', 400],
    ['http', '192.0.2.10', 400],
    ['http', '999.1.1.1', 400],
    ['http', '[::1]', 400],
    ['http', '[fe80::1]', 400],
    ['http', '[2001:db8::1]', 400],
    ['http', 'printer.local', 400],
    ['http', 'not-authorized.example.net', 403]
  ];
  for (const [type, host, status] of cases) {
    const { response } = await start(type, host);
    assert.equal(response.status, status, host);
  }
  assert.equal(seenProbeUrls.length, probesBefore, 'invalid targets must not reach the regional API');
});

test('blocks a hostname that resolves to a private address before contacting probe nodes', async () => {
  setBehavior({ dns: 'private' });
  const probesBefore = seenProbeUrls.length;
  const { response, body } = await start('http');
  assert.equal(response.status, 403);
  assert.match(body.error, /private or reserved/i);
  assert.equal(seenProbeUrls.length, probesBefore);
});

test('supports all four check types with the documented regional API and result format', async () => {
  setBehavior({ result: 'pending-once' });
  for (const type of ['ping', 'http', 'tcp', 'dns']) {
    const extra = type === 'tcp' ? 'port=443' : '';
    const { response, body } = await start(type, 'vexostream.bond', extra);
    assert.equal(response.status, 200, type);
    assert.equal(body.ok, true, type);
    assert.ok(body.id, type + ' request id');
    assert.equal(body.provider, 'check-host');
    assert.equal(body.nodes.length, 1, type + ' selected probe');
    assert.equal(body.edge.done, true, type + ' edge result');
    if (type === 'ping' || type === 'tcp') {
      assert.equal(body.edge.supported, false, type + ' must not fake an edge check');
    }
    const started = seenProbeUrls.at(-1);
    assert.equal(started.pathname, '/check-' + type);
    assert.equal(started.searchParams.get('host') !== null, true);
    assert.equal(started.searchParams.get('max_nodes'), '1');
    assert.deepEqual(started.searchParams.getAll('node'), ['us1.node.check-host.net']);

    const pending = await call('/api/check-host/result?id=' + encodeURIComponent(body.id) + '&type=' + type);
    const pendingData = await pending.json();
    assert.equal(pendingData.ok, true);
    assert.equal(pendingData.done, false);
    const done = await call('/api/check-host/result?id=' + encodeURIComponent(body.id) + '&type=' + type);
    const doneData = await done.json();
    assert.equal(doneData.ok, true);
    assert.equal(doneData.done, true);
    assert.equal(doneData.results['us1.node.check-host.net'].done, true);
  }
});

test('validates explicit host and port allowlists, including IPv4 and IPv6 literals', async () => {
  setBehavior();
  const env = { CHECK_HOST_ALLOWED_HOSTS: 'vexostream.bond,authorized.example.net,8.8.8.8,2606:4700:4700::1111' };
  const domain = await start('http', 'api.authorized.example.net', '', env);
  assert.equal(domain.response.status, 200);
  const ip4 = await start('ping', '8.8.8.8', '', env);
  assert.equal(ip4.response.status, 200);
  const ip6 = await start('tcp', '2606:4700:4700::1111', 'port=8443', {
    ...env,
    CHECK_HOST_ALLOWED_PORTS: '80,443,8443'
  });
  assert.equal(ip6.response.status, 200);
  assert.equal(ip6.body.target, '[2606:4700:4700::1111]:8443');

  const deniedPort = await start('tcp', 'vexostream.bond', 'port=8443');
  assert.equal(deniedPort.response.status, 403);
  const invalidPort = await start('tcp', 'vexostream.bond', 'port=65536');
  assert.equal(invalidPort.response.status, 400);
});

test('reports regional API denial, rate limiting, outages, malformed replies, and timeout without claiming success', async () => {
  for (const [regional, phrase] of [
    ['forbidden', 'HTTP 403'],
    ['limited', 'rate-limited'],
    ['unavailable', 'temporarily unavailable'],
    ['malformed', 'invalid response'],
    ['timeout', 'within 8 seconds']
  ]) {
    setBehavior({ regional });
    const { response, body } = await start('http', 'vexostream.bond', '', { CHECK_HOST_PROVIDER: 'check-host' });
    assert.equal(response.status, 200);
    assert.equal(body.ok, true, 'the edge result is present');
    assert.equal(body.id, null);
    assert.match(body.error, new RegExp(phrase, 'i'));
    assert.equal(body.edge.ok, true);
    assert.equal(Object.hasOwn(body, 'report'), false, 'external report URLs must not be returned to the browser');
  }
});

test('keeps an edge timeout visibly failed when regional probes are also unavailable', async () => {
  setBehavior({ regional: 'timeout', edge: 'timeout', gp: 'down' });
  const { body } = await start('http');
  assert.equal(body.ok, true, 'the API returns the failed edge row so the page can render it');
  assert.equal(body.id, null);
  assert.equal(body.edge.done, true);
  assert.equal(body.edge.ok, false);
  assert.equal(body.edge.error, 'Timed out');
  assert.match(body.error, /Check-Host.net could not be reached/i);
  assert.match(body.error, /Globalping is temporarily unavailable/i);
});

test('returns useful polling errors for upstream failures and timeouts', async () => {
  setBehavior({ result: 'unavailable' });
  const failed = await call('/api/check-host/result?id=abc123&type=http');
  assert.equal(failed.status, 502);
  assert.match((await failed.json()).error, /HTTP 503/);

  setBehavior({ result: 'timeout' });
  const timedOut = await call('/api/check-host/result?id=abc123&type=http');
  assert.equal(timedOut.status, 504);
  assert.match((await timedOut.json()).error, /timed out after 5 seconds/i);
});

test('renders desktop, menu, footer, status link, and same-origin browser resources', async () => {
  setBehavior();
  const response = await call('/check-host');
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /class="mast-nav"[\s\S]*?href="\/check-host"/);
  assert.match(html, /aria-label="More"[\s\S]*?href="\/check-host"/);
  assert.match(html, /aria-label="Footer"[\s\S]*?href="\/check-host"/);
  assert.match(html, /href="\/status"/);
  assert.match(html, /Check-Host\.net/);
  assert.match(html, /Globalping/);
  assert.match(html, /href="\/fonts\/css2\?family=Geist/);
  assert.doesNotMatch(html, /href="https:\/\/check-host\.net/);
  assert.doesNotMatch(html, /check-report/);
  assert.doesNotMatch(html, /fonts\.googleapis\.com|fonts\.gstatic\.com/);

  // Every loaded resource (scripts, styles, images, fonts) and form target is same-origin.
  const attrs = [...html.matchAll(/<(?:link|script|img|source|form)\b[^>]*\b(?:href|src|action)=["']([^"']+)["']/g)].map(m => m[1]);
  for (const value of attrs) {
    if (value.startsWith('#') || value.startsWith('data:')) continue;
    assert.equal(new URL(value, 'https://vexostream.bond').origin, 'https://vexostream.bond', value);
  }
  assert.doesNotMatch(html, /href="https?:\/\/[^"]*(check-host\.net|globalping\.io)/);
  const fetches = [...html.matchAll(/\bfetch\(\s*(['"`])([^'"`]+)\1/g)].map(m => m[2]);
  for (const value of fetches) assert.ok(value.startsWith('/'), 'browser fetch must be same-origin: ' + value);
});

test('Worker-compatible fetch options: no redirect:"error" anywhere in the bundle', async () => {
  const fs = await import('node:fs/promises');
  const bundle = await fs.readFile(new URL('../dist/worker.js', import.meta.url), 'utf8');
  assert.doesNotMatch(bundle, /redirect:\s*["']error["']/);
});

test('falls back from Cloudflare DNS to Google DNS before refusing a check', async () => {
  setBehavior({ dns: 'cloudflare-down' });
  const { response, body } = await start('http');
  assert.equal(response.status, 200);
  assert.ok(body.id);
  setBehavior({ dns: 'unavailable' });
  const failed = await start('http');
  assert.equal(failed.response.status, 503);
  assert.match(failed.body.error, /Cloudflare and Google DNS/);
});

test('auto mode falls back to Globalping when Check-Host.net refuses, for all four check types', async () => {
  setBehavior({ regional: 'forbidden', gpResult: 'pending-once' });
  for (const type of ['ping', 'http', 'tcp', 'dns']) {
    const extra = type === 'tcp' ? 'port=443' : '';
    const { response, body } = await start(type, 'vexostream.bond', extra);
    assert.equal(response.status, 200, type);
    assert.equal(body.provider, 'globalping', type);
    assert.match(body.id, /^gp\./);
    assert.match(body.notice, /Check-Host.net denied the request \(HTTP 403\)\. Using Globalping instead/);
    assert.equal(body.error, null);
    const sent = gpBodies.at(-1);
    assert.equal(sent.target, 'vexostream.bond');
    assert.deepEqual(sent.locations, [{ country: 'US', limit: 2 }]);
    if (type === 'tcp') assert.deepEqual(sent.measurementOptions, { packets: 3, protocol: 'TCP', port: 443 });
    if (type === 'http') assert.equal(sent.measurementOptions.protocol, 'HTTPS');

    const first = await (await call('/api/check-host/result?id=' + encodeURIComponent(body.id) + '&type=' + type)).json();
    assert.equal(first.ok, true);
    assert.equal(first.done, false);
    assert.equal(first.nodes.length, 1);
    const done = await (await call('/api/check-host/result?id=' + encodeURIComponent(body.id) + '&type=' + type)).json();
    assert.equal(done.done, true);
    const r = done.results[done.nodes[0].id];
    assert.equal(r.done, true);
    assert.equal(r.ok, true, type);
    if (type === 'ping') { assert.equal(r.sent, 4); assert.equal(r.recv, 2); assert.equal(r.avg, 0.011); }
    if (type === 'http') assert.equal(r.code, 200);
    if (type === 'dns') assert.deepEqual(r.A, ['93.184.216.34']);
    assert.equal(done.nodes[0].cc, 'us');
  }
});

test('Globalping skips Iran when it has no probes there, and reports a combined failure honestly', async () => {
  setBehavior({ regional: 'forbidden', gp: 'no-iran' });
  const q = new URLSearchParams({ type: 'http', host: 'vexostream.bond', cc: 'ir,us' });
  const ok = await (await call('/api/check-host/start?' + q)).json();
  assert.equal(ok.provider, 'globalping');
  assert.match(ok.notice, /Iran was skipped/);

  setBehavior({ regional: 'limited', gp: 'limited' });
  const both = await start('http');
  assert.equal(both.body.id, null);
  assert.match(both.body.error, /Check-Host.net rate-limited.*Globalping rate-limited.*edge result only/);
  assert.equal(both.body.edge.ok, true);
});

test('provider modes: globalping-only, and edge-only never contacts probe networks', async () => {
  setBehavior();
  const before = seenProbeUrls.length;
  const gp = await start('http', 'vexostream.bond', '', { CHECK_HOST_PROVIDER: 'globalping' });
  assert.equal(gp.body.provider, 'globalping');
  assert.equal(seenProbeUrls.length, before, 'globalping mode must not call Check-Host.net');
  const gpBefore = gpBodies.length;
  const edge = await start('http', 'vexostream.bond', '', { CHECK_HOST_PROVIDER: 'edge' });
  assert.equal(edge.body.id, null);
  assert.match(edge.body.error, /turned off/);
  assert.equal(gpBodies.length, gpBefore);
  const ping = await start('ping', 'vexostream.bond', '', { CHECK_HOST_PROVIDER: 'edge' });
  assert.equal(ping.body.ok, false, 'edge cannot ping, so there is nothing to show as success');
});

test('Globalping token is sent only as a server-side Authorization header', async () => {
  setBehavior();
  let auth = null;
  const prev = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const u = new URL(typeof input === 'string' ? input : input.url);
    if (u.origin === 'https://api.globalping.io') auth = init.headers && init.headers.Authorization;
    return prev(input, init);
  };
  await start('http', 'vexostream.bond', '', { CHECK_HOST_PROVIDER: 'globalping', GLOBALPING_TOKEN: 'unit-test-token' });
  globalThis.fetch = prev;
  assert.equal(auth, 'Bearer unit-test-token');
  const html = await (await call('/check-host', { GLOBALPING_TOKEN: 'unit-test-token' })).text();
  assert.doesNotMatch(html, /unit-test-token/);
});

test('same-origin font route serves only the site font sets and rewrites font files to /fonts/gstatic', async () => {
  setBehavior();
  const prev = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const u = new URL(typeof input === 'string' ? input : input.url);
    if (u.origin === 'https://fonts.googleapis.com') return new Response("@font-face{font-family:'Archivo';src:url(https://fonts.gstatic.com/s/archivo/v19/k3k6o8UDI-1M0wlSV9XAw6lQkqWY8Q82sJaRE-NWIDdgffTTNDNZ9xds.woff2) format('woff2')}", { headers: { 'Content-Type': 'text/css' } });
    if (u.origin === 'https://fonts.gstatic.com') return new Response(new Uint8Array([119, 79, 70, 50]), { headers: { 'Content-Type': 'font/woff2' } });
    return prev(input, init);
  };
  const html = await (await call('/check-host')).text();
  const href = /href="(\/fonts\/css2\?[^"]+)"/.exec(html)[1].replace(/&amp;/g, '&');
  const css = await call(href);
  assert.equal(css.status, 200);
  const text = await css.text();
  assert.match(text, /url\(\/fonts\/gstatic\/s\/archivo\//);
  assert.doesNotMatch(text, /fonts\.gstatic\.com/);
  const file = await call('/fonts/gstatic/s/archivo/v19/k3k6o8UDI-1M0wlSV9XAw6lQkqWY8Q82sJaRE-NWIDdgffTTNDNZ9xds.woff2');
  assert.equal(file.status, 200);
  assert.equal(file.headers.get('Content-Type'), 'font/woff2');
  assert.equal((await call('/fonts/css2?family=Evil+Font')).status, 404, 'not an open proxy');
  assert.equal((await call('/fonts/gstatic/../../etc/passwd')).status, 404);
  globalThis.fetch = prev;
});

test.after(() => {
  globalThis.fetch = realFetch;
});
