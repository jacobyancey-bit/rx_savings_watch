const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { createApp } = require('../src/app');
const config = require('../src/config');

describe('B2B Pharmacy & Clinic Partner Program', () => {
  let db;
  let server;
  let baseUrl;

  before(async () => {
    db = getDb(':memory:');
    initSchema(db);
    const app = createApp(db, { enableRateLimiter: false });
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', () => {
        baseUrl = `http://127.0.0.1:${server.address().port}`;
        resolve();
      });
    });
  });

  after(async () => {
    if (server) await new Promise((resolve) => server.close(resolve));
    if (db) db.close();
  });

  it('serves the standalone /partners B2B landing page', async () => {
    const res = await fetch(`${baseUrl}/partners`);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.match(html, /For Independent Pharmacies/);
    assert.match(html, /60-Day Free Pilot/);
  });

  it('handles full lifecycle: apply -> pending hidden -> admin approve -> visible in ZIP lookup', async () => {
    // 1. Submit partner application
    const applyRes = await fetch(`${baseUrl}/api/b2b/apply`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        business_name: 'Main Street Independent Pharmacy',
        business_type: 'pharmacy',
        contact_name: 'Dr. Jane Smith',
        contact_email: 'owner@mainstreetrx.com',
        phone: '(555) 234-5678',
        address: '123 Main St, Addison, TX 75001',
        website_url: 'https://mainstreetrx.com',
        transfer_url: 'https://mainstreetrx.com/transfer',
        tagline: 'Transparent cash prices & free local delivery',
        zip_codes: '75001, 75002',
        plan_tier: 'pilot_60d',
      }),
    });
    assert.equal(applyRes.status, 201);
    const created = await applyRes.json();
    assert.equal(created.success, true);
    assert.deepEqual(created.zip_codes, ['75001', '75002']);

    // 2. While pending, must NOT show up in public local lookup
    const beforeApprove = await fetch(`${baseUrl}/api/b2b/local`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zip: '75001' }),
    }).then(r => r.json());
    assert.equal(beforeApprove.partners.length, 0);

    // 3. Admin endpoint rejects unauthorized calls
    const unauth = await fetch(`${baseUrl}/api/admin/b2b/partners`);
    assert.equal(unauth.status, 401);

    // 4. Admin approves partner
    const approveRes = await fetch(`${baseUrl}/api/admin/b2b/partners/${created.id}/status`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Admin-Key': config.ADMIN_API_KEY,
      },
      body: JSON.stringify({ status: 'active' }),
    });
    assert.equal(approveRes.status, 200);

    // 5. Public ZIP lookup now returns the approved local pharmacy for 75001, not 90210
    const matched = await fetch(`${baseUrl}/api/b2b/local`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zip: '75001' }),
    }).then(r => r.json());
    assert.equal(matched.partners.length, 1);
    assert.equal(matched.partners[0].business_name, 'Main Street Independent Pharmacy');
    assert.equal(matched.partners[0].contact_email, undefined); // Private email never exposed publicly

    const unmatched = await fetch(`${baseUrl}/api/b2b/local`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zip: '90210' }),
    }).then(r => r.json());
    assert.equal(unmatched.partners.length, 0);
  });
});
