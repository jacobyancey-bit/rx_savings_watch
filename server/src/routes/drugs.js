const express = require('express');
const { discoverAndIngestDrug } = require('../ingestion/live_feeds');

/**
 * Drug details and lookup router with search and pagination
 * @param {import('node:sqlite').DatabaseSync} db
 * @returns {express.Router}
 */
function createDrugsRouter(db) {
  const router = express.Router();

  const getDrugByRxcui = db.prepare('SELECT * FROM drugs WHERE rxcui = ?');
  const getGenericStatus = db.prepare('SELECT * FROM generic_status WHERE drug_id = ?');
  const getMarket = db.prepare('SELECT * FROM market_availability WHERE drug_id = ?');
  const getShortages = db.prepare('SELECT * FROM drug_shortages WHERE drug_id = ?');
  const getAlerts = db.prepare('SELECT * FROM alert_events WHERE drug_id = ? ORDER BY detected_at DESC');

  const searchDrugsStmt = db.prepare(`
    SELECT * FROM drugs 
    WHERE brand_name LIKE ? OR generic_name LIKE ? OR rxcui LIKE ?
    ORDER BY brand_name ASC
    LIMIT ? OFFSET ?
  `);

  const countSearchDrugsStmt = db.prepare(`
    SELECT count(*) as total FROM drugs 
    WHERE brand_name LIKE ? OR generic_name LIKE ? OR rxcui LIKE ?
  `);

  router.get('/drugs', async (req, res) => {
    const query = req.query.q ? String(req.query.q).trim() : '';
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
    const allowLive = req.query.live !== 'false' && process.env.NODE_ENV !== 'test';

    const pattern = `%${query}%`;
    let drugs = searchDrugsStmt.all(pattern, pattern, pattern, limit, offset);
    let totalCount = countSearchDrugsStmt.get(pattern, pattern, pattern).total;
    let discoveredLive = false;

    // On-demand canonical federal cross-reference when a medication isn't in the local DB yet
    if (drugs.length === 0 && query.length >= 3 && offset === 0 && allowLive) {
      try {
        const discovered = await discoverAndIngestDrug(db, query);
        if (discovered) {
          discoveredLive = true;
          drugs = [discovered];
          totalCount = 1;
        }
      } catch (err) {
        console.error('[DrugsRouter] Live discovery error:', err.message);
      }
    }

    res.json({
      query,
      count: drugs.length,
      total: totalCount,
      limit,
      offset,
      discovered_live: discoveredLive,
      drugs
    });
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
