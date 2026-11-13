import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.caches ??= { default: { async match() { return undefined; }, async put() {} } };
const worker = (await import('../dist/worker.js')).default;

const settings = new Map([
  ['members_config', JSON.stringify({ requireLogin: false, embedsToo: false, modelsLogin: false, allowSignup: true })]
]);
const db = {
  prepare(sql) {
    const statement = {
      sql,
      values: [],
      bind(...values) { this.values = values; return this; },
      async run() { return { success: true, meta: { changes: 1 } }; },
      async all() { return { results: [{ name: 'id' }, { name: 'key' }, { name: 'value' }, { name: 'updated_at' }] }; },
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
  STREAM_SIGN_SECRET: 'test-provider-embed-secret',
  EDGE_TOKEN: 'test-provider-embed-edge',
  RAILWAY_URL: 'https://core-provider-embed.example.test',
  DB: db
};
const ctx = { waitUntil() {} };
const headers = { 'User-Agent': 'Mozilla/5.0 VexoStream-Embed-Test/1.0' };

async function watchPage(target) {
  const encoded = Buffer.from(target).toString('base64url');
  return worker.fetch(
    new Request(`https://vexostream.bond/video/${encoded}`, { headers }),
    env,
    ctx
  );
}

test('watch page offers a VexoStream /embed link for supported provider page formats', async () => {
  const sources = [
    'https://www.pornhub.com/view_video.php?viewkey=ph123456',
    'https://www.xvideos.com/video123456/example',
    'https://www.xnxx.com/video-12345678/example',
    'https://www.youporn.com/watch/505835/example-title/',
    'https://www.redtube.com/1795463'
  ];

  for (const source of sources) {
    const encoded = Buffer.from(source).toString('base64url');
    const expectedEmbed = `https://vexostream.bond/embed/${encoded}`;
    const response = await watchPage(source);
    assert.equal(response.status, 200, source);
    const html = await response.text();
    assert.ok(html.includes('id="vexoEmbedLink"'), source);
    assert.ok(html.includes(`href="${expectedEmbed}"`), source);
    assert.ok(html.includes('id="btnCopyVexoEmbed"'), source);
    assert.ok(html.includes('VexoStream’s own embedded player'), source);
  }
});

test('watch page does not create embeds for unsupported video URLs or deceptive hosts', async () => {
  for (const source of [
    'https://www.pornhub.com/?viewkey=ph123456',
    'https://www.pornhub.com.attacker.example/view_video.php?viewkey=ph123456',
    'https://www.xvideos.com.attacker.example/video123456/example'
  ]) {
    const response = await watchPage(source);
    assert.equal(response.status, 200, source);
    const html = await response.text();
    assert.ok(!html.includes('id="vexoEmbedLink"'), source);
    assert.ok(html.includes('id="vexoEmbedUnavailable"'), source);
  }
});
