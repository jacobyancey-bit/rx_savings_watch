const { ingestRxNorm } = require('./rxnorm');
const { ingestOrangeBook } = require('./orange_book');
const { ingestPurpleBook } = require('./purple_book');
const { ingestOpenFdaNdc } = require('./openfda_ndc');
const { ingestCmsNadac } = require('./cms_nadac');
const { ingestFdaShortages } = require('./fda_shortages');

/**
 * Record an ingestion run in the ingestion_runs audit table (if present).
 */
function recordIngestionRun(db, { feedName, status, recordsProcessed = 0, anomaliesRejected = 0, notes = null }) {
  try {
    const stmt = db.prepare(`
      INSERT INTO ingestion_runs (feed_name, status, records_processed, anomalies_rejected, source_date, notes, completed_at)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
    `);
    const today = new Date().toISOString().split('T')[0];
    stmt.run(feedName, status, recordsProcessed, anomaliesRejected, today, notes);
  } catch (_) {
    // Gracefully skip if running against a minimal test schema without ingestion_runs
  }
}

/**
 * Query latest successful ingestion timestamps across feeds for freshness provenance.
 */
function getDataFreshness(db) {
  try {
    const rows = db.prepare(`
      SELECT feed_name, MAX(completed_at) AS last_updated, SUM(records_processed) AS total_records
      FROM ingestion_runs
      WHERE status = 'success'
      GROUP BY feed_name
    `).all();

    const feeds = {};
    let latestTimestamp = null;
    for (const r of rows) {
      feeds[r.feed_name] = r.last_updated;
      if (!latestTimestamp || r.last_updated > latestTimestamp) {
        latestTimestamp = r.last_updated;
      }
    }

    const staleCutoffMs = 14 * 24 * 60 * 60 * 1000;
    const isStale = latestTimestamp
      ? (Date.now() - new Date(latestTimestamp.replace(' ', 'T') + 'Z').getTime()) > staleCutoffMs
      : false;

    return {
      last_verified_at: latestTimestamp,
      is_stale: isStale,
      feeds
    };
  } catch (_) {
    return { last_verified_at: null, is_stale: false, feeds: {} };
  }
}

async function runTrackedFeed(db, feedName, fn, feedOptions) {
  try {
    const res = await fn(db, feedOptions);
    const count = res?.inserted ?? res?.processed ?? 0;
    recordIngestionRun(db, { feedName, status: 'success', recordsProcessed: count });
    return res;
  } catch (err) {
    recordIngestionRun(db, { feedName, status: 'failed', notes: err.message });
    throw err;
  }
}

/**
 * Coordinate ingestion across all 6 feeds with provenance audit logging
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @returns {Promise<object>} Summary of ingested records per feed
 */
async function runAllIngestions(db, options = {}) {
  const results = {};

  results.rxnorm = await runTrackedFeed(db, 'rxnorm', ingestRxNorm, options.rxnorm);
  results.orange_book = await runTrackedFeed(db, 'orange_book', ingestOrangeBook, options.orange_book);
  results.purple_book = await runTrackedFeed(db, 'purple_book', ingestPurpleBook, options.purple_book);
  results.openfda_ndc = await runTrackedFeed(db, 'openfda_ndc', ingestOpenFdaNdc, options.openfda_ndc);
  results.cms_nadac = await runTrackedFeed(db, 'cms_nadac', ingestCmsNadac, options.cms_nadac);
  results.fda_shortages = await runTrackedFeed(db, 'fda_shortages', ingestFdaShortages, options.fda_shortages);

  return results;
}

module.exports = {
  runAllIngestions,
  getDataFreshness,
  recordIngestionRun,
  ingestRxNorm,
  ingestOrangeBook,
  ingestPurpleBook,
  ingestOpenFdaNdc,
  ingestCmsNadac,
  ingestFdaShortages
};
