const express = require("express");
const crypto = require("node:crypto");
const config = require("../config");

const SITE_ORIGIN = "https://rx.dangling-dice-studios.com";
const ALLOWED_TYPES = new Set(["pharmacy", "clinic", "senior_care"]);
const ALLOWED_PLANS = new Set(["pilot_60d", "local_149", "multi_349"]);
const ALLOWED_STATUSES = new Set(["pending", "active", "paused"]);
const ALLOWED_EVENTS = new Set(["call", "transfer", "website"]);
const SERVICE_LABELS = {
  free_delivery: "Free Local Delivery",
  compounding: "Compounding",
  med_sync: "Med-Sync / Auto-Refill",
  blister_packs: "Blister Packs",
  drive_thru: "Drive-Thru",
  bilingual: "Bilingual Staff",
  vaccines: "Walk-In Vaccines",
};
const APPLY_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const APPLY_MAX_PER_IP = 8;
const STRIPE_WEBHOOK_TOLERANCE_SEC = 300; // 5 minutes
const MAX_ACTIVE_PARTNERS_PER_ZIP = 2;

function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function cleanText(raw, maxLen = 160) {
  return String(raw || "")
    .replace(/[\x00-\x1F\x7F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLen);
}

function cleanHttpUrl(raw) {
  const trimmed = cleanText(raw, 300);
  if (!trimmed) return null;
  try {
    const parsed = new URL(
      trimmed.startsWith("http") ? trimmed : `https://${trimmed}`,
    );
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:")
      return null;
    return parsed.toString();
  } catch (_) {
    return null;
  }
}

function normalizeZipList(raw, maxZips = 25) {
  const matches = String(raw || "").match(/\b\d{5}\b/g) || [];
  return Array.from(new Set(matches)).slice(0, maxZips);
}

function normalizeServices(raw) {
  const items = Array.isArray(raw) ? raw : String(raw || "").split(",");
  const clean = items
    .map((s) =>
      String(s || "")
        .trim()
        .toLowerCase(),
    )
    .filter((s) => Object.prototype.hasOwnProperty.call(SERVICE_LABELS, s));
  return Array.from(new Set(clean));
}

function normalizeNpi(raw) {
  const digits = String(raw || "").replace(/[^0-9]/g, "");
  return digits.length === 10 ? digits : null;
}

function isValidAdminKey(req) {
  const provided = String(req.get("X-Admin-Key") || "");
  const expected = String(config.ADMIN_API_KEY || "");
  if (!provided || !expected) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

async function verifyNpiWithCms(npi) {
  if (!npi || npi.length !== 10 || process.env.NODE_ENV === "test") {
    return false;
  }
  try {
    const res = await fetch(
      `https://npiregistry.cms.hhs.gov/api/?version=2.1&number=${encodeURIComponent(npi)}`,
      {
        headers: { "User-Agent": "RxSavingsWatch/1.0" },
        signal: AbortSignal.timeout(6000),
      },
    );
    if (!res.ok) return false;
    const data = await res.json();
    const first = Array.isArray(data.results) ? data.results[0] : null;
    return Boolean(
      first && String(first.number) === npi && first.basic?.status === "A",
    );
  } catch (_) {
    return false;
  }
}

function getStripePriceId(planTier) {
  if (planTier === "local_149")
    return (process.env.STRIPE_PRICE_LOCAL_149 || "").trim() || null;
  if (planTier === "multi_349")
    return (process.env.STRIPE_PRICE_MULTI_349 || "").trim() || null;
  return null;
}

async function createStripeCheckoutSession({
  partnerId,
  planTier,
  contactEmail,
  businessName,
}) {
  const secretKey = (process.env.STRIPE_SECRET_KEY || "").trim();
  const priceId = getStripePriceId(planTier);
  if (!secretKey || !priceId) return null;

  const params = new URLSearchParams();
  params.set("mode", "subscription");
  params.set("client_reference_id", String(partnerId));
  params.set("customer_email", contactEmail);
  params.set("line_items[0][price]", priceId);
  params.set("line_items[0][quantity]", "1");
  params.set(
    "success_url",
    `${SITE_ORIGIN}/partners?checkout=success&partner_id=${partnerId}`,
  );
  params.set(
    "cancel_url",
    `${SITE_ORIGIN}/partners?checkout=canceled&partner_id=${partnerId}`,
  );
  params.set("metadata[partner_id]", String(partnerId));
  params.set("metadata[plan_tier]", planTier);
  params.set("metadata[business_name]", businessName.slice(0, 120));

  try {
    const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return typeof data.url === "string" ? data.url : null;
  } catch (_) {
    return null;
  }
}

function verifyStripeWebhookSignature(rawBody, signatureHeader, webhookSecret) {
  if (!rawBody || !signatureHeader || !webhookSecret) return false;
  const parts = String(signatureHeader).split(",");
  let timestamp = null;
  const signatures = [];
  for (const part of parts) {
    const [k, v] = part.trim().split("=");
    if (k === "t") timestamp = parseInt(v, 10);
    if (k === "v1" && v) signatures.push(v);
  }
  if (!timestamp || !Number.isFinite(timestamp) || signatures.length === 0)
    return false;

  const ageSec = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (ageSec > STRIPE_WEBHOOK_TOLERANCE_SEC) return false;

  const payload = `${timestamp}.${Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody)}`;
  const expectedHex = crypto
    .createHmac("sha256", webhookSecret)
    .update(payload, "utf8")
    .digest("hex");
  const expectedBuf = Buffer.from(expectedHex, "hex");

  for (const sig of signatures) {
    try {
      const providedBuf = Buffer.from(sig, "hex");
      if (
        providedBuf.length === expectedBuf.length &&
        crypto.timingSafeEqual(providedBuf, expectedBuf)
      ) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}

function renderFlyerHtml(partner, nonce = "") {
  const firstZip =
    String(partner.zip_codes || "")
      .split(",")
      .filter(Boolean)[0] || "";
  const targetUrl = firstZip
    ? `${SITE_ORIGIN}/?zip=${encodeURIComponent(firstZip)}`
    : `${SITE_ORIGIN}/`;
  const qrImgUrl = `https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=8&data=${encodeURIComponent(targetUrl)}`;
  const badges = normalizeServices(partner.services)
    .map((k) => `<span class="badge">${escapeHtml(SERVICE_LABELS[k])}</span>`)
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Counter Flyer — ${escapeHtml(partner.business_name)} × Rx Savings Watch</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f2f5f5; color: #122120; }
    .toolbar { text-align: center; padding: 14px; background: #fff; border-bottom: 1px solid #d9e4e3; }
    .print-btn { background: #057873; color: #fff; border: 0; padding: 10px 18px; border-radius: 10px; font-weight: 700; font-size: 14px; cursor: pointer; }
    .sheet { max-width: 640px; margin: 28px auto; background: #fff; border: 2px solid #057873; border-radius: 20px; padding: 36px 32px; text-align: center; }
    .eyebrow { display: inline-block; background: #e3f5ec; color: #057873; padding: 5px 14px; border-radius: 999px; font-size: 12px; font-weight: 800; letter-spacing: 0.6px; text-transform: uppercase; }
    h1 { margin: 14px 0 8px; font-size: 28px; line-height: 1.2; }
    .sub { color: #4f6362; font-size: 15px; margin: 0 auto 22px; max-width: 480px; }
    .qr-box { display: inline-block; padding: 14px; border: 1px solid #d9e4e3; border-radius: 16px; background: #fff; margin-bottom: 18px; }
    .cash { background: #eef8f7; border: 1px solid #b5dcd9; color: #045955; border-radius: 12px; padding: 12px 16px; font-weight: 700; margin: 12px auto 16px; max-width: 460px; }
    .badges { display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; margin-bottom: 18px; }
    .badge { background: #f1f5f9; border: 1px solid #cbd5e1; color: #1e293b; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }
    .contact { font-size: 14px; color: #334847; margin-top: 8px; }
    .foot { font-size: 11.5px; color: #64748b; margin-top: 22px; border-top: 1px solid #e2e8f0; padding-top: 12px; }
    @media print {
      body { background: #fff; }
      .toolbar { display: none; }
      .sheet { margin: 0 auto; border-width: 2px; box-shadow: none; }
    }
  </style>
</head>
<body>
  <div class="toolbar">
    <button class="print-btn" id="printBtn" type="button">Print Counter Flyer / Bag Stuffer</button>
  </div>
  <div class="sheet">
    <span class="eyebrow">Free Refill Reminders &amp; Generic Savings</span>
    <h1>Recommended by ${escapeHtml(partner.business_name)}</h1>
    <p class="sub">Scan the QR code to get free prescription refill countdowns, daily dose reminders, and FDA generic availability alerts—100% private with zero login.</p>
    <div class="qr-box">
      <img src="${qrImgUrl}" width="210" height="210" alt="Scan to open Rx Savings Watch">
    </div>
    ${partner.cash_price_note ? `<div class="cash">${escapeHtml(partner.cash_price_note)}</div>` : ""}
    ${badges ? `<div class="badges">${badges}</div>` : ""}
    <div class="contact">
      ${partner.phone ? `<strong>Call Us:</strong> ${escapeHtml(partner.phone)}` : ""}
      ${partner.address ? `<br>${escapeHtml(partner.address)}` : ""}
    </div>
    <div class="foot">
      Powered by Rx Savings Watch (rx.dangling-dice-studios.com) • Zero accounts, zero tracking, zero PHI collected.<br>
      Informational only — not insurance or medical advice.
    </div>
  </div>
  <script nonce="${nonce}">
    document.getElementById('printBtn').addEventListener('click', function () { window.print(); });
  </script>
</body>
</html>`;
}

function renderPartnersPageHtml(nonce = "") {
  const serviceCheckboxes = Object.entries(SERVICE_LABELS)
    .map(
      ([key, label]) => `
    <label class="check-pill">
      <input type="checkbox" name="services" value="${key}">
      <span>${escapeHtml(label)}</span>
    </label>
  `,
    )
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>For Independent Pharmacies &amp; Clinics — Rx Savings Watch B2B Partner Program</title>
  <meta name="description" content="Reach local cash-pay patients right when they refill. Flat-rate ZIP sponsorship (capped at 2 exclusive pharmacies per ZIP) with public cash pricing, service badges, counter QR flyers, and zero-PHI monthly ROI reports.">
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
    .hero p { margin: 0 0 20px; color: #d8f2f0; max-width: 740px; font-size: 16px; }
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
    .checks { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 6px; }
    .check-pill { display: inline-flex; align-items: center; gap: 6px; padding: 7px 12px; border: 1px solid #c5d4d3; border-radius: 999px; font-size: 13px; font-weight: 600; cursor: pointer; background: #fff; margin: 0; }
    .check-pill input { width: auto; margin: 0; }
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
      <span class="pill">LIMITED TO 2 EXCLUSIVE PARTNERS PER ZIP • ZERO HIPAA FRICTION</span>
      <h1>Win Back Local Cash-Pay Refills Without Big-Chain Software Costs</h1>
      <p>Showcase your public cash-price menu, highlight services chains can't match (free delivery, compounding, blister packs), hand customers a co-branded QR refill flyer, and receive monthly zero-PHI click &amp; impression reports.</p>
      <a class="btn" style="background:#fff;color:#035a56 !important;" href="#apply">Claim Your ZIP Codes</a>
    </section>

    <section class="grid-3">
      <div class="card">
        <strong>60-Day Free Pilot</strong>
        <div class="price">$0 <span class="muted" style="font-size:14px;font-weight:500;">/ 60 days</span></div>
        <p class="muted">For our first 5 independent pharmacy or DPC clinic partners.</p>
        <ul>
          <li>Featured <em>Sponsored Local Partner</em> card in up to 5 ZIP codes</li>
          <li>Public cash-price highlight + service badges (delivery, compounding, etc.)</li>
          <li>Printable co-branded Counter QR Flyer + monthly ROI counters</li>
        </ul>
        <button type="button" class="btn-outline" data-plan="pilot_60d">Start 60-Day Free Pilot</button>
      </div>

      <div class="card" style="border-color:#057873;border-width:2px;">
        <strong>Local Independent Pharmacy</strong>
        <div class="price">$149 <span class="muted" style="font-size:14px;font-weight:500;">/ month</span></div>
        <p class="muted">Flat-rate ZIP sponsorship (max 2 partners per ZIP) — never per-Rx kickbacks.</p>
        <ul>
          <li>Featured across up to 5 local 5-digit ZIP codes</li>
          <li>Public cash-price menu + service badges + 1-tap Call / Transfer Rx</li>
          <li>Printable Counter QR Flyer + monthly aggregate ROI report</li>
        </ul>
        <button type="button" class="btn" data-plan="local_149">Subscribe — $149/mo</button>
      </div>

      <div class="card">
        <strong>Multi-Location / Senior Care</strong>
        <div class="price">$349 <span class="muted" style="font-size:14px;font-weight:500;">/ month</span></div>
        <p class="muted">For regional independent chains, DPC groups, or senior communities.</p>
        <ul>
          <li>Up to 25 covered 5-digit ZIP codes</li>
          <li>Everything in Local Pharmacy + custom counter flyers per location</li>
          <li>Zero patient PHI ever shared or stored</li>
        </ul>
        <button type="button" class="btn-outline" data-plan="multi_349">Subscribe — $349/mo</button>
      </div>
    </section>

    <section class="card" id="apply" style="display:block;">
      <h2 style="margin-top:0;">Partner Onboarding &amp; Checkout</h2>
      <p class="muted" style="margin-bottom:18px;">Complete your public pharmacy details below. Paid plans proceed directly to secure Stripe Checkout, and pharmacies with a verified 10-digit NPI activate automatically upon payment.</p>

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
            <label for="npi_number">10-Digit NPI Number (Optional — instant verification)</label>
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
          <div>
            <label for="cash_price_note">Public Cash-Price Highlight (Optional)</label>
            <input id="cash_price_note" name="cash_price_note" maxlength="120" placeholder="Most 30-day generics $10 cash • Cost + $8 fee">
          </div>
        </div>
        <div style="margin-top:14px;">
          <label for="tagline">Short Patient Tagline (shown on your card)</label>
          <input id="tagline" name="tagline" maxlength="140" placeholder="Friendly independent pharmacists &amp; transparent cash fills">
        </div>
        <div style="margin-top:14px;">
          <label>Public Pharmacy Services (Select all that apply)</label>
          <div class="checks">${serviceCheckboxes}</div>
        </div>
        <div style="margin-top:18px;display:flex;align-items:center;gap:14px;flex-wrap:wrap;">
          <button class="btn" type="submit" id="submitBtn">Submit 60-Day Free Pilot Application</button>
          <span class="muted" style="font-size:12.5px;">Flat-rate sponsorship only • Max 2 pharmacies per ZIP • Zero patient PHI shared</span>
        </div>
        <div id="statusBox" class="status-box"></div>
      </form>
    </section>
  </main>

  <footer>
    <p><strong>Compliance &amp; Privacy:</strong> Local pharmacy sponsorships are flat monthly directory placements (never per-prescription volume fees). Rx Savings Watch never collects or transmits patient PHI.</p>
    <p>© 2026 Dangling Dice Studios™ • Questions? Email support@danglingdicestudios.com</p>
  </footer>

  <script nonce="${nonce}">
    function updateSubmitLabel(plan) {
      const btn = document.getElementById('submitBtn');
      if (!btn) return;
      if (plan === 'local_149') {
        btn.textContent = 'Continue to Checkout ($149/mo)';
      } else if (plan === 'multi_349') {
        btn.textContent = 'Continue to Checkout ($349/mo)';
      } else {
        btn.textContent = 'Submit 60-Day Free Pilot Application';
      }
    }

    function selectPlan(plan) {
      const sel = document.getElementById('plan_tier');
      if (sel) sel.value = plan;
      updateSubmitLabel(plan);
      const applyEl = document.getElementById('apply');
      if (applyEl) {
        applyEl.style.borderColor = '#057873';
        applyEl.style.borderWidth = '2px';
        applyEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
      const nameInput = document.getElementById('business_name');
      if (nameInput) nameInput.focus();
    }

    const planSelect = document.getElementById('plan_tier');
    if (planSelect) {
      planSelect.addEventListener('change', (e) => updateSubmitLabel(e.target.value));
      updateSubmitLabel(planSelect.value);
    }

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
      const fd = new FormData(form);
      const payload = Object.fromEntries(fd.entries());
      payload.services = fd.getAll('services');
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
          updateSubmitLabel('pilot_60d');
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

    document.querySelectorAll('[data-plan]').forEach(function (btn) {
      btn.addEventListener('click', function () { selectPlan(btn.getAttribute('data-plan')); });
    });
  </script>
</body>
</html>`;
}

/**
 * Strict Content-Security-Policy for server-rendered B2B pages. Inline scripts must carry the
 * per-response nonce; inline styles are allowed (static, no user-controlled CSS).
 */
function setStrictPageCsp(res, nonce, { allowQrImages = false } = {}) {
  const imgSrc = allowQrImages ? "img-src 'self' data: https://api.qrserver.com" : "img-src 'self' data:";
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'none'",
      `script-src 'nonce-${nonce}'`,
      "style-src 'unsafe-inline'",
      imgSrc,
      "connect-src 'self'",
      "form-action 'self'",
      "base-uri 'none'",
      "frame-ancestors 'self'",
    ].join("; "),
  );
}

function createB2bRouter(db) {
  const router = express.Router();
  const ipBuckets = new Map();

  // ROI counter integrity: each visitor (IP, held in memory only, never persisted) can add at most
  // ONE impression and ONE click of each type per partner per 24h, so paying partners see
  // de-duplicated numbers that cannot be trivially inflated by repeated requests.
  const COUNTER_DEDUPE_WINDOW_MS = 24 * 60 * 60 * 1000;
  const COUNTER_DEDUPE_MAX = 20000;
  const counterSeen = new Map(); // key -> expiresAt
  function shouldCountOnce(ip, partnerId, kind) {
    const now = Date.now();
    if (counterSeen.size >= COUNTER_DEDUPE_MAX) {
      for (const [k, exp] of counterSeen) {
        if (exp <= now) counterSeen.delete(k);
      }
      if (counterSeen.size >= COUNTER_DEDUPE_MAX) counterSeen.clear();
    }
    const key = `${ip}|${partnerId}|${kind}`;
    const exp = counterSeen.get(key);
    if (exp && exp > now) return false;
    counterSeen.set(key, now + COUNTER_DEDUPE_WINDOW_MS);
    return true;
  }

  // Stripe webhook idempotency: Stripe retries deliveries, so each event id is processed once.
  db.exec(`
    CREATE TABLE IF NOT EXISTS stripe_webhook_events (
      event_id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      received_at TEXT DEFAULT (datetime('now'))
    );
  `);
  const insertStripeEventStmt = db.prepare(
    "INSERT OR IGNORE INTO stripe_webhook_events (event_id, event_type) VALUES (?, ?)",
  );
  const reactivateBySubscriptionStmt = db.prepare(`
    UPDATE b2b_partners
    SET payment_status = 'paid',
        status = CASE WHEN npi_verified = 1 THEN 'active' ELSE status END,
        updated_at = datetime('now')
    WHERE stripe_subscription_id = ?
      AND payment_status = 'past_due'
      AND status = 'paused'
  `);

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
      phone, address, website_url, transfer_url, tagline, services, cash_price_note,
      zip_codes, plan_tier, npi_number, npi_verified, payment_status, status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
  `);

  const getPartnerByIdStmt = db.prepare(
    "SELECT * FROM b2b_partners WHERE id = ?",
  );

  const listActivePartnersStmt = db.prepare(`
    SELECT id, business_name, business_type, phone, address, website_url, transfer_url,
           tagline, services, cash_price_note, zip_codes
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

  const incImpressionStmt = db.prepare(
    "UPDATE b2b_partners SET impressions_count = impressions_count + 1 WHERE id = ?",
  );
  const incCallStmt = db.prepare(
    "UPDATE b2b_partners SET call_clicks = call_clicks + 1 WHERE id = ? AND status = 'active'",
  );
  const incTransferStmt = db.prepare(
    "UPDATE b2b_partners SET transfer_clicks = transfer_clicks + 1 WHERE id = ? AND status = 'active'",
  );
  const incWebsiteStmt = db.prepare(
    "UPDATE b2b_partners SET website_clicks = website_clicks + 1 WHERE id = ? AND status = 'active'",
  );

  // Standalone B2B landing page
  router.get("/partners", (req, res) => {
    const nonce = crypto.randomBytes(16).toString("base64");
    setStrictPageCsp(res, nonce);
    res.type("text/html; charset=utf-8").send(renderPartnersPageHtml(nonce));
  });

  // Printable Co-Branded Counter QR Flyer for any active partner pharmacy
  router.get("/partners/:id/flyer", (req, res) => {
    const id = parseInt(req.params.id, 10);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(404).type("text/plain").send("Partner flyer not found");
    }
    const partner = getPartnerByIdStmt.get(id);
    if (!partner || partner.status !== "active") {
      return res
        .status(404)
        .type("text/plain")
        .send("Partner flyer not available");
    }
    const nonce = crypto.randomBytes(16).toString("base64");
    setStrictPageCsp(res, nonce, { allowQrImages: true });
    res.type("text/html; charset=utf-8").send(renderFlyerHtml(partner, nonce));
  });

  // Public B2B application submission (+ automatic Stripe Checkout for paid plans when configured)
  router.post("/api/b2b/apply", async (req, res) => {
    const clientIp = req.ip || "unknown";
    if (!canApplyForIp(clientIp)) {
      return res.status(429).json({
        error: "Too Many Requests",
        message:
          "Too many applications submitted recently. Please try again later.",
      });
    }

    const body = req.body || {};
    const businessName = cleanText(body.business_name, 120);
    const businessType = ALLOWED_TYPES.has(body.business_type)
      ? body.business_type
      : "pharmacy";
    const contactName = cleanText(body.contact_name, 100);
    const contactEmail = cleanText(body.contact_email, 140);
    const phone = cleanText(body.phone, 40) || null;
    const address = cleanText(body.address, 160) || null;
    const websiteUrl = cleanHttpUrl(body.website_url);
    const transferUrl = cleanHttpUrl(body.transfer_url);
    const tagline = cleanText(body.tagline, 140) || null;
    const services = normalizeServices(body.services);
    const cashPriceNote = cleanText(body.cash_price_note, 120) || null;
    const planTier = ALLOWED_PLANS.has(body.plan_tier)
      ? body.plan_tier
      : "pilot_60d";
    const maxZips = planTier === "multi_349" ? 25 : 5;
    const zips = normalizeZipList(body.zip_codes, maxZips);
    const npiNumber = normalizeNpi(body.npi_number);

    if (businessName.length < 2) {
      return res
        .status(400)
        .json({ error: "Bad Request", message: "Business name is required." });
    }
    if (
      contactName.length < 2 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)
    ) {
      return res.status(400).json({
        error: "Bad Request",
        message: "Valid contact name and work email are required.",
      });
    }
    if (zips.length === 0) {
      return res.status(400).json({
        error: "Bad Request",
        message: "Please enter at least one valid 5-digit U.S. ZIP code.",
      });
    }

    const npiVerified = npiNumber
      ? (await verifyNpiWithCms(npiNumber))
        ? 1
        : 0
      : 0;
    const initialPaymentStatus = planTier === "pilot_60d" ? "trial" : "unpaid";

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
      services.join(","),
      cashPriceNote,
      zips.join(","),
      planTier,
      npiNumber,
      npiVerified,
      initialPaymentStatus,
    );

    const partnerId = Number(result.lastInsertRowid);
    let checkoutUrl = null;
    if (planTier !== "pilot_60d") {
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
      services,
      npi_verified: npiVerified === 1,
      checkout_url: checkoutUrl,
      message: checkoutUrl
        ? "Redirecting to secure Stripe Checkout..."
        : `Application received for ${businessName} (${zips.join(", ")}). We will review and follow up within 1-2 business days.`,
    });
  });

  // Signed Stripe webhook for automated payment & subscription lifecycle
  router.post("/api/b2b/stripe-webhook", (req, res) => {
    const webhookSecret = (process.env.STRIPE_WEBHOOK_SECRET || "").trim();
    if (!webhookSecret) {
      return res
        .status(503)
        .json({ error: "Stripe webhook secret not configured" });
    }

    const sigHeader = req.get("Stripe-Signature");
    if (!verifyStripeWebhookSignature(req.rawBody, sigHeader, webhookSecret)) {
      return res.status(400).json({ error: "Invalid Stripe signature" });
    }

    const event = req.body || {};
    const type = event.type;
    const obj = event.data?.object || {};

    if (typeof event.id === "string" && event.id) {
      const inserted = insertStripeEventStmt.run(event.id, String(type || "unknown"));
      if (inserted.changes === 0) {
        // Already processed this exact event (Stripe retry) — acknowledge without re-applying.
        return res.json({ received: true, duplicate: true });
      }
    }

    if (type === "checkout.session.completed") {
      const partnerId = parseInt(
        obj.client_reference_id || obj.metadata?.partner_id,
        10,
      );
      if (Number.isFinite(partnerId) && partnerId > 0) {
        markPaidByIdStmt.run(
          obj.customer ? String(obj.customer) : null,
          obj.subscription ? String(obj.subscription) : null,
          partnerId,
        );
      }
    } else if (type === "invoice.paid" || type === "invoice.payment_succeeded") {
      // A successful retry after a failed payment restores only partners that were auto-paused
      // for past_due (never overrides an admin-paused or canceled listing).
      const subId = obj.subscription ? String(obj.subscription) : null;
      if (subId) {
        reactivateBySubscriptionStmt.run(subId);
      }
    } else if (type === "invoice.payment_failed") {
      const subId = obj.subscription ? String(obj.subscription) : null;
      if (subId) {
        pauseBySubscriptionStmt.run("past_due", subId);
      }
    } else if (type === "customer.subscription.deleted") {
      const subId = obj.id ? String(obj.id) : null;
      if (subId) {
        pauseBySubscriptionStmt.run("canceled", subId);
      }
    }

    res.json({ received: true });
  });

const NPI_ZIP_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const NPI_ZIP_CACHE_MAX = 500;
const npiZipCache = new Map(); // zip -> { expiresAt, pharmacies }

function formatPharmacyName(raw) {
  let name = String(raw || "").trim();
  if (!name) return "Local Pharmacy";
  // Strip noisy corporate suffixes for readability
  name = name
    .replace(/\b(INC\.?|LLC\.?|L\.?L\.?C\.?|L\.?\s*P\.?|CORP\.?|CORPORATION|CO\.?|LTD\.?)\b/gi, "")
    .replace(/\s{2,}/g, " ")
    .replace(/[,-]\s*$/, "")
    .trim();
  if (!name) return "Local Pharmacy";
  // Convert ALL-CAPS CMS names to readable Title Case while preserving acronyms
  const ACRONYMS = new Set(["CVS", "RX", "HEB", "H-E-B", "US", "USA", "VA", "DR", "NW", "NE", "SW", "SE"]);
  if (name === name.toUpperCase()) {
    name = name
      .split(/\s+/)
      .map((word) => {
        const clean = word.replace(/[^A-Z0-9-]/g, "");
        if (ACRONYMS.has(clean)) return word;
        if (/^#?\d+$/.test(word)) return word;
        return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
      })
      .join(" ");
  }
  return name;
}

function formatUsPhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  if (digits.length === 10) {
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  }
  return raw ? String(raw).trim() : null;
}

function formatStreetAddress(loc) {
  if (!loc) return null;
  const line1 = [loc.address_1, loc.address_2]
    .map((s) => String(s || "").trim())
    .filter(Boolean)
    .join(", ");
  const city = String(loc.city || "").trim();
  const state = String(loc.state || "").trim().toUpperCase();
  const zip5 = String(loc.postal_code || "").replace(/\D/g, "").slice(0, 5);
  const title = (s) =>
    s
      .split(/\s+/)
      .map((w) => (w.length <= 2 && /^[A-Z]+$/.test(w) ? w : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()))
      .join(" ");
  const parts = [];
  if (line1) parts.push(title(line1));
  const cityState = [city ? title(city) : "", state].filter(Boolean).join(", ");
  if (cityState || zip5) parts.push([cityState, zip5].filter(Boolean).join(" "));
  return parts.join(", ") || null;
}

async function fetchNpiPharmaciesByTaxonomy(zip, taxonomy) {
  const url =
    `https://npiregistry.cms.hhs.gov/api/?version=2.1&enumeration_type=NPI-2` +
    `&taxonomy_description=${encodeURIComponent(taxonomy)}` +
    `&postal_code=${encodeURIComponent(zip)}&limit=25`;
  const res = await fetch(url, {
    headers: { "User-Agent": "RxSavingsWatch/1.0" },
    signal: AbortSignal.timeout(6000),
  });
  if (!res.ok) return [];
  const data = await res.json();
  return Array.isArray(data.results) ? data.results : [];
}

async function lookupLocalNpiPharmacies(zip) {
  if (process.env.NODE_ENV === "test") return [];
  const now = Date.now();
  const cached = npiZipCache.get(zip);
  if (cached && cached.expiresAt > now) return cached.pharmacies;

  try {
    let rawResults = await fetchNpiPharmaciesByTaxonomy(zip, "Community/Retail Pharmacy");
    if (rawResults.length === 0) {
      rawResults = await fetchNpiPharmaciesByTaxonomy(zip, "Pharmacy");
    }

    const seenKeys = new Set();
    const pharmacies = [];

    for (const entry of rawResults) {
      if (entry?.basic?.status && entry.basic.status !== "A") continue;
      const loc =
        (entry.addresses || []).find((a) => a.address_purpose === "LOCATION") ||
        (entry.addresses || [])[0];
      if (!loc) continue;
      const locZip = String(loc.postal_code || "").replace(/\D/g, "").slice(0, 5);
      if (locZip && locZip !== zip) continue;

      // Prefer Doing Business As (DBA) name when available (e.g., "Kroger Pharmacy" over "KROGER TEXAS L P")
      const dba = (entry.other_names || []).find(
        (n) => n?.organization_name && String(n.type || "").toLowerCase().includes("doing business"),
      )?.organization_name;
      const rawName = dba || entry.basic?.organization_name || "";
      const name = formatPharmacyName(rawName);
      const address = formatStreetAddress(loc);
      const phone = formatUsPhone(loc.telephone_number);
      const phoneDigits = String(loc.telephone_number || "").replace(/\D/g, "");
      const addrKey = String(loc.address_1 || "").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 14);
      const dedupeKey = phoneDigits.length >= 10 ? `p:${phoneDigits}` : `a:${addrKey}:${name.toLowerCase().slice(0, 12)}`;
      if (seenKeys.has(dedupeKey)) continue;
      seenKeys.add(dedupeKey);

      const query = [name, address].filter(Boolean).join(" ");
      pharmacies.push({
        npi: String(entry.number || ""),
        name,
        address,
        phone,
        maps_url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`,
      });
      if (pharmacies.length >= 6) break;
    }

    if (npiZipCache.size >= NPI_ZIP_CACHE_MAX) {
      npiZipCache.clear();
    }
    npiZipCache.set(zip, { expiresAt: now + NPI_ZIP_CACHE_TTL_MS, pharmacies });
    return pharmacies;
  } catch (_) {
    return [];
  }
}

  // Zero-PII local pharmacy lookup (ZIP-only POST body: up to 2 sponsored partners + real CMS NPI retail pharmacies)
  router.post("/api/b2b/local", async (req, res) => {
    const zip = String(req.body?.zip || "").replace(/[^0-9]/g, "");
    if (zip.length !== 5) {
      return res.json({ zip: null, partners: [], local_pharmacies: [] });
    }

    const active = listActivePartnersStmt.all();
    const matched = active
      .filter((p) =>
        String(p.zip_codes || "")
          .split(",")
          .includes(zip),
      )
      .slice(0, MAX_ACTIVE_PARTNERS_PER_ZIP);

    const clientIp = req.ip || "unknown";
    const payload = matched.map((p) => {
      if (shouldCountOnce(clientIp, p.id, "impression")) {
        incImpressionStmt.run(p.id);
      }
      const serviceLabels = normalizeServices(p.services).map(
        (k) => SERVICE_LABELS[k],
      );
      return {
        id: p.id,
        business_name: p.business_name,
        business_type: p.business_type,
        phone: p.phone || null,
        address: p.address || null,
        website_url: p.website_url || null,
        transfer_url: p.transfer_url || null,
        tagline: p.tagline || null,
        cash_price_note: p.cash_price_note || null,
        services: serviceLabels,
      };
    });

    const localPharmacies = await lookupLocalNpiPharmacies(zip);

    res.json({ zip, partners: payload, local_pharmacies: localPharmacies });
  });

  // Zero-PII aggregate click counter (partner_id + event_type ONLY — no IPs, user IDs, or drug names)
  router.post("/api/b2b/event", (req, res) => {
    const partnerId = parseInt(req.body?.partner_id, 10);
    const eventType = String(req.body?.event_type || "")
      .trim()
      .toLowerCase();
    if (
      !Number.isFinite(partnerId) ||
      partnerId <= 0 ||
      !ALLOWED_EVENTS.has(eventType)
    ) {
      return res.status(400).json({ error: "Invalid event payload" });
    }
    if (!shouldCountOnce(req.ip || "unknown", partnerId, eventType)) {
      // Same visitor already counted for this partner/event in the last 24h.
      return res.json({ recorded: false, deduplicated: true });
    }
    if (eventType === "call") incCallStmt.run(partnerId);
    else if (eventType === "transfer") incTransferStmt.run(partnerId);
    else if (eventType === "website") incWebsiteStmt.run(partnerId);
    res.json({ recorded: true });
  });

  // Admin: List all partner applications, active listings, flyer URLs, and aggregate ROI metrics
  router.get("/api/admin/b2b/partners", (req, res) => {
    if (!isValidAdminKey(req)) {
      return res.status(401).json({ error: "Unauthorized" });
    }
    const partners = listAllAdminStmt.all().map((p) => ({
      ...p,
      flyer_url:
        p.status === "active" ? `${SITE_ORIGIN}/partners/${p.id}/flyer` : null,
    }));
    res.json({ count: partners.length, partners });
  });

  // Admin: Approve ('active'), pause ('paused'), or revert ('pending') a partner
  router.post("/api/admin/b2b/partners/:id/status", (req, res) => {
    if (!isValidAdminKey(req)) {
      return res.status(401).json({ error: "Unauthorized" });
    }
    const id = parseInt(req.params.id, 10);
    const status = String(req.body?.status || "").trim();
    if (!Number.isFinite(id) || id <= 0 || !ALLOWED_STATUSES.has(status)) {
      return res.status(400).json({
        error: "Bad Request",
        message:
          "Valid partner id and status (pending, active, paused) required.",
      });
    }
    const result = updateStatusStmt.run(status, id);
    if (result.changes === 0) {
      return res
        .status(404)
        .json({ error: "Not Found", message: "Partner not found." });
    }
    res.json({
      success: true,
      id,
      status,
      flyer_url:
        status === "active" ? `${SITE_ORIGIN}/partners/${id}/flyer` : null,
    });
  });

  // Admin: Generate a Stripe Customer Billing Portal URL for a paid partner
  router.post(
    "/api/admin/b2b/partners/:id/billing-portal",
    async (req, res) => {
      if (!isValidAdminKey(req)) {
        return res.status(401).json({ error: "Unauthorized" });
      }
      const secretKey = (process.env.STRIPE_SECRET_KEY || "").trim();
      if (!secretKey) {
        return res
          .status(503)
          .json({ error: "STRIPE_SECRET_KEY not configured" });
      }
      const id = parseInt(req.params.id, 10);
      const partner = getPartnerByIdStmt.get(id);
      if (!partner || !partner.stripe_customer_id) {
        return res
          .status(404)
          .json({ error: "Partner has no Stripe customer record yet" });
      }

      const params = new URLSearchParams();
      params.set("customer", partner.stripe_customer_id);
      params.set("return_url", `${SITE_ORIGIN}/partners`);

      try {
        const stripeRes = await fetch(
          "https://api.stripe.com/v1/billing_portal/sessions",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${secretKey}`,
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body: params.toString(),
            signal: AbortSignal.timeout(10000),
          },
        );
        const data = await stripeRes.json();
        if (!stripeRes.ok || !data.url) {
          return res.status(502).json({
            error: "Stripe portal error",
            details: data.error?.message || "Unknown error",
          });
        }
        res.json({ success: true, url: data.url });
      } catch (err) {
        res
          .status(502)
          .json({ error: "Failed to reach Stripe", message: err.message });
      }
    },
  );

  return router;
}

module.exports = {
  createB2bRouter,
  verifyStripeWebhookSignature,
  SERVICE_LABELS,
};
