const express = require('express');
const crypto = require('node:crypto');
const config = require('../config');

const SITE_ORIGIN = 'https://rx.dangling-dice-studios.com';
const ALLOWED_TYPES = new Set(['pharmacy', 'clinic', 'senior_care']);
const ALLOWED_PLANS = new Set(['pilot_60d', 'local_149', 'multi_349']);
const ALLOWED_STATUSES = new Set(['pending', 'active', 'paused']);
const APPLY_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const APPLY_MAX_PER_IP = 8;

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
  const unique = Array.from(new Set(matches)).slice(0, maxZips);
  return unique;
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
    .btn-outline { display: inline-flex; align-items: center; gap: 8px; background: #fff; color: var(--teal-dark) !important; border: 1px solid #b8cfcd; padding: 10px 16px; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; }
    main { max-width: 1080px; margin: 0 auto; padding: 32px 20px 64px; }
    .hero { background: linear-gradient(135deg, #057873, #034e4a); color: #fff; border-radius: 20px; padding: 36px 28px; margin-bottom: 24px; }
    .hero h1 { margin: 8px 0 10px; font-size: 32px; line-height: 1.2; }
    .hero p { margin: 0 0 20px; color: #d8f2f0; max-width: 720px; font-size: 16px; }
    .pill { display: inline-block; background: rgba(255,255,255,0.16); padding: 4px 12px; border-radius: 999px; font-size: 12px; font-weight: 700; letter-spacing: 0.4px; }
    .grid-3 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 18px; margin-bottom: 24px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 22px; }
    .price { font-size: 28px; font-weight: 800; color: var(--teal-dark); margin: 8px 0; }
    .muted { color: var(--muted); font-size: 14px; }
    ul { padding-left: 18px; margin: 10px 0 0; }
    li { margin-bottom: 6px; font-size: 14px; }
    .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
    label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 5px; }
    input, select { width: 100%; padding: 10px 12px; border: 1px solid #c5d4d3; border-radius: 10px; font-size: 14px; font-family: inherit; background: #fff; }
    input:focus, select:focus { outline: 2px solid var(--teal); border-color: var(--teal); }
    .status-box { margin-top: 14px; padding: 12px 14px; border-radius: 10px; font-size: 14px; display: none; }
    .status-ok { background: #e3f5ec; color: #0f6b43; border: 1px solid #9ad6b8; }
    .status-err { background: #fdecec; color: #9c1c1c; border: 1px solid #f2b4b4; }
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
    <section class="hero">
      <span class="pill">B2B PARTNER PROGRAM • ZERO EHR OR HIPAA FRICTION</span>
      <h1>Reach Local Cash-Pay Patients Right When They Refill</h1>
      <p>Rx Savings Watch helps patients and caregivers track prescriptions, refill dates, and generic savings—100% free and private. Independent pharmacies, Direct Primary Care (DPC) clinics, and senior care facilities can sponsor local ZIP codes with a simple flat monthly fee.</p>
      <a class="btn" style="background:#fff;color:#035a56 !important;" href="#apply">Apply for Partner Listing</a>
    </section>

    <section class="grid-3">
      <div class="card">
        <strong>60-Day Free Pilot</strong>
        <div class="price">$0 <span class="muted" style="font-size:14px;font-weight:500;">/ 60 days</span></div>
        <p class="muted">For our first 5 independent pharmacy or DPC clinic partners.</p>
        <ul>
          <li>Featured <em>Sponsored Local Partner</em> card in up to 5 ZIP codes</li>
          <li>1-tap Call Pharmacy, Transfer Rx, and Directions buttons</li>
          <li>Zero setup fee — cancel anytime</li>
        </ul>
      </div>

      <div class="card" style="border-color:#057873;border-width:2px;">
        <strong>Local Independent Pharmacy</strong>
        <div class="price">$149 <span class="muted" style="font-size:14px;font-weight:500;">/ month</span></div>
        <p class="muted">Flat-rate local sponsorship — never per-prescription kickbacks.</p>
        <ul>
          <li>Featured across up to 5 local 5-digit ZIP codes</li>
          <li>Shown when local users compare cash prices or refill</li>
          <li>Custom tagline (e.g., free local delivery, transparent cash fills)</li>
        </ul>
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
      </div>
    </section>

    <section class="card" id="apply">
      <h2 style="margin-top:0;">Apply for the Partner Program</h2>
      <p class="muted" style="margin-bottom:18px;">Submit your business details below. We review applications within 1–2 business days and activate your ZIP sponsorship once approved.</p>

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
            <label for="plan_tier">Preferred Plan *</label>
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
          <button class="btn" type="submit" id="submitBtn">Submit Partner Application</button>
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
 * - GET  /partners                     (Standalone B2B landing page & signup form)
 * - POST /api/b2b/apply                (Submit pharmacy/clinic partner application)
 * - POST /api/b2b/local                (Zero-PII lookup by 5-digit ZIP only — never paired with drug names)
 * - GET  /api/admin/b2b/partners       (Admin-only list of applications & active partners)
 * - POST /api/admin/b2b/partners/:id/status (Admin-only approve/pause)
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
      phone, address, website_url, transfer_url, tagline, zip_codes, plan_tier, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
  `);

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

  // Standalone B2B landing page
  router.get('/partners', (req, res) => {
    res.type('text/html; charset=utf-8').send(renderPartnersPageHtml());
  });

  // Public B2B application submission
  router.post('/api/b2b/apply', (req, res) => {
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

    if (businessName.length < 2) {
      return res.status(400).json({ error: 'Bad Request', message: 'Business name is required.' });
    }
    if (contactName.length < 2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Valid contact name and work email are required.' });
    }
    if (zips.length === 0) {
      return res.status(400).json({ error: 'Bad Request', message: 'Please enter at least one valid 5-digit U.S. ZIP code.' });
    }

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
      planTier
    );

    res.status(201).json({
      success: true,
      id: Number(result.lastInsertRowid),
      zip_codes: zips,
      message: `Application received for ${businessName} (${zips.join(', ')}). We will review and follow up within 1-2 business days.`,
    });
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

  return router;
}

module.exports = {
  createB2bRouter,
};
