const express = require('express');

/**
 * Drug details and lookup router
 * @param {import('node:sqlite').DatabaseSync} db
 * @returns {express.Router}
 */
function createDrugsRouter(db) {
  const router = express.Router();

  const getDrugByRxcui = db.prepare('SELECT * FROM drugs WHERE rxcui = ?');
  const getAllDrugs = db.prepare('SELECT * FROM drugs ORDER BY brand_name ASC');
  const getGenericStatus = db.prepare('SELECT * FROM generic_status WHERE drug_id = ?');
  const getMarket = db.prepare('SELECT * FROM market_availability WHERE drug_id = ?');
  const getShortages = db.prepare('SELECT * FROM drug_shortages WHERE drug_id = ?');
  const getAlerts = db.prepare('SELECT * FROM alert_events WHERE drug_id = ? ORDER BY detected_at DESC');

  router.get('/drugs', (req, res) => {
    const drugs = getAllDrugs.all();
    res.json({ count: drugs.length, drugs });
  });

  router.get('/drugs/:rxcui', (req, res) => {
    const drug = getDrugByRxcui.get(req.params.rxcui);
    if (!drug) {
      return res.status(404).json({ error: 'Drug not found' });
    }

    const genericStatus = getGenericStatus.all(drug.id);
    const market = getMarket.all(drug.id);
    const shortages = getShortages.all(drug.id);
    const alerts = getAlerts.all(drug.id).map(a => ({
      ...a,
      signal_details: JSON.parse(a.signal_details)
    }));

    res.json({
      ...drug,
      generic_status: genericStatus,
      market_availability: market,
      shortages,
      alerts
    });
  });

  return router;
}

module.exports = {
  createDrugsRouter
};
