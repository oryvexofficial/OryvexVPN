import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;

const settings = new Map([
  ['members_config', JSON.stringify({ requireLogin: false, embedsToo: false, modelsLogin: false })]
]);
const db = {
  prepare(sql) {
    const statement = {
      sql,
      values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() {
        return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] };
      },
      async first() {
        if (!this.sql.includes('SELECT value FROM settings')) return null;
        const value = settings.get(String(this.values[0]));
        return value == null ? null : { value };
      }
    };
    return statement;
  }
};
const env = {
  STREAM_SIGN_SECRET: 'test-site-thumbnails-secret',
  EDGE_TOKEN: 'test-site-thumbnails-edge',
  RAILWAY_URL: 'https://core-site-thumbnails.example.test',
  DB: db
};
const ctx = { waitUntil() {} };
const browserHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
  'Accept-Language': 'en-US,en;q=0.9'
};

function pageUrl(path, target) {
  const encoded = Buffer.from(target).toString('base64url');
  return `https://vexostream.bond/${path}/${encoded}`;
}

test('/video and /embed pages render the shared poster loader and fallback logic', async () => {
  const target = 'https://www.xvideos.com/video123456/example';
  for (const path of ['video', 'embed']) {
    const response = await worker.fetch(
      new Request(pageUrl(path, target), { headers: browserHeaders }),
      env,
      ctx
    );
    assert.equal(response.status, 200, `${path} route`);
    const html = await response.text();
    assert.ok(html.includes('id="vxPoster"'), `${path} poster surface`);
    assert.ok(html.includes('function thumbnailCandidates'), `${path} thumbnail alias normalization`);
    assert.ok(html.includes('function resolvePosterFromSite'), `${path} site poster fallback`);
    assert.ok(html.includes("'/proxy-image?url='"), `${path} same-origin image proxy`);
  }
});

test('watch page keeps a fluid player and compact controls on phone widths', async () => {
  const target = 'https://www.xvideos.com/video123456/example';
  const response = await worker.fetch(
    new Request(pageUrl('video', target), { headers: browserHeaders }),
    env,
    ctx
  );
  const html = await response.text();
  const css = await readFile(new URL('../src/styles/app.css', import.meta.url), 'utf8');
  assert.equal(response.status, 200);
  assert.ok(html.includes('class="vx-player loading"'));
  assert.ok(css.includes('.watch-grid{width:100%;gap:0}'));
  assert.ok(css.includes('.stage .vx-player{width:100%;max-width:100vw;aspect-ratio:16/9}'));
  assert.ok(css.includes('@media (max-width:359px)'));
});

test('app_player compatibility query keeps the first-frame poster and shared poster loader', async () => {
  const target = 'https://www.xvideos.com/video123456/example';
  const response = await worker.fetch(new Request(pageUrl('embed', target) + '?app_player=1', {
    headers: browserHeaders
  }), env, ctx);
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('id="vxPoster"'), 'app embeds render the poster surface');
  assert.match(html, /"noPoster":false/);
  assert.match(html, /function resolvePosterFromSite/);
});

test('app-specific embed route paints the supplied listing thumbnail before player startup', async () => {
  const target = 'https://www.xvideos.com/video123456/example';
  const thumbnail = 'https://thumb.xvideos-cdn.com/video-thumb.jpg';
  const response = await worker.fetch(new Request(
    pageUrl('embed/for/app', target) + '?app_thumb=' + encodeURIComponent(thumbnail),
    { headers: browserHeaders }
  ), env, ctx);
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('class="embed app-embed"'));
  assert.ok(html.includes('id="vxPoster"'));
  assert.ok(html.includes('/proxy-image?url=https%3A%2F%2Fthumb.xvideos-cdn.com%2Fvideo-thumb.jpg'));
  assert.match(html, /"appMode":true/);
  assert.match(html, /searchParams\.delete\("app_thumb"\)/);
  const css = await readFile(new URL('../src/styles/app.css', import.meta.url), 'utf8');
  assert.ok(css.includes('html.app-embed #vxFs{display:none}'));
});

