const express = require('express');
const crypto = require('node:crypto');
const config = require('../config');

const SITE_ORIGIN = 'https://rx.dangling-dice-studios.com';
const ALLOWED_TYPES = new Set(['pharmacy', 'clinic', 'senior_care']);
const ALLOWED_PLANS = new Set(['pilot_60d', 'local_149', 'multi_349']);
const ALLOWED_STATUSES = new Set(['pending', 'active', 'paused']);
const APPLY_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const APPLY_MAX_PER_IP = 8;
const STRIPE_WEBHOOK_TOLERANCE_SEC = 300; // 5 minutes

function cleanText(raw, maxLen = 160) {
  return String(raw || '')
    .replace(/[\x00-\x1F\x7F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLen);
}

function cleanHttpUrl(raw) {
  const trimmed = cleanText(raw, 300);
  if (!trimmed) return null;
  try {
    const parsed = new URL(trimmed.startsWith('http') ? trimmed : `https://${trimmed}`);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return null;
    return parsed.toString();
  } catch (_) {
    return null;
  }
}

function normalizeZipList(raw, maxZips = 25) {
  const matches = String(raw || '').match(/\b\d{5}\b/g) || [];
  return Array.from(new Set(matches)).slice(0, maxZips);
}

function normalizeNpi(raw) {
  const digits = String(raw || '').replace(/[^0-9]/g, '');
  return digits.length === 10 ? digits : null;
}

function isValidAdminKey(req) {
  const provided = String(req.get('X-Admin-Key') || '');
  const expected = String(config.ADMIN_API_KEY || '');
  if (!provided || !expected) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Verifies a 10-digit NPI against the free public CMS NPPES NPI Registry API.
 * Returns true if the NPI exists and is active. Skipped during automated offline tests.
 */
async function verifyNpiWithCms(npi) {
  if (!npi || npi.length !== 10 || process.env.NODE_ENV === 'test') {
    return false;
  }
  try {
    const res = await fetch(`https://npiregistry.cms.hhs.gov/api/?version=2.1&number=${encodeURIComponent(npi)}`, {
      headers: { 'User-Agent': 'RxSavingsWatch/1.0' },
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) return false;
    const data = await res.json();
    const first = Array.isArray(data.results) ? data.results[0] : null;
    return Boolean(first && String(first.number) === npi && first.basic?.status === 'A');
  } catch (_) {
    return false;
  }
}

function getStripePriceId(planTier) {
  if (planTier === 'local_149') return (process.env.STRIPE_PRICE_LOCAL_149 || '').trim() || null;
  if (planTier === 'multi_349') return (process.env.STRIPE_PRICE_MULTI_349 || '').trim() || null;
  return null;
}

/**
 * Creates a hosted Stripe Checkout Session for recurring B2B subscriptions via official Stripe REST API.
 */
async function createStripeCheckoutSession({ partnerId, planTier, contactEmail, businessName }) {
  const secretKey = (process.env.STRIPE_SECRET_KEY || '').trim();
  const priceId = getStripePriceId(planTier);
  if (!secretKey || !priceId) return null;

  const params = new URLSearchParams();
  params.set('mode', 'subscription');
  params.set('client_reference_id', String(partnerId));
  params.set('customer_email', contactEmail);
  params.set('line_items[0][price]', priceId);
  params.set('line_items[0][quantity]', '1');
  params.set('success_url', `${SITE_ORIGIN}/partners?checkout=success&partner_id=${partnerId}`);
  params.set('cancel_url', `${SITE_ORIGIN}/partners?checkout=canceled&partner_id=${partnerId}`);
  params.set('metadata[partner_id]', String(partnerId));
  params.set('metadata[plan_tier]', planTier);
  params.set('metadata[business_name]', businessName.slice(0, 120));

  try {
    const res = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${secretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return typeof data.url === 'string' ? data.url : null;
  } catch (_) {
    return null;
  }
}

/**
 * Verifies Stripe-Signature header (`t=<ts>,v1=<hex>`) against raw request body using HMAC-SHA256.
 */
function verifyStripeWebhookSignature(rawBody, signatureHeader, webhookSecret) {
  if (!rawBody || !signatureHeader || !webhookSecret) return false;
  const parts = String(signatureHeader).split(',');
  let timestamp = null;
  const signatures = [];
  for (const part of parts) {
    const [k, v] = part.trim().split('=');
    if (k === 't') timestamp = parseInt(v, 10);
    if (k === 'v1' && v) signatures.push(v);
  }
  if (!timestamp || !Number.isFinite(timestamp) || signatures.length === 0) return false;

  const ageSec = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (ageSec > STRIPE_WEBHOOK_TOLERANCE_SEC) return false;

  const payload = `${timestamp}.${Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody)}`;
  const expectedHex = crypto.createHmac('sha256', webhookSecret).update(payload, 'utf8').digest('hex');
  const expectedBuf = Buffer.from(expectedHex, 'hex');

  for (const sig of signatures) {
    try {
      const providedBuf = Buffer.from(sig, 'hex');
      if (providedBuf.length === expectedBuf.length && crypto.timingSafeEqual(providedBuf, expectedBuf)) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}

function renderPartnersPageHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>For Independent Pharmacies &amp; Clinics — Rx Savings Watch B2B Partner Program</title>
  <meta name="description" content="Reach local cash-pay patients right when they refill. Flat-rate ZIP sponsorship for independent pharmacies, Direct Primary Care clinics, and senior care — zero EHR integration or HIPAA friction.">
  <link rel="canonical" href="${SITE_ORIGIN}/partners">
  <meta name="theme-color" content="#057873">
  <style>
    :root { --teal: #057873; --teal-dark: #035a56; --bg: #f6f9f9; --card: #ffffff; --text: #142221; --muted: #546665; --border: #dce6e5; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); line-height: 1.55; }
    header { background: var(--card); border-bottom: 1px solid var(--border); padding: 14px 20px; position: sticky; top: 0; z-index: 10; }
    .nav { max-width: 1080px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
    .brand { display: flex; align-items: center; gap: 10px; text-decoration: none; color: var(--text); font-weight: 700; font-size: 18px; }
    .brand-badge { background: var(--teal); color: #fff; padding: 5px 9px; border-radius: 8px; font-size: 13px; }
    .btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; background: var(--teal); color: #fff !important; padding: 11px 18px; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; border: 0; cursor: pointer; }
    .btn:hover { background: var(--teal-dark); }
    .btn-outline { display: inline-flex; align-items: center; justify-content: center; gap: 8px; background: #fff; color: var(--teal-dark) !important; border: 1px solid #b8cfcd; padding: 10px 16px; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; cursor: pointer; }
    .btn-outline:hover { background: #edf5f4; }
    main { max-width: 1080px; margin: 0 auto; padding: 32px 20px 64px; }
    .hero { background: linear-gradient(135deg, #057873, #034e4a); color: #fff; border-radius: 20px; padding: 36px 28px; margin-bottom: 24px; }
    .hero h1 { margin: 8px 0 10px; font-size: 32px; line-height: 1.2; }
    .hero p { margin: 0 0 20px; color: #d8f2f0; max-width: 720px; font-size: 16px; }
    .pill { display: inline-block; background: rgba(255,255,255,0.16); padding: 4px 12px; border-radius: 999px; font-size: 12px; font-weight: 700; letter-spacing: 0.4px; }
    .grid-3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 18px; margin-bottom: 24px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 22px; display: flex; flex-direction: column; }
    .price { font-size: 28px; font-weight: 800; color: var(--teal-dark); margin: 8px 0; }
    .muted { color: var(--muted); font-size: 14px; }
    ul { padding-left: 18px; margin: 10px 0 18px; flex: 1; }
    li { margin-bottom: 6px; font-size: 14px; }
    .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
    label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 5px; }
    input, select { width: 100%; padding: 10px 12px; border: 1px solid #c5d4d3; border-radius: 10px; font-size: 14px; font-family: inherit; background: #fff; }
    input:focus, select:focus { outline: 2px solid var(--teal); border-color: var(--teal); }
    .status-box { margin-top: 14px; padding: 12px 14px; border-radius: 10px; font-size: 14px; display: none; }
    .status-ok { background: #e3f5ec; color: #0f6b43; border: 1px solid #9ad6b8; }
    .status-err { background: #fdecec; color: #9c1c1c; border: 1px solid #f2b4b4; }
    .banner { padding: 14px 18px; border-radius: 12px; margin-bottom: 18px; font-size: 14px; font-weight: 600; display: none; }
    footer { max-width: 1080px; margin: 0 auto; padding: 20px; border-top: 1px solid var(--border); color: var(--muted); font-size: 12.5px; text-align: center; }
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <a class="brand" href="/">
        <span class="brand-badge">Rx</span>
        <span>Rx Savings Watch <span style="font-weight:500;color:#546665;">• For Pharmacies &amp; Clinics</span></span>
      </a>
      <div style="display:flex;gap:12px;align-items:center;">
        <a class="btn-outline" href="/">Back to Consumer App</a>
        <a class="btn" href="#apply">Start 60-Day Free Pilot</a>
      </div>
    </div>
  </header>

  <main>
    <div id="checkoutBanner" class="banner"></div>

    <section class="hero">
      <span class="pill">B2B PARTNER PROGRAM • ZERO EHR OR HIPAA FRICTION</span>
      <h1>Reach Local Cash-Pay Patients Right When They Refill</h1>
      <p>Rx Savings Watch helps patients and caregivers track prescriptions, refill dates, and generic savings—100% free and private. Independent pharmacies, Direct Primary Care (DPC) clinics, and senior care facilities can sponsor local ZIP codes with transparent flat monthly pricing.</p>
      <a class="btn" style="background:#fff;color:#035a56 !important;" href="#apply">Choose a Plan &amp; Apply</a>
    </section>

    <section class="grid-3">
      <div class="card">
        <strong>60-Day Free Pilot</strong>
        <div class="price">$0 <span class="muted" style="font-size:14px;font-weight:500;">/ 60 days</span></div>
        <p class="muted">For our first 5 independent pharmacy or DPC clinic partners.</p>
        <ul>
          <li>Featured <em>Sponsored Local Partner</em> card in up to 5 ZIP codes</li>
          <li>1-tap Call Pharmacy, Transfer Rx, and Website buttons</li>
          <li>Zero setup fee — cancel anytime</li>
        </ul>
        <button type="button" class="btn-outline" onclick="selectPlan('pilot_60d')">Start 60-Day Free Pilot</button>
      </div>

      <div class="card" style="border-color:#057873;border-width:2px;">
        <strong>Local Independent Pharmacy</strong>
        <div class="price">$149 <span class="muted" style="font-size:14px;font-weight:500;">/ month</span></div>
        <p class="muted">Flat-rate local sponsorship — never per-prescription kickbacks.</p>
        <ul>
          <li>Featured across up to 5 local 5-digit ZIP codes</li>
          <li>Shown when local users compare cash prices or refill</li>
          <li>Instant Stripe subscription billing &amp; receipts</li>
        </ul>
        <button type="button" class="btn" onclick="selectPlan('local_149')">Subscribe — $149/mo</button>
      </div>

      <div class="card">
        <strong>Multi-Location / Senior Care</strong>
        <div class="price">$349 <span class="muted" style="font-size:14px;font-weight:500;">/ month</span></div>
        <p class="muted">For regional independent chains, DPC groups, or senior communities.</p>
        <ul>
          <li>Up to 25 covered 5-digit ZIP codes</li>
          <li>Priority onboarding &amp; quarterly placement report</li>
          <li>Zero patient PHI ever shared or stored</li>
        </ul>
        <button type="button" class="btn-outline" onclick="selectPlan('multi_349')">Subscribe — $349/mo</button>
      </div>
    </section>

    <section class="card" id="apply" style="display:block;">
      <h2 style="margin-top:0;">Partner Onboarding &amp; Checkout</h2>
      <p class="muted" style="margin-bottom:18px;">Complete your business details below. Paid plans proceed directly to secure Stripe Checkout (when enabled), and pharmacies with a verified 10-digit NPI activate automatically upon payment.</p>

      <form id="partnerForm">
        <div class="form-grid">
          <div>
            <label for="business_name">Pharmacy / Clinic Name *</label>
            <input id="business_name" name="business_name" required maxlength="120" placeholder="Main Street Independent Pharmacy">
          </div>
          <div>
            <label for="business_type">Organization Type *</label>
            <select id="business_type" name="business_type">
              <option value="pharmacy">Independent Pharmacy</option>
              <option value="clinic">Direct Primary Care (DPC) / Clinic</option>
              <option value="senior_care">Senior Living / Caregiver Agency</option>
            </select>
          </div>
          <div>
            <label for="contact_name">Your Name *</label>
            <input id="contact_name" name="contact_name" required maxlength="100" placeholder="Dr. Jane Smith, PharmD">
          </div>
          <div>
            <label for="contact_email">Work Email *</label>
            <input id="contact_email" name="contact_email" type="email" required maxlength="140" placeholder="owner@mainstreetrx.com">
          </div>
          <div>
            <label for="phone">Public Pharmacy Phone *</label>
            <input id="phone" name="phone" required maxlength="40" placeholder="(555) 234-5678">
          </div>
          <div>
            <label for="npi_number">10-Digit NPI Number (Optional — speeds up verification)</label>
            <input id="npi_number" name="npi_number" maxlength="10" placeholder="1234567890">
          </div>
          <div>
            <label for="zip_codes">Target 5-Digit ZIP Codes (comma-separated) *</label>
            <input id="zip_codes" name="zip_codes" required maxlength="200" placeholder="75001, 75002, 75006">
          </div>
          <div>
            <label for="address">Street Address (City, State)</label>
            <input id="address" name="address" maxlength="160" placeholder="123 Main St, Addison, TX 75001">
          </div>
          <div>
            <label for="website_url">Website URL</label>
            <input id="website_url" name="website_url" maxlength="240" placeholder="https://mainstreetrx.com">
          </div>
          <div>
            <label for="transfer_url">Rx Transfer Page URL (optional)</label>
            <input id="transfer_url" name="transfer_url" maxlength="240" placeholder="https://mainstreetrx.com/transfer">
          </div>
          <div>
            <label for="plan_tier">Selected Plan *</label>
            <select id="plan_tier" name="plan_tier">
              <option value="pilot_60d">60-Day Free Pilot ($0 for 60 days)</option>
              <option value="local_149">Local Pharmacy ($149/month — up to 5 ZIPs)</option>
              <option value="multi_349">Multi-Location / Senior Care ($349/month — up to 25 ZIPs)</option>
            </select>
          </div>
        </div>
        <div style="margin-top:14px;">
          <label for="tagline">Short Patient Tagline (shown on your card)</label>
          <input id="tagline" name="tagline" maxlength="140" placeholder="Transparent cash prices &amp; free same-day local delivery">
        </div>
        <div style="margin-top:18px;display:flex;align-items:center;gap:14px;flex-wrap:wrap;">
          <button class="btn" type="submit" id="submitBtn">Continue</button>
          <span class="muted" style="font-size:12.5px;">Flat-rate sponsorship only • Clearly labeled "Sponsored Local Partner" • Zero patient PHI shared</span>
        </div>
        <div id="statusBox" class="status-box"></div>
      </form>
    </section>
  </main>

  <footer>
    <p><strong>Compliance &amp; Privacy:</strong> Local pharmacy sponsorships are flat monthly directory placements (never per-prescription volume fees). Rx Savings Watch never collects or transmits patient PHI.</p>
    <p>© 2026 Dangling Dice Studios™ • Questions? Email support@danglingdicestudios.com</p>
  </footer>

  <script>
    function selectPlan(plan) {
      const sel = document.getElementById('plan_tier');
      if (sel) sel.value = plan;
      document.getElementById('apply').scrollIntoView({ behavior: 'smooth' });
      document.getElementById('business_name').focus();
    }

    // Show Stripe Checkout return status if present
    (function () {
      const params = new URLSearchParams(window.location.search);
      const checkout = params.get('checkout');
      const banner = document.getElementById('checkoutBanner');
      if (checkout === 'success') {
        banner.className = 'banner status-ok';
        banner.textContent = 'Payment received! Thank you for partnering with Rx Savings Watch. Verified NPI listings activate automatically; otherwise our team reviews within 1 business day.';
        banner.style.display = 'block';
      } else if (checkout === 'canceled') {
        banner.className = 'banner status-err';
        banner.textContent = 'Checkout was canceled. Your application details were saved—you can choose a plan and try again anytime.';
        banner.style.display = 'block';
      }
    })();

    const form = document.getElementById('partnerForm');
    const statusBox = document.getElementById('statusBox');
    const submitBtn = document.getElementById('submitBtn');
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      submitBtn.disabled = true;
      statusBox.style.display = 'none';
      const payload = Object.fromEntries(new FormData(form).entries());
      try {
        const res = await fetch('/api/b2b/apply', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok) {
          if (data.checkout_url) {
            window.location.href = data.checkout_url;
            return;
          }
          statusBox.className = 'status-box status-ok';
          statusBox.textContent = data.message || 'Application received! We will review and follow up within 1-2 business days.';
          statusBox.style.display = 'block';
          form.reset();
        } else {
          statusBox.className = 'status-box status-err';
          statusBox.textContent = data.message || 'Please check your details and try again.';
          statusBox.style.display = 'block';
        }
      } catch (_) {
        statusBox.className = 'status-box status-err';
        statusBox.textContent = 'Network error. Please try again or email support@danglingdicestudios.com.';
        statusBox.style.display = 'block';
      } finally {
        submitBtn.disabled = false;
      }
    });
  </script>
</body>
</html>`;
}

/**
 * End-to-End B2B Independent Pharmacy & Clinic Partner Router
 * - GET  /partners                                (Standalone B2B landing page & pricing/signup form)
 * - POST /api/b2b/apply                           (Submit application + optional Stripe Checkout redirect)
 * - POST /api/b2b/stripe-webhook                  (Signed Stripe webhook for automated billing lifecycle)
 * - POST /api/b2b/local                           (Zero-PII lookup by 5-digit ZIP only)
 * - GET  /api/admin/b2b/partners                  (Admin-only list of applications & active partners)
 * - POST /api/admin/b2b/partners/:id/status       (Admin-only approve/pause)
 * - POST /api/admin/b2b/partners/:id/billing-portal (Admin-only Stripe Customer Portal link generator)
 * @param {import('node:sqlite').DatabaseSync} db
 */
function createB2bRouter(db) {
  const router = express.Router();
  const ipBuckets = new Map();

  function canApplyForIp(ip) {
    const now = Date.now();
    if (ipBuckets.size > 500) {
      for (const [k, v] of ipBuckets) {
        if (v.resetAt <= now) ipBuckets.delete(k);
      }
    }
    const b = ipBuckets.get(ip);
    if (!b || b.resetAt <= now) {
      ipBuckets.set(ip, { count: 1, resetAt: now + APPLY_WINDOW_MS });
      return true;
    }
    if (b.count >= APPLY_MAX_PER_IP) return false;
    b.count++;
    return true;
  }

  const insertPartnerStmt = db.prepare(`
    INSERT INTO b2b_partners (
      business_name, business_type, contact_name, contact_email,
      phone, address, website_url, transfer_url, tagline, zip_codes,
      plan_tier, npi_number, npi_verified, payment_status, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
  `);

  const getPartnerByIdStmt = db.prepare('SELECT * FROM b2b_partners WHERE id = ?');

  const listActivePartnersStmt = db.prepare(`
    SELECT id, business_name, business_type, phone, address, website_url, transfer_url, tagline, zip_codes
    FROM b2b_partners
    WHERE status = 'active'
    ORDER BY id ASC
  `);

  const listAllAdminStmt = db.prepare(`
    SELECT * FROM b2b_partners ORDER BY created_at DESC, id DESC
  `);

  const updateStatusStmt = db.prepare(`
    UPDATE b2b_partners
    SET status = ?, updated_at = datetime('now')
    WHERE id = ?
  `);

  const markPaidByIdStmt = db.prepare(`
    UPDATE b2b_partners
    SET payment_status = 'paid',
        stripe_customer_id = COALESCE(?, stripe_customer_id),
        stripe_subscription_id = COALESCE(?, stripe_subscription_id),
        status = CASE WHEN npi_verified = 1 THEN 'active' ELSE status END,
        updated_at = datetime('now')
    WHERE id = ?
  `);

  const pauseBySubscriptionStmt = db.prepare(`
    UPDATE b2b_partners
    SET payment_status = ?,
        status = 'paused',
        updated_at = datetime('now')
    WHERE stripe_subscription_id = ?
  `);

  // Standalone B2B landing page
  router.get('/partners', (req, res) => {
    res.type('text/html; charset=utf-8').send(renderPartnersPageHtml());
  });

  // Public B2B application submission (+ automatic Stripe Checkout for paid plans when configured)
  router.post('/api/b2b/apply', async (req, res) => {
    const clientIp = req.ip || 'unknown';
    if (!canApplyForIp(clientIp)) {
      return res.status(429).json({
        error: 'Too Many Requests',
        message: 'Too many applications submitted recently. Please try again later.',
      });
    }

    const body = req.body || {};
    const businessName = cleanText(body.business_name, 120);
    const businessType = ALLOWED_TYPES.has(body.business_type) ? body.business_type : 'pharmacy';
    const contactName = cleanText(body.contact_name, 100);
    const contactEmail = cleanText(body.contact_email, 140);
    const phone = cleanText(body.phone, 40) || null;
    const address = cleanText(body.address, 160) || null;
    const websiteUrl = cleanHttpUrl(body.website_url);
    const transferUrl = cleanHttpUrl(body.transfer_url);
    const tagline = cleanText(body.tagline, 140) || null;
    const planTier = ALLOWED_PLANS.has(body.plan_tier) ? body.plan_tier : 'pilot_60d';
    const maxZips = planTier === 'multi_349' ? 25 : 5;
    const zips = normalizeZipList(body.zip_codes, maxZips);
    const npiNumber = normalizeNpi(body.npi_number);

    if (businessName.length < 2) {
      return res.status(400).json({ error: 'Bad Request', message: 'Business name is required.' });
    }
    if (contactName.length < 2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Valid contact name and work email are required.' });
    }
    if (zips.length === 0) {
      return res.status(400).json({ error: 'Bad Request', message: 'Please enter at least one valid 5-digit U.S. ZIP code.' });
    }

    const npiVerified = npiNumber ? (await verifyNpiWithCms(npiNumber) ? 1 : 0) : 0;
    const initialPaymentStatus = planTier === 'pilot_60d' ? 'trial' : 'unpaid';

    const result = insertPartnerStmt.run(
      businessName,
      businessType,
      contactName,
      contactEmail,
      phone,
      address,
      websiteUrl,
      transferUrl,
      tagline,
      zips.join(','),
      planTier,
      npiNumber,
      npiVerified,
      initialPaymentStatus
    );

    const partnerId = Number(result.lastInsertRowid);
    let checkoutUrl = null;
    if (planTier !== 'pilot_60d') {
      checkoutUrl = await createStripeCheckoutSession({
        partnerId,
        planTier,
        contactEmail,
        businessName,
      });
    }

    res.status(201).json({
      success: true,
      id: partnerId,
      zip_codes: zips,
      npi_verified: npiVerified === 1,
      checkout_url: checkoutUrl,
      message: checkoutUrl
        ? 'Redirecting to secure Stripe Checkout...'
        : `Application received for ${businessName} (${zips.join(', ')}). We will review and follow up within 1-2 business days.`,
    });
  });

  // Signed Stripe webhook for automated payment & subscription lifecycle
  router.post('/api/b2b/stripe-webhook', (req, res) => {
    const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || '').trim();
    if (!webhookSecret) {
      return res.status(503).json({ error: 'Stripe webhook secret not configured' });
    }

    const sigHeader = req.get('Stripe-Signature');
    if (!verifyStripeWebhookSignature(req.rawBody, sigHeader, webhookSecret)) {
      return res.status(400).json({ error: 'Invalid Stripe signature' });
    }

    const event = req.body || {};
    const type = event.type;
    const obj = event.data?.object || {};

    if (type === 'checkout.session.completed') {
      const partnerId = parseInt(obj.client_reference_id || obj.metadata?.partner_id, 10);
      if (Number.isFinite(partnerId) && partnerId > 0) {
        markPaidByIdStmt.run(
          obj.customer ? String(obj.customer) : null,
          obj.subscription ? String(obj.subscription) : null,
          partnerId
        );
      }
    } else if (type === 'invoice.payment_failed') {
      const subId = obj.subscription ? String(obj.subscription) : null;
      if (subId) {
        pauseBySubscriptionStmt.run('past_due', subId);
      }
    } else if (type === 'customer.subscription.deleted') {
      const subId = obj.id ? String(obj.id) : null;
      if (subId) {
        pauseBySubscriptionStmt.run('canceled', subId);
      }
    }

    res.json({ received: true });
  });

  // Zero-PII local sponsored pharmacy lookup (ZIP-only POST body, never paired with a drug name)
  router.post('/api/b2b/local', (req, res) => {
    const zip = String(req.body?.zip || '').replace(/[^0-9]/g, '');
    if (zip.length !== 5) {
      return res.json({ zip: null, partners: [] });
    }

    const active = listActivePartnersStmt.all();
    const matched = active
      .filter(p => String(p.zip_codes || '').split(',').includes(zip))
      .slice(0, 3)
      .map(p => ({
        id: p.id,
        business_name: p.business_name,
        business_type: p.business_type,
        phone: p.phone || null,
        address: p.address || null,
        website_url: p.website_url || null,
        transfer_url: p.transfer_url || null,
        tagline: p.tagline || null,
      }));

    res.json({ zip, partners: matched });
  });

  // Admin: List all partner applications & active listings
  router.get('/api/admin/b2b/partners', (req, res) => {
    if (!isValidAdminKey(req)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const partners = listAllAdminStmt.all();
    res.json({ count: partners.length, partners });
  });

  // Admin: Approve ('active'), pause ('paused'), or revert ('pending') a partner
  router.post('/api/admin/b2b/partners/:id/status', (req, res) => {
    if (!isValidAdminKey(req)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const id = parseInt(req.params.id, 10);
    const status = String(req.body?.status || '').trim();
    if (!Number.isFinite(id) || id <= 0 || !ALLOWED_STATUSES.has(status)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Valid partner id and status (pending, active, paused) required.' });
    }
    const result = updateStatusStmt.run(status, id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Not Found', message: 'Partner not found.' });
    }
    res.json({ success: true, id, status });
  });

  // Admin: Generate a Stripe Customer Billing Portal URL for a paid partner
  router.post('/api/admin/b2b/partners/:id/billing-portal', async (req, res) => {
    if (!isValidAdminKey(req)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const secretKey = (process.env.STRIPE_SECRET_KEY || '').trim();
    if (!secretKey) {
      return res.status(503).json({ error: 'STRIPE_SECRET_KEY not configured' });
    }
    const id = parseInt(req.params.id, 10);
    const partner = getPartnerByIdStmt.get(id);
    if (!partner || !partner.stripe_customer_id) {
      return res.status(404).json({ error: 'Partner has no Stripe customer record yet' });
    }

    const params = new URLSearchParams();
    params.set('customer', partner.stripe_customer_id);
    params.set('return_url', `${SITE_ORIGIN}/partners`);

    try {
      const stripeRes = await fetch('https://api.stripe.com/v1/billing_portal/sessions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${secretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
        signal: AbortSignal.timeout(10000),
      });
      const data = await stripeRes.json();
      if (!stripeRes.ok || !data.url) {
        return res.status(502).json({ error: 'Stripe portal error', details: data.error?.message || 'Unknown error' });
      }
      res.json({ success: true, url: data.url });
    } catch (err) {
      res.status(502).json({ error: 'Failed to reach Stripe', message: err.message });
    }
  });

  return router;
}

module.exports = {
  createB2bRouter,
  verifyStripeWebhookSignature,
};
