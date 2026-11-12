import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;
const appKey = 'test-search-default-app-key';
const savedDefaultQuery = 'Brazzers';
let forwardedUrl;
const db = {
  prepare(sql) {
    const statement = {
      sql, values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() { return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] }; },
      async first() {
        if (!this.sql.includes('SELECT value FROM settings')) return null;
        if (this.values[0] === 'provider_config') return { value: JSON.stringify({ defaultProvider: 'pornhub', defaultQuery: savedDefaultQuery }) };
        return null;
      }
    };
    return statement;
  }
};
const env = {
  STREAM_SIGN_SECRET: 'test-search-default-secret',
  EDGE_TOKEN: 'test-search-default-edge',
  APP_KEY: appKey,
  RAILWAY_URL: 'https://core-search-default.example.test',
  DB: db
};
const ctx = { waitUntil() {} };
const headers = { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': appKey };

test('app config exposes the saved admin default search word', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/config', { headers }), env, ctx);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.defaultQuery, savedDefaultQuery);
});

test('catalog requests with no query use the saved admin default search word', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    forwardedUrl = new URL(typeof input === 'string' ? input : input.url);
    return new Response(JSON.stringify({ videos: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/catalog?provider=pornhub&page=1', { headers }), env, ctx);
    assert.equal(response.status, 200);
    assert.equal(forwardedUrl.pathname, '/api/explore');
    assert.equal(forwardedUrl.searchParams.get('q'), savedDefaultQuery);
    assert.equal(forwardedUrl.searchParams.get('provider'), 'pornhub');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('explicit app search terms still override the configured default', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    forwardedUrl = new URL(typeof input === 'string' ? input : input.url);
    return new Response(JSON.stringify({ videos: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/search?provider=pornhub&q=custom+term', { headers }), env, ctx);
    assert.equal(response.status, 200);
    assert.equal(forwardedUrl.searchParams.get('q'), 'custom term');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
