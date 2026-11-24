const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { getDb, initSchema } = require('../src/db');
const { createApp } = require('../src/app');

function httpGet(port, path) {
  return new Promise((resolve, reject) => {
    const req = http.get({ hostname: '127.0.0.1', port, path }, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    });
    req.on('error', reject);
  });
}

describe('SEO Routes (/robots.txt, /sitemap.xml, /medications, /medications/:slug)', () => {
  let db;
  let server;
  let port;

  before(async () => {
    process.env.NODE_ENV = 'test';
    db = getDb(':memory:');
    initSchema(db);
    const info = db.prepare(`
      INSERT INTO drugs (rxcui, brand_name, generic_name, strength, drug_type)
      VALUES ('262095', 'Lipitor', 'atorvastatin calcium', '10 mg', 'small_molecule')
    `).run();
    db.prepare(`
      INSERT INTO generic_status (drug_id, source, application_number, is_approved_generic)
      VALUES (?, 'orange_book', 'ANDA076477', 1)
    `).run(info.lastInsertRowid);
    db.prepare(`
      INSERT INTO market_availability (drug_id, source, ndc, marketing_category, is_commercialized, nadac_per_unit)
      VALUES (?, 'cms_nadac', '00071-0155-23', 'NDA', 1, 12.50),
             (?, 'cms_nadac', '00093-5056-98', 'ANDA', 1, 0.15)
    `).run(info.lastInsertRowid, info.lastInsertRowid);

    const app = createApp(db, { enableRateLimiter: false });
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', () => {
        port = server.address().port;
        resolve();
      });
    });
  });

  after(() => {
    if (server) server.close();
    if (db) db.close();
  });

  it('serves /robots.txt with sitemap pointer and /api/ disallow', async () => {
    const res = await httpGet(port, '/robots.txt');
    assert.strictEqual(res.status, 200);
    assert.match(res.body, /Sitemap: https:\/\/rx\.dangling-dice-studios\.com\/sitemap\.xml/);
    assert.match(res.body, /Disallow: \/api\//);
  });

  it('serves dynamic /sitemap.xml containing medication pages', async () => {
    const res = await httpGet(port, '/sitemap.xml');
    assert.strictEqual(res.status, 200);
    assert.match(res.body, /<urlset/);
    assert.match(res.body, /\/medications\/lipitor<\/loc>/);
  });

  it('serves /medications directory and individual /medications/lipitor page with JSON-LD', async () => {
    const dir = await httpGet(port, '/medications');
    assert.strictEqual(dir.status, 200);
    assert.match(dir.body, /Lipitor/);
    assert.match(dir.body, /Generic Available/);

    const page = await httpGet(port, '/medications/lipitor');
    assert.strictEqual(page.status, 200);
    assert.strictEqual(page.headers['referrer-policy'], 'no-referrer');
    assert.match(page.body, /application\/ld\+json/);
    assert.match(page.body, /atorvastatin calcium/);
    assert.match(page.body, /SingleCare Coupon/);
    assert.match(page.body, /GoodRx Coupon/);
  });

  it('returns 404 for unknown medication slugs', async () => {
    const res = await httpGet(port, '/medications/nonexistent-drug-xyz');
    assert.strictEqual(res.status, 404);
  });
});
