const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { createApp } = require('../src/app');
const config = require('../src/config');
const { isLikelyBot, recordDailyMetric } = require('../src/routes/stats');

describe('Zero-PII Daily Stats & Admin Endpoint', () => {
  let db;
  let server;
  let baseUrl;

  before(async () => {
    db = getDb(':memory:');
    initSchema(db);
    const app = createApp(db, { enableRateLimiter: false });
    await new Promise((resolve) => {
      server = app.listen(0, () => {
        const { port } = server.address();
        baseUrl = `http://127.0.0.1:${port}`;
        resolve();
      });
    });
  });

  after(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    if (db) db.close();
  });

  it('filters common bots/crawlers in memory without blocking real browsers', () => {
    assert.equal(isLikelyBot('Googlebot/2.1'), true);
    assert.equal(isLikelyBot('Twitterbot/1.0'), true);
    assert.equal(isLikelyBot('curl/8.5.0'), true);
    assert.equal(isLikelyBot(''), true);
    assert.equal(
      isLikelyBot('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36'),
      false
    );
  });

  it('requires X-Admin-Key for GET /api/admin/stats', async () => {
    const unauthed = await fetch(`${baseUrl}/api/admin/stats`);
    assert.equal(unauthed.status, 401);

    const wrongKey = await fetch(`${baseUrl}/api/admin/stats`, {
      headers: { 'X-Admin-Key': 'wrong-key' }
    });
    assert.equal(wrongKey.status, 401);
  });

  it('aggregates daily counters and returns structured admin stats', async () => {
    recordDailyMetric(db, 'web_visits');
    recordDailyMetric(db, 'web_visits');
    recordDailyMetric(db, 'api_searches');
    recordDailyMetric(db, 'cabinet_syncs');

    const res = await fetch(`${baseUrl}/api/admin/stats`, {
      headers: { 'X-Admin-Key': config.ADMIN_API_KEY }
    });
    assert.equal(res.status, 200);
    const data = await res.json();

    assert.equal(data.privacy_mode, 'zero_pii_aggregate_only');
    assert.equal(data.today.web_visits, 2);
    assert.equal(data.today.api_searches, 1);
    assert.equal(data.today.cabinet_syncs, 1);
    assert.equal(data.all_time.web_visits, 2);
    assert.ok(Array.isArray(data.daily));
  });
});
