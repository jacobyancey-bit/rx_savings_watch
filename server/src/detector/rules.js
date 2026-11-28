/**
 * Detection Rules & Signal Evaluators for Commercial Generic Launches
 */

/**
 * Evaluate Signal 1: Regulatory Approval
 * Check whether FDA has approved a generic ANDA (Orange Book) or biosimilar/interchangeable BLA (Purple Book)
 * 
 * @param {Array<object>} genericStatuses List of generic_status rows for a drug
 * @param {string} [asOfDate] Optional ISO date string (YYYY-MM-DD) for historical backtest
 * @returns {{ satisfied: boolean, signal: object|null }}
 */
function evaluateRegulatorySignal(genericStatuses, asOfDate) {
  const cutoff = asOfDate || new Date().toISOString().split('T')[0];

  // Filter for approved generics on or before the cutoff date
  const approved = genericStatuses.filter(gs => {
    if (!gs.is_approved_generic) return false;
    if (!gs.approval_date) return false;
    return gs.approval_date <= cutoff;
  });

  if (approved.length === 0) {
    return { satisfied: false, signal: null };
  }

  // Pick earliest approval among approved generics
  approved.sort((a, b) => a.approval_date.localeCompare(b.approval_date));
  const earliest = approved[0];

  return {
    satisfied: true,
    signal: {
      type: 'regulatory_approval',
      source: earliest.source,
      application_number: earliest.application_number,
      applicant: earliest.applicant,
      approval_date: earliest.approval_date,
      te_code: earliest.te_code || null,
      biosimilar_status: earliest.biosimilar_status || null,
      total_approved_applications: approved.length
    }
  };
}

/**
 * Evaluate Signal 2: Market Commercialization & Distribution
 * Check whether a generic NDC has entered active distribution via OpenFDA NDC start date or CMS NADAC pricing
 * 
 * @param {Array<object>} marketRows List of market_availability rows for a drug
 * @param {object} regulatorySignal Signal 1 details if available
 * @param {string} [asOfDate] Optional ISO date string (YYYY-MM-DD)
 * @returns {{ satisfied: boolean, signal: object|null }}
 */
function evaluateCommercialSignal(marketRows, regulatorySignal, asOfDate) {
  const cutoff = asOfDate || new Date().toISOString().split('T')[0];

  // Separate brand rows from generic candidate rows
  const genericCandidates = marketRows.filter(m => {
    if (!m.is_commercialized) return false;

    // Check if explicitly marked or named as brand
    const isBrand = m.marketing_category === 'NDA' ||
      m.labeler_name?.toLowerCase().includes('brand') ||
      m.package_description?.toLowerCase().includes('(brand)') ||
      m.package_description?.toLowerCase().includes('brand');

    if (isBrand) return false;

    // Generic rows: marketing_category is 'ANDA', 'AUTHORIZED_GENERIC', or BLA (biosimilar), or generic NADAC
    const isGenericCategory = m.marketing_category === 'ANDA' || 
      m.marketing_category === 'AUTHORIZED_GENERIC' ||
      (m.marketing_category === 'BLA' && regulatorySignal?.biosimilar_status);

    const hasGenericNadac = m.source === 'cms_nadac';

    return isGenericCategory || hasGenericNadac;
  });

  // Filter by cutoff date and exclude discontinued NDCs
  const activeGenerics = genericCandidates.filter(m => {
    const marketDate = m.marketing_start_date || m.nadac_effective_date;
    if (!marketDate) return false;
    if (marketDate > cutoff) return false;
    // Exclude discontinued products whose marketing ended before cutoff
    if (m.marketing_end_date && m.marketing_end_date < cutoff) return false;
    return true;
  });

  if (activeGenerics.length === 0) {
    return { satisfied: false, signal: null };
  }

  // Find earliest commercial date and available pricing on or before cutoff
  let earliestCommercialDate = null;
  let firstNdc = null;
  let latestNadacPrice = null;
  let pricingUnit = null;

  for (const item of activeGenerics) {
    const d = item.marketing_start_date || item.nadac_effective_date;
    if (!earliestCommercialDate || d < earliestCommercialDate) {
      earliestCommercialDate = d;
      firstNdc = item.ndc;
    }
    if (item.nadac_per_unit && item.nadac_effective_date && item.nadac_effective_date <= cutoff) {
      latestNadacPrice = item.nadac_per_unit;
      pricingUnit = item.pricing_unit;
    }
  }

  return {
    satisfied: true,
    signal: {
      type: 'commercial_distribution',
      earliest_commercial_date: earliestCommercialDate,
      first_commercial_ndc: firstNdc,
      nadac_per_unit: latestNadacPrice,
      pricing_unit: pricingUnit,
      sources: [...new Set(activeGenerics.map(g => g.source))],
      active_generic_ndcs_count: activeGenerics.length
    }
  };
}

