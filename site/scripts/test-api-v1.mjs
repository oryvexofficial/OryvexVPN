import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const api = await readFile(new URL('../src/05e-api-v1.ts', import.meta.url), 'utf8');
const router = await readFile(new URL('../src/07-router.ts', import.meta.url), 'utf8');
const wrangler = await readFile(new URL('../wrangler.toml', import.meta.url), 'utf8');
const migration = await readFile(new URL('../migrations/2026-11-11-api-sessions.sql', import.meta.url), 'utf8');
const adminMigration = await readFile(new URL('../migrations/2026-11-12-admin-api-sessions.sql', import.meta.url), 'utf8');
const social = await readFile(new URL('../src/05b-social.ts', import.meta.url), 'utf8');

test('Worker exposes the app pages through the versioned API', () => {
  for (const route of [
    "path === '/health'", "path === '/config'", "path === '/catalog'", "path === '/search'",
    "path === '/auth/signup'", "path === '/auth/login'", "path === '/auth/logout'", "path === '/account'",
    "path === '/videos/extract'", "path === '/embed/grant'", "path === '/models'", "path === '/status'", "path === '/social'",
    "path === '/developers'", "path === '/image'", "path === '/check-host/start'", "path === '/check-host/result'",
    "defaultQuery: cfg.defaultQuery || 'trending'","path === '/admin/team'","path === '/admin/password'",
    "path === '/admin/members'","path === '/admin/live'","path === '/admin/social'","path === '/admin/telegram'","path === '/admin/operations'",
    "action === 'check_channel'", "action === 'repair'"
  ]) assert.ok(api.includes(route), `missing API contract: ${route}`);
  assert.ok(social.includes("action === 'bot_import_tg'"), 'missing Telegram bot import action');
  assert.ok(router.includes('handleAppApiV1(request, url, env, ctx)'));
  assert.ok(router.includes("'Access-Control-Allow-Headers': 'Authorization, Content-Type"));
});

test('API uses a zone route, not a custom domain, and sessions persist hashes only', () => {
  assert.ok(/pattern = "api\.vexostream\.bond\/\*", zone_name = "vexostream\.bond"/.test(wrangler));
  assert.ok(!wrangler.includes('custom_domain = true'));
  assert.ok(migration.includes('token_hash TEXT PRIMARY KEY'));
  assert.ok(migration.includes('revoked_at TEXT'));
  assert.ok(!migration.toLowerCase().includes('token TEXT'));
  assert.ok(adminMigration.includes('CREATE TABLE IF NOT EXISTS admin_api_sessions'));
  assert.ok(adminMigration.includes('token_hash TEXT PRIMARY KEY'));
  assert.ok(!adminMigration.toLowerCase().includes('token TEXT'));
});

const worker = (await import('../dist/worker.js')).default;
const testAppKey = 'test-app-key-for-ci-only';

test('API hostname serves no website at its root', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/'), {
    STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey
  }, { waitUntil() {} });
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not Found');
});

test('API hostname returns 404 for website paths', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/browse'), {
    STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey
  }, { waitUntil() {} });
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not Found');
});

test('API endpoints reject missing or wrong app keys', async () => {
  for (const headers of [
    { 'User-Agent': 'VexoStream-Test/1.0', Accept: 'application/json' },
    { 'User-Agent': 'VexoStream-Test/1.0', Accept: 'application/json', 'X-App-Key': 'wrong-key' }
  ]) {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/health', { headers }), {
      STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey
    }, { waitUntil() {} });
    assert.equal(response.status, 401);
  }
});

test('fallback API host also requires APP_KEY and accepts the configured key', async () => {
  const env = { STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey };
  const missing = await worker.fetch(new Request('https://vexostream.bond/api/v1/health', {
    headers: { 'User-Agent': 'VexoStream-Test/1.0', Accept: 'application/json', 'Accept-Language': 'en-US' }
  }), env, { waitUntil() {} });
  assert.equal(missing.status, 401);
  const valid = await worker.fetch(new Request('https://vexostream.bond/api/v1/health', {
    headers: { 'User-Agent': 'VexoStream-Test/1.0', Accept: 'application/json', 'Accept-Language': 'en-US', 'X-App-Key': testAppKey }
  }), env, { waitUntil() {} });
  assert.equal(valid.status, 200);
});

test('API hostname returns 404 even when app secrets are missing', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/'), {}, { waitUntil() {} });
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not Found');
});

test('API health endpoint requires the app key', async () => {
  const request = new Request('https://api.vexostream.bond/api/v1/health', {
    headers: { 'User-Agent': 'VexoStream-Test/1.0', Accept: 'application/json', 'X-App-Key': testAppKey }
  });
  const response = await worker.fetch(request, { STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey }, { waitUntil() {} });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
  const payload = await response.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.version, 1);
});

test('API preflight accepts the bearer Authorization header', async () => {
  const request = new Request('https://api.vexostream.bond/api/v1/account', {
    method: 'OPTIONS',
    headers: { Origin: 'null', 'Access-Control-Request-Method': 'GET', 'Access-Control-Request-Headers': 'authorization, x-app-key' }
  });
  const response = await worker.fetch(request, { STREAM_SIGN_SECRET: 'test-secret-for-ci-only', EDGE_TOKEN: 'edge-test-token', APP_KEY: testAppKey }, { waitUntil() {} });
  assert.equal(response.status, 204);
  assert.match(response.headers.get('Access-Control-Allow-Headers') || '', /Authorization/i);
  assert.match(response.headers.get('Access-Control-Allow-Headers') || '', /X-App-Key/i);
});

