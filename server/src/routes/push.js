const express = require('express');
const { getOrInitVapidKeys } = require('../services/webPush');

const ALLOWED_PUSH_HOST_SUFFIXES = [
  'fcm.googleapis.com',
  'android.googleapis.com',
  'updates.push.services.mozilla.com',
  '.push.services.mozilla.com',
  '.push.apple.com',
  '.notify.windows.com',
];

const MAX_PUSH_SUBSCRIPTIONS = 10000;
const SUBSCRIBE_WINDOW_MS = 15 * 60 * 1000;
const SUBSCRIBE_MAX_PER_IP = 10;

function isValidPushEndpoint(endpoint) {
  if (typeof endpoint !== 'string' || endpoint.length < 16 || endpoint.length > 1024) {
    return false;
  }
  try {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
      return false;
    }
    const host = parsed.hostname.toLowerCase();
    return ALLOWED_PUSH_HOST_SUFFIXES.some(suffix =>
      suffix.startsWith('.') ? host.endsWith(suffix) : host === suffix
    );
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
  const countSubsStmt = db.prepare('SELECT COUNT(*) AS total FROM push_subscriptions');
  const ipSubscribeBuckets = new Map();

  function canSubscribeForIp(ip) {
    const now = Date.now();
    if (ipSubscribeBuckets.size > 500) {
      for (const [k, v] of ipSubscribeBuckets) {
        if (v.resetAt <= now) ipSubscribeBuckets.delete(k);
      }
    }
    const bucket = ipSubscribeBuckets.get(ip);
    if (!bucket || bucket.resetAt <= now) {
      ipSubscribeBuckets.set(ip, { count: 1, resetAt: now + SUBSCRIBE_WINDOW_MS });
      return true;
    }
    if (bucket.count >= SUBSCRIBE_MAX_PER_IP) return false;
    bucket.count++;
    return true;
  }

  router.get('/push/vapid-public-key', (req, res) => {
    const { publicKey } = getOrInitVapidKeys(db);
    res.json({ publicKey });
  });

  router.post('/push/subscribe', (req, res) => {
    const clientIp = req.ip || 'unknown';
    if (!canSubscribeForIp(clientIp)) {
      return res.status(429).json({
        error: 'Too Many Requests',
        message: 'Too many subscription attempts. Please try again later.'
      });
    }

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
        message: 'Valid trusted browser push subscription endpoint and keys are required.'
      });
    }

    const totalSubs = countSubsStmt.get().total;
    if (totalSubs >= MAX_PUSH_SUBSCRIPTIONS) {
      return res.status(503).json({
        error: 'Service Unavailable',
        message: 'Push subscription capacity reached.'
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
