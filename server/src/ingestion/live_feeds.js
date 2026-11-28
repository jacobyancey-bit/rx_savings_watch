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

const SALT_SUFFIX_REGEX = /\b(hydrochloride|hcl|dihydrochloride|sodium|potassium|calcium|magnesium|mesylate|besylate|tartrate|bitartrate|succinate|fumarate|hemifumarate|maleate|citrate|acetate|phosphate|sulfate|bisulfate|bromide|chloride|dimesylate|monohydrate|dihydrate|trihydrate|anhydrous|tromethamine|olamine|propionate|valerate|dipropionate|acetonide|saccharate|aspartate|gluconate|lactate|nitrate|oxide|benzoate|pamoate|stearate|tosylate|xinafoate|furoate|malate|carbonate|bicarbonate|erbumine|medoxomil|cilexetil|pivoxil|k\b|na\b)\b/gi;
// NOTE: "disoproxil" and "alafenamide" are intentionally NOT stripped: tenofovir disoproxil (TDF)
// and tenofovir alafenamide (TAF) are clinically distinct, non-substitutable prodrugs.

/**
 * Normalize an active ingredient string to its base chemical moiety (salt-stripped, lowercase).
 */
function normalizeIngredientName(name) {
  if (!name) return '';
  const cleaned = String(name)
    .toLowerCase()
    .replace(/\([^)]*\)/g, ' ')
    .replace(/[^a-z0-9\s\-]/g, ' ')
    .replace(SALT_SUFFIX_REGEX, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned || String(name).toLowerCase().trim();
}

/**
 * Parse a generic name string or ingredient array into a sorted, deduplicated list of base moieties.
 */
function parseExpectedIngredients(genericNameOrList) {
  if (!genericNameOrList) return [];
  const rawParts = Array.isArray(genericNameOrList)
    ? genericNameOrList
    : String(genericNameOrList).split(/\s*(?:,|;|\/|\band\b|\bwith\b)\s*/i);

  const normalized = rawParts
    .map(p => normalizeIngredientName(p))
    .filter(Boolean);

  return [...new Set(normalized)].sort();
}

function isMixedAmphetamineSet(baseNames) {
  // Mixed-salt products (Adderall / Mydayis) contain BOTH amphetamine and dextroamphetamine.
  // A single-moiety product (Dexedrine = dextroamphetamine only, Evekeo = amphetamine only)
  // must never be treated as equivalent to a mixed-salt product.
  if (!Array.isArray(baseNames) || baseNames.length === 0) return false;
  if (!baseNames.every(n => n.includes('amphetamine'))) return false;
  const hasDextro = baseNames.some(n => n.startsWith('dextroamphetamine'));
  const hasRacemic = baseNames.some(n => n.startsWith('amphetamine') || n.startsWith('levoamphetamine'));
  return hasDextro && hasRacemic;
}

/**
 * Verify that two single normalized ingredient names refer to the same active moiety.
 */
function ingredientTokensMatch(a, b) {
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a))) return true;
  // First-word match is only safe when one side is a bare single-word moiety
  // (e.g. "tamsulosin" vs "tamsulosin xyz"). Two multi-word names that merely share a
  // first word are distinct drugs (insulin glargine vs insulin lispro,
  // tenofovir alafenamide vs tenofovir disoproxil).
  const aTokens = a.split(/[\s\-]+/).filter(Boolean);
  const bTokens = b.split(/[\s\-]+/).filter(Boolean);
  if (aTokens.length > 1 && bTokens.length > 1) return false;
  return aTokens[0].length >= 5 && aTokens[0] === bTokens[0];
}

/**
 * Clinical Accuracy Invariant:
 * Strictly verify that a candidate product's active ingredient list has the EXACT SAME
 * ingredient count AND matching active moieties as the expected drug formulation.
 * Prevents single-ingredient brands (e.g. Flomax = tamsulosin, Glucophage = metformin)
 * from ever colliding with multi-ingredient combos (e.g. Jalyn = dutasteride/tamsulosin,
 * Janumet = sitagliptin/metformin), and vice versa.
 */
function matchesExpectedIngredients(candidateIngredients, expectedBaseIngredients) {
  const expected = Array.isArray(expectedBaseIngredients)
    ? expectedBaseIngredients.map(normalizeIngredientName).filter(Boolean)
    : parseExpectedIngredients(expectedBaseIngredients);
  if (expected.length === 0) return true;

  if (!Array.isArray(candidateIngredients) || candidateIngredients.length === 0) {
    return false;
  }

  const candidateRaw = candidateIngredients
    .map(item => (typeof item === 'string' ? item : item?.name || ''))
    .filter(Boolean);
  const candidateBases = [...new Set(candidateRaw.map(normalizeIngredientName).filter(Boolean))].sort();
  if (candidateBases.length === 0) return false;

  // Mixed-salt amphetamine formulations (e.g. Adderall XR / Mydayis) list 4 amphetamine salts
  // that map to 1-2 RxNorm base ingredients (amphetamine / dextroamphetamine).
  if (isMixedAmphetamineSet(expected) && isMixedAmphetamineSet(candidateBases)) {
    return true;
  }

  // Exact active ingredient count MUST match (1 !== 2!)
  if (candidateBases.length !== expected.length) {
    return false;
  }

  // Bijective 1-to-1 ingredient match
  const used = new Set();
  for (const exp of expected) {
    const idx = candidateBases.findIndex((cand, i) => !used.has(i) && ingredientTokensMatch(exp, cand));
    if (idx === -1) return false;
    used.add(idx);
  }
  return true;
}

/**
 * Detect whether an RxNorm concept name (SBD/SCD/BPCK/GPCK) represents a multi-ingredient product.
 * RxNorm separates distinct active ingredients with " / " (spaces around slash),
 * whereas single-ingredient concentrations use "MG/ML" or "MG/0.8 ML" (no space before slash).
 */
function isMultiIngredientRxNormName(name) {
  return /\s\/\s/.test(String(name || ''));
}

