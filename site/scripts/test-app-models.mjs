import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;
const appKey = 'test-app-models-key';
let backendUrl;
const db = {
  prepare(sql) {
    const statement = {
      sql, values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() { return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] }; },
      async first() {
        if (this.sql.includes('SELECT value FROM settings')) {
          if (this.values[0] === 'members_config') return { value: JSON.stringify({ modelsLogin: false, requireLogin: false }) };
          return null;
        }
        return null;
      }
    };
    return statement;
  }
};

test('app Models request forwards the same Core query the web directory uses', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    backendUrl = new URL(typeof input === 'string' ? input : input.url);
    return new Response(JSON.stringify({ models: [{ name: 'Example model', image_url: 'https://img.example.test/model.jpg' }], has_more: false }), {
      status: 200, headers: { 'Content-Type': 'application/json' }
    });
  };
  try {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/models?gender=women&page=1', {
      headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': appKey }
    }), {
      STREAM_SIGN_SECRET: 'test-app-models-secret', EDGE_TOKEN: 'test-app-models-edge', APP_KEY: appKey,
      RAILWAY_URL: 'https://core.example.test', DB: db
    }, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { models: [{ name: 'Example model', image_url: 'https://img.example.test/model.jpg' }], has_more: false });
    assert.equal(backendUrl.origin, 'https://core.example.test');
    assert.equal(backendUrl.pathname, '/api/models');
    assert.equal(backendUrl.searchParams.get('gender'), 'women');
    assert.equal(backendUrl.searchParams.get('sort'), 'popularity');
    assert.equal(backendUrl.searchParams.get('page'), '1');
    assert.equal(backendUrl.searchParams.has('search'), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
