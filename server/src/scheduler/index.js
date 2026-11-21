const { runAllIngestions, ingestFdaShortages, ingestCmsNadac } = require('../ingestion');
const { GenericLaunchDetector } = require('../detector');

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
    
    this.timers = [];
    this.isRunning = false;
    this.isCycleRunning = false;
    this.lastSyncTimes = {
      shortages: null,
      nadac: null,
      full: null
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
   * Start the background scheduler daemon
   */
  start() {
    if (this.isRunning) return;
    this.isRunning = true;

    console.log(`[Scheduler] Daemon started. Shortages interval: ${this.shortagesIntervalMs}ms, NADAC interval: ${this.nadacIntervalMs}ms`);

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
