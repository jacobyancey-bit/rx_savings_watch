/**
 * Live Multi-Source Government Cross-Reference Ingestion Engine
 *
 * 100% Free, Zero-Subscription Official U.S. Government APIs:
 *   1. NLM RxNav / RxNorm REST API (canonical RXCUI, strengths, dosage forms)
 *   2. OpenFDA Drugs@FDA API (FDA Orange Book ANDA / BLA approvals & TE codes)
 *   3. OpenFDA NDC Directory API (finished commercial NDCs, start/end dates)
 *   4. CMS Medicaid NADAC Open Data API (live pharmacy acquisition prices, B vs G)
 *   5. OpenFDA Drug Shortages API (live active FDA shortages)
 *   6. NLM DailyMed SPL API (active published FDA product labeling verification)
 */

const { recordIngestionRun } = require('./index');

const FETCH_TIMEOUT_MS = 12000;
let cachedNadacDatasetId = null;

async function fetchJsonSafe(url) {
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'RxSavingsWatch/1.0 (https://dangling-dice-studios.com)' },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (!res.ok) return null;
    return await res.json();
  } catch (_) {
    return null;
  }
}

function formatFdaDate(raw) {
  if (!raw) return null;
  const s = String(raw).replace(/[^0-9]/g, '');
  if (s.length === 8) {
    return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
  }
  if (/^\d{4}-\d{2}-\d{2}/.test(String(raw))) {
    return String(raw).slice(0, 10);
  }
  return null;
}

/**
 * 1. NLM RxNav: Resolve a drug name to a canonical RxNorm concept (preferring SBD/SCD).
 */
async function fetchRxNormConcept(brandName, genericName) {
  const query = encodeURIComponent(brandName || genericName);
  const data = await fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/drugs.json?name=${query}`);
  const groups = data?.drugGroup?.conceptGroup || [];

  // Prefer Semantic Branded Drug (SBD), fallback to Semantic Clinical Drug (SCD)
  const preferredOrder = ['SBD', 'SCD', 'BPCK', 'GPCK'];
  for (const tty of preferredOrder) {
    const group = groups.find(g => g.tty === tty && Array.isArray(g.conceptProperties) && g.conceptProperties.length > 0);
    if (group) {
      const prop = group.conceptProperties[0];
      const fullName = prop.name || '';
      const strengthMatch = fullName.match(/\b(\d+(?:\.\d+)?\s*(?:MG|MCG|ML|G|%|UNT)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:ML|MG|ACTUAT))?)\b/i);
      const formMatch = fullName.match(/\b(Oral Tablet|Oral Capsule|Injectable Solution|Auto-Injector|Subcutaneous Solution|Ophthalmic Solution|Inhalation Powder|Metered Dose Inhaler|Delayed Release Oral Capsule|Extended Release Oral Tablet)\b/i);
      return {
        rxcui: String(prop.rxcui),
        strength: strengthMatch ? strengthMatch[1].toLowerCase() : null,
        dosage_form: formMatch ? formMatch[1].toLowerCase() : null,
      };
    }
  }
  return null;
}

/**
 * 2. OpenFDA Drugs@FDA: Pull FDA approvals (ANDA / BLA / NDA) & Therapeutic Equivalence (TE) codes.
 */
async function fetchDrugsAtFda(genericName, brandName) {
  const term = encodeURIComponent(`"${genericName}"`);
  let data = await fetchJsonSafe(`https://api.fda.gov/drug/drugsfda.json?search=openfda.generic_name:${term}&limit=25`);
  if (!data?.results?.length && brandName) {
    const bTerm = encodeURIComponent(`"${brandName}"`);
    data = await fetchJsonSafe(`https://api.fda.gov/drug/drugsfda.json?search=openfda.brand_name:${bTerm}&limit=25`);
  }
  return data?.results || [];
}

/**
 * 3. OpenFDA NDC Directory: Pull FINISHED commercial drug listings (excluding bulk ingredients).
 */
async function fetchOpenFdaNdcs(genericName) {
  const term = encodeURIComponent(`"${genericName}"`);
  const data = await fetchJsonSafe(
    `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+generic_name:${term}&limit=25`
  );
  return data?.results || [];
}

