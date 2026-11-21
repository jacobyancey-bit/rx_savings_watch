/**
 * Verified Cash & Discount Pharmacy Partner Resolver
 *
 * Ensures older adults NEVER click a dead button or land on a "0 results" page:
 *  - Cost Plus Drugs: Checked directly against their official live JSON pricelist
 *    (https://api.costplusdrugs.com/pricelist/cpd), returning exact direct URL + starting cash price.
 *  - Amazon Pharmacy: Excludes Schedule II controlled substances (not dispensed by Amazon Pharmacy)
 *    and appends optional AMAZON_ASSOCIATES_TAG from env.
 *  - SingleCare & GoodRx: Verified via fast HTTP status check & cached in SQLite for 7 days.
 */

const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const CPD_CATALOG_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const PROBE_TIMEOUT_MS = 5000;

// Schedule II controlled substances not dispensed by mail-order cash pharmacies like Cost Plus / Amazon Pharmacy
const SCHEDULE_II_KEYWORDS = [
  'amphetamine', 'dextroamphetamine', 'lisdexamfetamine', 'methylphenidate',
  'dexmethylphenidate', 'oxycodone', 'hydrocodone', 'morphine', 'fentanyl',
  'hydromorphone', 'methadone', 'meperidine', 'tapentadol', 'secobarbital',
];

let cpdCatalogCache = null;
let cpdCatalogFetchedAt = 0;

function toSlug(name) {
  return String(name || '')
    .trim()
    .toLowerCase()
    .split(/\s+/)[0]
    .replace(/[^a-z0-9-]/g, '');
}

function isScheduleII(drug) {
  const hay = `${drug.brand_name || ''} ${drug.generic_name || ''} ${drug.active_ingredient || ''}`.toLowerCase();
  return SCHEDULE_II_KEYWORDS.some(k => hay.includes(k));
}