/**
 * Shared brand-row classifier for NADAC / NDC market rows.
 * @param {object} m market_availability row
 * @param {string|null} [brandName]
 */
function isBrandMarketRow(m, brandName = null) {
  const desc = (m.package_description || '').toLowerCase();
  const labeler = (m.labeler_name || '').toLowerCase();
  const brandLower = brandName ? String(brandName).toLowerCase() : null;
  return m.marketing_category === 'NDA' ||
    desc.includes('(brand)') ||
    labeler.includes('brand') ||
    Boolean(brandLower && desc.startsWith(brandLower));
}

/**
 * Extract a comparable strength + form key from a NADAC / NDC package description,
 * e.g. "LIPITOR 10 MG TABLET (Brand)" and "ATORVASTATIN CALCIUM 10 MG TABLET" -> "10mg|tab".
 * Returns null when no strength can be parsed (such rows are never compared).
 * @param {string} description
 */
function strengthFormKey(description) {
  const desc = String(description || '').toUpperCase().replace(/\(BRAND\)/g, ' ');
  const m = desc.match(/(\d+(?:\.\d+)?)\s*(MG|MCG|UNIT|UNITS|%|G)\b(\s*\/\s*(\d+(?:\.\d+)?)?\s*(ML|ACTUAT|G))?/);
  if (!m) return null;
  let value = Number.parseFloat(m[1]);
  let unit = m[2];
  if (unit === 'MCG') { value = value / 1000; unit = 'MG'; }
  if (unit === 'UNITS') unit = 'UNIT';
  const per = m[3] ? `/${m[4] || '1'}${m[5]}` : '';
  let form = /\b(ER|XR|XL|SR|CR|ER24|EXTENDED|24HR|12HR)\b/.test(desc) ? 'er-' : '';
  if (/TABLET|\bTAB\b/.test(desc)) form += 'tab';
  else if (/CAPSULE|\bCAP\b/.test(desc)) form += 'cap';
  else if (/SOLUTION|SUSP|SYRUP|ELIXIR/.test(desc)) form += 'liq';
  else if (/INHAL|AEROSOL|DISKUS|ELLIPTA|HANDIHALER|RESPIMAT/.test(desc)) form += 'inh';
  else if (/SYRINGE|VIAL|PEN|INJ|AUTOINJ|CARTRIDGE/.test(desc)) form += 'inj';
  else form += 'other';
  return `${Number(value.toFixed(6))}${unit}${per}|${form}`;
}

/**
 * Strength-matched brand vs generic NADAC comparison.
 * Only compares brand and generic rows that share the SAME strength, dosage form and
 * NADAC pricing unit, so e.g. a 80 mg brand tablet is never compared against a 10 mg generic.
 * When several strengths match, the most conservative (lowest) savings figure is reported.
 *
 * @param {Array<object>} marketRows
 * @param {object} [options]
 * @param {string|null} [options.brandName]
 * @param {(row: object) => boolean} [options.isBrand] custom brand classifier
 * @param {(row: object) => boolean} [options.isGeneric] custom generic classifier
 * @returns {{ brandPrice: number|null, genericPrice: number|null, savingsPct: number|null, matchedKey: string|null, priceAnomaly: boolean }}
 */
