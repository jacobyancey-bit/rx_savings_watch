const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { runAllIngestions } = require('../src/ingestion');
const { GenericLaunchDetector } = require('../src/detector');
const { createApp } = require('../src/app');

// Helper to make mock requests to express app without spinning up network socket
function makeRequest(app, method, path, body = null, headers = {}) {
  return new Promise((resolve) => {
    const req = {
      method,
      url: path,
      body,
      headers: {
        'content-type': 'application/json',
        ...headers
      }
    };

    let statusCode = 200;
    const resHeaders = {};
    let responseBody = null;

    const res = {
      setHeader(k, v) { resHeaders[k.toLowerCase()] = v; },
      getHeader(k) { return resHeaders[k.toLowerCase()]; },
      removeHeader(k) { delete resHeaders[k.toLowerCase()]; },
      status(code) {
        statusCode = code;
        return this;
      },
      json(data) {
        responseBody = data;
        resolve({ statusCode, headers: resHeaders, body: responseBody });
      },
      send(data) {
        responseBody = data;
        resolve({ statusCode, headers: resHeaders, body: responseBody });
      }
    };

    app.handle(req, res);
  });
}

test('API: GET /health returns status healthy and security headers', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  const app = createApp(db, { enableRateLimiter: false });

  const res = await makeRequest(app, 'GET', '/health');
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.status, 'healthy');
  assert.ok(res.body.timestamp);

  // Verify privacy cache-control header
  assert.equal(res.headers['cache-control'], 'no-store, no-cache, must-revalidate, private');
  assert.equal(res.headers['x-content-type-options'], 'nosniff');
});

test('API: POST /api/check-updates rejects missing or invalid inputs', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  const app = createApp(db, { enableRateLimiter: false });

  // Missing rxcuis
  const res1 = await makeRequest(app, 'POST', '/api/check-updates', {});
  assert.equal(res1.statusCode, 400);

  // Empty rxcuis
  const res2 = await makeRequest(app, 'POST', '/api/check-updates', { rxcuis: [] });
  assert.equal(res2.statusCode, 400);

  // Exceeding maximum RXCUI limit (bounds check)
  const tooMany = Array.from({ length: 51 }, (_, i) => `rxcui_${i}`);
  const res3 = await makeRequest(app, 'POST', '/api/check-updates', { rxcuis: tooMany });
  assert.equal(res3.statusCode, 400);
  assert.ok(res3.body.message.includes('Maximum allowed'));

  // Invalid date format
  const res4 = await makeRequest(app, 'POST', '/api/check-updates', {
    rxcuis: ['855333'],
    last_checked: 'invalid-date'
  });
  assert.equal(res4.statusCode, 400);
});

test('API: POST /api/check-updates anonymous status check and alert filtering', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  await runAllIngestions(db);

  // Run detector to generate alerts
  const detector = new GenericLaunchDetector(db);
  detector.runAll({ persistAlert: true });

  const app = createApp(db, { enableRateLimiter: false });

  // Check updates for Vyvanse (855333) and Eliquis (1364430)
  const res1 = await makeRequest(app, 'POST', '/api/check-updates', {
    rxcuis: ['855333', '1364430'],
    last_checked: '2020-01-01T00:00:00Z'
  });

  assert.equal(res1.statusCode, 200);
  assert.equal(res1.body.success, true);
  assert.equal(res1.body.drugs.length, 2);

  const vyvanse = res1.body.drugs.find(d => d.rxcui === '855333');
  const eliquis = res1.body.drugs.find(d => d.rxcui === '1364430');

  // Vyvanse checks
  assert.equal(vyvanse.brand_name, 'Vyvanse');
  assert.equal(vyvanse.has_approved_generic, true);
  assert.equal(vyvanse.commercial_generic_available, true);
  assert.ok(vyvanse.pricing.estimated_savings_pct > 80, 'Vyvanse savings should be > 80%');
  assert.equal(vyvanse.has_active_shortage, true, 'Vyvanse should report active shortage');
  assert.ok(vyvanse.new_alerts_count >= 1, 'Should have received launch alert since 2020');

  // Eliquis checks (brand-only)
  assert.equal(eliquis.brand_name, 'Eliquis');
  assert.equal(eliquis.has_approved_generic, false);
  assert.equal(eliquis.commercial_generic_available, false);
  assert.equal(eliquis.new_alerts_count, 0, 'Eliquis must have zero alerts');

  // Request 2: Checked AFTER launch date (e.g. 2026-01-01) -> 0 new alerts
  const res2 = await makeRequest(app, 'POST', '/api/check-updates', {
    rxcuis: ['855333'],
    last_checked: '2026-01-01T00:00:00Z'
  });

  assert.equal(res2.statusCode, 200);
  assert.equal(res2.body.updates_found, 0, 'No new alerts should be returned after launch date');
  assert.equal(res2.body.drugs[0].commercial_generic_available, true, 'Snapshot still reflects available generic');
});

test('API: GET /api/drugs supports search query and pagination', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  await runAllIngestions(db);
  const app = createApp(db, { enableRateLimiter: false });

  // 1. List all
  const resAll = await makeRequest(app, 'GET', '/api/drugs');
  assert.equal(resAll.statusCode, 200);
  assert.ok(resAll.body.total >= 5);

  // 2. Search query 'vyvanse'
  const resVyvanse = await makeRequest(app, 'GET', '/api/drugs?q=vyvanse');
  assert.equal(resVyvanse.statusCode, 200);
  assert.equal(resVyvanse.body.drugs.length, 1);
  assert.equal(resVyvanse.body.drugs[0].brand_name, 'Vyvanse');

  // 3. Search pagination
  const resPaged = await makeRequest(app, 'GET', '/api/drugs?limit=2&offset=0');
  assert.equal(resPaged.statusCode, 200);
  assert.equal(resPaged.body.drugs.length, 2);
  assert.equal(resPaged.body.limit, 2);
  assert.equal(resPaged.body.offset, 0);
});

test('API: POST /api/scheduler/trigger requires admin authentication', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  const app = createApp(db, { enableRateLimiter: false });

  // 1. Unauthenticated request -> 401
  const resUnauthorized = await makeRequest(app, 'POST', '/api/scheduler/trigger', {});
  assert.equal(resUnauthorized.statusCode, 401);
  assert.equal(resUnauthorized.body.error, 'Unauthorized');

  // 2. Request with invalid key -> 401
  const resInvalid = await makeRequest(app, 'POST', '/api/scheduler/trigger', {}, {
    'x-admin-key': 'wrong-key'
  });
  assert.equal(resInvalid.statusCode, 401);

  // 3. Request with valid admin key -> 200
  const resValid = await makeRequest(app, 'POST', '/api/scheduler/trigger', {}, {
    'x-admin-key': 'dev-admin-secret-key'
  });
  assert.equal(resValid.statusCode, 200);
  assert.equal(resValid.body.success, true);
});
