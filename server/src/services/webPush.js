const webpush = require('web-push');

let configuredVapid = null;

/**
 * Load VAPID keys from environment variables or auto-generate & persist them in SQLite app_metadata.
 * Guarantees stable Web Push keys across Railway redeploys when mounted on /app/data.
 */
function getOrInitVapidKeys(db) {
  if (configuredVapid) return configuredVapid;

  let publicKey = process.env.VAPID_PUBLIC_KEY;
  let privateKey = process.env.VAPID_PRIVATE_KEY;
  const subject = process.env.VAPID_SUBJECT || 'mailto:support@dangling-dice-studios.com';

  if (!publicKey || !privateKey) {
    try {
      const pubRow = db.prepare("SELECT value FROM app_metadata WHERE key = 'vapid_public_key'").get();
      const privRow = db.prepare("SELECT value FROM app_metadata WHERE key = 'vapid_private_key'").get();

      if (pubRow?.value && privRow?.value) {
        publicKey = pubRow.value;
        privateKey = privRow.value;
      } else {
        const generated = webpush.generateVAPIDKeys();
        publicKey = generated.publicKey;
        privateKey = generated.privateKey;
        const upsert = db.prepare(`
          INSERT INTO app_metadata (key, value, updated_at)
          VALUES (?, ?, datetime('now'))
          ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
        `);
        upsert.run('vapid_public_key', publicKey);
        upsert.run('vapid_private_key', privateKey);
      }
    } catch (_) {
      const generated = webpush.generateVAPIDKeys();
      publicKey = generated.publicKey;
      privateKey = generated.privateKey;
    }
  }

  webpush.setVapidDetails(subject, publicKey, privateKey);
  configuredVapid = { publicKey, privateKey, subject };
  return configuredVapid;
}

/**
 * Broadcast a public, non-PII generic launch or shortage signal to all anonymous Web Push subscribers.
 * Each browser's local Service Worker filters the signal against its private on-device cabinet.
 */
async function broadcastPublicAlert(db, payload) {
  getOrInitVapidKeys(db);

  const subs = db.prepare('SELECT id, endpoint, p256dh, auth FROM push_subscriptions').all();
  if (subs.length === 0) return { sent: 0, pruned: 0 };

  const deleteSub = db.prepare('DELETE FROM push_subscriptions WHERE id = ?');
  const message = JSON.stringify(payload);
  let sent = 0;
  let pruned = 0;

  for (const sub of subs) {
    try {
      await webpush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        },
        message,
        { TTL: 86400 }
      );
      sent++;
    } catch (err) {
      if (err.statusCode === 404 || err.statusCode === 410) {
        deleteSub.run(sub.id);
        pruned++;
      }
    }
  }

  return { sent, pruned };
}

module.exports = {
  getOrInitVapidKeys,
  broadcastPublicAlert,
};
