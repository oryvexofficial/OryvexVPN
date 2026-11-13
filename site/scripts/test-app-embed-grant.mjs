import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;

const appKey = 'test-app-embed-grant-key';
const appToken = 'a'.repeat(64);
const memberId = 73;
const memberStamp = 'test-member-stamp';
const memberSessionHash = createHash('sha256').update(appToken).digest('hex');
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
        if (/SELECT value FROM settings/i.test(this.sql)) {
          const value = settings.get(String(this.values[0]));
          return value == null ? null : { value };
        }
        if (/FROM api_sessions s JOIN members m/i.test(this.sql)) {
          if (String(this.values[0]) !== memberSessionHash) return null;
          return {
            token_hash: memberSessionHash,
            member_id: memberId,
            session_stamp: memberStamp,
            expires_at: Math.floor(Date.now() / 1000) + 3600,
            username: 'Viewer',
            member_stamp: memberStamp,
            disabled: 0,
            created_at: '2026-11-12',
            last_login_at: '2026-11-12'
          };
        }
        return null;
      }
    };
    return statement;
  }
};
const env = {
  STREAM_SIGN_SECRET: 'test-app-embed-grant-secret',
  EDGE_TOKEN: 'test-app-embed-grant-edge',
  APP_KEY: appKey,
  RAILWAY_URL: 'https://core-app-embed-grant.example.test',
  DB: db
};
const ctx = { waitUntil() {} };
const ip = '203.0.113.91';
const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36';
const appHeaders = {
  'User-Agent': 'VexoStream-Windows/1.1',
  'Accept-Language': 'en-US,en;q=0.9',
  'X-App-Key': appKey,
  Authorization: `Bearer ${appToken}`
};
const videoUrl = 'https://www.pornhub.com/view_video.php?viewkey=ph123456';
const encodedVideo = Buffer.from(videoUrl).toString('base64url');

async function issueGrant(url = videoUrl, headers = appHeaders) {
  return worker.fetch(new Request('https://api.vexostream.bond/api/v1/embed/grant', {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify({ url })
  }), env, ctx);
}

test('authenticated app member can mint a short-lived grant for a supported embed video', async () => {
  const response = await issueGrant();
  assert.equal(response.status, 200, await response.clone().text());
  const data = await response.json();
  assert.match(data.grant, /^\d{10}\.[a-f0-9]{64}$/);
  assert.ok(data.expiresAt > Math.floor(Date.now() / 1000));
  assert.ok(data.expiresAt <= Math.floor(Date.now() / 1000) + 300);
});

test('embed grant endpoint rejects anonymous, malformed, and unlisted targets', async () => {
  const anonymous = { ...appHeaders };
  delete anonymous.Authorization;
  assert.equal((await issueGrant(videoUrl, anonymous)).status, 401);
  assert.equal((await issueGrant('https://example.com/video/123')).status, 400);
  assert.equal((await issueGrant('https://www.pornhub.com.attacker.example/view_video.php?viewkey=ph123456')).status, 400);
});

test('app grant opens the member-gated VexoStream embed and authorizes only its matching extraction', async () => {
  const issued = await (await issueGrant()).json();
  const embedUrl = new URL(`https://vexostream.bond/embed/${encodedVideo}`);
  embedUrl.searchParams.set('app_grant', issued.grant);
  const appEmbedUrl = new URL(`https://vexostream.bond/embed/for/app/${encodedVideo}`);
  appEmbedUrl.searchParams.set('app_grant', issued.grant);
  const pageRequestHeaders = {
    'User-Agent': ua,
    'Accept-Language': 'en-US,en;q=0.9',
    'CF-Connecting-IP': ip
  };
  const appPage = await worker.fetch(new Request(appEmbedUrl, { headers: pageRequestHeaders }), env, ctx);
  assert.equal(appPage.status, 200);
  const appHtml = await appPage.text();
  assert.match(appHtml, /class="embed app-embed"/);
  assert.match(appHtml, /"appMode":true/);
  assert.match(appHtml, /searchParams\.delete\("app_grant"\)/);
  assert.doesNotMatch(appHtml, /Videos are for VexoStream members|Please log in first\./);

  const page = await worker.fetch(new Request(embedUrl, { headers: pageRequestHeaders }), env, ctx);
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /id="vxPoster"/);
  assert.match(html, /appGrant/);
  assert.match(html, /searchParams\.delete\("app_grant"\)/);
  assert.ok(html.indexOf('searchParams.delete("app_grant")') < html.indexOf('id="hlsjs"'));
  assert.doesNotMatch(html, /Videos are for VexoStream members|Please log in first\./);

  const config = appHtml.match(/window\.VX=(\{.*?\});window\.API_TOKEN/s);
  assert.ok(config, 'app embed page contains the browser session config');
  const browserToken = JSON.parse(config[1]).token;
  assert.match(browserToken, /^v1\./);

  const originalFetch = globalThis.fetch;
  let upstreamTarget;
  globalThis.fetch = async (input) => {
    upstreamTarget = new URL(typeof input === 'string' ? input : input.url);
    return new Response(JSON.stringify({
      status: 'success',
      title: 'Embed grant test',
      streams: {
        qualities: [{ quality: '480p', type: 'mp4', url: 'https://cdn.example.test/video.mp4' }],
        fallback: []
      }
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const extraction = new URL('https://vexostream.bond/api/extract');
    extraction.searchParams.set('url', videoUrl);
    extraction.searchParams.set('token', browserToken);
    assert.equal(extraction.searchParams.has('app_grant'), false);
    const stream = await worker.fetch(new Request(extraction, {
      headers: {
        ...pageRequestHeaders,
        'X-Edge-Token': browserToken,
        'X-Vexo-Embed-Grant': issued.grant,
        Referer: `https://vexostream.bond/embed/for/app/${encodedVideo}`
      }
    }), env, ctx);
    assert.equal(stream.status, 200, await stream.clone().text());
    assert.equal(upstreamTarget.pathname, '/api/extract');
    const data = await stream.json();
    assert.ok(data.streams.qualities[0].x_sig);

    const mismatch = new URL('https://vexostream.bond/api/extract');
    mismatch.searchParams.set('url', 'https://www.pornhub.com/view_video.php?viewkey=ph654321');
    mismatch.searchParams.set('token', browserToken);
    const denied = await worker.fetch(new Request(mismatch, {
      headers: {
        ...pageRequestHeaders,
        'X-Edge-Token': browserToken,
        'X-Vexo-Embed-Grant': issued.grant,
        Referer: `https://vexostream.bond/embed/for/app/${encodedVideo}`
      }
    }), env, ctx);
    assert.equal(denied.status, 401);
    assert.equal((await denied.json()).code, 'login');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('expired grants do not bypass the regular member gate', async () => {
  const expired = `${Math.floor(Date.now() / 1000) - 10}.${'0'.repeat(64)}`;
  const url = new URL(`https://vexostream.bond/embed/${encodedVideo}`);
  url.searchParams.set('app_grant', expired);
  const response = await worker.fetch(new Request(url, {
    headers: { 'User-Agent': ua, 'Accept-Language': 'en-US,en;q=0.9', 'CF-Connecting-IP': ip }
  }), env, ctx);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Please log in first\./);
});
