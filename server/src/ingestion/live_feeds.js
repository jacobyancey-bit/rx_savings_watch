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
    let targetUrl = url;
    const fdaKey = (process.env.OPENFDA_API_KEY || '').trim();
    if (fdaKey && targetUrl.startsWith('https://api.fda.gov/')) {
      const sep = targetUrl.includes('?') ? '&' : '?';
      targetUrl = `${targetUrl}${sep}api_key=${encodeURIComponent(fdaKey)}`;
    }
    const res = await fetch(targetUrl, {
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
  const str = String(raw).trim();
  // Handle MM/DD/YYYY (used by OpenFDA Drug Shortages initial_posting_date)
  const usMatch = str.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (usMatch) {
    return `${usMatch[3]}-${usMatch[1]}-${usMatch[2]}`;
  }
  if (/^\d{4}-\d{2}-\d{2}/.test(str)) {
    return str.slice(0, 10);
  }
  const s = str.replace(/[^0-9]/g, '');
  if (s.length === 8) {
    return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
  }
  return null;
}

/**
 * 1. NLM RxNav: Resolve a drug name to a canonical RxNorm concept (preferring SBD/SCD).
 */
async function fetchRxNormConcept(brandName, genericName) {
  const candidates = [
    brandName,
    brandName ? brandName.split(' ')[0] : null,
    genericName,
    genericName ? genericName.split(/[,/]/)[0].trim() : null,
  ].filter(Boolean);

  for (const candidate of candidates) {
    const query = encodeURIComponent(candidate);
    const data = await fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/drugs.json?name=${query}`);
    const groups = data?.drugGroup?.conceptGroup || [];

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
  }
  return null;
}

/**
 * 1b. NLM RxNav: Fetch canonical sorted Ingredient (IN) names for an RxCUI.
 * Enables order-independent, salt-independent cross-referencing for multi-ingredient drugs.
 */
async function fetchRxNormIngredients(rxcui) {
  if (!rxcui) return [];
  const data = await fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/rxcui/${encodeURIComponent(rxcui)}/related.json?tty=IN`);
  const groups = data?.relatedGroup?.conceptGroup || [];
  const names = [];
  for (const g of groups) {
    for (const prop of g.conceptProperties || []) {
      if (prop.name) names.push(prop.name.toLowerCase().trim());
    }
  }
  return [...new Set(names)].sort();
}

/**
 * 2. OpenFDA Drugs@FDA: Reference-NDA-First FDA Orange Book Lookup!
 *
 * CRITICAL FDA ORANGE BOOK INVARIANT:
 * A brand-name NDA ONLY receives a `te_code` (AB, AB1, AB2, AP, AA, etc.) once FDA approves
 * a therapeutically equivalent generic ANDA for that exact formulation.
 * If the reference brand NDA has NO `te_code` (e.g. Jornay PM NDA209311, Ozempic, Eliquis),
 * then ZERO therapeutically equivalent generics exist — we MUST NOT pull generic ANDAs
 * belonging to OTHER brands that merely share the same active ingredient (e.g. Ritalin/Concerta)!
 */
async function fetchDrugsAtFda(genericName, brandName, drugType = 'small_molecule') {
  // Step A: For small-molecule branded drugs, ALWAYS inspect the Reference Brand NDA first!
  if (brandName && drugType !== 'biologic') {
    const bTerm = encodeURIComponent(`"${brandName}"`);
    const brandData = await fetchJsonSafe(
      `https://api.fda.gov/drug/drugsfda.json?search=products.brand_name:${bTerm}+OR+openfda.brand_name:${bTerm}&limit=10`
    );
    const brandResults = brandData?.results || [];
    const ndaCandidates = brandResults.filter(a => (a.application_number || '').startsWith('NDA'));

    // When a brand has multiple NDAs (e.g. Lyrica capsules AB vs Lyrica oral solution),
    // prefer an exact-brand NDA that carries an active FDA TE code.
    const brandLower = brandName.toLowerCase();
    const getActiveTeCodes = (nda) => {
      const refProds = (nda.products || []).filter(
        p => (p.marketing_status || '').toLowerCase() !== 'discontinued'
      );
      const prods = refProds.length > 0 ? refProds : (nda.products || []);
      return [...new Set(prods.map(p => p.te_code).filter(Boolean))];
    };
    const isExactBrandNda = (nda) =>
      (nda.products || []).some(p => (p.brand_name || '').toLowerCase() === brandLower);

    const refNda =
      ndaCandidates.find(a => isExactBrandNda(a) && getActiveTeCodes(a).length > 0) ||
      ndaCandidates.find(a => getActiveTeCodes(a).length > 0) ||
      ndaCandidates.find(a => isExactBrandNda(a)) ||
      ndaCandidates[0];

    if (refNda) {
      const refProducts = (refNda.products || []).filter(
        p => (p.marketing_status || '').toLowerCase() !== 'discontinued'
      );
      const isEntireBrandDiscontinued = refProducts.length === 0;
      const activeProducts = refProducts.length > 0 ? refProducts : (refNda.products || []);
      const teCodes = [...new Set(activeProducts.map(p => p.te_code).filter(Boolean))];
      const refDosageForms = [...new Set(activeProducts.map(p => p.dosage_form).filter(Boolean))];
      const substances = refNda.openfda?.substance_name || [];

      // FDA Orange Book Rule:
      // - If the reference brand NDA is ACTIVELY marketed and has NO TE code (e.g. Jornay PM, Ozempic, Jardiance),
      //   ZERO therapeutically equivalent generics exist -> return strictly [refNda] (Brand Name Only).
      // - If the entire reference brand NDA is DISCONTINUED (e.g. Glucophage, Prinivil, Prilosec), FDA removes
      //   the brand's TE code when moving it to the Discontinued Section, so fall through to Step B to fetch active generic ANDAs.
      if (teCodes.length === 0 && !isEntireBrandDiscontinued) {
        return [refNda];
      }

      if (teCodes.length > 0) {
        // Reference NDA HAS a TE code (e.g. AB, AB1, AB2, AP) -> fetch ONLY matching-TE ANDAs!
        let results = [refNda];
        const teCode = teCodes[0];
        const formClause = refDosageForms[0]
          ? `+AND+products.dosage_form:${encodeURIComponent(`"${refDosageForms[0]}"`)}`
          : '';
        const teClause = `+AND+products.te_code:${encodeURIComponent(`"${teCode}"`)}`;

        if (substances.length > 0) {
          const subQuery = encodeURIComponent(`"${substances[0]}"`);
          const matched = await fetchJsonSafe(
            `https://api.fda.gov/drug/drugsfda.json?search=openfda.substance_name:${subQuery}${formClause}${teClause}&limit=25`
          );
          if (matched?.results?.length) {
            results = [...results, ...matched.results];
          }
        }

        // Fallback if substance_name query missed (e.g. generic_name exact match with matching TE code)
        if (!results.some(a => (a.application_number || '').startsWith('ANDA'))) {
          const gTerm = encodeURIComponent(`"${genericName}"`);
          const matched2 = await fetchJsonSafe(
            `https://api.fda.gov/drug/drugsfda.json?search=openfda.generic_name:${gTerm}${teClause}&limit=25`
          );
          if (matched2?.results?.length) {
            results = [...results, ...matched2.results];
          }
        }

        const seen = new Set();
        return results.filter(a => {
          if (!a.application_number || seen.has(a.application_number)) return false;
          seen.add(a.application_number);
          return true;
        });
      }
    }
  }

  // Step B: Biologics (Purple Book / BLA) or unbranded generic searches
  const term = encodeURIComponent(`"${genericName}"`);
  let data = await fetchJsonSafe(`https://api.fda.gov/drug/drugsfda.json?search=openfda.generic_name:${term}&limit=25`);
  let results = data?.results || [];

  if (results.length === 0 && brandName) {
    const bTerm = encodeURIComponent(`"${brandName}"`);
    const brandData = await fetchJsonSafe(
      `https://api.fda.gov/drug/drugsfda.json?search=products.brand_name:${bTerm}+OR+openfda.brand_name:${bTerm}&limit=10`
    );
    results = brandData?.results || [];
  }

  const seen = new Set();
  return results.filter(a => {
    if (!a.application_number || seen.has(a.application_number)) return false;
    seen.add(a.application_number);
    return true;
  });
}

/**
 * 3. OpenFDA NDC Directory: Pull FINISHED commercial drug listings (excluding bulk ingredients).
 * For multi-ingredient drugs (comma-separated generic_name), also searches by primary active ingredient
 * to capture commercial generic ANDA NDCs regardless of salt listing order.
 */
async function fetchOpenFdaNdcs(genericName) {
  const term = encodeURIComponent(`"${genericName}"`);
  const data = await fetchJsonSafe(
    `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+generic_name:${term}&limit=25`
  );
  let results = data?.results || [];

  const hasCommercialAnda = results.some(r => {
    const c = (r.marketing_category || '').toUpperCase();
    return c.includes('ANDA') || c.includes('AUTHORIZED GENERIC');
  });
  if (!hasCommercialAnda && (genericName.includes(',') || genericName.includes(' and ') || genericName.includes('/'))) {
    const primaryIngredient = genericName.split(/[,/]| and /i)[0].trim();
    if (primaryIngredient.length >= 4) {
      const ingTerm = encodeURIComponent(`"${primaryIngredient}"`);
      const fallback = await fetchJsonSafe(
        `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(marketing_category:"ANDA"+OR+marketing_category:"NDA+AUTHORIZED+GENERIC")+AND+active_ingredients.name:${ingTerm}&limit=25`
      );
      if (fallback?.results?.length) {
        results = [...results, ...fallback.results];
      }
    }
  }

  return results;
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
  const data = await fetchJsonSafe('https://api.fda.gov/drug/shortages.json?search=status:"Current"&limit=1000');
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

  // Fetch FDA Drugs@FDA first so we know if this brand has an approved TE-rated generic
  const fdaApps = await fetchDrugsAtFda(genericName, brandName, drugType);
  const hasFdaApprovedGeneric = fdaApps.some(app => {
    const appNo = app.application_number || '';
    if (appNo.startsWith('ANDA')) return true;
    if (appNo.startsWith('BLA') && drugType === 'biologic') {
      const products = app.products || [];
      const isRefBrand = brandName && products.some(p => (p.brand_name || '').toLowerCase() === brandName.toLowerCase());
      return !isRefBrand;
    }
    return false;
  });

  // For brand-only formulations (no TE-rated generic, e.g. Jornay PM), only pull brand NDCs/pricing
  // so generic NDCs from OTHER brands sharing the same ingredient (e.g. Ritalin/Concerta) never pollute this drug!
  const [ndcRows, nadacGenericRows, nadacBrandRows, dailyMedRows, rxIngredients] = await Promise.all([
    hasFdaApprovedGeneric
      ? fetchOpenFdaNdcs(genericName)
      : (brandName ? fetchJsonSafe(`https://api.fda.gov/drug/ndc.json?search=finished:true+AND+brand_name:${encodeURIComponent(`"${brandName}"`)}&limit=25`).then(d => d?.results || []) : Promise.resolve([])),
    hasFdaApprovedGeneric ? fetchCmsNadacPrices(genericName) : Promise.resolve([]),
    brandName ? fetchCmsNadacPrices(brandName) : Promise.resolve([]),
    fetchDailyMedSpls(brandName || genericName),
    fetchRxNormIngredients(rxcui),
  ]);

  if (rxIngredients.length > 0) {
    db.prepare("UPDATE drugs SET active_ingredient = ?, updated_at = datetime('now') WHERE id = ?")
      .run(rxIngredients.join(' / '), drugId);
  }

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

  // Detect patent-litigation-delayed generics (e.g., Eliquis):
  // If CMS NADAC actively tracks the Brand (B) but has ZERO Generic (G) pharmacy acquisition rows,
  // and OpenFDA only shows a handful of pre-registered ANDA NDCs (not yet dispensed at retail),
  // do NOT mark those pre-registered ANDA NDCs as commercially launched!
  const hasBrandNadac = [...nadacGenericRows, ...nadacBrandRows].some(
    r => r.classification_for_rate_setting === 'B' && Number.parseFloat(r.nadac_per_unit) > 0
  );
  const hasGenericNadac = [...nadacGenericRows, ...nadacBrandRows].some(
    r => r.classification_for_rate_setting === 'G' && Number.parseFloat(r.nadac_per_unit) > 0
  );
  const distinctAndaLabelers = new Set(
    ndcRows
      .filter(r => {
        const c = (r.marketing_category || '').toUpperCase();
        return c.includes('ANDA') || c.includes('AUTHORIZED GENERIC');
      })
      .map(r => (r.labeler_name || '').toLowerCase().trim())
      .filter(Boolean)
  );
  const patentDelayedPreRegistration =
    hasBrandNadac && !hasGenericNadac && distinctAndaLabelers.size < 4;

  // Step 3: Persist OpenFDA NDC Directory (finished commercial products with expiration dates)
  const upsertNdc = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, labeler_name, marketing_category,
      marketing_start_date, marketing_end_date, is_commercialized, package_description, updated_at
    ) VALUES (?, 'openfda_ndc', ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      labeler_name = excluded.labeler_name,
      marketing_category = excluded.marketing_category,
      marketing_start_date = COALESCE(excluded.marketing_start_date, market_availability.marketing_start_date),
      marketing_end_date = excluded.marketing_end_date,
      is_commercialized = excluded.is_commercialized,
      package_description = excluded.package_description,
      updated_at = datetime('now')
  `);

  for (const item of ndcRows) {
    const ndc = item.product_ndc;
    if (!ndc) continue;
    const cat = (item.marketing_category || '').toUpperCase();
    const normCat = cat.includes('AUTHORIZED GENERIC')
      ? 'AUTHORIZED_GENERIC'
      : cat.includes('ANDA')
        ? 'ANDA'
        : cat.includes('BLA')
          ? 'BLA'
          : cat.includes('NDA')
            ? 'NDA'
            : cat;

    // If FDA lists an Authorized Generic under the brand's NDA, record equivalent generic approval
    if (normCat === 'AUTHORIZED_GENERIC') {
      upsertGeneric.run(
        drugId,
        'orange_book',
        `AUTH-GEN-${ndc}`,
        item.labeler_name || 'Authorized Generic',
        formatFdaDate(item.marketing_start_date),
        1,
        'AB',
        null
      );
      regulatoryCount++;
    }

    const isCommercialFlag =
      (normCat === 'ANDA' || normCat === 'AUTHORIZED_GENERIC') && patentDelayedPreRegistration
        ? 0
        : 1;

    upsertNdc.run(
      drugId,
      ndc,
      item.labeler_name || null,
      normCat,
      formatFdaDate(item.marketing_start_date),
      formatFdaDate(item.marketing_expiration_date),
      isCommercialFlag,
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

function classifyDosageBucket(formStr) {
  const f = String(formStr || '').toLowerCase();
  if (!f) return 'unknown';
  if (/inject|intraven|infus|syringe|vial|ampul|subcut|intramusc/.test(f)) return 'injection';
  if (/inhal|aerosol|nebul|spray/.test(f)) return 'inhalation';
  if (/ophthalm|eye|otic|ear/.test(f)) return 'ophthalmic';
  if (/cream|oint|gel|lotion|patch|film|transdermal|topical/.test(f)) return 'topical';
  if (/tablet|capsule|oral|chew|lozenge|powder/.test(f)) return 'oral';
  return 'other';
}

function extractShortageStrength(presentation) {
  if (!presentation) return null;
  const m = String(presentation).match(/\b(\d*(?:\.\d+)?)\s*(mg|mcg|ug|ml|g|%)\b/i);
  if (!m || !m[1]) return null;
  const num = m[1].startsWith('.') ? `0${m[1]}` : m[1];
  const unit = m[2].toLowerCase() === 'ug' ? 'mcg' : m[2].toLowerCase();
  return unit === '%' ? `${num}%` : `${num} ${unit}`;
}

function isExtendedRelease(str) {
  return /\b(extended|delayed|sustained|controlled)\s*[- ]?release\b|\b(er|xr|sr|dr|cr|la|cd)\b/i.test(String(str || ''));
}

/**
 * Sync live FDA Drug Shortages and match them STRICTLY to drugs in our catalog.
 * - Replaces stale 'Current' rows so resolved shortages clear immediately.
 * - Enforces route/dosage-form compatibility (oral vs injection vs inhalation vs ophthalmic vs topical).
 * - Enforces extended-release vs immediate-release compatibility and exact strength compatibility.
 * - Stores the specific affected strength + dosage form so the UI only warns on the exact affected dose.
 * - Excludes FDA entries explicitly marked availability="Available".
 */
async function ingestLiveShortages(db) {
  const shortages = await fetchLiveFdaShortages();
  if (shortages.length === 0) return { matched: 0, fetched: 0 };

  const allDrugs = db.prepare('SELECT id, generic_name, brand_name, dosage_form, strength FROM drugs').all();

  // Clear previously cached 'Current' shortages so resolved shortages never linger and cause false panic
  db.prepare("DELETE FROM drug_shortages WHERE status = 'Current'").run();

  const findExisting = db.prepare(
    'SELECT id FROM drug_shortages WHERE drug_id = ? AND status = ? AND generic_name = ? AND COALESCE(dosage_form, \'\') = ?'
  );
  const insertShortage = db.prepare(`
    INSERT INTO drug_shortages (
      drug_id, generic_name, dosage_form, status, reason, shortage_start_date, updated_at
    ) VALUES (?, ?, ?, 'Current', ?, ?, datetime('now'))
  `);

  let matched = 0;
  for (const s of shortages) {
    if ((s.status || '').toLowerCase() !== 'current') continue;
    const avail = (s.availability || '').toLowerCase().trim();
    if (avail === 'available') continue;

    const genLower = (s.generic_name || '').toLowerCase().trim();
    if (!genLower) continue;

    const presentation = String(s.presentation || '');
    const shortageFormRaw = String(s.dosage_form || '');
    const shortageBucket = classifyDosageBucket(shortageFormRaw || presentation || genLower);
    const shortageStrength = extractShortageStrength(presentation);
    const shortageIsEr = isExtendedRelease(`${shortageFormRaw} ${presentation} ${genLower}`);
    const shortageIsTablet = /\btablet/i.test(`${shortageFormRaw} ${presentation}`);
    const shortageIsCapsule = /\bcapsule/i.test(`${shortageFormRaw} ${presentation}`);

    const formattedForm = [shortageStrength, shortageFormRaw].filter(Boolean).join(' • ') || null;

    // Find all matching drugs in our catalog with compatible dosage form, release type, and strength
    const matchingDrugs = allDrugs.filter(d => {
      const drugGen = (d.generic_name || '').toLowerCase().trim();
      const firstWord = drugGen.split(/[\s,/]+/)[0];
      if (firstWord.length < 5) return false;

      const wordRegex = new RegExp(`\\b${firstWord.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`);
      if (!wordRegex.test(genLower)) return false;

      // Single-ingredient vs multi-ingredient combo check
      const drugIsCombo = drugGen.includes(',') || drugGen.includes(' and ');
      const shortageIsCombo = genLower.includes(',') || genLower.includes(' and ') || genLower.includes('/');
      if (drugIsCombo !== shortageIsCombo) return false;

      // Route/dosage-form bucket check (oral vs injection vs inhalation vs ophthalmic vs topical)
      const drugForm = String(d.dosage_form || '');
      const drugBucket = classifyDosageBucket(drugForm);
      if (shortageBucket !== 'unknown' && drugBucket !== 'unknown' && shortageBucket !== drugBucket) {
        return false;
      }

      // Oral tablet vs capsule & extended-release vs immediate-release check
      if (shortageBucket === 'oral' && drugBucket === 'oral') {
        const drugIsEr = isExtendedRelease(`${d.brand_name || ''} ${drugForm}`);
        if (shortageIsEr !== drugIsEr) return false;
        const drugIsTablet = /\btablet/i.test(drugForm);
        const drugIsCapsule = /\bcapsule/i.test(drugForm);
        if ((shortageIsTablet && drugIsCapsule && !drugIsTablet) || (shortageIsCapsule && drugIsTablet && !drugIsCapsule)) {
          return false;
        }
      }

      // Strength compatibility: if shortage specifies a strength and drug lists strengths, require match
      if (shortageStrength && d.strength) {
        const drugStrengthsNorm = String(d.strength)
          .toLowerCase()
          .replace(/\s+/g, ' ');
        if (!drugStrengthsNorm.includes(shortageStrength.toLowerCase())) {
          return false;
        }
      }

      return true;
    });

    for (const drug of matchingDrugs) {
      const existing = findExisting.get(drug.id, 'Current', s.generic_name, formattedForm || '');
      if (!existing) {
        insertShortage.run(
          drug.id,
          s.generic_name,
          formattedForm,
          s.shortage_reason || 'Reported by FDA Drug Shortages',
          formatFdaDate(s.initial_posting_date)
        );
        matched++;
      }
    }
  }

  recordIngestionRun(db, {
    feedName: 'live_fda_shortages',
    status: 'success',
    recordsProcessed: matched,
    notes: `Scanned ${shortages.length} active FDA shortages (strict form+ER+strength match)`,
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
      .map(ai =>
        (ai.strength || '')
          .toLowerCase()
          .replace(/\/1\b/g, '')
          .replace(/(^|[\s\/])\.(\d)/g, '$10.$2')
          .replace(/\s+/g, ' ')
          .trim()
      )
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
    const m = name.match(/\b(\d*(?:\.\d+)?\s*(?:MG|MCG|ML|G|%)(?:\s*\/\s*\d*(?:\.\d+)?\s*(?:ML|MG|ACTUAT))?)\b/i);
    if (m) {
      const norm = m[1]
        .toLowerCase()
        .replace(/(^|[\s\/])\.(\d)/g, '$10.$2')
        .replace(/\s+/g, ' ')
        .trim();
      if (/^\d/.test(norm)) {
        strengthSet.add(norm);
      }
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
async function discoverAndIngestDrug(db, rawQuery, options = {}) {
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

  // Fallback 2: Discontinued legacy brand names (e.g., Glucophage -> metformin, Prinivil -> lisinopril, Flomax -> tamsulosin)
  // Resolve the legacy brand via RxNav rxcui -> ingredient (IN), then pull active generic NDCs!
  let legacyBrandAlias = null;
  if (!ndcData?.results?.length) {
    const rxcuiLookup = await fetchJsonSafe(
      `https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(clean)}&search=2`
    );
    const candidateId = rxcuiLookup?.idGroup?.rxnormId?.[0];
    if (candidateId) {
      const ingNames = await fetchRxNormIngredients(candidateId);
      if (ingNames.length > 0) {
        legacyBrandAlias = toTitleCase(clean);
        const ingTerm = encodeURIComponent(`"${ingNames[0]}"`);
        ndcData = await fetchJsonSafe(
          `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+generic_name:${ingTerm}&limit=100`
        );
        if (!rxData?.drugGroup?.conceptGroup?.length) {
          rxData = await fetchJsonSafe(
            `https://rxnav.nlm.nih.gov/REST/drugs.json?name=${encodeURIComponent(ingNames[0])}`
          );
        }
      }
    }
  }

  const results = ndcData?.results || [];
  if (results.length === 0) return null;

  const rxConcepts = (rxData?.drugGroup?.conceptGroup || [])
    .filter(g => g.tty === 'SBD' || g.tty === 'SCD')
    .flatMap(g => g.conceptProperties || []);

  // Pick the best canonical match:
  // 1. Prefer exact brand match + Prescription NDA/BLA (avoiding OTC variants like "Prilosec Otc")
  // 2. If user searched an exact single-ingredient generic name (e.g. "Omeprazole"), prefer exact generic
  //    match so we NEVER hijack it with a multi-ingredient combo NDA like "Talicia" (omeprazole+amoxicillin+rifabutin)!
  const cleanLower = clean.toLowerCase();
  const isRx = (r) => (r.product_type || '').toUpperCase().includes('PRESCRIPTION');
  const isNdaOrBla = (r) => r.marketing_category === 'NDA' || r.marketing_category === 'BLA';
  const isExactBrand = (r) => (r.brand_name || '').trim().toLowerCase() === cleanLower;
  const isExactGeneric = (r) => (r.generic_name || '').trim().toLowerCase() === cleanLower;

  const primary =
    results.find(r => isRx(r) && isNdaOrBla(r) && isExactBrand(r)) ||
    results.find(r => isRx(r) && isExactGeneric(r) && isNdaOrBla(r)) ||
    results.find(r => isRx(r) && isExactGeneric(r)) ||
    results.find(r => isRx(r) && isNdaOrBla(r)) ||
    results.find(r => isRx(r) && isExactBrand(r)) ||
    results.find(r => isNdaOrBla(r)) ||
    results[0];

  const canonicalGeneric = (primary.generic_name || '').trim().toLowerCase();
  if (!canonicalGeneric) return null;

  // For pure generic ANDA searches (where brand_name === generic_name), keep brand_name null
  const rawBrand = primary.brand_name ? primary.brand_name.trim() : null;
  const isUnbrandedGeneric = !legacyBrandAlias && rawBrand && rawBrand.toLowerCase() === canonicalGeneric;
  const canonicalBrand = legacyBrandAlias || (isUnbrandedGeneric ? null : (rawBrand ? toTitleCase(rawBrand) : null));
  const drugType = (primary.marketing_category || '').includes('BLA') ? 'biologic' : 'small_molecule';
  const dosageForm = primary.dosage_form ? primary.dosage_form.toLowerCase() : null;

  // Deduplicate ALL official strengths cleanly (sorted ascending, summing mixed salts accurately)
  const allStrengths = extractCleanStrengths(results, rxConcepts);
  const combinedStrengths = allStrengths.slice(0, 12).join(', ') || null;

  // Check if this canonical drug already exists (match by brand_name when present so distinct brands
  // sharing ingredients like Mydayis vs Adderall XR never collide!)
  const existing = canonicalBrand
    ? db.prepare('SELECT * FROM drugs WHERE LOWER(brand_name) = LOWER(?)').get(canonicalBrand)
    : db.prepare('SELECT * FROM drugs WHERE brand_name IS NULL AND LOWER(generic_name) = LOWER(?)').get(canonicalGeneric);

  if (existing && !options.forceRefresh) {
    if (combinedStrengths && combinedStrengths.length > (existing.strength || '').length) {
      db.prepare("UPDATE drugs SET strength = ?, updated_at = datetime('now') WHERE id = ?")
        .run(combinedStrengths, existing.id);
      return db.prepare('SELECT * FROM drugs WHERE id = ?').get(existing.id);
    }
    return existing;
  }

  // Run full 6-source cross-referenced live ingestion (only clear stale rows after live API confirms match)
  if (existing && options.forceRefresh && results.length > 0) {
    db.prepare('DELETE FROM generic_status WHERE drug_id = ?').run(existing.id);
    db.prepare('DELETE FROM market_availability WHERE drug_id = ?').run(existing.id);
    db.prepare('DELETE FROM alert_events WHERE drug_id = ?').run(existing.id);
  }
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
