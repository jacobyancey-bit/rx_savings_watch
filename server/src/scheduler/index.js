const { runAllIngestions, ingestFdaShortages, ingestCmsNadac } = require('../ingestion');
const { discoverAndIngestDrug, ingestLiveShortages } = require('../ingestion/live_feeds');
const { GenericLaunchDetector } = require('../detector');
const { broadcastPublicAlert } = require('../services/webPush');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Ingestion Scheduler & Post-Ingestion Launch Detection Pipeline
 */
class IngestionScheduler {
  /**
   * @param {import('node:sqlite').DatabaseSync} db
   * @param {object} [options]
   * @param {number} [options.shortagesIntervalMs] Default: 24h (or test value)
   * @param {number} [options.nadacIntervalMs] Default: 7 days
   */
  constructor(db, options = {}) {
    this.db = db;
    this.detector = new GenericLaunchDetector(db);
    this.shortagesIntervalMs = options.shortagesIntervalMs || 24 * 60 * 60 * 1000;
    this.nadacIntervalMs = options.nadacIntervalMs || 7 * 24 * 60 * 60 * 1000;
    this.rollingAuditIntervalMs = options.rollingAuditIntervalMs || 6 * 60 * 60 * 1000;
    this.rollingAuditBatchSize = options.rollingAuditBatchSize || 50;
    
    this.timers = [];
    this.isRunning = false;
    this.isCycleRunning = false;
    this.lastSyncTimes = {
      shortages: null,
      nadac: null,
      full: null,
      rollingAudit: null
    };
  }

  /**
   * Run full ingestion across all 6 feeds and immediately trigger detector
   * @param {object} [ingestionOptions]
   * @returns {Promise<{ ingestion: object, detection: Array<object> }>}
   */
  async runFullCycle(ingestionOptions = {}) {
    if (this.isCycleRunning) {
      return { skipped: true, reason: 'Ingestion cycle already in progress' };
    }
    this.isCycleRunning = true;
    try {
      console.log(`[Scheduler ${new Date().toISOString()}] Starting full ingestion cycle...`);
      
      // 1. Ingest all feeds
      const ingestionResults = await runAllIngestions(this.db, ingestionOptions);
      this.lastSyncTimes.full = new Date().toISOString();

      // 2. Post-ingestion: Run 2-signal generic launch detector across all drugs
      console.log(`[Scheduler ${new Date().toISOString()}] Ingestion complete. Running 2-signal launch detector...`);
      const detectionResults = this.detector.runAll({ persistAlert: true });

      const newLaunches = detectionResults.filter(r => r.launch_detected && r.alert_created);
      console.log(`[Scheduler ${new Date().toISOString()}] Cycle finished. ${newLaunches.length} new commercial generic launch alerts created.`);

      // Broadcast anonymous public launch signals to Web Push subscribers (filtered locally on each device)
      if (process.env.NODE_ENV !== 'test') {
        for (const launch of newLaunches) {
          broadcastPublicAlert(this.db, {
            type: 'generic_launch',
            rxcui: launch.rxcui,
            brand_name: launch.brand_name || launch.generic_name,
            generic_name: launch.generic_name,
            savings_pct: launch.savings?.savingsPct ?? null,
          }).catch(err => console.error('[Scheduler] Web Push broadcast error:', err.message));
        }
      }

      return {
        ingestion: ingestionResults,
        detection: detectionResults,
        new_launches_count: newLaunches.length
      };
    } finally {
      this.isCycleRunning = false;
    }
  }

  /**
   * Run periodic shortages update
   */
  async runShortagesSync() {
    console.log(`[Scheduler ${new Date().toISOString()}] Syncing FDA Drug Shortages...`);
    try {
      const res = await ingestFdaShortages(this.db);
      this.lastSyncTimes.shortages = new Date().toISOString();
      return res;
    } catch (err) {
      console.error('[Scheduler] Error syncing shortages:', err);
      throw err;
    }
  }

  /**
   * Run periodic CMS NADAC pricing update followed by detector
   */
  async runNadacSync() {
    console.log(`[Scheduler ${new Date().toISOString()}] Syncing CMS NADAC acquisition pricing...`);
    try {
      const res = await ingestCmsNadac(this.db);
      this.lastSyncTimes.nadac = new Date().toISOString();

      // Trigger detector as new prices might confirm commercial generic launch
      const detectionResults = this.detector.runAll({ persistAlert: true });
      return {
        nadac: res,
        detection: detectionResults
      };
    } catch (err) {
      console.error('[Scheduler] Error syncing NADAC:', err);
      throw err;
    }
  }

