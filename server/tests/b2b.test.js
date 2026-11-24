const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
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

  it('verifies Stripe webhook HMAC signatures and updates partner payment & subscription lifecycle', async () => {
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test_secret_123';
    try {
      // Create a partner with pre-verified NPI
      const info = db.prepare(`
        INSERT INTO b2b_partners (
          business_name, business_type, contact_name, contact_email,
          zip_codes, plan_tier, npi_number, npi_verified, payment_status, status
        ) VALUES ('Oakwood Apothecary', 'pharmacy', 'Sam Lee', 'sam@oakwoodrx.com', '75006', 'local_149', '1234567890', 1, 'unpaid', 'pending')
      `).run();
      const partnerId = Number(info.lastInsertRowid);

      const signPayload = (bodyStr) => {
        const ts = Math.floor(Date.now() / 1000);
        const sig = crypto
          .createHmac('sha256', process.env.STRIPE_WEBHOOK_SECRET)
          .update(`${ts}.${bodyStr}`, 'utf8')
          .digest('hex');
        return `t=${ts},v1=${sig}`;
      };

      // 1. Reject tampered signature
      const badRes = await fetch(`${baseUrl}/api/b2b/stripe-webhook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Stripe-Signature': 't=12345,v1=deadbeef' },
        body: JSON.stringify({ type: 'checkout.session.completed' }),
      });
      assert.equal(badRes.status, 400);

      // 2. Accept valid checkout.session.completed -> marks paid + auto-activates NPI-verified partner
      const completedBody = JSON.stringify({
        type: 'checkout.session.completed',
        data: {
          object: {
            client_reference_id: String(partnerId),
            customer: 'cus_test_123',
            subscription: 'sub_test_456',
          },
        },
      });
      const okRes = await fetch(`${baseUrl}/api/b2b/stripe-webhook`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Stripe-Signature': signPayload(completedBody),
        },
        body: completedBody,
      });
      assert.equal(okRes.status, 200);

      const activeRow = db.prepare('SELECT payment_status, status, stripe_customer_id, stripe_subscription_id FROM b2b_partners WHERE id = ?').get(partnerId);
      assert.equal(activeRow.payment_status, 'paid');
      assert.equal(activeRow.status, 'active');
      assert.equal(activeRow.stripe_customer_id, 'cus_test_123');
      assert.equal(activeRow.stripe_subscription_id, 'sub_test_456');

      // 3. Accept valid customer.subscription.deleted -> auto-pauses listing
      const cancelBody = JSON.stringify({
        type: 'customer.subscription.deleted',
        data: { object: { id: 'sub_test_456' } },
      });
      const cancelRes = await fetch(`${baseUrl}/api/b2b/stripe-webhook`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Stripe-Signature': signPayload(cancelBody),
        },
        body: cancelBody,
      });
      assert.equal(cancelRes.status, 200);

      const pausedRow = db.prepare('SELECT payment_status, status FROM b2b_partners WHERE id = ?').get(partnerId);
      assert.equal(pausedRow.payment_status, 'canceled');
      assert.equal(pausedRow.status, 'paused');
    } finally {
      delete process.env.STRIPE_WEBHOOK_SECRET;
    }
  });
});
