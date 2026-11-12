import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;
const appKey = 'test-owner-app-key';
const ownerName = 'Muvixo';
const ownerPassword = 'CorrectOwnerPassword42!';
const ownerHash = createHash('sha256').update(ownerPassword).digest('hex');
const settings = new Map([['maintenance_mode', 'on']]);
const admins = new Map();
const sessions = new Map();
let ownerToken = '';

const db = {
  prepare(sql) {
    const statement = { sql, values: [], bind(...values) { this.values = values; return this; } };
    statement.run = async () => {
      const q = statement.sql;
      const v = statement.values;
      if (/INSERT INTO admin_users/i.test(q)) {
        admins.set(String(v[0]).toLowerCase(), {
          username: v[0], password_hash: v[1], salt: v[2], iterations: v[3], permissions: v[4],
          is_owner: v[5], disabled: 0, stamp: v[6], created_by: v[7], created_at: '2026-11-12', last_login: '2026-11-12'
        });
      } else if (/UPDATE admin_users SET last_login/i.test(q)) {
        const row = admins.get(String(v[0]).toLowerCase());
        if (row) row.last_login = '2026-11-12';
      } else if (/INSERT INTO admin_api_sessions/i.test(q)) {
        sessions.set(String(v[0]), { token_hash: v[0], username: v[1], stamp: v[2], expires_at: v[3], revoked_at: null });
      } else if (/UPDATE admin_api_sessions SET revoked_at/i.test(q)) {
        const row = sessions.get(String(v[0]));
        if (row) row.revoked_at = '2026-11-12';
      } else if (/INSERT INTO settings/i.test(q)) {
        settings.set(String(v[0]), String(v[1]));
      } else if (/DELETE FROM settings/i.test(q)) {
        // No duplicate settings in this fake store.
      }
      return { success: true, meta: { changes: 1 } };
    };
    statement.all = async () => ({ results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] });
    statement.first = async () => {
      const q = statement.sql;
      const v = statement.values;
      if (/SELECT value FROM settings/i.test(q)) return settings.has(String(v[0])) ? { value: settings.get(String(v[0])) } : null;
      if (/SELECT \* FROM admin_users/i.test(q)) return admins.get(String(v[0]).toLowerCase()) || null;
      if (/SELECT username FROM admin_users WHERE is_owner/i.test(q)) {
        const row = [...admins.values()].find((entry) => Number(entry.is_owner) === 1 && Number(entry.disabled) === 0);
        return row ? { username: row.username } : null;
      }
      if (/SELECT username, stamp, expires_at FROM admin_api_sessions/i.test(q)) {
        const row = sessions.get(String(v[0]));
        return row && !row.revoked_at ? { username: row.username, stamp: row.stamp, expires_at: row.expires_at } : null;
      }
      return null;
    };
    return statement;
  }
};
const env = {
  STREAM_SIGN_SECRET: 'test-owner-stream-secret',
  EDGE_TOKEN: 'test-owner-edge-token',
  APP_KEY: appKey,
  ADMIN_USERS: JSON.stringify({ [ownerName]: ownerHash }),
  DB: db
};
const ctx = { waitUntil() {} };
const headers = { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': appKey };

async function call(path, { method = 'GET', token, body } = {}) {
  const requestHeaders = { ...headers };
  if (token) requestHeaders.Authorization = `Bearer ${token}`;
  if (body) requestHeaders['Content-Type'] = 'application/json';
  return worker.fetch(new Request('https://api.vexostream.bond/api/v1' + path, {
    method,
    headers: requestHeaders,
    body: body ? JSON.stringify(body) : undefined
  }), env, ctx);
}

test('Owner can sign into the app during maintenance and open native admin settings', async () => {
  const login = await call('/auth/login', { method: 'POST', body: { username: ownerName, password: ownerPassword } });
  assert.equal(login.status, 200);
  const loginData = await login.json();
  assert.equal(loginData.account.role, 'Owner');
  assert.equal(loginData.account.isOwner, true);
  assert.ok(loginData.token);
  ownerToken = loginData.token;

  const admin = await call('/admin', { token: loginData.token });
  assert.equal(admin.status, 200);
  const adminData = await admin.json();
  assert.equal(adminData.owner.username, ownerName);
  assert.equal(adminData.maintenanceOn, true);

  const save = await call('/admin/settings', {
    method: 'POST', token: loginData.token,
    body: { defaultQuery: 'custom search', defaultProvider: 'pornhub', maintenanceOn: false }
  });
  assert.equal(save.status, 200);
  const saved = await save.json();
  assert.equal(saved.defaultQuery, 'custom search');
  assert.equal(saved.maintenanceOn, false);

  const account = await call('/account', { token: loginData.token });
  assert.equal(account.status, 200);
  assert.equal((await account.json()).account.role, 'Owner');
});

test('incorrect app key gets an explicit key error instead of a network diagnosis', async () => {
  const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/health', {
    headers: { ...headers, 'X-App-Key': 'wrong-key' }
  }), env, ctx);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).code, 'app_key_invalid');
});

test('ordinary members cannot sign in while maintenance mode is active', async () => {
  const ownerSave = await call('/admin/settings', { method: 'POST', token: ownerToken, body: { maintenanceOn: true } });
  assert.equal(ownerSave.status, 200);
  const response = await call('/auth/login', {
    method: 'POST', body: { username: 'regularmember', password: 'MemberPassword123!' }
  });
  assert.equal(response.status, 503);
  const payload = await response.json();
  assert.equal(payload.code, 'maintenance');
});