  /**
   * Rolling Live Database Audit & Refresh Sweep:
   * Continuously cycles through the oldest-verified prescriptions in SQLite,
   * re-verifying each one against live FDA/RxNorm/CMS APIs, catching anomalies
   * before users ever report them, and broadcasting genuine new generic launches.
   */
  async runRollingLiveAudit(options = {}) {
    if (process.env.NODE_ENV === 'test') {
      return { skipped: true, reason: 'Disabled in offline test mode' };
    }
    if (this.isCycleRunning) {
      return { skipped: true, reason: 'Another ingestion cycle is already running' };
    }
    this.isCycleRunning = true;

    const batchSize = options.batchSize || this.rollingAuditBatchSize;
    const delayMs = options.delayMs ?? 500;
    let refreshed = 0;
    let newlyLaunched = 0;
    let anomaliesCorrected = 0;
    let errors = 0;

    try {
      const oldestDrugs = this.db.prepare(`
        SELECT id, rxcui, brand_name, generic_name, updated_at
        FROM drugs
        ORDER BY updated_at ASC
        LIMIT ?
      `).all(batchSize);

      if (oldestDrugs.length === 0) {
        return { refreshed: 0, newlyLaunched: 0, anomaliesCorrected: 0, errors: 0 };
      }

      console.log(`[Rolling Audit ${new Date().toISOString()}] Re-verifying ${oldestDrugs.length} oldest prescription(s) against live FDA/RxNorm/CMS feeds...`);

      for (let i = 0; i < oldestDrugs.length; i++) {
        const drug = oldestDrugs[i];
        const query = drug.brand_name || drug.generic_name;
        try {
          const beforeEval = this.detector.evaluateDrug(drug, { persistAlert: false });
          const updated = await discoverAndIngestDrug(this.db, query, { forceRefresh: true });
          if (updated) {
            refreshed++;
            const afterEval = this.detector.evaluateDrug(updated, { persistAlert: true });

            if (!beforeEval.launch_detected && afterEval.launch_detected) {
              newlyLaunched++;
              console.log(`[Rolling Audit] NEW commercial generic launch confirmed: ${updated.brand_name || updated.generic_name}`);
              broadcastPublicAlert(this.db, {
                type: 'generic_launch',
                rxcui: updated.rxcui,
                brand_name: updated.brand_name || updated.generic_name,
                generic_name: updated.generic_name,
                savings_pct: afterEval.savings?.savingsPct ?? null,
              }).catch(err => console.error('[Rolling Audit] Web Push error:', err.message));
            } else if (beforeEval.launch_detected && !afterEval.launch_detected) {
              anomaliesCorrected++;
              console.log(`[Rolling Audit] Self-corrected status to Brand Only: ${updated.brand_name || updated.generic_name}`);
            }
          }
        } catch (err) {
          errors++;
          console.error(`[Rolling Audit] Error verifying ${query}:`, err.message);
        }

        if (i < oldestDrugs.length - 1 && delayMs > 0) {
          await sleep(delayMs);
        }
      }

      // Also refresh live FDA Drug Shortages once per audit cycle
      await ingestLiveShortages(this.db).catch(err => {
        console.error('[Rolling Audit] Live shortages refresh error:', err.message);
      });

      this.lastSyncTimes.rollingAudit = new Date().toISOString();
      this.db.prepare(`
        INSERT INTO ingestion_runs (source, status, records_processed, anomalies_rejected, started_at, finished_at)
        VALUES ('rolling_live_audit', ?, ?, ?, datetime('now'), datetime('now'))
      `).run(errors === 0 ? 'success' : 'partial', refreshed, anomaliesCorrected);

      console.log(`[Rolling Audit] Complete: ${refreshed}/${oldestDrugs.length} refreshed, ${newlyLaunched} new launches, ${anomaliesCorrected} self-corrected, ${errors} errors.`);
      return { refreshed, newlyLaunched, anomaliesCorrected, errors };
    } finally {
      this.isCycleRunning = false;
    }
  }

  /**
   * Start the background scheduler daemon
   */
  start() {
    if (this.isRunning) return;
    this.isRunning = true;

    console.log(`[Scheduler] Daemon started. Shortages interval: ${this.shortagesIntervalMs}ms, NADAC interval: ${this.nadacIntervalMs}ms, Rolling live audit: ${this.rollingAuditIntervalMs}ms (${this.rollingAuditBatchSize} drugs/cycle)`);

    // Schedule Shortages Poll
    const shortagesTimer = setInterval(() => {
      this.runShortagesSync().catch(err => console.error('[Scheduler Shortages Poll Error]', err));
    }, this.shortagesIntervalMs);
    shortagesTimer.unref?.();
    this.timers.push(shortagesTimer);

    // Schedule Weekly NADAC Poll
    const nadacTimer = setInterval(() => {
      this.runNadacSync().catch(err => console.error('[Scheduler NADAC Poll Error]', err));
    }, this.nadacIntervalMs);
    nadacTimer.unref?.();
    this.timers.push(nadacTimer);

    // Schedule Rolling Live FDA/RxNorm/CMS Database Audit (production/dev only)
    if (process.env.NODE_ENV !== 'test') {
      const rollingTimer = setInterval(() => {
        this.runRollingLiveAudit().catch(err => console.error('[Scheduler Rolling Audit Error]', err));
      }, this.rollingAuditIntervalMs);
      rollingTimer.unref?.();
      this.timers.push(rollingTimer);
    }
  }

  /**
   * Stop the background scheduler
   */
  stop() {
    for (const t of this.timers) {
      clearInterval(t);
    }
    this.timers = [];
    this.isRunning = false;
    console.log('[Scheduler] Daemon stopped.');
  }
}

module.exports = {
  IngestionScheduler
};
