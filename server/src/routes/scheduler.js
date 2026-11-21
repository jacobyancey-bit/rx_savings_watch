const crypto = require('node:crypto');
const express = require('express');
const config = require('../config');

function safeKeyEquals(provided, expected) {
  if (typeof provided !== 'string' || typeof expected !== 'string') return false;
  const a = Buffer.from(provided, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Scheduler management & status router (strictly admin-authenticated)
 * @param {import('../scheduler').IngestionScheduler} scheduler
 * @returns {express.Router}
 */
function createSchedulerRouter(scheduler) {
  const router = express.Router();

  // Fail-closed, constant-time authentication middleware for administrative actions
  function requireAdminAuth(req, res, next) {
    if (!config.ADMIN_API_KEY) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Administrative endpoints are disabled until ADMIN_API_KEY is configured.'
      });
    }

    const authHeader = req.headers.authorization;
    const adminKeyHeader = req.headers['x-admin-key'];

    let providedKey = null;
    if (typeof adminKeyHeader === 'string') {
      providedKey = adminKeyHeader;
    } else if (typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
      providedKey = authHeader.substring(7);
    }

    if (!providedKey || !safeKeyEquals(providedKey, config.ADMIN_API_KEY)) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Valid admin API key required in X-Admin-Key or Authorization header.'
      });
    }

    next();
  }

  router.get('/scheduler/status', requireAdminAuth, (req, res) => {
    res.json({
      is_running: scheduler.isRunning,
      last_sync_times: scheduler.lastSyncTimes,
      shortages_interval_ms: scheduler.shortagesIntervalMs,
      nadac_interval_ms: scheduler.nadacIntervalMs
    });
  });

  router.post('/scheduler/trigger', requireAdminAuth, async (req, res) => {
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
        error: 'Internal Server Error'
      });
    }
  });

  return router;
}

module.exports = {
  createSchedulerRouter
};
