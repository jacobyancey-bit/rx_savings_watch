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

    // Generic rows: marketing_category is 'ANDA', or BLA (biosimilar), or generic NADAC
    const isGenericCategory = m.marketing_category === 'ANDA' || 
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
 * Calculate Brand vs Generic Savings Percentage
 * @param {Array<object>} marketRows
 * @param {number|null} genericPrice
 * @returns {{ brandPrice: number|null, savingsPct: number|null }}
 */
function calculateSavings(marketRows, genericPrice) {
  if (!genericPrice || genericPrice <= 0) return { brandPrice: null, savingsPct: null, priceAnomaly: false };

  // Find brand NADAC price
  const brandRow = marketRows.find(m => 
    m.nadac_per_unit && m.nadac_per_unit > 0 && (
      m.marketing_category === 'NDA' ||
      m.labeler_name?.toLowerCase().includes('brand') ||
      m.package_description?.toLowerCase().includes('brand')
    )
  );

  if (!brandRow || !brandRow.nadac_per_unit || brandRow.nadac_per_unit <= 0) {
    return { brandPrice: null, savingsPct: null, priceAnomaly: false };
  }

  const brandPrice = brandRow.nadac_per_unit;
  const priceAnomaly = genericPrice > brandPrice;
  const savingsPct = Number((((brandPrice - genericPrice) / brandPrice) * 100).toFixed(1));

  return {
    brandPrice,
    savingsPct: Math.max(0, savingsPct),
    priceAnomaly
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
  evaluateSubstitutionStatus
};
