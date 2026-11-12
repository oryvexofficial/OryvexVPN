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
      headers: { 'User-Agent': 'VexoStream-Test/1.0', 'CF-Connecting-IP': clientIp }
    }), env, { waitUntil() {} });
    assert.equal(media.status, 200);
    assert.equal(media.headers.get('Content-Type'), 'video/mp4');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
