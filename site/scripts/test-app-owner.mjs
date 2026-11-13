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
  const accountData = (await account.json()).account;
  assert.equal(accountData.role, 'Owner');
  assert.equal(accountData.isOwner, true);
  assert.equal(accountData.createdAt, '2026-11-12');
  assert.equal(accountData.lastLoginAt, '2026-11-12');
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

test('owner app embed and stream extraction continue working during maintenance', async () => {
  const videoUrl = 'https://www.pornhub.com/view_video.php?viewkey=ph123456';
  const grantResponse = await call('/embed/grant', {
    method: 'POST',
    token: ownerToken,
    body: { url: videoUrl }
  });
  assert.equal(grantResponse.status, 200, await grantResponse.clone().text());
  const grant = (await grantResponse.json()).grant;
  assert.match(grant, /^\d{10}\.admin\.[a-f0-9]{64}$/);

  const encodedVideo = Buffer.from(videoUrl).toString('base64url');
  const embedUrl = new URL(`https://vexostream.bond/embed/for/app/${encodedVideo}`);
  embedUrl.searchParams.set('app_grant', grant);
  embedUrl.searchParams.set('app_thumb', 'https://thumb.example.test/video.jpg');
  const pageHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': headers['Accept-Language'],
    'CF-Connecting-IP': '203.0.113.91'
  };
  const page = await worker.fetch(new Request(embedUrl, { headers: pageHeaders }), env, ctx);
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /id="vxVideo"/);
  assert.match(html, /class="embed app-embed"/);
  assert.match(html, /thumb\.example\.test/);
  assert.match(html, /"appMode":true/);
  assert.doesNotMatch(html, /We&rsquo;ll be right back\./);
  const config = html.match(/window\.VX=(\{.*?\});window\.API_TOKEN/s);
  assert.ok(config, 'embedded player contains its browser session config');
  const browserToken = JSON.parse(config[1]).token;

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const requestUrl = new URL(typeof input === 'string' ? input : input.url);
    if (requestUrl.pathname === '/api/posters') {
      return new Response(JSON.stringify({
        posters: { [videoUrl]: 'https://thumb.example.test/resolved.jpg' }
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }
    return new Response(JSON.stringify({
      status: 'success',
      title: 'Maintenance embed test',
      streams: {
        qualities: [{ quality: '480p', type: 'mp4', url: 'https://cdn.example.test/video.mp4' }],
        fallback: []
      }
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const extractUrl = new URL('https://vexostream.bond/api/extract');
    extractUrl.searchParams.set('url', videoUrl);
    extractUrl.searchParams.set('token', browserToken);
    const extraction = await worker.fetch(new Request(extractUrl, {
      headers: {
        ...pageHeaders,
        'X-Edge-Token': browserToken,
        'X-Vexo-Embed-Grant': grant,
        Referer: `https://vexostream.bond/embed/for/app/${encodedVideo}`
      }
    }), env, ctx);
    assert.equal(extraction.status, 200, await extraction.clone().text());

    const posterUrl = new URL('https://vexostream.bond/api/posters');
    posterUrl.searchParams.set('u', videoUrl);
    posterUrl.searchParams.set('token', browserToken);
    const posterResponse = await worker.fetch(new Request(posterUrl, {
      headers: {
        ...pageHeaders,
        'X-Edge-Token': browserToken,
        'X-Vexo-Embed-Grant': grant,
        Referer: `https://vexostream.bond/embed/for/app/${encodedVideo}`
      }
    }), env, ctx);
    assert.equal(posterResponse.status, 200, await posterResponse.clone().text());
    assert.deepEqual(await posterResponse.json(), {
      posters: { [videoUrl]: 'https://thumb.example.test/resolved.jpg' }
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

function seedAdmin(username, permissions, tokenChar) {
  const token = tokenChar.repeat(64);
  const stamp = `stamp-${username}`;
  admins.set(username.toLowerCase(), {
    username, permissions: JSON.stringify(permissions), is_owner: 0, disabled: 0, stamp,
    created_at: '2026-11-12', last_login: '2026-11-12'
  });
  const hash = createHash('sha256').update(token).digest('hex');
  sessions.set(hash, { username, stamp, expires_at: Math.floor(Date.now() / 1000) + 3600, revoked_at: null });
  return token;
}

test('delegated admin bypasses maintenance while anonymous requests remain blocked', async () => {
  const token = seedAdmin('siteadmin', ['site'], 'a');
  assert.equal((await call('/config')).status, 503);
  assert.equal((await call('/config', { token })).status, 200);
  const account = await call('/account', { token });
  assert.equal((await account.json()).account.role, 'Admin');
  const response = await call('/admin', { token });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.owner.permissions, ['site']);
  assert.equal(data.maintenanceOn, true);
  assert.equal(data.backendUrl, undefined);
  assert.equal(data.team, undefined);
  assert.equal(data.live, undefined);
});

test('delegated admin gets only assigned controls and mixed writes are rejected before mutation', async () => {
  const token = seedAdmin('providersadmin', ['providers'], 'b');
  const before = [...settings.entries()];
  const mixed = await call('/admin/settings', { method: 'POST', token, body: { defaultQuery: 'should not save', maintenanceOn: false } });
  assert.equal(mixed.status, 403);
  assert.deepEqual([...settings.entries()], before);
  assert.equal((await call('/admin/live', { method: 'POST', token, body: { config: {} } })).status, 403);
  assert.equal((await call('/admin/team', { method: 'POST', token, body: { action: 'remove', username: ownerName } })).status, 403);
  assert.equal((await call('/admin/settings', { method: 'POST', token, body: { defaultQuery: 'allowed search' } })).status, 200);
  const data = await (await call('/admin', { token })).json();
  assert.equal(data.defaultQuery, 'allowed search');
  assert.equal(data.members, undefined);
  assert.equal(data.maintenanceOn, undefined);
});

test('admin with no permissions can bypass maintenance but cannot change site settings', async () => {
  const token = seedAdmin('noperms', [], 'c');
  assert.equal((await call('/config', { token })).status, 200);
  const data = await (await call('/admin', { token })).json();
  assert.equal(data.owner.role, 'Admin');
  assert.equal(data.providers, undefined);
  assert.equal((await call('/admin/settings', { method: 'POST', token, body: { maintenanceOn: false } })).status, 403);
});