/**
 * Extract the bracketed brand name from an RxNorm SBD name, e.g. "... [Flomax]" -> "flomax".
 */
function extractRxNormBrand(name) {
  const m = String(name || '').match(/\[([^\]]+)\]\s*$/);
  return m ? m[1].trim().toLowerCase() : null;
}

/**
 * Filter an RxNorm conceptProperties list by exact brand (when provided) and exact ingredient multiplicity.
 */
function filterRxNormConcepts(concepts, { brandName = null, expectedIngredients = [] } = {}) {
  if (!Array.isArray(concepts) || concepts.length === 0) return [];
  const expected = parseExpectedIngredients(expectedIngredients);
  const expectedIsMixedAmp = isMixedAmphetamineSet(expected);
  const expectedIsCombo = expected.length > 1 && !expectedIsMixedAmp;
  const brandLower = brandName ? brandName.trim().toLowerCase() : null;

  const matchesMultiplicity = (prop) => {
    if (expected.length === 0 || expectedIsMixedAmp) return true;
    const isMulti = isMultiIngredientRxNormName(prop.name);
    if (isMulti !== expectedIsCombo) return false;
    const nameLower = (prop.name || '').toLowerCase();
    return expected.every(ing => {
      const stem = ing.split(/[\s\-]+/)[0];
      return stem.length < 4 || nameLower.includes(stem);
    });
  };

  // 1. If a brandName was requested, prefer exact [Brand] match + matching ingredient multiplicity
  if (brandLower) {
    const exactBrandAndIng = concepts.filter(
      p => extractRxNormBrand(p.name) === brandLower && matchesMultiplicity(p)
    );
    if (exactBrandAndIng.length > 0) return exactBrandAndIng;

    const exactBrand = concepts.filter(p => extractRxNormBrand(p.name) === brandLower);
    if (exactBrand.length > 0) return exactBrand;
  }

  // 2. Otherwise enforce exact ingredient multiplicity & stems
  const byIng = concepts.filter(matchesMultiplicity);
  return byIng.length > 0 ? byIng : [];
}

/**
 * 1. NLM RxNav: Resolve a drug name to a canonical RxNorm concept (strictly matching brand & ingredient count).
 */