test('catalog pages render cards that load listing thumbnails immediately with a branded fallback', async () => {
  const response = await worker.fetch(new Request('https://vexostream.bond/browse/xvideos', {
    headers: browserHeaders
  }), env, ctx);
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('window.vxThumb = function'));
  assert.ok(html.includes('function videoThumbCandidates'));
  assert.ok(html.includes('if (listings.length) loadNextListing();'));
  assert.ok(html.includes('thumb-failed'));
  assert.ok(html.includes('window.vxUsable = function(list)'));
});

test('thumbnail metadata accepts nested aliases and stays limited to safe HTTP image URLs', async () => {
  const response = await worker.fetch(
    new Request(pageUrl('video', 'https://www.pornhub.com/view_video.php?viewkey=ph123456'), {
      headers: browserHeaders
    }),
    env,
    ctx
  );
  const html = await response.text();
  assert.match(html, /thumbnail_url/);
  assert.match(html, /default_thumb/);
  assert.match(html, /poster_url/);
  assert.match(html, /blank\|placeholder\|default/);
  assert.match(html, /https?:/);
});

test('image proxy uses matching provider Referers and retries without Origin when blocked', async () => {
  const originalFetch = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async (input, init = {}) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const headers = new Headers(init.headers);
    seen.push({ url: url.toString(), origin: headers.get('Origin'), referer: headers.get('Referer') });
    if (headers.has('Origin')) return new Response('blocked', { status: 403 });
    return new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), {
      status: 200,
      headers: { 'Content-Type': 'image/jpeg' }
    });
  };
  try {
    const cases = [
      ['https://thumb.xvideos-cdn.com/video.jpg', 'https://www.xvideos.com/'],
      ['https://thumb.xnxx-cdn.com/video.jpg', 'https://www.xnxx.com/'],
      ['https://ei.rdtcdn.com/video.jpg', 'https://www.redtube.com/'],
      ['https://thumb.ypncdn.com/video.jpg', 'https://www.youporn.com/'],
      ['https://ci.phncdn.com/video.jpg', 'https://www.pornhub.com/'],
      ['https://video.xhcdn.com/video.jpg', 'https://xhamster.com/']
    ];
    for (const [image, expectedReferer] of cases) {
      const requestUrl = new URL('https://vexostream.bond/proxy-image');
      requestUrl.searchParams.set('url', image);
      const response = await worker.fetch(new Request(requestUrl, {
        headers: { ...browserHeaders, 'X-Edge-Token': env.EDGE_TOKEN }
      }), env, ctx);

      assert.equal(response.status, 200, image);
      assert.equal(response.headers.get('Content-Type'), 'image/jpeg');
      const pair = seen.slice(-2);
      assert.equal(pair.length, 2, 'second request retries after the Origin-header rejection');
      assert.equal(pair[0].referer, expectedReferer, image);
      assert.equal(pair[0].origin, expectedReferer.replace(/\/$/, ''), image);
      assert.equal(pair[1].referer, expectedReferer, image);
      assert.equal(pair[1].origin, null, image);
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('batched site poster lookup forwards validated video pages to the poster backend', async () => {
  const originalFetch = globalThis.fetch;
  let forwarded;
  globalThis.fetch = async (input, init = {}) => {
    forwarded = new URL(typeof input === 'string' ? input : input.url);
    assert.equal(new Headers(init.headers).get('X-Edge-Token'), env.EDGE_TOKEN);
    return new Response(JSON.stringify({
      posters: { 'https://www.redtube.com/1795463': 'https://thumb.rdtcdn.com/1795463.jpg' }
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const target = 'https://www.redtube.com/1795463';
    const requestUrl = new URL('https://vexostream.bond/api/posters');
    requestUrl.searchParams.append('u', target);
    const response = await worker.fetch(new Request(requestUrl, {
      headers: { ...browserHeaders, 'X-Edge-Token': env.EDGE_TOKEN }
    }), env, ctx);
    assert.equal(response.status, 200);
    assert.equal(forwarded.pathname, '/api/posters');
    assert.deepEqual((await response.json()).posters, {
      'https://www.redtube.com/1795463': 'https://thumb.rdtcdn.com/1795463.jpg'
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
