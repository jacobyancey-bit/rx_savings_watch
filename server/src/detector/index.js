const { evaluateRegulatorySignal, evaluateCommercialSignal, calculateSavings } = require('./rules');

/**
 * 2-Signal Commercial Generic Launch Detector
 */
class GenericLaunchDetector {
  /**
   * @param {import('node:sqlite').DatabaseSync} db
   */
  constructor(db) {
    this.db = db;

    // Prepared statements
    this.getAllDrugsStmt = this.db.prepare('SELECT * FROM drugs');
    this.getDrugByIdStmt = this.db.prepare('SELECT * FROM drugs WHERE id = ?');
    this.getDrugByRxcuiStmt = this.db.prepare('SELECT * FROM drugs WHERE rxcui = ?');
    this.getGenericStatusStmt = this.db.prepare('SELECT * FROM generic_status WHERE drug_id = ?');
    this.getMarketAvailabilityStmt = this.db.prepare('SELECT * FROM market_availability WHERE drug_id = ?');
    this.getExistingAlertsStmt = this.db.prepare(`
      SELECT * FROM alert_events 
      WHERE drug_id = ? AND event_type = 'commercial_generic_launch'
    `);
    this.insertAlertStmt = this.db.prepare(`
      INSERT INTO alert_events (
        drug_id, event_type, signal_summary, signal_details, confidence_score, detected_at
      ) VALUES (
        ?, 'commercial_generic_launch', ?, ?, ?, ?
      )
    `);
  }

  /**
   * Evaluate a single drug for 2-signal commercial generic launch
   * 
   * @param {object} drug Drug record
   * @param {object} [options]
   * @param {string} [options.asOfDate] Simulated current date (YYYY-MM-DD)
   * @param {boolean} [options.persistAlert=true] Whether to save alert to alert_events table
   * @returns {object} Detection evaluation result
   */
  evaluateDrug(drug, options = {}) {
    const asOfDate = options.asOfDate || new Date().toISOString().split('T')[0];
    const persistAlert = options.persistAlert !== undefined ? options.persistAlert : true;

    // Fetch related records
    const genericStatuses = this.getGenericStatusStmt.all(drug.id);
    const marketRows = this.getMarketAvailabilityStmt.all(drug.id);

    // 1. Evaluate Signal 1: Regulatory Approval
    const regSignal = evaluateRegulatorySignal(genericStatuses, asOfDate);

    // 2. Evaluate Signal 2: Market Commercialization & Distribution
    const commSignal = evaluateCommercialSignal(marketRows, regSignal.signal, asOfDate);

    // Check if both signals are satisfied
    const launchDetected = regSignal.satisfied && commSignal.satisfied;

    let lagDays = null;
    let confidenceScore = 0.0;
    let savings = { brandPrice: null, savingsPct: null };
    let alertCreated = false;
    let signalSummary = null;

    if (launchDetected) {
      const approvalDate = regSignal.signal.approval_date;
      const commercialDate = commSignal.signal.earliest_commercial_date;

      // Calculate lag days between regulatory approval and actual market appearance
      const appMs = new Date(approvalDate).getTime();
      const commMs = new Date(commercialDate).getTime();
      lagDays = Math.max(0, Math.round((commMs - appMs) / (1000 * 60 * 60 * 24)));

      // Calculate potential savings if pricing exists
      savings = calculateSavings(marketRows, commSignal.signal.nadac_per_unit);

      // Determine confidence score:
      // 1.00 if verified by CMS NADAC pricing (actual pharmacy wholesale acquisition)
      // 0.92 if verified by OpenFDA active commercial distribution start date
      confidenceScore = commSignal.signal.sources.includes('cms_nadac') ? 1.00 : 0.92;

      const drugTypeLabel = drug.drug_type === 'biologic' ? 'biosimilar' : 'generic';
      signalSummary = `Confirmed commercial ${drugTypeLabel} launch for ${drug.brand_name || drug.generic_name}. ` +
        `Regulatory approval (${regSignal.signal.application_number}) on ${approvalDate}; ` +
        `market availability observed on ${commercialDate} (lag: ${lagDays} days).` +
        (savings.savingsPct !== null ? ` Estimated acquisition savings: ${savings.savingsPct}%.` : '');

      // Persist alert if requested and not already existing
      if (persistAlert) {
        const existingAlerts = this.getExistingAlertsStmt.all(drug.id);
        if (existingAlerts.length === 0) {
          const signalDetails = JSON.stringify({
            signal_1_regulatory: regSignal.signal,
            signal_2_commercial: commSignal.signal,
            lag_days: lagDays,
            brand_price: savings.brandPrice,
            generic_price: commSignal.signal.nadac_per_unit,
            savings_pct: savings.savingsPct,
            evaluation_as_of: asOfDate
          });

          this.insertAlertStmt.run(
            drug.id,
            signalSummary,
            signalDetails,
            confidenceScore,
            commercialDate
          );
          alertCreated = true;
        }
      }
    }

    return {
      rxcui: drug.rxcui,
      brand_name: drug.brand_name,
      generic_name: drug.generic_name,
      drug_type: drug.drug_type,
      launch_detected: launchDetected,
      signal_1_regulatory: regSignal,
      signal_2_commercial: commSignal,
      lag_days: lagDays,
      confidence_score: confidenceScore,
      savings,
      alert_created: alertCreated,
      summary: signalSummary || `No commercial generic launch detected as of ${asOfDate}.`
    };
  }

  /**
   * Run 2-signal detection across all drugs in the database
   * @param {object} [options]
   * @param {string} [options.asOfDate]
   * @param {boolean} [options.persistAlert=true]
   * @returns {Array<object>}
   */
  runAll(options = {}) {
    const drugs = this.getAllDrugsStmt.all();
    const results = [];

    for (const drug of drugs) {
      const res = this.evaluateDrug(drug, options);
      results.push(res);
    }

    return results;
  }
}

module.exports = {
  GenericLaunchDetector
};
