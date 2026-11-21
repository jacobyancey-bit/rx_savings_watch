const express = require('express');
const { getOrInitVapidKeys } = require('../services/webPush');

function isValidPushEndpoint(endpoint) {
  if (typeof endpoint !== 'string' || endpoint.length < 16 || endpoint.length > 1024) {
    return false;
  }
  try {
    const parsed = new URL(endpoint);
    return parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

/**
 * Zero-PII Anonymous Web Push Subscription Router
 * Stores ONLY browser push endpoints & encryption keys — NEVER user identities or medication lists.
 */
function createPushRouter(db) {
  const router = express.Router();

  const upsertSubStmt = db.prepare(`
    INSERT INTO push_subscriptions (endpoint, p256dh, auth, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(endpoint) DO UPDATE SET
      p256dh = excluded.p256dh,
      auth = excluded.auth,
      updated_at = datetime('now')
  `);

  const deleteSubStmt = db.prepare('DELETE FROM push_subscriptions WHERE endpoint = ?');

  router.get('/push/vapid-public-key', (req, res) => {
    const { publicKey } = getOrInitVapidKeys(db);
    res.json({ publicKey });
  });

  router.post('/push/subscribe', (req, res) => {
    const { endpoint, keys } = req.body || {};
    if (
      !isValidPushEndpoint(endpoint) ||
      !keys ||
      typeof keys.p256dh !== 'string' ||
      typeof keys.auth !== 'string' ||
      keys.p256dh.length < 20 ||
      keys.p256dh.length > 256 ||
      keys.auth.length < 10 ||
      keys.auth.length > 128
    ) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Valid HTTPS push subscription endpoint and keys are required.'
      });
    }

    upsertSubStmt.run(endpoint, keys.p256dh, keys.auth);
    res.status(201).json({ success: true });
  });

  router.post('/push/unsubscribe', (req, res) => {
    const { endpoint } = req.body || {};
    if (!isValidPushEndpoint(endpoint)) {
      return res.status(400).json({ error: 'Bad Request', message: 'Valid endpoint required.' });
    }
    deleteSubStmt.run(endpoint);
    res.json({ success: true });
  });

  return router;
}

module.exports = {
  createPushRouter,
};
