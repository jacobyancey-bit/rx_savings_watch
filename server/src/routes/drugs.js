const express = require('express');
const config = require('../config');
const { discoverAndIngestDrug } = require('../ingestion/live_feeds');
const {
  getVerifiedPartnersForDrug,
  getConfiguredDiscountCard,
  getBrandAssistanceForDrug,
} = require('../services/partnerResolver');

const RXCUI_PATTERN = /^\d{1,12}$/;
const ALLOWED_FLAG_TYPES = new Set([
  'missing_dosage',
  'generic_available',
  'brand_only_now',
  'price_looks_off',
  'shortage_incorrect',
]);
const NEGATIVE_CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes
const MAX_CACHE_ENTRIES = 500;

function escapeLike(str) {
  return str.replace(/[\\%_]/g, '\\$&');
}

/**
 * Drug details and lookup router with search, pagination, and abuse-protected live discovery
 * @param {import('node:sqlite').DatabaseSync} db
 * @returns {express.Router}
 */
function createDrugsRouter(db) {
  const router = express.Router();

  // Bounded in-memory caches to prevent outbound API flooding & duplicate concurrent lookups
  const negativeCache = new Map(); // queryLower -> expiresAtMs
  const inFlightLookups = new Map(); // queryLower -> Promise<object|null>
  const ipDiscoveryBuckets = new Map(); // ip -> { count, resetAt }
  const ipFlagBuckets = new Map(); // ip -> { count, resetAt }
  const FLAG_MAX_PER_IP = 10;

  function canSubmitFlagForIp(ip) {
    const now = Date.now();
    if (ipFlagBuckets.size > MAX_CACHE_ENTRIES) {
      for (const [k, v] of ipFlagBuckets) {
        if (v.resetAt <= now) ipFlagBuckets.delete(k);
      }
    }
    const bucket = ipFlagBuckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      ipFlagBuckets.set(ip, { count: 1, resetAt: now + config.RATE_LIMIT_WINDOW_MS });
      return true;
    }
    if (bucket.count >= FLAG_MAX_PER_IP) return false;
    bucket.count++;
    return true;
  }

  function canRunLiveDiscoveryForIp(ip) {
    const now = Date.now();
    if (ipDiscoveryBuckets.size > MAX_CACHE_ENTRIES) {
      for (const [k, v] of ipDiscoveryBuckets) {
        if (v.resetAt <= now) ipDiscoveryBuckets.delete(k);
      }
    }
    const bucket = ipDiscoveryBuckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      ipDiscoveryBuckets.set(ip, { count: 1, resetAt: now + config.RATE_LIMIT_WINDOW_MS });
      return true;
    }
    if (bucket.count >= config.LIVE_DISCOVERY_MAX_PER_IP) {
      return false;
    }
    bucket.count++;
    return true;
  }

  const getDrugByRxcui = db.prepare('SELECT * FROM drugs WHERE rxcui = ?');
  const getGenericStatus = db.prepare('SELECT * FROM generic_status WHERE drug_id = ?');
  const getMarket = db.prepare('SELECT * FROM market_availability WHERE drug_id = ?');
  const getShortages = db.prepare('SELECT * FROM drug_shortages WHERE drug_id = ?');
  const getAlerts = db.prepare('SELECT * FROM alert_events WHERE drug_id = ? ORDER BY detected_at DESC');

  const searchDrugsStmt = db.prepare(`
    SELECT * FROM drugs 
    WHERE brand_name LIKE ? ESCAPE '\\'
       OR generic_name LIKE ? ESCAPE '\\'
       OR rxcui LIKE ? ESCAPE '\\'
    ORDER BY LOWER(COALESCE(NULLIF(TRIM(brand_name), ''), generic_name)) ASC
    LIMIT ? OFFSET ?
  `);

  const countSearchDrugsStmt = db.prepare(`
    SELECT count(*) as total FROM drugs 
    WHERE brand_name LIKE ? ESCAPE '\\'
       OR generic_name LIKE ? ESCAPE '\\'
       OR rxcui LIKE ? ESCAPE '\\'
  `);

  router.get('/drugs', async (req, res) => {
    const query = req.query.q ? String(req.query.q).trim().slice(0, 80) : '';
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 500);
    const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
    const allowLive = req.query.live !== 'false' && process.env.NODE_ENV !== 'test';

    const pattern = `%${escapeLike(query)}%`;
    let drugs = searchDrugsStmt.all(pattern, pattern, pattern, limit, offset);
    let totalCount = countSearchDrugsStmt.get(pattern, pattern, pattern).total;
    let discoveredLive = false;

    // On-demand canonical federal cross-reference with negative-caching & per-IP abuse cap
    const queryKey = query.toLowerCase();
    const negExpires = negativeCache.get(queryKey);
    const isNegativelyCached = negExpires !== undefined && negExpires > Date.now();

    if (drugs.length === 0 && query.length >= 3 && offset === 0 && allowLive && !isNegativelyCached) {
      const clientIp = req.ip || 'unknown';
      if (canRunLiveDiscoveryForIp(clientIp)) {
        try {
          let lookupPromise = inFlightLookups.get(queryKey);
          if (!lookupPromise) {
            lookupPromise = discoverAndIngestDrug(db, query).finally(() => {
              inFlightLookups.delete(queryKey);
            });
            inFlightLookups.set(queryKey, lookupPromise);
          }

          const discovered = await lookupPromise;
          if (discovered) {
            discoveredLive = true;
            drugs = [discovered];
            totalCount = 1;
          } else {
            if (negativeCache.size >= MAX_CACHE_ENTRIES) {
              negativeCache.clear();
            }
            negativeCache.set(queryKey, Date.now() + NEGATIVE_CACHE_TTL_MS);
          }
        } catch (err) {
          console.error('[DrugsRouter] Live discovery error:', err.message);
        }
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
    const rxcui = String(req.params.rxcui || '').trim();
    if (!RXCUI_PATTERN.test(rxcui)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid RxCUI format.' });
    }

    const drug = getDrugByRxcui.get(rxcui);
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

  // Zero-PII anonymous data quality flag endpoint (strict enum, no free-text)
  const insertFlagStmt = db.prepare(`
    INSERT INTO data_flags (drug_id, rxcui, issue_type)
    VALUES (?, ?, ?)
  `);

  router.post('/drugs/:rxcui/flag', (req, res) => {
    const clientIp = req.ip || 'unknown';
    if (!canSubmitFlagForIp(clientIp)) {
      return res.status(429).json({
        error: 'Too Many Requests',
        message: 'Too many data flags submitted. Please try again later.'
      });
    }

    const rxcui = String(req.params.rxcui || '').trim();
    if (!RXCUI_PATTERN.test(rxcui)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid RxCUI format.' });
    }

    const issueType = String(req.body?.issue_type || '').trim();
    if (!ALLOWED_FLAG_TYPES.has(issueType)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid issue_type.' });
    }

    const drug = getDrugByRxcui.get(rxcui);
    if (!drug) {
      return res.status(404).json({ error: 'Drug not found' });
    }

    insertFlagStmt.run(drug.id, rxcui, issueType);

    // Self-healing: if user flagged missing dosage, generic availability, or false-positive brand-only, trigger background refresh
    if (
      (issueType === 'missing_dosage' || issueType === 'generic_available' || issueType === 'brand_only_now') &&
      process.env.NODE_ENV !== 'test'
    ) {
      const clientIp = req.ip || 'unknown';
      if (canRunLiveDiscoveryForIp(clientIp)) {
        discoverAndIngestDrug(db, drug.brand_name || drug.generic_name, { forceRefresh: true, rxcui: drug.rxcui })
          .catch(err => console.error('[DrugsRouter] Flag-triggered refresh error:', err.message));
      }
    }

    res.status(201).json({
      success: true,
      message: 'Thank you. Flag recorded anonymously with zero personal data.'
    });
  });

  // Verified Cash & Discount Pharmacy Links + Optional PBM Card + Brand Patient Assistance
  router.get('/drugs/:rxcui/partners', async (req, res) => {
    const rxcui = String(req.params.rxcui || '').trim();
    if (!RXCUI_PATTERN.test(rxcui)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Invalid RxCUI format.' });
    }

    const drug = getDrugByRxcui.get(rxcui);
    if (!drug) {
      return res.status(404).json({ error: 'Drug not found' });
    }

    const hasGenericApproved = db.prepare(
      'SELECT 1 FROM generic_status WHERE drug_id = ? AND is_approved_generic = 1 LIMIT 1'
    ).get(drug.id) != null;

    const discountCard = getConfiguredDiscountCard();
    const brandAssistance = getBrandAssistanceForDrug(drug, hasGenericApproved);

    try {
      const partners = await getVerifiedPartnersForDrug(db, drug);
      res.json({
        rxcui,
        partners,
        discount_card: discountCard,
        brand_assistance: brandAssistance,
      });
    } catch (err) {
      console.error('[DrugsRouter] Partner resolution error:', err.message);
      res.json({
        rxcui,
        partners: [],
        discount_card: discountCard,
        brand_assistance: brandAssistance,
      });
    }
  });

  return router;
}

module.exports = {
  createDrugsRouter
};
