const express = require('express');
const { getVerifiedPartnersForDrug } = require('../services/partnerResolver');

const SITE_ORIGIN = 'https://rx.dangling-dice-studios.com';

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function drugSlug(drug) {
  const base = (drug.brand_name && drug.brand_name.trim()) ? drug.brand_name.trim() : (drug.generic_name || '').trim();
  const slug = base
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug || String(drug.rxcui || 'medication');
}

function renderLayout({ title, description, canonicalUrl, jsonLd, bodyHtml }) {
  const ldScript = jsonLd
    ? `<script type="application/ld+json">${JSON.stringify(jsonLd).replace(/</g, '\\u003c')}</script>`
    : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">
  <meta property="og:site_name" content="Rx Savings Watch">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta name="theme-color" content="#057873">
  ${ldScript}
  <style>
    :root { --teal: #057873; --teal-dark: #035a56; --bg: #f6f9f9; --card: #ffffff; --text: #142221; --muted: #546665; --border: #dce6e5; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); line-height: 1.55; }
    header { background: var(--card); border-bottom: 1px solid var(--border); padding: 14px 20px; position: sticky; top: 0; z-index: 10; }
    .nav { max-width: 1040px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
    .brand { display: flex; align-items: center; gap: 10px; text-decoration: none; color: var(--text); font-weight: 700; font-size: 18px; }
    .brand-badge { background: var(--teal); color: #fff; padding: 5px 9px; border-radius: 8px; font-size: 13px; }
    .nav-links { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; }
    .nav-links a { text-decoration: none; color: var(--teal-dark); font-weight: 600; font-size: 14px; }
    .btn { display: inline-flex; align-items: center; gap: 8px; background: var(--teal); color: #fff !important; padding: 10px 16px; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; }
    .btn:hover { background: var(--teal-dark); }
    .btn-outline { display: inline-flex; align-items: center; gap: 8px; background: #fff; color: var(--teal-dark) !important; border: 1px solid #b8cfcd; padding: 10px 14px; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; }
    .btn-outline:hover { background: #edf5f4; }
    main { max-width: 1040px; margin: 0 auto; padding: 28px 20px 56px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px; padding: 22px; margin-bottom: 18px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 18px; }
    .pill { display: inline-block; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 700; }
    .pill-green { background: #e3f5ec; color: #0f6b43; }
    .pill-slate { background: #e8efef; color: #364f4e; }
    .pill-amber { background: #fff3db; color: #9a5200; }
    h1 { margin: 8px 0 6px; font-size: 30px; line-height: 1.2; }
    h2 { margin: 0 0 10px; font-size: 18px; }
    .muted { color: var(--muted); font-size: 14px; }
    .btn-row { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 12px; }
    .dir-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
    .dir-item { display: block; background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 14px; text-decoration: none; color: var(--text); }
    .dir-item:hover { border-color: var(--teal); }
    footer { max-width: 1040px; margin: 0 auto; padding: 20px; border-top: 1px solid var(--border); color: var(--muted); font-size: 12.5px; text-align: center; }
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <a class="brand" href="/">
        <span class="brand-badge">Rx</span>
        <span>Rx Savings Watch</span>
      </a>
      <div class="nav-links">
        <a href="/medications">Medication Directory</a>
        <a class="btn" href="/">Open Free App</a>
      </div>
    </div>
  </header>
  <main>
    ${bodyHtml}
  </main>
  <footer>
    <p><strong>Privacy-First:</strong> Zero accounts, zero ad trackers, zero personal data collected. All medication cabinets and refill reminders stay strictly on your device.</p>
    <p>Informational only — not medical advice and not insurance. Always verify prescriptions, dosages, and generic substitutions with your doctor or pharmacist. As an Amazon Associate, Dangling Dice Studios™ earns from qualifying purchases.</p>
    <p>© 2026 Dangling Dice Studios™ • Public FDA, NLM RxNorm &amp; CMS NADAC Data</p>
  </footer>
</body>
</html>`;
}

/**
 * Server-rendered SEO router for organic Google discovery (/robots.txt, /sitemap.xml,
 * /medications directory, and /medications/:slug pages).
 * @param {import('node:sqlite').DatabaseSync} db
 */
function createSeoRouter(db) {
  const router = express.Router();

  const listAllDrugsStmt = db.prepare(`
    SELECT d.*,
      (SELECT MAX(is_approved_generic) FROM generic_status gs WHERE gs.drug_id = d.id) AS has_approved_generic,
      (SELECT MAX(CASE WHEN ma.is_commercialized = 1 AND UPPER(COALESCE(ma.marketing_category, '')) IN ('ANDA', 'AUTHORIZED_GENERIC', 'BIOSIMILAR') THEN 1 ELSE 0 END)
         FROM market_availability ma WHERE ma.drug_id = d.id) AS has_commercial_generic,
      (SELECT AVG(ma.nadac_per_unit) FROM market_availability ma
         WHERE ma.drug_id = d.id AND ma.nadac_per_unit IS NOT NULL AND UPPER(COALESCE(ma.marketing_category, '')) IN ('NDA', 'BLA')) AS brand_nadac,
      (SELECT AVG(ma.nadac_per_unit) FROM market_availability ma
         WHERE ma.drug_id = d.id AND ma.nadac_per_unit IS NOT NULL AND UPPER(COALESCE(ma.marketing_category, '')) IN ('ANDA', 'AUTHORIZED_GENERIC', 'BIOSIMILAR')) AS generic_nadac,
      (SELECT COUNT(*) FROM drug_shortages ds WHERE ds.drug_id = d.id AND ds.status = 'Current') AS active_shortages
    FROM drugs d
    ORDER BY LOWER(COALESCE(NULLIF(TRIM(d.brand_name), ''), d.generic_name)) ASC
  `);

  router.get('/robots.txt', (req, res) => {
    res.type('text/plain; charset=utf-8');
    res.send([
      'User-agent: *',
      'Allow: /',
      'Allow: /medications',
      'Allow: /medications/',
      'Disallow: /api/',
      `Sitemap: ${SITE_ORIGIN}/sitemap.xml`,
      '',
    ].join('\n'));
  });

  router.get('/sitemap.xml', (req, res) => {
    const drugs = listAllDrugsStmt.all();
    const today = new Date().toISOString().split('T')[0];
    const seenSlugs = new Set();

    const urls = [
      `  <url><loc>${SITE_ORIGIN}/</loc><lastmod>${today}</lastmod><changefreq>weekly</changefreq><priority>1.0</priority></url>`,
      `  <url><loc>${SITE_ORIGIN}/medications</loc><lastmod>${today}</lastmod><changefreq>daily</changefreq><priority>0.9</priority></url>`,
      `  <url><loc>${SITE_ORIGIN}/partners</loc><lastmod>${today}</lastmod><changefreq>monthly</changefreq><priority>0.8</priority></url>`,
    ];

    for (const d of drugs) {
      const slug = drugSlug(d);
      if (seenSlugs.has(slug)) continue;
      seenSlugs.add(slug);
      const lastmod = (d.updated_at || today).toString().split('T')[0].split(' ')[0];
      urls.push(
        `  <url><loc>${SITE_ORIGIN}/medications/${encodeURIComponent(slug)}</loc><lastmod>${escapeHtml(lastmod)}</lastmod><changefreq>weekly</changefreq><priority>0.8</priority></url>`
      );
    }

    res.type('application/xml; charset=utf-8');
    res.send(
      `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join('\n')}\n</urlset>`
    );
  });

  router.get('/medications', (req, res) => {
    const drugs = listAllDrugsStmt.all();
    const seenSlugs = new Set();
    const cards = [];

    for (const d of drugs) {
      const slug = drugSlug(d);
      if (seenSlugs.has(slug)) continue;
      seenSlugs.add(slug);
      const displayName = (d.brand_name && d.brand_name.trim()) ? d.brand_name.trim() : d.generic_name;
      const hasGeneric = Boolean(d.has_approved_generic && d.has_commercial_generic);
      const pill = hasGeneric
        ? '<span class="pill pill-green">Generic Available</span>'
        : '<span class="pill pill-slate">Brand-Only Watch</span>';
      cards.push(`
        <a class="dir-item" href="/medications/${encodeURIComponent(slug)}">
          <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-bottom:6px;">
            <strong>${escapeHtml(displayName)}</strong>
            ${pill}
          </div>
          <div class="muted">${escapeHtml(d.generic_name || '')}</div>
        </a>
      `);
    }

    const html = renderLayout({
      title: 'Prescription Generic Availability & Cash Price Directory — Rx Savings Watch',
      description: `Check FDA-approved generic availability, supply shortages, and cash-pay pharmacy coupons for ${seenSlugs.size}+ top U.S. prescriptions—100% free with zero login.`,
      canonicalUrl: `${SITE_ORIGIN}/medications`,
      bodyHtml: `
        <div class="card">
          <h1>Prescription Savings &amp; Generic Directory</h1>
          <p class="muted">Browse ${seenSlugs.size} top U.S. medications for FDA-approved generic availability, supply shortage alerts, and free cash-pay pharmacy coupons. Zero login or tracking required.</p>
          <div class="btn-row">
            <a class="btn" href="/">Open Interactive Medication Cabinet</a>
          </div>
        </div>
        <div class="dir-grid">${cards.join('\n')}</div>
      `,
    });

    res.type('text/html; charset=utf-8').send(html);
  });

  router.get('/medications/:slug', async (req, res) => {
    const requested = String(req.params.slug || '').trim().toLowerCase();
    if (!requested || requested.length > 100) {
      return res.status(404).type('text/plain').send('Medication not found');
    }

    const drugs = listAllDrugsStmt.all();
    const drug = drugs.find(d => drugSlug(d) === requested);
    if (!drug) {
      return res.status(404).type('text/html; charset=utf-8').send(
        renderLayout({
          title: 'Medication Not Found — Rx Savings Watch',
          description: 'Search thousands of FDA-approved medications in Rx Savings Watch.',
          canonicalUrl: `${SITE_ORIGIN}/medications`,
          bodyHtml: `
            <div class="card">
              <h1>Medication Not Found</h1>
              <p class="muted">We couldn't find that medication slug in our directory, but you can search live FDA databases directly inside the app.</p>
              <div class="btn-row">
                <a class="btn" href="/">Search in Rx Savings Watch</a>
                <a class="btn-outline" href="/medications">Browse All Medications</a>
              </div>
            </div>
          `,
        })
      );
    }

    const displayName = (drug.brand_name && drug.brand_name.trim()) ? drug.brand_name.trim() : drug.generic_name;
    const isUnbranded = !drug.brand_name || drug.brand_name.trim().toLowerCase() === String(drug.generic_name || '').trim().toLowerCase();
    const hasGeneric = Boolean(drug.has_approved_generic && drug.has_commercial_generic);
    const hasShortage = Number(drug.active_shortages || 0) > 0;
    const partners = await getVerifiedPartnersForDrug(db, drug).catch(() => []);

    const statusBadge = hasGeneric
      ? '<span class="pill pill-green">FDA Generic Available</span>'
      : '<span class="pill pill-slate">Currently Brand-Name Only</span>';
    const shortageBadge = hasShortage
      ? ' <span class="pill pill-amber">Active FDA Supply Shortage</span>'
      : '';

    const genericGuidance = isUnbranded
      ? `${displayName} is already an FDA-approved generic medication.`
      : hasGeneric
        ? `An FDA-approved commercial generic (${drug.generic_name}) is available. Ask your pharmacist if automatic substitution applies to your prescription.`
        : `${displayName} (${drug.generic_name}) is currently available as brand-name only. Add it to your private Rx Savings Watch cabinet to get alerted when a generic launches.`;

    const pricingLines = [];
    if (drug.brand_nadac != null) {
      pricingLines.push(`<div><strong>Brand Acquisition Benchmark (CMS NADAC):</strong> $${Number(drug.brand_nadac).toFixed(2)} / unit</div>`);
    }
    if (drug.generic_nadac != null) {
      pricingLines.push(`<div><strong>Generic Acquisition Benchmark (CMS NADAC):</strong> $${Number(drug.generic_nadac).toFixed(2)} / unit</div>`);
    }
    if (drug.brand_nadac != null && drug.generic_nadac != null && Number(drug.brand_nadac) > Number(drug.generic_nadac)) {
      const gapPct = ((Number(drug.brand_nadac) - Number(drug.generic_nadac)) / Number(drug.brand_nadac)) * 100;
      if (gapPct > 0) {
        pricingLines.push(`<div><strong>Estimated Brand vs. Generic Gap:</strong> ~${Math.round(gapPct)}%</div>`);
      }
    }

    const partnerButtons = partners.map(p => {
      const label = p.price_hint ? `${p.label} (${p.price_hint})` : p.label;
      return `<a class="btn-outline" href="${escapeHtml(p.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`;
    }).join('\n');

    const title = `${displayName} (${drug.generic_name}) — Generic Availability, Cash Prices & Refill Tracker | Rx Savings Watch`;
    const description = `Check whether a generic for ${displayName} (${drug.generic_name}) is available, compare cash-pay pharmacy coupons, and track refills privately with zero login.`;
    const canonicalUrl = `${SITE_ORIGIN}/medications/${encodeURIComponent(drugSlug(drug))}`;

    const jsonLd = {
      '@context': 'https://schema.org',
      '@type': 'Drug',
      name: displayName,
      nonProprietaryName: drug.generic_name,
      url: canonicalUrl,
      code: {
        '@type': 'MedicalCode',
        codeValue: drug.rxcui,
        codingSystem: 'RxNorm',
      },
    };

    const html = renderLayout({
      title,
      description,
      canonicalUrl,
      jsonLd,
      bodyHtml: `
        <div class="card">
          <div>${statusBadge}${shortageBadge}</div>
          <h1>${escapeHtml(displayName)}</h1>
          <div class="muted">${escapeHtml(drug.generic_name || '')}${drug.strength ? ` • ${escapeHtml(drug.strength)}` : ''}</div>
          <div class="btn-row" style="margin-top:16px;">
            <a class="btn" href="/">Track Refills &amp; Alerts in Free App</a>
            <a class="btn-outline" href="/medications">All Medications</a>
          </div>
        </div>

        <div class="grid">
          <div class="card">
            <h2>Generic Option &amp; Pharmacy Guidance</h2>
            <p>${escapeHtml(genericGuidance)}</p>
            ${pricingLines.length > 0 ? `<div style="margin-top:12px;display:flex;flex-direction:column;gap:6px;">${pricingLines.join('')}</div>` : ''}
          </div>

          <div class="card">
            <h2>Compare Cash &amp; Pharmacy Prices</h2>
            <p class="muted">Free cash-pay prices and retail pharmacy coupons for ${escapeHtml(displayName)} (no account required):</p>
            <div class="btn-row">
              ${partnerButtons || '<a class="btn" href="/">Open App to Check Prices</a>'}
            </div>
            <p class="muted" style="font-size:12px;margin-top:14px;">Cash-pay discounts only — not insurance. Clicking an external link opens that pharmacy's site under its own privacy policy.</p>
          </div>
        </div>
      `,
    });

    res.type('text/html; charset=utf-8').send(html);
  });

  return router;
}

module.exports = {
  createSeoRouter,
  drugSlug,
};
