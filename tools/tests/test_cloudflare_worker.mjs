import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sourcePath = new URL('../../fox/docs/relay/cloudflare/worker.js', import.meta.url);
const bundledPath = new URL('../../apps/shared/assets/cloudflare/worker.js', import.meta.url);
const source = readFileSync(sourcePath, 'utf8');
assert.equal(readFileSync(bundledPath, 'utf8'), source, 'the app bundle must use the reviewed Worker source');
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const { default: worker } = await import(moduleUrl);

const status = await worker.fetch(new Request('https://relay.example.workers.dev/'), { SECRET: 's'.repeat(40) });
assert.equal(status.status, 200);
assert.match(status.headers.get('content-type'), /text\/html/);
assert.match(await status.text(), /OryvexVPN Relay for Fox connection was created/);
assert.match(await (await worker.fetch(new Request('https://relay.example.workers.dev/'))).text(), /Created by Muvixo/);

const health = await worker.fetch(new Request(`https://relay.example.workers.dev/?health=1&secret=${'s'.repeat(40)}`), { SECRET: 's'.repeat(40) });
assert.equal(health.status, 200);
assert.deepEqual(await health.json(), { relay: 'oryvex-vpn', version: 1, ready: true });

const denied = await worker.fetch(new Request('https://relay.example.workers.dev/?health=1&secret=wrong'), { SECRET: 's'.repeat(40) });
assert.equal(denied.status, 403);

const noSecret = await worker.fetch(new Request('https://relay.example.workers.dev/?health=1&secret=wrong'));
assert.equal(noSecret.status, 503);

let seen;
globalThis.fetch = async (url, options) => {
  seen = { url: url.href, options };
  return new Response('ok', { status: 200, headers: { 'content-type': 'text/plain', 'connection': 'close' } });
};
const pass = await worker.fetch(new Request(`https://relay.example.workers.dev/?secret=${'s'.repeat(40)}&url=${encodeURIComponent('https://accounts.firefox.com/v1/test')}`, {
  method: 'POST',
  headers: { 'authorization': 'Bearer fixture', 'x-forwarded-for': '127.0.0.1', 'cf-ray': 'fixture' },
  body: 'payload',
}), { SECRET: 's'.repeat(40) });
assert.equal(pass.status, 200);
assert.equal(pass.headers.get('x-oryvex-relay'), '1');
assert.equal(seen.url, 'https://accounts.firefox.com/v1/test');
assert.equal(seen.options.headers.get('authorization'), 'Bearer fixture');
assert.equal(seen.options.headers.has('x-forwarded-for'), false);
assert.equal(seen.options.headers.has('cf-ray'), false);
assert.equal(seen.options.redirect, 'manual');

globalThis.fetch = async (_url, options) => {
  assert.equal(options.redirect, 'manual');
  return new Response(null, { status: 302, headers: { location: 'https://accounts.firefox.com/next' } });
};
const redirected = await worker.fetch(new Request(`https://relay.example.workers.dev/?secret=${'s'.repeat(40)}&url=${encodeURIComponent('https://accounts.firefox.com/start')}`), { SECRET: 's'.repeat(40) });
assert.equal(redirected.status, 302);
assert.equal(redirected.headers.get('location'), 'https://accounts.firefox.com/next');

const disallowed = await worker.fetch(new Request(`https://relay.example.workers.dev/?secret=${'s'.repeat(40)}&url=${encodeURIComponent('https://example.com/')}`), { SECRET: 's'.repeat(40) });
assert.equal(disallowed.status, 403);

console.log('Cloudflare Worker checks passed: status page, secret/health, allowlist, header filtering, and bundled-source parity.');
