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

test('website directory renders podium markup and popularity ranking code', async () => {
  const response = await worker.fetch(new Request('https://vexostream.bond/models', {
    headers: { 'User-Agent': 'Mozilla/5.0 VexoStream-Test/1.0', 'Accept-Language': 'en-US' }
  }), {
    STREAM_SIGN_SECRET: 'test-podium-secret', EDGE_TOKEN: 'test-podium-edge',
    APP_KEY: appKey, RAILWAY_URL: 'https://core.example.test', DB: db
  }, { waitUntil() {} });
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /id="modelsPodium"/);
  assert.match(html, /state\.page === 1 && !state\.q && list\.length >= 3/);
  assert.match(html, /\[1, 0, 2\]\.forEach/);
  assert.match(html, /list\.slice\(ranked \? 3 : 0\)/);
  assert.match(html, /The leaderboard/);
  assert.match(html, /Top three profiles right now/);
  assert.match(html, /podium-entry\[data-rank="1"\]/);
  assert.match(html, /@media\(max-width:520px\)/);
});

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
    assert.equal(backendUrl.searchParams.get('gender'), 'Female');
    assert.equal(backendUrl.searchParams.get('sort'), 'popularity');
    assert.equal(backendUrl.searchParams.get('page'), '1');
    assert.equal(backendUrl.searchParams.has('search'), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test('app women/both/men filters map to the Core API gender values', async () => {
  const originalFetch = globalThis.fetch;
  const received = [];
  globalThis.fetch = async (input) => {
    received.push(new URL(typeof input === 'string' ? input : input.url).searchParams.get('gender'));
    return new Response(JSON.stringify({ models: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    for (const filter of ['women', 'both', 'men']) {
      const response = await worker.fetch(new Request(`https://api.vexostream.bond/api/v1/models?gender=${filter}`, {
        headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': appKey }
      }), {
        STREAM_SIGN_SECRET: 'test-app-models-secret', EDGE_TOKEN: 'test-app-models-edge', APP_KEY: appKey,
        RAILWAY_URL: 'https://core.example.test', DB: db
      }, { waitUntil() {} });
      assert.equal(response.status, 200);
    }
    assert.deepEqual(received, ['Female', 'Female,Male', 'Male']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('model profile keeps nested personal details, physical attributes, and images', async () => {
  const originalFetch = globalThis.fetch;
  const profile = {
    name: 'Example model',
    personal_details: { age: 29, country: 'France', birth_date: '1997-01-01' },
    physical_attributes: { height: '170 cm', hair_color: 'Brown' },
    images: ['https://img.example.test/first.jpg', 'https://img.example.test/second.jpg']
  };
  globalThis.fetch = async (input) => {
    const target = new URL(typeof input === 'string' ? input : input.url);
    assert.equal(target.pathname, '/api/models/example-model');
    return new Response(JSON.stringify(profile), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  try {
    const response = await worker.fetch(new Request('https://api.vexostream.bond/api/v1/models/example-model', {
      headers: { 'User-Agent': 'VexoStream-Windows/1.1', 'Accept-Language': 'en-US', 'X-App-Key': appKey }
    }), {
      STREAM_SIGN_SECRET: 'test-app-models-secret', EDGE_TOKEN: 'test-app-models-edge', APP_KEY: appKey,
      RAILWAY_URL: 'https://core.example.test', DB: db
    }, { waitUntil() {} });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), profile);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
