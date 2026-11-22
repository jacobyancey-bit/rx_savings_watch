const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { createApp } = require('../src/app');

describe('Private Reviews API', () => {
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

  it('accepts valid private review and saves it to SQLite', async () => {
    const res = await fetch(`${baseUrl}/api/reviews`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        rating: 5,
        category: 'caregiver',
        message: 'Super helpful for tracking my mom and my own meds separately!',
        platform: 'web'
      })
    });

    assert.equal(res.status, 201);
    const data = await res.json();
    assert.equal(data.success, true);

    const row = db.prepare('SELECT * FROM user_reviews ORDER BY id DESC LIMIT 1').get();
    assert.equal(row.rating, 5);
    assert.equal(row.category, 'caregiver');
    assert.equal(row.platform, 'web');
  });

  it('rejects invalid rating or too-short message', async () => {
    const badRating = await fetch(`${baseUrl}/api/reviews`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ rating: 9, message: 'Great app' })
    });
    assert.equal(badRating.status, 400);

    const shortMsg = await fetch(`${baseUrl}/api/reviews`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ rating: 4, message: 'hi' })
    });
    assert.equal(shortMsg.status, 400);
  });

  it('never exposes reviews publicly via GET /api/reviews or unauthenticated admin route', async () => {
    const publicGet = await fetch(`${baseUrl}/api/reviews`);
    assert.equal(publicGet.status, 404);

    const unauthedAdmin = await fetch(`${baseUrl}/api/admin/reviews`);
    assert.equal(unauthedAdmin.status, 401);
  });
});
