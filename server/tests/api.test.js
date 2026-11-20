const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { runAllIngestions } = require('../src/ingestion');
const { GenericLaunchDetector } = require('../src/detector');
const { createApp } = require('../src/app');

// Helper to make mock requests to express app without spinning up network socket
function makeRequest(app, method, path, body = null) {
  return new Promise((resolve) => {
    const req = {
      method,
      url: path,
      body,
      headers: { 'content-type': 'application/json' }
    };

    let statusCode = 200;
    const headers = {};
    let responseBody = null;

    const res = {
      setHeader(k, v) { headers[k] = v; },
      status(code) {
        statusCode = code;
        return this;
      },
      json(data) {
        responseBody = data;
        resolve({ statusCode, headers, body: responseBody });
      },
      send(data) {
        responseBody = data;
        resolve({ statusCode, headers, body: responseBody });
      }
    };

    app.handle(req, res);
  });
}

test('API: GET /health returns status healthy', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  const app = createApp(db);

  const res = await makeRequest(app, 'GET', '/health');
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.status, 'healthy');
  assert.ok(res.body.timestamp);
});

test('API: POST /api/check-updates rejects missing or invalid rxcuis', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  const app = createApp(db);

  const res1 = await makeRequest(app, 'POST', '/api/check-updates', {});
  assert.equal(res1.statusCode, 400);

  const res2 = await makeRequest(app, 'POST', '/api/check-updates', { rxcuis: [] });
  assert.equal(res2.statusCode, 400);
});

test('API: POST /api/check-updates anonymous status check and alert filtering', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  await runAllIngestions(db);

  // Run detector to generate alerts
  const detector = new GenericLaunchDetector(db);
  detector.runAll({ persistAlert: true });

  const app = createApp(db);

  // Check updates for Vyvanse (855333) and Eliquis (1364430)
  // Request 1: Checked since 1970 (receives historical launch alert for Vyvanse)
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

test('API: GET /api/drugs and GET /api/drugs/:rxcui', async () => {
  const db = getDb(':memory:');
  initSchema(db);
  await runAllIngestions(db);
  const app = createApp(db);

  const resAll = await makeRequest(app, 'GET', '/api/drugs');
  assert.equal(resAll.statusCode, 200);
  assert.ok(resAll.body.count >= 5);

  const resOne = await makeRequest(app, 'GET', '/api/drugs/855333');
  assert.equal(resOne.statusCode, 200);
  assert.equal(resOne.body.brand_name, 'Vyvanse');
  assert.ok(resOne.body.generic_status.length >= 3);
  assert.ok(resOne.body.market_availability.length >= 2);
});
