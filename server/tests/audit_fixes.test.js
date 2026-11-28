// Regression tests for the 9-pillar production readiness audit fixes.
const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { getDb, initSchema } = require('../src/db');
const { createApp } = require('../src/app');
const {
  matchesExpectedIngredients,
  dedupeStrengths,
  canonicalizeStrength,
} = require('../src/ingestion/live_feeds');
const { calculateMatchedSavings, strengthFormKey } = require('../src/detector/rules');

describe('Ingredient matcher: clinically distinct moieties never collide', () => {
  const cases = [
    ['insulin lispro is not insulin glargine', ['insulin lispro'], ['insulin glargine'], false],
    ['TDF is not TAF', ['tenofovir disoproxil fumarate'], ['tenofovir alafenamide'], false],
    ['TDF matches TDF', ['TENOFOVIR DISOPROXIL FUMARATE'], ['tenofovir disoproxil fumarate'], true],
    ['Dexedrine is not Adderall', ['dextroamphetamine sulfate'], ['amphetamine aspartate', 'dextroamphetamine sulfate'], false],
    ['Evekeo is not Adderall', ['amphetamine sulfate'], ['amphetamine', 'dextroamphetamine'], false],
    [
      'Adderall 4-salt product matches Adderall',
      ['AMPHETAMINE ASPARTATE MONOHYDRATE', 'AMPHETAMINE SULFATE', 'DEXTROAMPHETAMINE SACCHARATE', 'DEXTROAMPHETAMINE SULFATE'],
      ['amphetamine', 'dextroamphetamine'],
      true,
    ],
    ['diltiazem HCl matches diltiazem', ['diltiazem hydrochloride'], ['diltiazem'], true],
    ['Jalyn combo never matches single-ingredient tamsulosin', ['dutasteride', 'tamsulosin hydrochloride'], 'tamsulosin', false],
  ];
  for (const [name, candidate, expected, want] of cases) {
    test(name, () => {
      assert.equal(matchesExpectedIngredients(candidate, expected), want);
    });
  }
});

describe('Strength normalization', () => {
  test('collapses mg/mcg duplicates and prefers published mcg labels', () => {
    const out = dedupeStrengths(['0.025 mg', '25 ug', '0.05 mg', '50 ug', '0.3 mg']);
    assert.deepEqual(out, ['25 mcg', '50 mcg', '0.3 mg']);
  });
  test('collapses insulin unit spellings', () => {
    assert.deepEqual(dedupeStrengths(['100 [iu]/ml', '100 unt/ml']), ['100 units/ml']);
  });
  test('never rounds small inhaler strengths (Spiriva Respimat 1.25 mcg/actuation)', () => {
    assert.equal(canonicalizeStrength('0.00125 mg/actuat'), '0.00125 mg/actuat');
    assert.deepEqual(dedupeStrengths(['0.018 mg', '18 ug']), ['18 mcg']);
  });
  test('keeps conventional mg combination labels unchanged', () => {
    assert.equal(canonicalizeStrength('0.5 mg / 0.4 mg'), '0.5 mg / 0.4 mg');
  });
});

describe('Strength-matched NADAC savings', () => {
  const rows = [
    { package_description: 'LIPITOR 80 MG TABLET (Brand)', marketing_category: 'NDA', nadac_per_unit: 19.06, pricing_unit: 'EA' },
    { package_description: 'LIPITOR 10 MG TABLET (Brand)', marketing_category: 'NDA', nadac_per_unit: 12.0, pricing_unit: 'EA' },
    { package_description: 'ATORVASTATIN CALCIUM 10 MG TABLET', marketing_category: 'ANDA', nadac_per_unit: 0.03, pricing_unit: 'EA' },
    { package_description: 'ATORVASTATIN CALCIUM 40 MG TABLET', marketing_category: 'ANDA', nadac_per_unit: 0.06, pricing_unit: 'EA' },
  ];

  test('only compares identical strength + form + unit', () => {
    const r = calculateMatchedSavings(rows);
    assert.equal(r.brandPrice, 12.0, 'must use the 10 mg brand row, not the 80 mg one');
    assert.equal(r.genericPrice, 0.03);
    assert.equal(r.matchedKey, '10MG|tab|EA');
  });

  test('returns null when no strengths overlap', () => {
    const r = calculateMatchedSavings([rows[0], rows[3]]);
    assert.equal(r.savingsPct, null);
    assert.equal(r.brandPrice, null);
  });

  test('never compares tablets against extended-release tablets', () => {
    assert.notEqual(strengthFormKey('FOO 10 MG TABLET'), strengthFormKey('FOO ER 10 MG TABLET'));
  });
});