async function fetchRxNormConcept(brandName, genericName, expectedIngredients = null) {
  const expected = parseExpectedIngredients(expectedIngredients || genericName);
  const expectedIsCombo = expected.length > 1 && !isMixedAmphetamineSet(expected);

  const candidates = [
    brandName,
    brandName && brandName.includes(' ') ? brandName.split(' ')[0] : null,
    genericName,
    // NEVER truncate a multi-ingredient generic name to its first ingredient!
    !expectedIsCombo && genericName ? genericName.split(/[,/]/)[0].trim() : null,
  ].filter(Boolean);

  const seenCandidates = new Set();
  for (const candidate of candidates) {
    const candKey = candidate.toLowerCase();
    if (seenCandidates.has(candKey)) continue;
    seenCandidates.add(candKey);

    const query = encodeURIComponent(candidate);
    const data = await fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/drugs.json?name=${query}`);
    const groups = data?.drugGroup?.conceptGroup || [];

    // Prefer SBD for branded drugs, SCD for unbranded generic searches
    const preferredOrder = brandName ? ['SBD', 'SCD', 'BPCK', 'GPCK'] : ['SCD', 'SBD', 'GPCK', 'BPCK'];
    for (const tty of preferredOrder) {
      const group = groups.find(g => g.tty === tty && Array.isArray(g.conceptProperties) && g.conceptProperties.length > 0);
      if (!group) continue;

      const filtered = filterRxNormConcepts(group.conceptProperties, {
        brandName: tty === 'SBD' || tty === 'BPCK' ? brandName : null,
        expectedIngredients: expected,
      });
      const prop = filtered[0];
      if (!prop) continue;

      const fullName = prop.name || '';
      const strengthMatch = fullName.match(/\b(\d+(?:\.\d+)?\s*(?:MG|MCG|ML|G|%|UNT)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:ML|MG|ACTUAT))?)\b/i);
      const formMatch = fullName.match(/\b(Oral Tablet|Oral Capsule|Injectable Solution|Auto-Injector|Subcutaneous Solution|Ophthalmic Solution|Inhalation Powder|Metered Dose Inhaler|Delayed Release Oral Capsule|Extended Release Oral Tablet)\b/i);
      return {
        rxcui: String(prop.rxcui),
        name: fullName,
        tty,
        strength: strengthMatch ? strengthMatch[1].toLowerCase() : null,
        dosage_form: formMatch ? formMatch[1].toLowerCase() : null,
      };
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
 * Extract the active ingredient list from an OpenFDA Drugs@FDA application record.
 */
function getFdaAppIngredients(app) {
  const prods = app?.products || [];
  const activeProds = prods.filter(p => (p.marketing_status || '').toLowerCase() !== 'discontinued');
  const sampleProd = activeProds[0] || prods[0];
  if (Array.isArray(sampleProd?.active_ingredients) && sampleProd.active_ingredients.length > 0) {
    return sampleProd.active_ingredients;
  }
  if (Array.isArray(app?.openfda?.substance_name) && app.openfda.substance_name.length > 0) {
    return app.openfda.substance_name.map(name => ({ name }));
  }
  return [];
}

/**
 * 2. OpenFDA Drugs@FDA: Reference-NDA-First FDA Orange Book Lookup!
 *
 * CRITICAL FDA ORANGE BOOK INVARIANTS:
 * 1. A brand-name NDA ONLY receives a `te_code` (AB, AB1, AB2, AP, AA, etc.) once FDA approves
 *    a therapeutically equivalent generic ANDA for that exact formulation.
 *    If the reference brand NDA has NO `te_code` (e.g. Jornay PM NDA209311, Ozempic, Eliquis),
 *    then ZERO therapeutically equivalent generics exist — we MUST NOT pull generic ANDAs
 *    belonging to OTHER brands that merely share the same active ingredient (e.g. Ritalin/Concerta)!
 * 2. Exact Active Ingredient Count & Set Match: Every generic ANDA attached to a drug MUST have
 *    the exact same active ingredient count and moieties as the reference NDA (e.g. Flomax NDA020579
 *    has 1 ingredient: tamsulosin -> NEVER attach 2-ingredient Jalyn/dutasteride+tamsulosin ANDAs!).
 */
async function fetchDrugsAtFda(genericName, brandName, drugType = 'small_molecule', expectedIngredients = null) {
  const fallbackExpected = parseExpectedIngredients(expectedIngredients || genericName);

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
      const refIngredientsRaw = getFdaAppIngredients(refNda);
      const refExpected = parseExpectedIngredients(refIngredientsRaw.map(a => a.name));
      const strictExpected = refExpected.length > 0 ? refExpected : fallbackExpected;
      const substances =
        refNda.openfda?.substance_name?.length > 0
          ? refNda.openfda.substance_name
          : refIngredientsRaw.map(a => a.name).filter(Boolean);

      // FDA Orange Book Rule:
      // - If the reference brand NDA is ACTIVELY marketed and has NO TE code (e.g. Jornay PM, Ozempic, Jardiance),
      //   ZERO therapeutically equivalent generics exist -> return strictly [refNda] (Brand Name Only).
      // - If the entire reference brand NDA is DISCONTINUED (e.g. Glucophage, Prinivil, Prilosec), FDA removes
      //   the brand's TE code when moving it to the Discontinued Section, so fall through to Step B to fetch active generic ANDAs.
      if (teCodes.length === 0 && !isEntireBrandDiscontinued) {
        return [refNda];
      }

      if (teCodes.length > 0) {
        // Reference NDA HAS a TE code (e.g. AB, AB1, AB2, AP) -> fetch ONLY matching-TE, matching-ingredient ANDAs!
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
            const exactMatched = matched.results.filter(a =>
              matchesExpectedIngredients(getFdaAppIngredients(a), strictExpected)
            );
            results = [...results, ...exactMatched];
          }
        }

        // Fallback if substance_name query missed (e.g. generic_name exact match with matching TE code)
        if (!results.some(a => (a.application_number || '').startsWith('ANDA'))) {
          const gTerm = encodeURIComponent(`"${genericName}"`);
          const matched2 = await fetchJsonSafe(
            `https://api.fda.gov/drug/drugsfda.json?search=openfda.generic_name:${gTerm}${teClause}&limit=25`
          );
          if (matched2?.results?.length) {
            const exactMatched2 = matched2.results.filter(a =>
              matchesExpectedIngredients(getFdaAppIngredients(a), strictExpected)
            );
            results = [...results, ...exactMatched2];
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

  // Step B: Biologics (Purple Book / BLA), discontinued legacy brands, or unbranded generic searches
  const term = encodeURIComponent(`"${genericName}"`);
  let data = await fetchJsonSafe(`https://api.fda.gov/drug/drugsfda.json?search=openfda.generic_name:${term}&limit=25`);
  let results = data?.results || [];

  if (results.length > 0 && fallbackExpected.length > 0) {
    const exactFiltered = results.filter(a =>
      matchesExpectedIngredients(getFdaAppIngredients(a), fallbackExpected)
    );
    // Fail closed: never fall back to unfiltered name-search hits (which may be different
    // salts, prodrugs, or combinations) when nothing matches the exact ingredient profile.
    results = exactFiltered;
  }

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
 * Strictly filters returned NDCs by exact active ingredient count & moieties so single-ingredient
 * drugs never absorb combination NDCs (and vice versa).
 */
async function fetchOpenFdaNdcs(genericName, expectedIngredients = null) {
  const expected = parseExpectedIngredients(expectedIngredients || genericName);
  const term = encodeURIComponent(`"${genericName}"`);
  const data = await fetchJsonSafe(
    `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+generic_name:${term}&limit=50`
  );
  let results = data?.results || [];

  if (expected.length > 0) {
    results = results.filter(r => matchesExpectedIngredients(r.active_ingredients, expected));
  }

  const hasCommercialAnda = results.some(r => {
    const c = (r.marketing_category || '').toUpperCase();
    return c.includes('ANDA') || c.includes('AUTHORIZED GENERIC');
  });
  if (!hasCommercialAnda && (genericName.includes(',') || genericName.includes(' and ') || genericName.includes('/'))) {
    const primaryIngredient = genericName.split(/[,/]| and /i)[0].trim();
    if (primaryIngredient.length >= 4) {
      const ingTerm = encodeURIComponent(`"${primaryIngredient}"`);
      const fallback = await fetchJsonSafe(
        `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(marketing_category:"ANDA"+OR+marketing_category:"NDA+AUTHORIZED+GENERIC")+AND+active_ingredients.name:${ingTerm}&limit=50`
      );
      if (fallback?.results?.length) {
        const filteredFallback = expected.length > 0
          ? fallback.results.filter(r => matchesExpectedIngredients(r.active_ingredients, expected))
          : fallback.results;
        results = [...results, ...filteredFallback];
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

/**
 * Check whether a CMS NADAC ndc_description matches the expected single vs multi-ingredient profile.
 * CMS NADAC formats combination drugs with a hyphen between ingredient names before the strength,
 * e.g. "DUTASTERIDE-TAMSULOSIN 0.5-0.4", "LISINOPRIL-HCTZ 20-12.5 MG", "SITAGLIPTIN-METFORMIN 50-500".
 */
function matchesNadacIngredientProfile(ndcDescription, expectedIngredients, isBrandQuery = false) {
  if (isBrandQuery) return true;
  const expected = parseExpectedIngredients(expectedIngredients);
  if (expected.length === 0 || isMixedAmphetamineSet(expected)) return true;

  const desc = String(ndcDescription || '').toUpperCase().trim();
  if (!desc) return false;

  // Portion of the description before the first numeric strength token
  const namePart = desc.split(/\s+\d/)[0] || desc;
  const looksLikeCombo = /[A-Z]{3,}-[A-Z]{3,}/.test(namePart) || namePart.includes('/');

  if (expected.length === 1) {
    // Reject combination NADAC rows (e.g. DUTASTERIDE-TAMSULOSIN) for single-ingredient drugs!
    if (looksLikeCombo) return false;
    return true;
  }

  // For multi-ingredient drugs, require at least 2 ingredient stems (or combo separator) to match
  const matchedStems = expected.filter(ing => {
    const stem = ing.split(/[\s\-]+/)[0].toUpperCase();
    if (stem === 'HYDROCHLOROTHIAZIDE' && /\bHCTZ\b/.test(desc)) return true;
    return stem.length >= 4 && desc.includes(stem.slice(0, Math.min(stem.length, 6)));
  });
  return matchedStems.length >= Math.min(expected.length, 2);
}

async function fetchCmsNadacPrices(searchKeyword, expectedIngredients = null, isBrandQuery = false) {
  const datasetId = await getLatestNadacDatasetId();
  if (!datasetId) return [];
  const token = encodeURIComponent(`%${searchKeyword.toUpperCase().split(' ')[0]}%`);
  const url = `https://data.medicaid.gov/api/1/datastore/query/${datasetId}/0?limit=30&conditions[0][property]=ndc_description&conditions[0][value]=${token}&conditions[0][operator]=LIKE`;
  const data = await fetchJsonSafe(url);
  const rows = data?.results || [];
  if (!expectedIngredients || isBrandQuery) return rows;
  return rows.filter(r => matchesNadacIngredientProfile(r.ndc_description, expectedIngredients, false));
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
  const expectedIngredients = parseExpectedIngredients(seed.expected_ingredients || genericName);

  // Step 1: Resolve canonical RxNorm RXCUI (match strictly by brand_name when present so distinct
  // brands sharing ingredients — e.g. Ozempic vs Wegovy, Mydayis vs Adderall XR, Flomax vs Jalyn — NEVER collide!)
  const existing = (seed.rxcui ? db.prepare('SELECT * FROM drugs WHERE rxcui = ?').get(String(seed.rxcui)) : null) ||
    (brandName
      ? db.prepare('SELECT * FROM drugs WHERE LOWER(brand_name) = LOWER(?)').get(brandName)
      : db.prepare('SELECT * FROM drugs WHERE brand_name IS NULL AND LOWER(generic_name) = LOWER(?)').get(genericName));

  const rxConcept = await fetchRxNormConcept(brandName, genericName, expectedIngredients);
  const rxcui = existing?.rxcui || rxConcept?.rxcui;
  if (!rxcui) {
    return { skipped: true, reason: 'No RxNorm RXCUI resolved' };
  }

  // Upsert canonical drug record
  const dosageOptionsJson = Array.isArray(seed.dosage_options) && seed.dosage_options.length > 0
    ? JSON.stringify(seed.dosage_options)
    : null;
  const referenceBrandsJson = Array.isArray(seed.reference_brands) && seed.reference_brands.length > 0
    ? JSON.stringify(seed.reference_brands)
    : null;

  db.prepare(`
    INSERT INTO drugs (
      rxcui, brand_name, generic_name, active_ingredient, dosage_form, strength, dosage_options, reference_brands, drug_type, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(rxcui) DO UPDATE SET
      brand_name = COALESCE(excluded.brand_name, drugs.brand_name),
      generic_name = excluded.generic_name,
      dosage_form = COALESCE(drugs.dosage_form, excluded.dosage_form),
      strength = COALESCE(excluded.strength, drugs.strength),
      dosage_options = COALESCE(excluded.dosage_options, drugs.dosage_options),
      reference_brands = COALESCE(excluded.reference_brands, drugs.reference_brands),
      drug_type = excluded.drug_type,
      updated_at = datetime('now')
  `).run(
    rxcui,
    brandName || null,
    genericName,
    genericName,
    seed.dosage_form || rxConcept?.dosage_form || null,
    seed.strength || rxConcept?.strength || null,
    dosageOptionsJson,
    referenceBrandsJson,
    drugType
  );

  const drugRow = db.prepare('SELECT id FROM drugs WHERE rxcui = ?').get(rxcui);
  const drugId = drugRow.id;

  // Fetch FDA Drugs@FDA first so we know if this brand has an approved TE-rated generic
  const fdaApps = await fetchDrugsAtFda(genericName, brandName, drugType, expectedIngredients);
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
      ? fetchOpenFdaNdcs(genericName, expectedIngredients)
      : (brandName ? fetchJsonSafe(`https://api.fda.gov/drug/ndc.json?search=finished:true+AND+brand_name:${encodeURIComponent(`"${brandName}"`)}&limit=25`).then(d => d?.results || []) : Promise.resolve([])),
    hasFdaApprovedGeneric ? fetchCmsNadacPrices(genericName, expectedIngredients, false) : Promise.resolve([]),
    brandName ? fetchCmsNadacPrices(brandName, expectedIngredients, true) : Promise.resolve([]),
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
  const m = String(str).match(/(\d+(?:\.\d+)?)\s*(mcg|ug|mg|g)?/i);
  if (!m) return Number.MAX_SAFE_INTEGER;
  const value = Number.parseFloat(m[1]);
  const unit = (m[2] || '').toLowerCase();
  // Sort in mg-equivalent so "25 mcg" sorts before "1 mg"
  if (unit === 'mcg' || unit === 'ug') return value / 1000;
  if (unit === 'g') return value * 1000;
  return value;
}

function formatStrengthNumber(num) {
  return Number(num.toFixed(3)).toString();
}

/**
 * Canonicalize unit spelling in a strength label (display value otherwise unchanged):
 *   "25 ug" -> "25 mcg", "100 [iu]/ml" / "100 unt/ml" -> "100 units/ml", "1000 mcg" -> "1 mg"
 */
function canonicalizeStrength(raw) {
  if (!raw) return raw;
  const canonPart = (part) => {
    const p = String(part)
      .toLowerCase()
      .replace(/\[iu\]|\biu\b|\bunt\b|\bunits?\b/g, 'units')
      .replace(/\bug\b|µg|\bmcg\b/g, 'mcg')
      .replace(/\s+/g, ' ')
      .trim();
    const m = p.match(/^(\d*(?:\.\d+)?)\s*(mg|mcg)(\s*\/.*)?$/);
    if (!m || m[1] === '') return p;
    let value = Number.parseFloat(m[1]);
    let unit = m[2];
    if (unit === 'mcg' && value >= 1000) { value = value / 1000; unit = 'mg'; }
    const rest = (m[3] || '').replace(/\s*\/\s*/, '/');
    // Preserve full precision (e.g. 0.00125 mg/actuat) — never round clinical strengths
    return `${Number(value.toPrecision(10))} ${unit}${rest}`;
  };
  return String(raw).split(/\s\/\s/).map(canonPart).join(' / ');
}

/** mg-equivalent identity key so "0.025 mg" and "25 mcg" are recognized as the same strength. */
function strengthIdentityKey(label) {
  return String(label).split(/\s\/\s/).map(part => {
    const m = String(part).match(/^(\d*(?:\.\d+)?)\s*(mg|mcg)(\/.*)?$/);
    if (!m || m[1] === '') return part;
    const mg = m[2] === 'mcg' ? Number.parseFloat(m[1]) / 1000 : Number.parseFloat(m[1]);
    return `${Number(mg.toFixed(6))}mg${m[3] || ''}`;
  }).join(' / ');
}

/**
 * Collapse equivalent strengths (e.g. "0.025 mg" + "25 mcg") into one label.
 * Prefers the mcg label when the source itself published one (e.g. levothyroxine "25 mcg").
 */
function dedupeStrengths(labels) {
  const byKey = new Map();
  for (const raw of labels) {
    const label = canonicalizeStrength(raw);
    if (!label) continue;
    const key = strengthIdentityKey(label);
    const existing = byKey.get(key);
    if (!existing || (/\bmg\b/.test(existing) && /\bmcg\b/.test(label))) byKey.set(key, label);
  }
  return [...byKey.values()];
}

function normalizeDosageFormLabel(rawForm, rawRoute = '') {
  const f = `${rawForm || ''} ${rawRoute || ''}`.toLowerCase();
  if (!f.trim()) return 'Oral';
  if (/ophthalm|eye/.test(f)) return 'Eye Drops';
  if (/otic|ear/.test(f)) return 'Ear Drops';
  if (/inhal|aerosol|nebul|diskus|ellipta|metered|spray/.test(f)) return 'Inhaler / Spray';
  if (/inject|intraven|infus|syringe|vial|ampul|subcut|intramusc|auto-injector/.test(f)) return 'Injectable';
  if (/patch|transdermal/.test(f)) return 'Patch';
  if (/cream|oint|gel|lotion|foam|shampoo|topical/.test(f)) return 'Topical';
  if (/tablet/.test(f)) {
    if (/extended|sustained|controlled/.test(f)) return 'Extended-Release Tablet';
    if (/delayed/.test(f)) return 'Delayed-Release Tablet';
    if (/disintegrat|odt/.test(f)) return 'Orally Disintegrating Tablet';
    if (/chew/.test(f)) return 'Chewable Tablet';
    return 'Oral Tablet';
  }
  if (/capsule/.test(f)) {
    if (/extended|sustained|controlled/.test(f)) return 'Extended-Release Capsule';
    if (/delayed/.test(f)) return 'Delayed-Release Capsule';
    return 'Oral Capsule';
  }
  if (/solution|syrup|suspension|elixir|liquid|concentrate|drops/.test(f)) return 'Oral Solution';
  if (/granule|powder|packet/.test(f)) return 'Oral Powder / Granules';
  return 'Oral';
}

function extractStrengthFromNdcRecord(r) {
  if (!Array.isArray(r.active_ingredients) || r.active_ingredients.length === 0) return null;

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
      return `${formatStrengthNumber(totalMg)} mg`;
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
  return combined || null;
}

/**
 * Group official FDA strengths strictly by their exact Dosage Form (e.g. Oral Tablet,
 * Extended-Release Capsule, Oral Solution, Injectable) sorted ascending within each form.
 */
function extractDosageOptions(ndcResults) {
  const formMap = new Map();
  for (const r of (ndcResults || [])) {
    const strength = extractStrengthFromNdcRecord(r);
    if (!strength) continue;
    const routeStr = Array.isArray(r.route) ? r.route.join(' ') : (r.route || '');
    const formLabel = normalizeDosageFormLabel(r.dosage_form, routeStr);
    if (!formMap.has(formLabel)) {
      formMap.set(formLabel, new Set());
    }
    formMap.get(formLabel).add(canonicalizeStrength(strength));
  }

  const preferredOrder = [
    'Oral Tablet',
    'Extended-Release Tablet',
    'Delayed-Release Tablet',
    'Orally Disintegrating Tablet',
    'Chewable Tablet',
    'Oral Capsule',
    'Extended-Release Capsule',
    'Delayed-Release Capsule',
    'Oral Solution',
    'Oral Powder / Granules',
    'Inhaler / Spray',
    'Topical',
    'Patch',
    'Eye Drops',
    'Ear Drops',
    'Injectable',
  ];

  const ordered = [];
  for (const form of preferredOrder) {
    if (formMap.has(form)) {
      ordered.push({
        form,
        strengths: dedupeStrengths(formMap.get(form)).sort((a, b) => parseNumericStrength(a) - parseNumericStrength(b)),
      });
      formMap.delete(form);
    }
  }
  for (const [form, set] of formMap.entries()) {
    ordered.push({
      form,
      strengths: dedupeStrengths(set).sort((a, b) => parseNumericStrength(a) - parseNumericStrength(b)),
    });
  }
  return ordered;
}

/**
 * Extract clean, clinician-accurate total strengths from OpenFDA NDC results & RxNav concepts.
 * Handles mixed-salt medications (e.g. Mydayis / Adderall: 4 equal amphetamine salts summed to
 * 12.5 mg, 25 mg, 37.5 mg, 50 mg), ignores bare container volumes (e.g. "1 ML"), and sorts numerically ascending.
 */
function extractCleanStrengths(ndcResults, rxConcepts = []) {
  const strengthSet = new Set();

  for (const r of ndcResults) {
    const s = extractStrengthFromNdcRecord(r);
    if (s) strengthSet.add(s);
  }

  // Cross-check NLM RxNav SBD/SCD concepts to catch any strengths missing from NDC sample.
  // NOTE: Strictly match real dose/concentration units (MG, MCG, G, %, UNT, MG/ML, etc.) —
  // NEVER bare container volumes like "1 ML" or "3 ML" from "1 ML propranolol 1 MG/ML Injection"!
  const rxStrengthRegex = /\b(\d*(?:\.\d+)?\s*(?:MG|MCG|G|%|UNT)(?:\s*\/\s*\d*(?:\.\d+)?\s*(?:ML|MG|G|ACTUAT))?)\b/i;

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
    if (isMultiIngredientRxNormName(name)) {
      const parts = name.split(/\s\/\s/).map(part => {
        const pm = part.match(rxStrengthRegex);
        if (!pm) return null;
        const norm = pm[1]
          .toLowerCase()
          .replace(/(^|[\s\/])\.(\d)/g, '$10.$2')
          .replace(/\s+/g, ' ')
          .trim();
        return /^\d/.test(norm) ? norm : null;
      }).filter(Boolean);
      if (parts.length >= 2) {
        strengthSet.add(canonicalizeStrength(parts.join(' / ')));
      }
      continue;
    }
    const m = name.match(rxStrengthRegex);
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

  return dedupeStrengths(strengthSet).sort((a, b) => parseNumericStrength(a) - parseNumericStrength(b));
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

  const cleanLower = clean.toLowerCase();
  const term = encodeURIComponent(`"${clean}"`);
  // 1. Resolve canonical brand/generic/strengths via OpenFDA NDC (up to 100 finished products) + RxNav
  let [ndcData, rxData] = await Promise.all([
    fetchJsonSafe(
      `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(brand_name:${term}+OR+generic_name:${term})&limit=100`
    ),
    fetchJsonSafe(`https://rxnav.nlm.nih.gov/REST/drugs.json?name=${encodeURIComponent(clean)}`),
  ]);

  // Extract authoritative RxNorm exact-brand SBD ingredients if the user searched a brand name
  // (e.g. Flomax -> SBD "... [Flomax]" -> ['tamsulosin']; Jalyn -> SBD "... [Jalyn]" -> ['dutasteride', 'tamsulosin'])
  let expectedIngredients = [];
  const allInitialRxConcepts = (rxData?.drugGroup?.conceptGroup || [])
    .filter(g => g.tty === 'SBD' || g.tty === 'SCD' || g.tty === 'BPCK')
    .flatMap(g => g.conceptProperties || []);
  const exactRxBrandSbd = allInitialRxConcepts.find(p => extractRxNormBrand(p.name) === cleanLower);
  if (exactRxBrandSbd?.rxcui) {
    expectedIngredients = await fetchRxNormIngredients(exactRxBrandSbd.rxcui);
  }

  // Helper: verify that an OpenFDA NDC payload actually contains at least one product
  // matching expectedIngredients (e.g. searching "Micardis" returns only 2-ingredient
  // "Micardis HCT" in active NDCs, so we must trigger Fallback 2 for single-ingredient telmisartan!)
  const hasIngredientMatchingNdc = (payload) => {
    const list = payload?.results || [];
    if (list.length === 0) return false;
    if (expectedIngredients.length === 0) return true;
    return list.some(r => matchesExpectedIngredients(r.active_ingredients, expectedIngredients));
  };

  // Fallback: unquoted token search if exact phrase missed
  if (!hasIngredientMatchingNdc(ndcData)) {
    const loose = encodeURIComponent(clean.split(' ')[0]);
    const looseData = await fetchJsonSafe(
      `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+(brand_name:${loose}+OR+generic_name:${loose})&limit=100`
    );
    if (hasIngredientMatchingNdc(looseData)) {
      ndcData = looseData;
    }
  }

  // Fallback 2: Discontinued legacy brand names (e.g., Glucophage -> metformin, Prinivil -> lisinopril,
  // Flomax -> tamsulosin, Micardis -> telmisartan where only Micardis HCT remains in active NDCs)
  // Resolve the legacy brand via RxNav SBD/BN -> exact Ingredient (IN) set, then pull active generic NDCs!
  let legacyBrandAlias = null;
  if (!hasIngredientMatchingNdc(ndcData)) {
    let ingNames = expectedIngredients;
    if (ingNames.length === 0) {
      const rxcuiLookup = await fetchJsonSafe(
        `https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(clean)}&search=2`
      );
      const candidateId = rxcuiLookup?.idGroup?.rxnormId?.[0];
      if (candidateId) {
        ingNames = await fetchRxNormIngredients(candidateId);
      }
    }
    if (ingNames.length > 0) {
      expectedIngredients = ingNames;
      legacyBrandAlias = toTitleCase(clean);
      const ndcSearchClause = ingNames
        .map(ing => `generic_name:${encodeURIComponent(`"${ing}"`)}`)
        .join('+AND+');
      ndcData = await fetchJsonSafe(
        `https://api.fda.gov/drug/ndc.json?search=finished:true+AND+${ndcSearchClause}&limit=100`
      );
      if (!rxData?.drugGroup?.conceptGroup?.length) {
        rxData = await fetchJsonSafe(
          `https://rxnav.nlm.nih.gov/REST/drugs.json?name=${encodeURIComponent(ingNames.join(' '))}`
        );
      }
    }
  }

  const rawResults = ndcData?.results || [];
  if (rawResults.length === 0) {
    // Fallback 3: Official NLM RxNav spelling suggestions for minor typos (e.g. "pramapexole" -> "pramipexole")
    if (!options._fromSpellingSuggestion) {
      const spellData = await fetchJsonSafe(
        `https://rxnav.nlm.nih.gov/REST/spellingsuggestions.json?name=${encodeURIComponent(clean)}`
      );
      const suggestion = spellData?.suggestionGroup?.suggestionList?.suggestion?.[0];
      if (suggestion && suggestion.toLowerCase() !== cleanLower) {
        return discoverAndIngestDrug(db, suggestion, { ...options, _fromSpellingSuggestion: true });
      }
    }
    return null;
  }

  const isRx = (r) => (r.product_type || '').toUpperCase().includes('PRESCRIPTION');
  const isNdaOrBla = (r) => r.marketing_category === 'NDA' || r.marketing_category === 'BLA';
  const isExactBrand = (r) => (r.brand_name || '').trim().toLowerCase() === cleanLower;
  const isExactGeneric = (r) => (r.generic_name || '').trim().toLowerCase() === cleanLower;

  // If no RxNorm brand SBD was matched AND there is no distinct brand match
  // (where brand_name is NOT itself one of the generic ingredients — e.g. "Propranolol" vs
  // "Propranolol Hydrochloride" or "Ibuprofen" vs "Ibuprofen and Diphenhydramine" is a generic search,
  // NOT a distinct brand!), derive expectedIngredients from the query so multi-ingredient combos
  // (e.g. Jalyn, Talicia, Inderide, OTC ibuprofen cold combos) can NEVER pollute a single-ingredient generic!
  const isDistinctBrand = (r) => {
    if (!isRx(r) || !isNdaOrBla(r) || !isExactBrand(r)) return false;
    const brandNorm = normalizeIngredientName(r.brand_name);
    const genIngs = parseExpectedIngredients(r.generic_name);
    if (genIngs.length === 0) return false;
    return brandNorm && !genIngs.some(g => ingredientTokensMatch(g, brandNorm));
  };

  if (expectedIngredients.length === 0 && !rawResults.some(isDistinctBrand)) {
    const queryIngredients = parseExpectedIngredients(clean);
    if (
      queryIngredients.length > 0 &&
      rawResults.some(r => matchesExpectedIngredients(r.active_ingredients, queryIngredients))
    ) {
      expectedIngredients = queryIngredients;
    }
  }

  // Strictly filter OpenFDA NDC candidates to the exact active ingredient count & moieties!
  // For Flomax (['tamsulosin']), this eliminates Jalyn (['dutasteride', 'tamsulosin']) BEFORE
  // primary selection AND BEFORE strength extraction!
  const ingredientMatchedResults =
    expectedIngredients.length > 0
      ? rawResults.filter(r => matchesExpectedIngredients(r.active_ingredients, expectedIngredients))
      : rawResults;
  const results = ingredientMatchedResults.length > 0 ? ingredientMatchedResults : rawResults;

  const rawRxConcepts = (rxData?.drugGroup?.conceptGroup || [])
    .filter(g => g.tty === 'SBD' || g.tty === 'SCD')
    .flatMap(g => g.conceptProperties || []);
  const rxConcepts =
    expectedIngredients.length > 0
      ? filterRxNormConcepts(rawRxConcepts, {
          brandName: legacyBrandAlias || (exactRxBrandSbd ? clean : null),
          expectedIngredients,
        })
      : rawRxConcepts;

  // Pick the best canonical match from the ingredient-verified candidate set:
  // 1. Prefer exact brand match + Prescription NDA/BLA (avoiding OTC variants like "Prilosec Otc")
  // 2. If user searched an exact generic name (e.g. "Omeprazole", "Tamsulosin"), prefer exact generic match
  // 3. For legacy brands (where brand NDA is discontinued), prefer Rx NDA/BLA or Rx ANDA within the exact ingredient set
  const primary =
    results.find(r => isRx(r) && isNdaOrBla(r) && isExactBrand(r)) ||
    results.find(r => isRx(r) && isExactGeneric(r) && isNdaOrBla(r)) ||
    results.find(r => isRx(r) && isExactGeneric(r)) ||
    results.find(r => isRx(r) && isNdaOrBla(r)) ||
    results.find(r => isRx(r) && isExactBrand(r)) ||
    results.find(r => isRx(r)) ||
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

  // For unbranded generic searches, extract known FDA/RxNorm reference brand names
  // (e.g. propranolol -> ["Inderal", "Inderal LA", "Hemangeol"], tamsulosin -> ["Flomax"])
  // strictly from ingredient-verified RxNorm SBDs and OpenFDA NDAs!
  const referenceBrandSet = new Map(); // lower -> display Title Case
  if (!canonicalBrand) {
    const genNorm = normalizeIngredientName(canonicalGeneric);
    const addRefBrand = (raw) => {
      if (!raw) return;
      const trimmed = String(raw).trim();
      if (trimmed.length < 3 || trimmed.length > 40) return;
      const norm = normalizeIngredientName(trimmed);
      if (!norm || norm === genNorm || trimmed.toLowerCase() === canonicalGeneric) return;
      const key = trimmed.toLowerCase();
      if (!referenceBrandSet.has(key)) {
        referenceBrandSet.set(key, toTitleCase(trimmed));
      }
    };
    for (const p of rxConcepts) {
      const m = String(p.name || '').match(/\[([^\]]+)\]\s*$/);
      if (m) addRefBrand(m[1]);
    }
    for (const r of results) {
      if ((r.marketing_category === 'NDA' || r.marketing_category === 'BLA') && r.brand_name) {
        addRefBrand(r.brand_name);
      }
    }
  }
  const referenceBrands = [...referenceBrandSet.values()].slice(0, 5);

  // Deduplicate ALL official strengths cleanly (strictly from ingredient-matched results & RxNorm concepts!)
  // and build exact FDA Dosage Form -> Strengths groups so multi-form drugs (e.g. propranolol) never lose oral doses!
  const dosageOptions = extractDosageOptions(results);
  const allStrengths = extractCleanStrengths(results, rxConcepts);
  const combinedStrengths = allStrengths.slice(0, 30).join(', ') || null;

  // Check if this canonical drug already exists (prefer explicit rxcui on forceRefresh,
  // otherwise match by brand_name when present so distinct brands never collide!)
  const existing = (options.rxcui ? db.prepare('SELECT * FROM drugs WHERE rxcui = ?').get(String(options.rxcui)) : null) ||
    (canonicalBrand
      ? db.prepare('SELECT * FROM drugs WHERE LOWER(brand_name) = LOWER(?)').get(canonicalBrand)
      : db.prepare('SELECT * FROM drugs WHERE brand_name IS NULL AND LOWER(generic_name) = LOWER(?)').get(canonicalGeneric));

  if (existing && !options.forceRefresh) {
    if (combinedStrengths && combinedStrengths.length > (existing.strength || '').length) {
      db.prepare("UPDATE drugs SET strength = ?, dosage_options = COALESCE(?, dosage_options), reference_brands = COALESCE(?, reference_brands), updated_at = datetime('now') WHERE id = ?")
        .run(
          combinedStrengths,
          dosageOptions.length > 0 ? JSON.stringify(dosageOptions) : null,
          referenceBrands.length > 0 ? JSON.stringify(referenceBrands) : null,
          existing.id
        );
      return db.prepare('SELECT * FROM drugs WHERE id = ?').get(existing.id);
    }
    return existing;
  }

  // Run full 6-source cross-referenced live ingestion (only clear stale rows after live API confirms match)
  // Preserve the original launch-detection timestamp across forced refreshes so a routine
  // re-audit never re-announces an already-known generic launch as a "new" alert.
  let priorLaunchDetectedAt = null;
  if (existing && options.forceRefresh && results.length > 0) {
    priorLaunchDetectedAt = db.prepare(
      "SELECT MIN(detected_at) AS first FROM alert_events WHERE drug_id = ? AND event_type = 'commercial_generic_launch'"
    ).get(existing.id)?.first || null;
    db.prepare('DELETE FROM generic_status WHERE drug_id = ?').run(existing.id);
    db.prepare('DELETE FROM market_availability WHERE drug_id = ?').run(existing.id);
    db.prepare('DELETE FROM alert_events WHERE drug_id = ?').run(existing.id);
  }
  const ingestRes = await ingestLiveDrug(db, {
    rxcui: existing?.rxcui,
    brand_name: canonicalBrand,
    generic_name: canonicalGeneric,
    expected_ingredients: expectedIngredients.length > 0 ? expectedIngredients : undefined,
    drug_type: drugType,
    dosage_form: dosageForm,
    strength: combinedStrengths,
    dosage_options: dosageOptions,
    reference_brands: referenceBrands,
  });

  if (ingestRes.skipped || !ingestRes.rxcui) return null;

  const savedDrug = db.prepare('SELECT * FROM drugs WHERE rxcui = ?').get(ingestRes.rxcui);
  if (!savedDrug) return null;

  // Immediately evaluate 2-signal commercial generic launch for the newly discovered drug
  const { GenericLaunchDetector } = require('../detector');
  const detector = new GenericLaunchDetector(db);
  detector.evaluateDrug(savedDrug, {
    persistAlert: true,
    ...(priorLaunchDetectedAt ? { detectedAt: priorLaunchDetectedAt } : {}),
  });

  return savedDrug;
}

/**
 * Incrementally seed ONLY missing drugs from a seed list (leaving existing rows untouched).
 * Uses discoverAndIngestDrug so every newly seeded medication gets full FDA dosage_options,
 * reference_brands, strict ingredient matching, and 2-signal generic launch evaluation.
 */
async function seedMissingDrugs(db, seedList, options = {}) {
  const delayMs = options.delayMs ?? 350;
  const maxPerRun = options.maxPerRun ?? seedList.length;

  const existingRows = db.prepare('SELECT brand_name, generic_name FROM drugs').all();
  const existingBrands = new Set(
    existingRows.map(r => (r.brand_name || '').trim().toLowerCase()).filter(Boolean)
  );
  const existingUnbrandedGenerics = new Set(
    existingRows
      .filter(r => !r.brand_name || !r.brand_name.trim())
      .map(r => normalizeIngredientName(r.generic_name))
      .filter(Boolean)
  );

  const missing = seedList.filter(seed => {
    const b = (seed.brand_name || '').trim().toLowerCase();
    if (b) return !existingBrands.has(b);
    const gNorm = normalizeIngredientName(seed.generic_name);
    return gNorm && !existingUnbrandedGenerics.has(gNorm);
  }).slice(0, maxPerRun);

  const summary = {
    totalInSeedList: seedList.length,
    missingCount: missing.length,
    seeded: 0,
    skipped: 0,
    errors: 0,
  };

  if (missing.length === 0) return summary;

  for (let i = 0; i < missing.length; i++) {
    const seed = missing[i];
    const query = (seed.brand_name || seed.generic_name || '').trim();
    if (!query) continue;
    try {
      const saved = await discoverAndIngestDrug(db, query);
      if (saved) {
        summary.seeded++;
      } else {
        summary.skipped++;
      }
    } catch (err) {
      summary.errors++;
      console.error(`[SeedMissing] Error seeding "${query}":`, err.message);
    }
    if (delayMs > 0 && i < missing.length - 1) {
      await new Promise(r => setTimeout(r, delayMs));
    }
  }

  recordIngestionRun(db, {
    feedName: 'incremental_seed',
    status: summary.errors === 0 ? 'success' : 'warning',
    recordsProcessed: summary.seeded,
    notes: `seeded=${summary.seeded}/${summary.missingCount} missing (skipped=${summary.skipped}, errors=${summary.errors})`,
  });

  return summary;
}

module.exports = {
  runLiveIngestion,
  seedMissingDrugs,
  ingestLiveDrug,
  ingestLiveShortages,
  discoverAndIngestDrug,
  normalizeIngredientName,
  parseExpectedIngredients,
  matchesExpectedIngredients,
  isMultiIngredientRxNormName,
  extractRxNormBrand,
  filterRxNormConcepts,
  matchesNadacIngredientProfile,
  canonicalizeStrength,
  dedupeStrengths,
};
