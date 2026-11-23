const { runAllIngestions, ingestFdaShortages, ingestCmsNadac, recordIngestionRun } = require('../ingestion');
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
      const res = process.env.NODE_ENV === 'test'
        ? await ingestFdaShortages(this.db)
        : await ingestLiveShortages(this.db);
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
    const discoverFn = options.discoverFn || discoverAndIngestDrug;
    const shortagesFn = options.shortagesFn || ingestLiveShortages;

    if (process.env.NODE_ENV === 'test' && !options.discoverFn) {
      return { skipped: true, reason: 'Disabled in offline test mode' };
    }
    if (this.isCycleRunning) {
      return { skipped: true, reason: 'Another ingestion cycle is already running' };
    }
    this.isCycleRunning = true;

    const batchSize = options.batchSize || this.rollingAuditBatchSize;
    const delayMs = options.delayMs ?? 500;
    const minAgeHours = options.minAgeHours ?? 12;
    let refreshed = 0;
    let newlyLaunched = 0;
    let anomaliesCorrected = 0;
    let errors = 0;
    const auditedRxcuis = [];

    try {
      // Only select prescriptions that haven't been verified within the last `minAgeHours`
      // (ordered oldest-first so every drug in the DB rotates evenly with zero redundant polling).
      const oldestDrugs = this.db.prepare(`
        SELECT id, rxcui, brand_name, generic_name, updated_at
        FROM drugs
        WHERE updated_at IS NULL
           OR updated_at <= datetime('now', ?)
        ORDER BY COALESCE(updated_at, '1970-01-01 00:00:00') ASC, id ASC
        LIMIT ?
      `).all(`-${minAgeHours} hours`, batchSize);

      if (oldestDrugs.length === 0) {
        // Still refresh live FDA Drug Shortages even when all drugs were recently verified
        await shortagesFn(this.db).catch(err => {
          console.error('[Rolling Audit] Live shortages refresh error:', err.message);
        });
        return {
          refreshed: 0,
          newlyLaunched: 0,
          anomaliesCorrected: 0,
          errors: 0,
          auditedRxcuis: [],
        };
      }

      const touchDrugStmt = this.db.prepare(
        "UPDATE drugs SET updated_at = datetime('now') WHERE id = ?"
      );

      console.log(`[Rolling Audit ${new Date().toISOString()}] Re-verifying ${oldestDrugs.length} oldest prescription(s) against live FDA/RxNorm/CMS feeds...`);

      for (let i = 0; i < oldestDrugs.length; i++) {
        const drug = oldestDrugs[i];
        const query = drug.brand_name || drug.generic_name;
        auditedRxcuis.push(drug.rxcui);
        try {
          const beforeEval = this.detector.evaluateDrug(drug, { persistAlert: false });
          const updated = await discoverFn(this.db, query, { forceRefresh: true, rxcui: drug.rxcui });
          // Always advance updated_at so a drug that fails or returns null never gets stuck at the front of the queue
          touchDrugStmt.run(drug.id);

          if (updated) {
            refreshed++;
            const afterEval = this.detector.evaluateDrug(updated, { persistAlert: true });

            if (!beforeEval.launch_detected && afterEval.launch_detected) {
              newlyLaunched++;
              console.log(`[Rolling Audit] NEW commercial generic launch confirmed: ${updated.brand_name || updated.generic_name}`);
              if (process.env.NODE_ENV !== 'test' && !options.discoverFn) {
                broadcastPublicAlert(this.db, {
                  type: 'generic_launch',
                  rxcui: updated.rxcui,
                  brand_name: updated.brand_name || updated.generic_name,
                  generic_name: updated.generic_name,
                  savings_pct: afterEval.savings?.savingsPct ?? null,
                }).catch(err => console.error('[Rolling Audit] Web Push error:', err.message));
              }
            } else if (beforeEval.launch_detected && !afterEval.launch_detected) {
              anomaliesCorrected++;
              console.log(`[Rolling Audit] Self-corrected status to Brand Only: ${updated.brand_name || updated.generic_name}`);
            }
          }
        } catch (err) {
          errors++;
          touchDrugStmt.run(drug.id);
          console.error(`[Rolling Audit] Error verifying ${query}:`, err.message);
        }

        if (i < oldestDrugs.length - 1 && delayMs > 0) {
          await sleep(delayMs);
        }
      }

      // Also refresh live FDA Drug Shortages once per audit cycle
      await shortagesFn(this.db).catch(err => {
        console.error('[Rolling Audit] Live shortages refresh error:', err.message);
      });

      this.lastSyncTimes.rollingAudit = new Date().toISOString();
      recordIngestionRun(this.db, {
        feedName: 'rolling_live_audit',
        status: errors === 0 ? 'success' : 'partial',
        recordsProcessed: refreshed,
        anomaliesRejected: anomaliesCorrected,
        notes: `audited=${oldestDrugs.length}, launches=${newlyLaunched}, corrected=${anomaliesCorrected}, errors=${errors}`,
      });

      console.log(`[Rolling Audit] Complete: ${refreshed}/${oldestDrugs.length} refreshed, ${newlyLaunched} new launches, ${anomaliesCorrected} self-corrected, ${errors} errors.`);
      return { refreshed, newlyLaunched, anomaliesCorrected, errors, auditedRxcuis };
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
