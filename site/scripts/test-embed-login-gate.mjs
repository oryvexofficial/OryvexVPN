import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;

const settings = new Map([
  ['members_config', JSON.stringify({ requireLogin: true, embedsToo: true, modelsLogin: false })]
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
  STREAM_SIGN_SECRET: 'test-embed-login-gate-secret',
  EDGE_TOKEN: 'test-embed-login-gate-edge',
  RAILWAY_URL: 'https://core-embed-login-gate.example.test',
  DB: db
};
const ctx = { waitUntil() {} };
const headers = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
  'Accept-Language': 'en-US,en;q=0.9'
};

test('member-gated embed login opens the top page and returns to that embed', async () => {
  const target = 'https://www.xvideos.com/video123456/example';
  const encoded = Buffer.from(target).toString('base64url');
  const response = await worker.fetch(new Request(`https://vexostream.bond/embed/${encoded}`, { headers }), env, ctx);
  assert.equal(response.status, 200);
  const html = await response.text();
  const loginUrl = `https://vexostream.bond/login?next=${encodeURIComponent(`/embed/${encoded}`)}`;
  assert.ok(html.includes(`href="${loginUrl}" target="_top"`));
  assert.ok(html.includes('Log in to watch'));
  assert.ok(!html.includes('target="_blank"'));
});
