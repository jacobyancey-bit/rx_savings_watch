const express = require('express');

/**
 * Scheduler management & status router
 * @param {import('../scheduler').IngestionScheduler} scheduler
 * @returns {express.Router}
 */
function createSchedulerRouter(scheduler) {
  const router = express.Router();

  router.get('/scheduler/status', (req, res) => {
    res.json({
      is_running: scheduler.isRunning,
      last_sync_times: scheduler.lastSyncTimes,
      shortages_interval_ms: scheduler.shortagesIntervalMs,
      nadac_interval_ms: scheduler.nadacIntervalMs
    });
  });

  router.post('/scheduler/trigger', async (req, res) => {
    try {
      const { feed } = req.body || {};
      let result;

      if (feed === 'shortages') {
        result = await scheduler.runShortagesSync();
      } else if (feed === 'nadac') {
        result = await scheduler.runNadacSync();
      } else {
        result = await scheduler.runFullCycle();
      }

      res.json({
        success: true,
        triggered_at: new Date().toISOString(),
        result
      });
    } catch (err) {
      console.error('Trigger sync error:', err);
      res.status(500).json({
        success: false,
        error: err.message
      });
    }
  });

  return router;
}

module.exports = {
  createSchedulerRouter
};