/**
 * 4. CMS Medicaid NADAC: Auto-discover latest yearly NADAC dataset UUID and query prices.
 */
async function getLatestNadacDatasetId() {
  if (cachedNadacDatasetId) return cachedNadacDatasetId;
  const items = await fetchJsonSafe('https://data.medicaid.gov/api/1/metastore/schemas/dataset/items');
  if (!Array.isArray(items)) return null;
  const nadacs = items
    .filter(i => i.title && i.title.includes('NADAC (National Average Drug Acquisition Cost)'))
    .sort((a, b) => b.title.localeCompare(a.title));
  if (nadacs[0]?.identifier) {
    cachedNadacDatasetId = nadacs[0].identifier;
    return cachedNadacDatasetId;
  }
  return null;
}

async function fetchCmsNadacPrices(searchKeyword) {
  const datasetId = await getLatestNadacDatasetId();
  if (!datasetId) return [];
  const token = encodeURIComponent(`%${searchKeyword.toUpperCase().split(' ')[0]}%`);
  const url = `https://data.medicaid.gov/api/1/datastore/query/${datasetId}/0?limit=20&conditions[0][property]=ndc_description&conditions[0][value]=${token}&conditions[0][operator]=LIKE`;
  const data = await fetchJsonSafe(url);
  return data?.results || [];
}

/**
 * 5. NLM DailyMed: Cross-verify active FDA Structured Product Labels (SPLs).
 */
async function fetchDailyMedSpls(genericName) {
  const q = encodeURIComponent(genericName.split(' ')[0]);
  const data = await fetchJsonSafe(`https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?drug_name=${q}&pagesize=5`);
  return data?.data || [];
}

/**
 * 6. OpenFDA Drug Shortages: Pull current live FDA shortages.
 */
async function fetchLiveFdaShortages() {
  const data = await fetchJsonSafe('https://api.fda.gov/drug/shortages.json?search=status:"Current"&limit=100');
  return data?.results || [];
}

/**
 * Cross-reference and ingest a single drug across all live government APIs.
 */
