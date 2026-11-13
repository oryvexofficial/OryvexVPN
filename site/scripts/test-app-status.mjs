import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.caches ??= { default: { async match() {}, async put() {} } };
const worker = (await import('../dist/worker.js')).default;

test('app status API includes 90-day history and incidents', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('ok', { status: 200 });
  const today = new Date().toISOString().slice(0, 10);
  const db = {
    prepare(sql) {
      return {
        bind() { return this; },
        async first() { return null; },
        async all() {
          if (sql.includes('status_history')) {
            return { results: [{ dt: today, status_code: 'degraded', note: JSON.stringify({ extract: 'degraded' }), created_at: `${today} 01:00:00` }] };
          }
          return { results: [] };
        },
        async run() { return { success: true }; }
      };
    }
  };
  try {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/status', {
      headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': 'test-key' }
    }), {
      STREAM_SIGN_SECRET: 'test-secret', EDGE_TOKEN: 'test-edge', APP_KEY: 'test-key',
      RAILWAY_URL: 'https://core.example.test', DB: db, STATUS: db
    }, { waitUntil() {} });
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.history.tracked, 1);
    assert.equal(data.history.bars.extract.length, 90);
    assert.equal(data.history.bars.extract.at(-1).status, 'degraded');
    assert.equal(data.history.incidents.length, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
