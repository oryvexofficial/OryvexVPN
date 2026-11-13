import test from 'node:test';
import assert from 'node:assert/strict';

const worker = (await import('../dist/worker.js')).default;
const appKey = 'test-maintenance-app-key';

const maintenanceDb = {
  prepare(sql) {
    const statement = {
      sql,
      values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() { return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] }; },
      async first() {
        if (this.sql.includes('SELECT value FROM settings')) {
          return { value: this.values[0] === 'maintenance_mode' ? 'on' : null };
        }
        return null;
      }
    };
    return statement;
  }
};

const env = {
  STREAM_SIGN_SECRET: 'test-maintenance-secret',
  EDGE_TOKEN: 'test-maintenance-edge-token',
  APP_KEY: appKey,
  DB: maintenanceDb
};
const ctx = { waitUntil() {} };
const headers = { 'User-Agent': 'Mozilla/5.0 VexoStream maintenance test', 'Accept-Language': 'en-US,en;q=0.9' };

test('website renders its maintenance page while maintenance mode is enabled', async () => {
  const response = await worker.fetch(new Request('https://vexostream.bond/', { headers }), env, ctx);
  assert.equal(response.status, 503);
  assert.match(response.headers.get('Content-Type') || '', /text\/html/i);
  assert.match(await response.text(), /We&rsquo;ll be right back\./);
});

test('app API returns a typed maintenance response while maintenance mode is enabled', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/health', {
    headers: { ...headers, 'X-App-Key': appKey }
  }), env, ctx);
  assert.equal(response.status, 503);
  const payload = await response.json();
  assert.equal(payload.code, 'maintenance');
  assert.match(payload.error, /under maintenance/i);
});

test('API hostname still hides the website root during maintenance', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/', { headers }), env, ctx);
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not Found');
});