function calculateMatchedSavings(marketRows, options = {}) {
  const isBrand = options.isBrand || ((m) => isBrandMarketRow(m, options.brandName || null));
  const isGeneric = options.isGeneric || ((m) => !isBrand(m));
  const priced = (marketRows || []).filter(m => Number(m.nadac_per_unit) > 0);

  const brandByKey = new Map();
  const genericByKey = new Map();
  for (const m of priced) {
    const key = strengthFormKey(m.package_description);
    if (!key) continue;
    const fullKey = `${key}|${(m.pricing_unit || 'EA').toUpperCase()}`;
    const price = Number(m.nadac_per_unit);
    const target = isBrand(m) ? brandByKey : (isGeneric(m) ? genericByKey : null);
    if (!target) continue;
    // Keep the lowest observed price per strength (most representative pharmacy acquisition cost)
    if (!target.has(fullKey) || price < target.get(fullKey)) target.set(fullKey, price);
  }

  let best = null;
  for (const [key, brandPrice] of brandByKey) {
    const genericPrice = genericByKey.get(key);
    if (genericPrice === undefined || brandPrice <= 0) continue;
    const pct = ((brandPrice - genericPrice) / brandPrice) * 100;
    if (best === null || pct < best.pct) best = { key, brandPrice, genericPrice, pct };
  }

  if (!best) {
    return { brandPrice: null, genericPrice: null, savingsPct: null, matchedKey: null, priceAnomaly: false };
  }
  return {
    brandPrice: best.brandPrice,
    genericPrice: best.genericPrice,
    savingsPct: Math.max(0, Number(best.pct.toFixed(1))),
    matchedKey: best.key,
    priceAnomaly: best.genericPrice > best.brandPrice,
  };
}

/**
 * Calculate Brand vs Generic Savings Percentage (strength-matched).
 * @param {Array<object>} marketRows
 * @param {number|null} genericPrice Kept for backwards compatibility; matched generic price is used instead.
 * @returns {{ brandPrice: number|null, savingsPct: number|null, priceAnomaly: boolean }}
 */
function calculateSavings(marketRows, genericPrice) {
  if (!genericPrice || genericPrice <= 0) return { brandPrice: null, savingsPct: null, priceAnomaly: false };
  const matched = calculateMatchedSavings(marketRows);
  return {
    brandPrice: matched.brandPrice,
    savingsPct: matched.savingsPct,
    priceAnomaly: matched.priceAnomaly,
  };
}

/**
 * Evaluate pharmacist auto-substitution eligibility based on FDA Orange Book TE codes
 * and FDA Purple Book interchangeable biologic designations.
 *
 * @param {Array<object>} genericStatuses
 * @param {string} drugType 'small_molecule' | 'biologic'
 * @returns {{ substitution_status: string, te_code: string|null, biosimilar_status: string|null }}
 */
function evaluateSubstitutionStatus(genericStatuses, drugType = 'small_molecule') {
  const approved = (genericStatuses || []).filter(gs => gs.is_approved_generic);
  if (approved.length === 0) {
    return { substitution_status: 'brand_only', te_code: null, biosimilar_status: null };
  }

  if (drugType === 'biologic') {
    const interchangeable = approved.find(gs => gs.biosimilar_status === 'interchangeable');
    if (interchangeable) {
      return {
        substitution_status: 'auto_substitutable',
        te_code: null,
        biosimilar_status: 'interchangeable'
      };
    }
    return {
      substitution_status: 'doctor_prescription_required',
      te_code: null,
      biosimilar_status: approved[0].biosimilar_status || 'biosimilar'
    };
  }

  // Small molecule: FDA Orange Book 'A'-rated (AB, AA, AP, etc.) is therapeutically equivalent
  const aRated = approved.find(gs => gs.te_code && gs.te_code.toUpperCase().startsWith('A'));
  if (aRated) {
    return {
      substitution_status: 'auto_substitutable',
      te_code: aRated.te_code.toUpperCase(),
      biosimilar_status: null
    };
  }

  return {
    substitution_status: 'doctor_prescription_required',
    te_code: approved[0].te_code ? approved[0].te_code.toUpperCase() : null,
    biosimilar_status: null
  };
}

module.exports = {
  evaluateRegulatorySignal,
  evaluateCommercialSignal,
  calculateSavings,
  calculateMatchedSavings,
  strengthFormKey,
  isBrandMarketRow,
  evaluateSubstitutionStatus
};
