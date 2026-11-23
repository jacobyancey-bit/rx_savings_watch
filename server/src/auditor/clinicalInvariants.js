/**
 * Universal Clinical Data Quality Invariants & SQLite Database Auditor
 *
 * Enforces pharmacist-verified clinical accuracy rules across any drug record
 * or entire SQLite database (production, staging, local, or :memory: test DBs):
 *   1. Ingredient-count parity between generic_name and RxNorm active_ingredient
 *   2. Strength-to-ingredient parity (single-ingredient drugs never carry combo "a / b" strengths)
 *   3. Brand-vs-generic placeholder detection (brand_name !== generic_name for branded rows)
 *   4. Duplicate brand-name / RXCUI collision detection
 *   5. CMS NADAC sanity check (generic NADAC should not exceed 2x brand NADAC)
 */

const { parseExpectedIngredients } = require('../ingestion/live_feeds');

function isMixedAmphetamineList(list) {
  return Array.isArray(list) && list.length > 0 && list.every(n => n.includes('amphetamine'));
}

/**
 * Split a comma-separated strength string into individual strength tokens
 * and detect any multi-ingredient slash strengths (e.g. "0.5 mg / 0.4 mg"),
 * while allowing single-ingredient concentrations (e.g. "40 mg/0.8 ml", "500 mg/5ml").
 */
function findComboStrengthTokens(strengthStr) {
  if (!strengthStr) return [];
  return String(strengthStr)
    .split(',')
    .map(s => s.trim())
    .filter(token => /\s\/\s/.test(token));
}

/**
 * Audit a single drug record (with optional market_availability rows) against clinical invariants.
 * Returns { errors: string[], warnings: string[] }.
 */
function auditDrugRecord(drug, { marketRows = [] } = {}) {
  const errors = [];
  const warnings = [];

  if (!drug) {
    errors.push('Drug record is null or undefined');
    return { errors, warnings };
  }

  const brand = (drug.brand_name || '').trim();
  const generic = (drug.generic_name || '').trim();
  const activeIng = (drug.active_ingredient || '').trim();

  if (!generic) {
    errors.push('Missing generic_name');
  }

  // Invariant 1: Branded row should not have generic_name literally equal to a brand placeholder
  // (e.g. brand_name="mydayis", generic_name="mydayis")
  if (brand && generic && brand.toLowerCase() === generic.toLowerCase()) {
    errors.push(`Branded drug "${brand}" has generic_name identical to brand_name ("${generic}")`);
  }

  // Invariant 2: Ingredient-count parity between generic_name and RxNorm active_ingredient
  const genericIngs = parseExpectedIngredients(generic);
  const rxIngs = parseExpectedIngredients(activeIng);
  const bothMixedAmp = isMixedAmphetamineList(genericIngs) && isMixedAmphetamineList(rxIngs);

  if (genericIngs.length > 0 && rxIngs.length > 0 && !bothMixedAmp) {
    if (genericIngs.length !== rxIngs.length) {
      errors.push(
        `Ingredient-count mismatch: generic_name "${generic}" has ${genericIngs.length} ingredient(s) [${genericIngs.join(', ')}] ` +
        `but RxNorm active_ingredient "${activeIng}" has ${rxIngs.length} [${rxIngs.join(', ')}]`
      );
    }
  }

  // Invariant 3: Single-ingredient drugs must NEVER carry multi-ingredient "a / b" strength tokens
  const canonicalCount = rxIngs.length > 0 ? rxIngs.length : genericIngs.length;
  if (canonicalCount === 1 && !isMixedAmphetamineList(genericIngs)) {
    const comboTokens = findComboStrengthTokens(drug.strength);
    if (comboTokens.length > 0) {
      errors.push(
        `Single-ingredient drug "${brand || generic}" contains multi-ingredient strength token(s): ${comboTokens.join(', ')}`
      );
    }
  }

  // Invariant 4: CMS NADAC price sanity (generic NADAC > 2x brand NADAC indicates price/combo leakage)
  const nadacRows = (marketRows || []).filter(
    r => r.source === 'cms_nadac' && Number.isFinite(r.nadac_per_unit) && r.nadac_per_unit > 0
  );
  if (nadacRows.length > 0) {
    const genericPrices = nadacRows
      .filter(r => r.marketing_category === 'ANDA')
      .map(r => r.nadac_per_unit);
    const brandPrices = nadacRows
      .filter(r => r.marketing_category === 'NDA')
      .map(r => r.nadac_per_unit);

    if (genericPrices.length > 0 && brandPrices.length > 0) {
      const minGeneric = Math.min(...genericPrices);
      const maxBrand = Math.max(...brandPrices);
      if (minGeneric > maxBrand * 2) {
        warnings.push(
          `Suspicious NADAC ratio: min generic ($${minGeneric.toFixed(4)}) > 2x max brand ($${maxBrand.toFixed(4)})`
        );
      }
    }
  }

  return { errors, warnings };
}

/**
 * Audit every drug in a SQLite database against universal clinical invariants.
 */
function auditDatabase(db) {
  const drugs = db.prepare('SELECT * FROM drugs ORDER BY COALESCE(brand_name, generic_name) ASC').all();
  const getMarket = db.prepare('SELECT source, marketing_category, nadac_per_unit, package_description FROM market_availability WHERE drug_id = ?');

  const findings = [];
  const brandSeen = new Map();
  let errorCount = 0;
  let warningCount = 0;

  for (const drug of drugs) {
    const marketRows = getMarket.all(drug.id);
    const { errors, warnings } = auditDrugRecord(drug, { marketRows });

    // Cross-row invariant: duplicate case-insensitive brand_name
    if (drug.brand_name) {
      const key = drug.brand_name.trim().toLowerCase();
      if (brandSeen.has(key)) {
        errors.push(`Duplicate brand_name "${drug.brand_name}" (also on rxcui ${brandSeen.get(key)})`);
      } else {
        brandSeen.set(key, drug.rxcui);
      }
    }

    if (errors.length > 0 || warnings.length > 0) {
      errorCount += errors.length;
      warningCount += warnings.length;
      findings.push({
        id: drug.id,
        rxcui: drug.rxcui,
        brand_name: drug.brand_name,
        generic_name: drug.generic_name,
        active_ingredient: drug.active_ingredient,
        strength: drug.strength,
        errors,
        warnings,
      });
    }
  }

  return {
    totalDrugs: drugs.length,
    errorCount,
    warningCount,
    findings,
  };
}

module.exports = {
  auditDrugRecord,
  auditDatabase,
  findComboStrengthTokens,
};
