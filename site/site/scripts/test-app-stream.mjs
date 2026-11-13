import test from 'node:test';
import assert from 'node:assert/strict';

const worker = (await import('../dist/worker.js')).default;
const appKey = 'test-app-stream-key';
globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const clientIp = '198.51.100.42';

const db = {
  prepare(sql) {
    const statement = {
      sql,
      values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() { return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] }; },
      async first() {
        if (this.sql.includes('SELECT value FROM settings')) {
          const key = this.values[0];
          if (key === 'members_config') return { value: JSON.stringify({ requireLogin: false, modelsLogin: false, allowSignup: true }) };
          return null;
        }
        return null;
      }
    };
    return statement;
  }
};

test('native extraction creates signed media playable without forwarding APP_KEY to HLS subrequests', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const target = new URL(typeof input === 'string' ? input : input.url);
    if (target.origin === 'https://core.example.test' && target.pathname === '/api/extract') {
      return new Response(JSON.stringify({
        status: 'success',
        streams: { qualities: [{ quality: '720p', type: 'mp4', url: 'https://cdn.example.test/video.mp4' }] }
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }
    if (target.origin === 'https://cdn.example.test') {
      return new Response(new Uint8Array([0, 0, 0, 0]), { status: 200, headers: { 'Content-Type': 'video/mp4' } });
    }
    throw new Error('Unexpected test fetch: ' + target.toString());
  };
  try {
    const env = {
      STREAM_SIGN_SECRET: 'test-app-stream-secret', EDGE_TOKEN: 'test-app-stream-edge',
      APP_KEY: appKey, RAILWAY_URL: 'https://core.example.test', DB: db
    };
    const extraction = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/videos/extract', {
      method: 'POST',
      headers: {
        'User-Agent': 'VexoStream-Test/1.0', 'Accept': 'application/json', 'Accept-Language': 'en-US',
        'Content-Type': 'application/json', 'X-App-Key': appKey, 'CF-Connecting-IP': clientIp
      },
      body: JSON.stringify({ url: 'https://www.pornhub.com/view_video.php?viewkey=abc12345' })
    }), env, { waitUntil() {} });
    assert.equal(extraction.status, 200);
    const data = await extraction.json();
    const quality = data.streams.qualities[0];
    assert.ok(quality.x_sig);
    const rawUrl = decodeURIComponent(atob(quality.x_url));
    const proxyUrl = new URL('https://api.vexostream.bond/proxy-video');
    proxyUrl.searchParams.set('url', rawUrl);
    proxyUrl.searchParams.set('sig', quality.x_sig);
    proxyUrl.searchParams.set('exp', String(quality.x_exp));
    const media = await worker.fetch(new Request(proxyUrl, {
      headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'CF-Connecting-IP': '203.0.113.61' }
    }), env, { waitUntil() {} });
    assert.equal(media.status, 200);
    assert.equal(media.headers.get('Content-Type'), 'video/mp4');
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test('native HLS proxy rewrites relative playlists, keys and segments to signed Worker URLs', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (input, init = {}) => {
    const target = new URL(typeof input === 'string' ? input : input.url);
    requests.push({ target, init });
    if (target.origin === 'https://core.example.test' && target.pathname === '/api/extract') {
      return new Response(JSON.stringify({ status: 'success', streams: { qualities: [{ quality: '720p', type: 'hls', url: 'https://cdn.example.test/hls/master.m3u8?token=abc%2B123' }], fallback: [] } }), {
        status: 200, headers: { 'Content-Type': 'application/json' }
      });
    }
    if (target.origin === 'https://cdn.example.test' && target.pathname === '/hls/master.m3u8') {
      return new Response('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nvariant/index.m3u8\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:4,\nsegment-1.ts\n#EXT-X-ENDLIST\n', {
        status: 200, headers: { 'Content-Type': 'application/vnd.apple.mpegurl' }
      });
    }
    if (target.origin === 'https://cdn.example.test' && target.pathname === '/hls/key.bin') {
      return new Response(new Uint8Array([1, 2, 3, 4]), { status: 200, headers: { 'Content-Type': 'application/octet-stream' } });
    }
    if (target.origin === 'https://cdn.example.test' && target.pathname === '/hls/segment-1.ts') {
      return new Response(new Uint8Array([0, 0, 0, 1]), { status: 200, headers: { 'Content-Type': 'video/mp2t' } });
    }
    throw new Error('Unexpected test fetch: ' + target.toString());
  };
  try {
    const env = { STREAM_SIGN_SECRET: 'test-hls-stream-secret', EDGE_TOKEN: 'test-hls-edge', APP_KEY: appKey, RAILWAY_URL: 'https://core.example.test', DB: db };
    const extraction = await worker.fetch(new Request('https://vexostream.bond/api/v1/videos/extract', {
      method: 'POST', headers: { 'User-Agent': 'VexoStream-Test/1.0', 'Accept-Language': 'en-US', 'Content-Type': 'application/json', 'X-App-Key': appKey, 'CF-Connecting-IP': clientIp },
      body: JSON.stringify({ url: 'https://www.pornhub.com/view_video.php?viewkey=abc12345' })
    }), env, { waitUntil() {} });
    assert.equal(extraction.status, 200);
    const data = await extraction.json();
    const quality = data.streams.qualities[0];
    const rawUrl = decodeURIComponent(atob(quality.x_url));
    assert.equal(rawUrl, 'https://cdn.example.test/hls/master.m3u8?token=abc%2B123');
    const matching = new URL('https://vexostream.bond/proxy-m3u8');
    matching.searchParams.set('url', rawUrl); matching.searchParams.set('sig', quality.x_sig); matching.searchParams.set('exp', String(quality.x_exp));
    const wrongTarget = new URL(matching);
    wrongTarget.searchParams.set('url', 'https://cdn.example.test/hls/other.m3u8?token=abc%2B123');
    const rejected = await worker.fetch(new Request(wrongTarget, { headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'CF-Connecting-IP': '203.0.113.62' } }), env, { waitUntil() {} });
    assert.equal(rejected.status, 403, 'portable signatures still cannot be reused for a different CDN URL');
    const proxy = new URL('https://vexostream.bond/proxy-m3u8');
    proxy.searchParams.set('url', rawUrl); proxy.searchParams.set('sig', quality.x_sig); proxy.searchParams.set('exp', String(quality.x_exp));
    const playlist = await worker.fetch(new Request(proxy, { headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'CF-Connecting-IP': '203.0.113.62' } }), env, { waitUntil() {} });
    assert.equal(playlist.status, 200);
    assert.match(playlist.headers.get('Content-Type'), /mpegurl/i);
    const text = await playlist.text();
    assert.match(text, /#EXTM3U/);
    assert.ok(text.includes('/proxy-m3u8.m3u8?'), 'nested playlist proxy URLs have a native-recognized HLS suffix');
    const urls = [...text.matchAll(/https:\/\/vexostream\.bond\/proxy-video(?:\.[a-z0-9]+)?\?[^\s"\']+/g)].map(m => new URL(m[0]));
    assert.equal(urls.length, 2, 'AES key and segment are both proxied');
    assert.ok(urls.some(u => u.pathname === '/proxy-video.ts'), 'extensionless key and segment URLs get a .ts suffix FFmpeg accepts');
    for (const url of urls) {
      assert.equal(url.searchParams.get('exp'), String(quality.x_exp));
      assert.ok(url.searchParams.get('sig'));
      const media = await worker.fetch(new Request(url, { headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'CF-Connecting-IP': '203.0.113.63' } }), env, { waitUntil() {} });
      assert.equal(media.status, 200);
    }
    assert.ok(requests.some(({ target }) => target.pathname === '/hls/master.m3u8'));
    assert.ok(requests.some(({ target }) => target.pathname === '/hls/key.bin'));
    assert.ok(requests.some(({ target }) => target.pathname === '/hls/segment-1.ts'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('native thumbnail proxy requests codec-friendly image formats', async () => {
  const originalFetch = globalThis.fetch;
  let upstreamAccept = '';
  globalThis.fetch = async (input, init = {}) => {
    const target = new URL(typeof input === 'string' ? input : input.url);
    if (target.origin === 'https://img.example.test') {
      upstreamAccept = new Headers(init.headers).get('Accept') || '';
      return new Response(new Uint8Array([0xff, 0xd8, 0xff]), {
        status: 200,
        headers: { 'Content-Type': 'image/jpeg' }
      });
    }
    throw new Error('Unexpected test fetch: ' + target.toString());
  };
  try {
    const env = { STREAM_SIGN_SECRET: 'test-image-stream-secret', EDGE_TOKEN: 'test-image-edge', APP_KEY: appKey, DB: db };
    const imageUrl = new URL('https://vexostream.bond/api/v1/image');
    imageUrl.searchParams.set('url', 'https://img.example.test/thumb.jpg');
    const response = await worker.fetch(new Request(imageUrl, {
      headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept': 'image/webp,image/png,image/jpeg,*/*', 'X-App-Key': appKey }
    }), env, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Content-Type'), 'image/jpeg');
    assert.ok(!upstreamAccept.includes('avif'));
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test('website media signatures remain client-IP-bound', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const target = new URL(typeof input === 'string' ? input : input.url);
    if (target.origin === 'https://core.example.test' && target.pathname === '/api/extract') {
      return new Response(JSON.stringify({ status: 'success', streams: { qualities: [{ quality: '360p', type: 'mp4', url: 'https://cdn.example.test/site-video.mp4' }] } }), {
        status: 200, headers: { 'Content-Type': 'application/json' }
      });
    }
    if (target.origin === 'https://cdn.example.test' && target.pathname === '/site-video.mp4') {
      return new Response(new Uint8Array([0, 0, 0, 0]), { status: 200, headers: { 'Content-Type': 'video/mp4' } });
    }
    throw new Error('Unexpected test fetch: ' + target.toString());
  };
  try {
    const env = { STREAM_SIGN_SECRET: 'test-app-stream-secret', EDGE_TOKEN: 'test-app-stream-edge', APP_KEY: appKey, RAILWAY_URL: 'https://core.example.test', DB: db };
    const extraction = await worker.fetch(new Request('https://vexostream.bond/api/extract?url=' + encodeURIComponent('https://www.pornhub.com/view_video.php?viewkey=abc12345'), {
      headers: { 'User-Agent': 'VexoStream-Site-Test/1.0', 'Accept-Language': 'en-US', 'X-Edge-Token': env.EDGE_TOKEN, 'CF-Connecting-IP': clientIp }
    }), env, { waitUntil() {} });
    assert.equal(extraction.status, 200, await extraction.clone().text());
    const quality = (await extraction.json()).streams.qualities[0];
    const target = decodeURIComponent(atob(quality.x_url));
    const url = new URL('https://vexostream.bond/proxy-video');
    url.searchParams.set('url', target); url.searchParams.set('sig', quality.x_sig); url.searchParams.set('exp', String(quality.x_exp));
    const valid = await worker.fetch(new Request(url, { headers: { 'User-Agent': 'VexoStream-Site-Test/1.0', 'CF-Connecting-IP': clientIp } }), env, { waitUntil() {} });
    assert.equal(valid.status, 200);
    const wrongIp = await worker.fetch(new Request(url, { headers: { 'User-Agent': 'VexoStream-Site-Test/1.0', 'CF-Connecting-IP': '203.0.113.88' } }), env, { waitUntil() {} });
    assert.equal(wrongIp.status, 403);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