describe('Privacy & B2B integrity endpoints', () => {
  let db;
  let server;
  let baseUrl;

  before(async () => {
    db = getDb(':memory:');
    initSchema(db);
    db.prepare("INSERT INTO drugs (rxcui, brand_name, generic_name) VALUES ('12345', 'Testbrand', 'testgeneric')").run();
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

  const post = (path, body, headers = {}) => fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

  test('data-quality flag takes RxCUI in the POST body, not the URL', async () => {
    const ok = await post('/api/drugs/flag', { rxcui: '12345', issue_type: 'price_looks_off' });
    assert.equal(ok.status, 201);
    const legacy = await post('/api/drugs/12345/flag', { issue_type: 'price_looks_off' });
    assert.equal(legacy.status, 404, 'legacy RxCUI-in-URL flag route must be removed');
  });

  test('RxCUI-in-URL GET lookups are removed and GET search queries are rejected', async () => {
    assert.equal((await fetch(`${baseUrl}/api/drugs/12345`)).status, 404);
    assert.equal((await fetch(`${baseUrl}/api/drugs/12345/partners`)).status, 404);
    assert.equal((await fetch(`${baseUrl}/api/drugs?q=testbrand`)).status, 400);
    const detail = await post('/api/drugs/detail', { rxcui: '12345' });
    assert.equal(detail.status, 200);
  });

  test('ROI counters count each visitor once per partner per event type', async () => {
    const info = db.prepare(`
      INSERT INTO b2b_partners (business_name, business_type, contact_name, contact_email, zip_codes, plan_tier, status)
      VALUES ('Dedupe Rx', 'pharmacy', 'Al', 'al@example.com', '75001', 'pilot_60d', 'active')
    `).run();
    const id = Number(info.lastInsertRowid);

    for (let i = 0; i < 5; i++) {
      await post('/api/b2b/local', { zip: '75001' });
      await post('/api/b2b/event', { partner_id: id, event_type: 'call' });
    }
    const row = db.prepare('SELECT impressions_count, call_clicks FROM b2b_partners WHERE id = ?').get(id);
    assert.equal(row.impressions_count, 1);
    assert.equal(row.call_clicks, 1);
  });

  test('Stripe webhook is idempotent and invoice.paid reactivates past_due partners', async () => {
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_audit_fix';
    const sign = (body) => {
      const ts = Math.floor(Date.now() / 1000);
      const sig = crypto.createHmac('sha256', process.env.STRIPE_WEBHOOK_SECRET).update(`${ts}.${body}`, 'utf8').digest('hex');
      return `t=${ts},v1=${sig}`;
    };
    try {
      const info = db.prepare(`
        INSERT INTO b2b_partners (business_name, business_type, contact_name, contact_email, zip_codes, plan_tier,
          npi_number, npi_verified, payment_status, status, stripe_subscription_id)
        VALUES ('Retry Rx', 'pharmacy', 'Bo', 'bo@example.com', '75002', 'local_149', '1234567890', 1, 'paid', 'active', 'sub_retry')
      `).run();
      const id = Number(info.lastInsertRowid);

      const failed = JSON.stringify({ id: 'evt_fail_1', type: 'invoice.payment_failed', data: { object: { subscription: 'sub_retry' } } });
      assert.equal((await post('/api/b2b/stripe-webhook', failed, { 'Stripe-Signature': sign(failed) })).status, 200);
      assert.equal(db.prepare('SELECT status FROM b2b_partners WHERE id = ?').get(id).status, 'paused');

      const paid = JSON.stringify({ id: 'evt_paid_1', type: 'invoice.paid', data: { object: { subscription: 'sub_retry' } } });
      assert.equal((await post('/api/b2b/stripe-webhook', paid, { 'Stripe-Signature': sign(paid) })).status, 200);
      const row = db.prepare('SELECT status, payment_status FROM b2b_partners WHERE id = ?').get(id);
      assert.equal(row.status, 'active');
      assert.equal(row.payment_status, 'paid');

      // Replaying the earlier failure event must NOT re-pause the partner
      const replay = await post('/api/b2b/stripe-webhook', failed, { 'Stripe-Signature': sign(failed) });
      assert.equal(replay.status, 200);
      assert.equal((await replay.json()).duplicate, true);
      assert.equal(db.prepare('SELECT status FROM b2b_partners WHERE id = ?').get(id).status, 'active');
    } finally {
      delete process.env.STRIPE_WEBHOOK_SECRET;
    }
  });

  test('server-rendered pages send a strict nonce-based CSP', async () => {
    const res = await fetch(`${baseUrl}/partners`);
    const csp = res.headers.get('content-security-policy') || '';
    assert.match(csp, /script-src 'nonce-[A-Za-z0-9+/=]+'/);
    const html = await res.text();
    assert.ok(!/onclick=/.test(html), 'no inline event handlers allowed under CSP');
    const nonce = csp.match(/'nonce-([^']+)'/)[1];
    assert.ok(html.includes(`<script nonce="${nonce}">`));

    const med = await fetch(`${baseUrl}/medications`);
    assert.match(med.headers.get('content-security-policy') || '', /default-src 'none'/);
    const medHtml = await med.text();
    assert.match(medHtml, /Not a government website/);
    assert.match(medHtml, /https:\/\/www\.accessdata\.fda\.gov/);
  });
});
