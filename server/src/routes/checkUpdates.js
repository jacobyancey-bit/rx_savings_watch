const express = require('express');
const config = require('../config');

/**
 * Anonymous Check Updates Endpoint
 * Privacy-first: No user ID, account, IP logging, or PII tracked or stored.
 * 
 * @param {import('node:sqlite').DatabaseSync} db
 * @returns {express.Router}
 */
function createCheckUpdatesRouter(db) {
  const router = express.Router();

  const getDrugByRxcui = db.prepare('SELECT * FROM drugs WHERE rxcui = ?');
  const getAlertsForDrug = db.prepare(`
    SELECT * FROM alert_events 
    WHERE drug_id = ? AND detected_at > ?
    ORDER BY detected_at DESC
  `);
  const getAllAlertsForDrug = db.prepare(`
    SELECT * FROM alert_events 
    WHERE drug_id = ?
    ORDER BY detected_at DESC
  `);
  const getGenericStatusForDrug = db.prepare(`
    SELECT * FROM generic_status 
    WHERE drug_id = ? AND is_approved_generic = 1
  `);
  const getMarketForDrug = db.prepare(`
    SELECT * FROM market_availability 
    WHERE drug_id = ?
  `);
  const getShortagesForDrug = db.prepare(`
    SELECT * FROM drug_shortages 
    WHERE drug_id = ? AND status = 'Current'
  `);

  router.post('/check-updates', (req, res) => {
    const { rxcuis, last_checked } = req.body || {};

    // 1. Strict Validation: Array of strings
    if (!Array.isArray(rxcuis) || rxcuis.length === 0) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Must provide an array of rxcuis to check for updates.'
      });
    }

    // 2. Strict Bounds Checking: Max RXCUIs to prevent memory exhaustion
    if (rxcuis.length > config.MAX_RXCUIS_PER_CHECK) {
      return res.status(400).json({
        error: 'Bad Request',
        message: `Maximum allowed rxcuis per check is ${config.MAX_RXCUIS_PER_CHECK}.`
      });
    }

    // 3. Validate each item is a clean string/number
    for (const rxcui of rxcuis) {
      if (typeof rxcui !== 'string' && typeof rxcui !== 'number') {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'Each rxcui must be a string or number.'
        });
      }
    }

    // 4. Validate last_checked timestamp if provided
    let lastCheckedDate = '1970-01-01T00:00:00Z';
    if (last_checked) {
      if (typeof last_checked !== 'string' || isNaN(Date.parse(last_checked))) {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'last_checked must be a valid ISO-8601 date string.'
        });
      }
      lastCheckedDate = last_checked;
    }

    const checkedAt = new Date().toISOString();
    const results = [];
    let totalUpdatesFound = 0;

    for (const rxcui of rxcuis) {
      const drug = getDrugByRxcui.get(rxcui.toString());
      if (!drug) {
        continue;
      }

      const alertsSince = getAlertsForDrug.all(drug.id, lastCheckedDate);
      const allAlerts = getAllAlertsForDrug.all(drug.id);
      const genericRows = getGenericStatusForDrug.all(drug.id);
      const marketRows = getMarketForDrug.all(drug.id);
      const activeShortages = getShortagesForDrug.all(drug.id);

      const hasApprovedGeneric = genericRows.length > 0;
      const brandNameLower = drug.brand_name?.toLowerCase();

      const isBrandRow = (m) => {
        const desc = m.package_description?.toLowerCase() || '';
        const labeler = m.labeler_name?.toLowerCase() || '';
        return m.marketing_category === 'NDA' ||
               desc.includes('(brand)') ||
               desc.includes('brand') ||
               labeler.includes('brand') ||
               (brandNameLower && desc.startsWith(brandNameLower));
      };

      const genericMarketRows = marketRows.filter(m => 
        m.is_commercialized && !isBrandRow(m) && (
          m.marketing_category === 'ANDA' || 
          (m.marketing_category === 'BLA' && drug.drug_type === 'biologic') ||
          m.source === 'cms_nadac'
        )
      );

      const commercialGenericAvailable = hasApprovedGeneric && genericMarketRows.length > 0;

      // Calculate latest generic and brand prices
      let latestGenericPrice = null;
      let brandPrice = null;

      for (const m of marketRows) {
        if (m.nadac_per_unit) {
          if (isBrandRow(m)) {
            brandPrice = m.nadac_per_unit;
          } else {
            latestGenericPrice = m.nadac_per_unit;
          }
        }
      }

      let estimatedSavingsPct = null;
      if (brandPrice && latestGenericPrice && brandPrice > 0) {
        estimatedSavingsPct = Number((((brandPrice - latestGenericPrice) / brandPrice) * 100).toFixed(1));
      }

      const formattedAlerts = alertsSince.map(a => ({
        id: a.id,
        event_type: a.event_type,
        signal_summary: a.signal_summary,
        details: JSON.parse(a.signal_details),
        confidence_score: a.confidence_score,
        detected_at: a.detected_at
      }));

      totalUpdatesFound += formattedAlerts.length;

      results.push({
        rxcui: drug.rxcui,
        brand_name: drug.brand_name,
        generic_name: drug.generic_name,
        drug_type: drug.drug_type,
        dosage_form: drug.dosage_form,
        strength: drug.strength,
        has_approved_generic: hasApprovedGeneric,
        commercial_generic_available: commercialGenericAvailable,
        generic_manufacturers_count: genericRows.length,
        pricing: {
          brand_nadac_unit_price: brandPrice,
          generic_nadac_unit_price: latestGenericPrice,
          estimated_savings_pct: estimatedSavingsPct
        },
        has_active_shortage: activeShortages.length > 0,
        active_shortage_details: activeShortages.map(s => ({
          status: s.status,
          reason: s.reason,
          start_date: s.shortage_start_date
        })),
        new_alerts_count: formattedAlerts.length,
        alerts: formattedAlerts,
        total_historical_alerts_count: allAlerts.length
      });
    }

    return res.json({
      success: true,
      checked_at: checkedAt,
      updates_found: totalUpdatesFound,
      drugs: results
    });
  });

  return router;
}

module.exports = {
  createCheckUpdatesRouter
};