async function ingestLiveDrug(db, seed) {
  const { brand_name: brandName, generic_name: genericName, drug_type: drugType = 'small_molecule' } = seed;

  // Step 1: Resolve canonical RxNorm RXCUI (or reuse existing row by brand/generic name)
  const existing = db.prepare(
    'SELECT * FROM drugs WHERE LOWER(brand_name) = LOWER(?) OR LOWER(generic_name) = LOWER(?)'
  ).get(brandName || '', genericName);

  const rxConcept = await fetchRxNormConcept(brandName, genericName);
  const rxcui = existing?.rxcui || rxConcept?.rxcui;
  if (!rxcui) {
    return { skipped: true, reason: 'No RxNorm RXCUI resolved' };
  }

  // Upsert canonical drug record
  db.prepare(`
    INSERT INTO drugs (
      rxcui, brand_name, generic_name, active_ingredient, dosage_form, strength, drug_type, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(rxcui) DO UPDATE SET
      brand_name = COALESCE(excluded.brand_name, drugs.brand_name),
      generic_name = excluded.generic_name,
      dosage_form = COALESCE(drugs.dosage_form, excluded.dosage_form),
      strength = COALESCE(excluded.strength, drugs.strength),
      drug_type = excluded.drug_type,
      updated_at = datetime('now')
  `).run(
    rxcui,
    brandName || null,
    genericName,
    genericName,
    seed.dosage_form || rxConcept?.dosage_form || null,
    seed.strength || rxConcept?.strength || null,
    drugType
  );

  const drugRow = db.prepare('SELECT id FROM drugs WHERE rxcui = ?').get(rxcui);
  const drugId = drugRow.id;

  // Fetch all 4 drug-specific cross-reference feeds in parallel!
  const [fdaApps, ndcRows, nadacGenericRows, nadacBrandRows, dailyMedRows] = await Promise.all([
    fetchDrugsAtFda(genericName, brandName),
    fetchOpenFdaNdcs(genericName),
    fetchCmsNadacPrices(genericName),
    brandName ? fetchCmsNadacPrices(brandName) : Promise.resolve([]),
    fetchDailyMedSpls(genericName),
  ]);

  let regulatoryCount = 0;
  let ndcCount = 0;
  let nadacCount = 0;
  let dailyMedCount = 0;
  let anomaliesRejected = 0;

  // Step 2: Persist FDA Drugs@FDA (Orange Book / Purple Book approvals & TE codes)
  const upsertGeneric = db.prepare(`
    INSERT INTO generic_status (
      drug_id, source, application_number, applicant, approval_date,
      is_approved_generic, te_code, biosimilar_status, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(drug_id, application_number, source) DO UPDATE SET
      applicant = excluded.applicant,
      approval_date = COALESCE(excluded.approval_date, generic_status.approval_date),
      is_approved_generic = excluded.is_approved_generic,
      te_code = COALESCE(excluded.te_code, generic_status.te_code),
      biosimilar_status = COALESCE(excluded.biosimilar_status, generic_status.biosimilar_status),
      updated_at = datetime('now')
  `);

  for (const app of fdaApps) {
    const appNo = app.application_number;
    if (!appNo) continue;
    const isAnda = appNo.startsWith('ANDA');
    const isBla = appNo.startsWith('BLA');
    const source = drugType === 'biologic' || isBla ? 'purple_book' : 'orange_book';

    const origSub = (app.submissions || []).find(s => s.submission_type === 'ORIG' && s.submission_status === 'AP');
    const approvalDate = formatFdaDate(origSub?.submission_status_date);

    // Extract TE code from products list
    const products = app.products || [];
    const teCode = products.find(p => p.te_code)?.te_code || null;
    const isRefBrand = brandName && products.some(p => (p.brand_name || '').toLowerCase() === brandName.toLowerCase());

    const isApprovedGeneric = isAnda || (isBla && drugType === 'biologic' && !isRefBrand);
    const biosimilarStatus = isBla && isApprovedGeneric ? 'biosimilar' : null;

    upsertGeneric.run(
      drugId,
      source,
      appNo,
      app.sponsor_name || null,
      approvalDate,
      isApprovedGeneric ? 1 : 0,
      teCode,
      biosimilarStatus
    );
    regulatoryCount++;
  }

  // Step 3: Persist OpenFDA NDC Directory (finished commercial products with expiration dates)
  const upsertNdc = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, labeler_name, marketing_category,
      marketing_start_date, marketing_end_date, is_commercialized, package_description, updated_at
    ) VALUES (?, 'openfda_ndc', ?, ?, ?, ?, ?, 1, ?, datetime('now'))
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      labeler_name = excluded.labeler_name,
      marketing_category = excluded.marketing_category,
      marketing_start_date = COALESCE(excluded.marketing_start_date, market_availability.marketing_start_date),
      marketing_end_date = excluded.marketing_end_date,
      is_commercialized = 1,
      package_description = excluded.package_description,
      updated_at = datetime('now')
  `);

  for (const item of ndcRows) {
    const ndc = item.product_ndc;
    if (!ndc) continue;
    const cat = item.marketing_category || '';
    const normCat = cat.includes('ANDA')
      ? 'ANDA'
      : cat.includes('BLA')
        ? 'BLA'
        : cat.includes('NDA')
          ? 'NDA'
          : cat;

    upsertNdc.run(
      drugId,
      ndc,
      item.labeler_name || null,
      normCat,
      formatFdaDate(item.marketing_start_date),
      formatFdaDate(item.marketing_expiration_date),
      item.packaging?.[0]?.description || item.brand_name || null
    );
    ndcCount++;
  }

  // Step 4: Persist CMS NADAC 2026 live acquisition prices (strictly validating > 0 and tagging B vs G)
  const upsertNadac = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, marketing_category, package_description,
      nadac_per_unit, nadac_effective_date, pricing_unit, is_commercialized, updated_at
    ) VALUES (?, 'cms_nadac', ?, ?, ?, ?, ?, ?, 1, datetime('now'))
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      marketing_category = excluded.marketing_category,
      package_description = excluded.package_description,
      nadac_per_unit = excluded.nadac_per_unit,
      nadac_effective_date = excluded.nadac_effective_date,
      pricing_unit = excluded.pricing_unit,
      is_commercialized = 1,
      updated_at = datetime('now')
  `);

  const allNadac = [...nadacGenericRows, ...nadacBrandRows];
  const seenNdc = new Set();
  for (const row of allNadac) {
    if (!row.ndc || seenNdc.has(row.ndc)) continue;
    seenNdc.add(row.ndc);

    const price = Number.parseFloat(row.nadac_per_unit);
    if (!Number.isFinite(price) || price <= 0) {
      anomaliesRejected++;
      continue;
    }

    const isBrand = row.classification_for_rate_setting === 'B';
    const desc = `${row.ndc_description || ''}${isBrand ? ' (Brand)' : ''}`.trim();

    upsertNadac.run(
      drugId,
      row.ndc,
      isBrand ? 'NDA' : 'ANDA',
      desc,
      price,
      formatFdaDate(row.effective_date),
      row.pricing_unit || 'EA'
    );
    nadacCount++;
  }

  // Step 5: Persist NLM DailyMed SPL verification
  const upsertDailyMed = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, package_description, is_commercialized, updated_at
    ) VALUES (?, 'dailymed', ?, ?, 1, datetime('now'))
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      package_description = excluded.package_description,
      updated_at = datetime('now')
  `);

  for (const spl of dailyMedRows.slice(0, 3)) {
    if (!spl.setid) continue;
    upsertDailyMed.run(drugId, `SPL-${spl.setid.slice(0, 12)}`, spl.title || null);
    dailyMedCount++;
  }

  return {
    rxcui,
    brand_name: brandName,
    generic_name: genericName,
    regulatoryCount,
    ndcCount,
    nadacCount,
    dailyMedCount,
    anomaliesRejected,
  };
}

/**
 * Sync live FDA Drug Shortages and match them to drugs currently in our catalog.
 */
async function ingestLiveShortages(db) {
  const shortages = await fetchLiveFdaShortages();
  if (shortages.length === 0) return { matched: 0, fetched: 0 };

  const allDrugs = db.prepare('SELECT id, generic_name, brand_name FROM drugs').all();
  const findExisting = db.prepare(
    'SELECT id FROM drug_shortages WHERE drug_id = ? AND status = ? AND generic_name = ?'
  );
  const insertShortage = db.prepare(`
    INSERT INTO drug_shortages (
      drug_id, generic_name, dosage_form, status, reason, shortage_start_date, updated_at
    ) VALUES (?, ?, ?, 'Current', ?, ?, datetime('now'))
  `);

  let matched = 0;
  for (const s of shortages) {
    const genLower = (s.generic_name || '').toLowerCase();
    if (!genLower) continue;
    const drug = allDrugs.find(d => {
      const firstWord = (d.generic_name || '').toLowerCase().split(' ')[0];
      return firstWord.length >= 5 && genLower.includes(firstWord);
    });
    if (!drug) continue;

    const existing = findExisting.get(drug.id, 'Current', s.generic_name);
    if (!existing) {
      insertShortage.run(
        drug.id,
        s.generic_name,
        s.dosage_form || null,
        s.shortage_reason || 'Reported by FDA Drug Shortages',
        formatFdaDate(s.initial_posting_date)
      );
    }
    matched++;
  }

  recordIngestionRun(db, {
    feedName: 'live_fda_shortages',
    status: 'success',
    recordsProcessed: matched,
    notes: `Scanned ${shortages.length} active FDA shortages`,
  });

  return { matched, fetched: shortages.length };
}

/**
 * Run full live cross-referenced ingestion across a seed list of drugs.
 */
async function runLiveIngestion(db, seedList, options = {}) {
  const delayMs = options.delayMs ?? 150;
  const summary = {
    drugsProcessed: 0,
    drugsSkipped: 0,
    regulatoryRecords: 0,
    ndcRecords: 0,
    nadacRecords: 0,
    dailyMedRecords: 0,
    anomaliesRejected: 0,
    shortagesMatched: 0,
  };

  for (const seed of seedList) {
    const res = await ingestLiveDrug(db, seed);
    if (res.skipped) {
      summary.drugsSkipped++;
    } else {
      summary.drugsProcessed++;
      summary.regulatoryRecords += res.regulatoryCount;
      summary.ndcRecords += res.ndcCount;
      summary.nadacRecords += res.nadacCount;
      summary.dailyMedRecords += res.dailyMedCount;
      summary.anomaliesRejected += res.anomaliesRejected;
    }
    if (delayMs > 0) {
      await new Promise(r => setTimeout(r, delayMs));
    }
  }

  const shortageRes = await ingestLiveShortages(db);
  summary.shortagesMatched = shortageRes.matched;

  recordIngestionRun(db, {
    feedName: 'live_multi_source_sync',
    status: 'success',
    recordsProcessed: summary.drugsProcessed,
    anomaliesRejected: summary.anomaliesRejected,
    notes: `Cross-referenced RxNorm, OpenFDA Drugs@FDA, OpenFDA NDC, CMS NADAC, DailyMed, FDA Shortages`,
  });

  return summary;
}

function toTitleCase(str) {
  if (!str) return null;
  return str
    .toLowerCase()
    .split(' ')
    .map(w => (w.length > 0 ? w[0].toUpperCase() + w.slice(1) : ''))
    .join(' ');
}

function parseNumericStrength(str) {
  const m = String(str).match(/(\d+(?:\.\d+)?)/);
  return m ? Number.parseFloat(m[1]) : Number.MAX_SAFE_INTEGER;
}

function formatStrengthNumber(num) {
  return Number(num.toFixed(3)).toString();
}

/**
 * Extract clean, clinician-accurate total strengths from OpenFDA NDC results & RxNav concepts.
 * Handles mixed-salt medications (e.g. Mydayis / Adderall: 4 equal amphetamine salts summed to
 * 12.5 mg, 25 mg, 37.5 mg, 50 mg) and sorts numerically ascending.
 */
function extractCleanStrengths(ndcResults, rxConcepts = []) {
  const strengthSet = new Set();

  for (const r of ndcResults) {
    if (!Array.isArray(r.active_ingredients) || r.active_ingredients.length === 0) continue;

    // Detect mixed-salt amphetamine / multi-salt formulations where each salt is a fraction of total mg
    const isMixedAmphetamine =
      r.active_ingredients.length >= 2 &&
      r.active_ingredients.every(ai => (ai.name || '').toLowerCase().includes('amphetamine'));

    if (isMixedAmphetamine) {
      let totalMg = 0;
      let valid = true;
      for (const ai of r.active_ingredients) {
        const m = String(ai.strength || '').match(/(\d+(?:\.\d+)?)\s*mg/i);
        if (!m) {
          valid = false;
          break;
        }
        totalMg += Number.parseFloat(m[1]);
      }
      if (valid && totalMg > 0) {
        strengthSet.add(`${formatStrengthNumber(totalMg)} mg`);
        continue;
      }
    }

    const combined = r.active_ingredients
      .map(ai => (ai.strength || '').toLowerCase().replace(/\/1\b/g, '').trim())
      .filter(Boolean)
      .join(' / ');
    if (combined) {
      strengthSet.add(combined);
    }
  }

  // Cross-check NLM RxNav SBD/SCD concepts to catch any strengths missing from NDC sample
  for (const prop of rxConcepts) {
    const name = prop.name || '';
    if (name.toLowerCase().includes('amphetamine') && name.includes('/')) {
      const matches = [...name.matchAll(/(\d+(?:\.\d+)?)\s*MG/gi)];
      if (matches.length >= 2) {
        const sum = matches.reduce((acc, m) => acc + Number.parseFloat(m[1]), 0);
        if (sum > 0) strengthSet.add(`${formatStrengthNumber(sum)} mg`);
        continue;
      }
    }
    const m = name.match(/\b(\d+(?:\.\d+)?\s*(?:MG|MCG|ML|G|%)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:ML|MG|ACTUAT))?)\b/i);
    if (m) {
      strengthSet.add(m[1].toLowerCase().replace(/\s+/g, ' ').trim());
    }
  }

  return [...strengthSet].sort((a, b) => parseNumericStrength(a) - parseNumericStrength(b));
}

/**
 * Live On-Demand Discovery & Canonical Cross-Reference:
 * Resolves a user search term strictly to an official FDA/RxNorm canonical drug
 * (user text is NEVER stored as the medication name), deduplicates by canonical name/RXCUI,
 * collects ALL official dosages into one record, runs 6-source ingestion + 2-signal detection,
 * and saves it to SQLite for instant future lookups.
 */
async function discoverAndIngestDrug(db, rawQuery) {
  const clean = String(rawQuery || '').replace(/[^a-zA-Z0-9\s\-]/g, '').trim();
  if (clean.length < 3 || clean.length > 80) return null;

  const term = encodeURIComponent(`"${clean}"`);
  // 1. Resolve canonical brand/generic/strengths via OpenFDA NDC (up to 100 finished products) + RxNav
  let [ndcData, rxData] = await Promise.all([
    fetchJsonSafe(
      `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(brand_name:${term}+OR+generic_name:${term})&limit=100`
    ),
    fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/drugs.json?name=${encodeURIComponent(clean)}`),
  ]);

  // Fallback: unquoted token search if exact phrase missed
  if (!ndcData?.results?.length) {
    const loose = encodeURIComponent(clean.split(' ')[0]);
    ndcData = await fetchJsonSafe(
      `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(brand_name:${loose}+OR+generic_name:${loose})&limit=100`
    );
  }

  const results = ndcData?.results || [];
  if (results.length === 0) return null;

  const rxConcepts = (rxData?.drugGroup?.conceptGroup || [])
    .filter(g => g.tty === 'SBD' || g.tty === 'SCD')
    .flatMap(g => g.conceptProperties || []);

  // Pick the best canonical match (prefer NDA/BLA reference brand if present)
  const primary =
    results.find(r => r.marketing_category === 'NDA' || r.marketing_category === 'BLA') ||
    results[0];

  const canonicalGeneric = (primary.generic_name || '').trim().toLowerCase();
  if (!canonicalGeneric) return null;

  const canonicalBrand = primary.brand_name ? toTitleCase(primary.brand_name.trim()) : null;
  const drugType = (primary.marketing_category || '').includes('BLA') ? 'biologic' : 'small_molecule';
  const dosageForm = primary.dosage_form ? primary.dosage_form.toLowerCase() : null;

  // Deduplicate ALL official strengths cleanly (sorted ascending, summing mixed salts accurately)
  const allStrengths = extractCleanStrengths(results, rxConcepts);
  const combinedStrengths = allStrengths.slice(0, 12).join(', ') || null;

  // Check if this canonical drug already exists (update strengths if we found a more complete list!)
  const existing = db.prepare(
    'SELECT * FROM drugs WHERE LOWER(generic_name) = LOWER(?) OR (brand_name IS NOT NULL AND LOWER(brand_name) = LOWER(?))'
  ).get(canonicalGeneric, canonicalBrand || '');

  if (existing) {
    if (combinedStrengths && combinedStrengths.length > (existing.strength || '').length) {
      db.prepare("UPDATE drugs SET strength = ?, updated_at = datetime('now') WHERE id = ?")
        .run(combinedStrengths, existing.id);
      return db.prepare('SELECT * FROM drugs WHERE id = ?').get(existing.id);
    }
    return existing;
  }

  // Run full 6-source cross-referenced live ingestion
  const ingestRes = await ingestLiveDrug(db, {
    brand_name: canonicalBrand,
    generic_name: canonicalGeneric,
    drug_type: drugType,
    dosage_form: dosageForm,
    strength: combinedStrengths,
  });

  if (ingestRes.skipped || !ingestRes.rxcui) return null;

  const savedDrug = db.prepare('SELECT * FROM drugs WHERE rxcui = ?').get(ingestRes.rxcui);
  if (!savedDrug) return null;

  // Immediately evaluate 2-signal commercial generic launch for the newly discovered drug
  const { GenericLaunchDetector } = require('../detector');
  const detector = new GenericLaunchDetector(db);
  detector.evaluateDrug(savedDrug, { persistAlert: true });

  return savedDrug;
}

module.exports = {
  runLiveIngestion,
  ingestLiveDrug,
  ingestLiveShortages,
  discoverAndIngestDrug,
};