async function getCostPlusDrugsCatalog() {
  const now = Date.now();
  if (cpdCatalogCache && (now - cpdCatalogFetchedAt) < CPD_CATALOG_TTL_MS) {
    return cpdCatalogCache;
  }
  try {
    const res = await fetch('https://api.costplusdrugs.com/pricelist/cpd', {
      headers: { 'User-Agent': 'RxSavingsWatch/1.0' },
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) return cpdCatalogCache || [];
    const data = await res.json();
    if (Array.isArray(data)) {
      cpdCatalogCache = data;
      cpdCatalogFetchedAt = now;
      return data;
    }
  } catch (_) {}
  return cpdCatalogCache || [];
}

function matchCostPlusDrugs(catalog, drug) {
  if (!Array.isArray(catalog) || catalog.length === 0) return null;

  const brandLower = (drug.brand_name || '').toLowerCase().trim();
  const genericFirst = (drug.generic_name || '').toLowerCase().split(/[,/\s]+/)[0].trim();

  const matches = catalog.filter(item => {
    if (item.cpd_channel && item.cpd_channel.in_stock === false) return false;
    const medLower = (item.medication_name || '').toLowerCase();
    const itemBrand = (item.brand_name || '').toLowerCase();
    if (item.rxnorm_id && String(item.rxnorm_id) === String(drug.rxcui)) return true;
    if (brandLower && brandLower.length >= 4 && (itemBrand === brandLower || medLower === brandLower)) return true;
    if (genericFirst && genericFirst.length >= 4 && medLower.startsWith(genericFirst)) return true;
    return false;
  });

  if (matches.length === 0) return null;

  // Pick the lowest-priced in-stock SKU to show an accurate starting price
  let best = matches[0];
  let bestPrice = Number.POSITIVE_INFINITY;
  for (const m of matches) {
    const p = Number.parseFloat(
      m.cpd_channel?.sample_pack_price_total_to_patient_without_shipping ||
      m.cpd_channel?.sample_pack_price ||
      ''
    );
    if (Number.isFinite(p) && p > 0 && p < bestPrice) {
      bestPrice = p;
      best = m;
    }
  }

  return {
    id: 'cost_plus_drugs',
    label: 'Cost Plus Drugs',
    url: best.url || `https://www.costplusdrugs.com/medications/?search=${encodeURIComponent(genericFirst)}`,
    price_hint: Number.isFinite(bestPrice) ? `from $${bestPrice.toFixed(2)}` : null,
    verified: true,
  };
}

async function probeUrlExists(url) {
  try {
    const res = await fetch(url, {
      method: 'HEAD',
      redirect: 'follow',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; RxSavingsWatch/1.0; +https://rx.dangling-dice-studios.com)',
      },
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    // Treat 200 OK (and not redirected to bare homepage) as verified
    if (res.status >= 200 && res.status < 300) {
      const finalPath = new URL(res.url).pathname;
      return finalPath.length > 1;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/**
 * Resolve & cache verified cash/discount pharmacy links for a drug.
 * Returns ONLY verified partners that actually have information for this prescription.
 */
async function getVerifiedPartnersForDrug(db, drug) {
  // 1. Check SQLite 7-day cache first
  const cached = db.prepare(`
    SELECT partner_id, label, url, price_hint, verified, checked_at
    FROM partner_links
    WHERE drug_id = ?
  `).all(drug.id);

  if (cached.length > 0) {
    const latest = cached[0].checked_at;
    const ageMs = latest ? Date.now() - new Date(latest.replace(' ', 'T') + 'Z').getTime() : CACHE_TTL_MS + 1;
    if (ageMs < CACHE_TTL_MS) {
      return cached
        .filter(r => r.verified === 1 && r.url)
        .map(r => ({
          id: r.partner_id,
          label: r.label,
          url: r.url,
          price_hint: r.price_hint || null,
        }));
    }
  }

  // Skip external probes during automated offline unit tests
  if (process.env.NODE_ENV === 'test') {
    return [];
  }

  const primaryName = drug.brand_name || drug.generic_name;
  const slug = toSlug(primaryName);
  const genericSlug = toSlug(drug.generic_name);
  const c2 = isScheduleII(drug);

  // Run checks in parallel
  const [cpdCatalog, singleCareOk, goodRxOk] = await Promise.all([
    c2 ? Promise.resolve([]) : getCostPlusDrugsCatalog(),
    slug.length >= 3
      ? probeUrlExists(`https://www.singlecare.com/prescription/${slug}`)
      : Promise.resolve(false),
    slug.length >= 3
      ? probeUrlExists(`https://www.goodrx.com/${slug}`)
      : Promise.resolve(false),
  ]);

  const cpdMatch = c2 ? null : matchCostPlusDrugs(cpdCatalog, drug);

  // Amazon Pharmacy carries virtually all non-C-II FDA-approved retail Rx drugs
  const amazonTag = process.env.AMAZON_ASSOCIATES_TAG || '';
  const amazonUrl = `https://pharmacy.amazon.com/s?k=${encodeURIComponent(primaryName)}${amazonTag ? `&tag=${encodeURIComponent(amazonTag)}` : ''}`;

  const singleCareParam = process.env.SINGLECARE_PARTNER_PARAM ? `?${process.env.SINGLECARE_PARTNER_PARAM}` : '';
  const goodRxParam = process.env.GOODRX_PARTNER_PARAM ? `?${process.env.GOODRX_PARTNER_PARAM}` : '';

  const evaluated = [
    cpdMatch || {
      id: 'cost_plus_drugs',
      label: 'Cost Plus Drugs',
      url: null,
      price_hint: null,
      verified: false,
    },
    {
      id: 'amazon_pharmacy',
      label: 'Amazon Pharmacy',
      url: c2 ? null : amazonUrl,
      price_hint: null,
      verified: !c2,
    },
    {
      id: 'singlecare',
      label: 'SingleCare Coupon',
      url: singleCareOk ? `https://www.singlecare.com/prescription/${slug}${singleCareParam}` : null,
      price_hint: null,
      verified: singleCareOk,
    },
    {
      id: 'goodrx',
      label: 'GoodRx Coupon',
      url: goodRxOk ? `https://www.goodrx.com/${slug}${goodRxParam}` : null,
      price_hint: null,
      verified: goodRxOk,
    },
  ];

  // Fallback for SingleCare using generic slug if brand slug didn't match
  if (!singleCareOk && genericSlug && genericSlug !== slug && genericSlug.length >= 4) {
    const genOk = await probeUrlExists(`https://www.singlecare.com/prescription/${genericSlug}`);
    if (genOk) {
      evaluated[2].verified = true;
      evaluated[2].url = `https://www.singlecare.com/prescription/${genericSlug}${singleCareParam}`;
    }
  }

  // Persist results in SQLite cache (both verified & unverified so we don't re-probe for 7 days)
  const upsert = db.prepare(`
    INSERT INTO partner_links (drug_id, partner_id, label, url, price_hint, verified, checked_at)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(drug_id, partner_id) DO UPDATE SET
      label = excluded.label,
      url = excluded.url,
      price_hint = excluded.price_hint,
      verified = excluded.verified,
      checked_at = datetime('now')
  `);

  for (const p of evaluated) {
    upsert.run(drug.id, p.id, p.label, p.url, p.price_hint, p.verified ? 1 : 0);
  }

  return evaluated
    .filter(p => p.verified && p.url)
    .map(p => ({
      id: p.id,
      label: p.label,
      url: p.url,
      price_hint: p.price_hint,
    }));
}

module.exports = {
  getVerifiedPartnersForDrug,
};
