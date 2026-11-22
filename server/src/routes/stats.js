const express = require('express');
const crypto = require('node:crypto');
const config = require('../config');

const ALLOWED_METRICS = new Set(['web_visits', 'api_searches', 'cabinet_syncs']);

const BOT_PATTERN =
  /(bot|crawler|spider|slurp|curl|wget|python-requests|go-http-client|headless|playwright|puppeteer|uptime|healthcheck|monitoring|facebookexternalhit|whatsapp|preview)/i;

function timingSafeEquals(a, b) {
  if (!a || !b) return false;
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function isLikelyBot(userAgent) {
  if (!userAgent || typeof userAgent !== 'string') return true;
  return BOT_PATTERN.test(userAgent);
}

function utcDateKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function ensureDailyStatsTable(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS daily_stats (
      date_key TEXT PRIMARY KEY,
      web_visits INTEGER NOT NULL DEFAULT 0,
      api_searches INTEGER NOT NULL DEFAULT 0,
      cabinet_syncs INTEGER NOT NULL DEFAULT 0
    );
  `);
}

/**
 * Increments a single aggregate daily integer counter.
 * Stores ZERO PII (no IPs, no user agents, no cookies, no drug names).
 */
function recordDailyMetric(db, metricName, date = new Date()) {
  if (!ALLOWED_METRICS.has(metricName)) return;
  try {
    const key = utcDateKey(date);
    db.prepare(`
      INSERT INTO daily_stats (date_key, ${metricName})
      VALUES (?, 1)
      ON CONFLICT(date_key) DO UPDATE SET ${metricName} = ${metricName} + 1
    `).run(key);
  } catch (err) {
    // Non-fatal: never block user requests for analytics
    console.warn(`[stats] Failed to record ${metricName}: ${err.message}`);
  }
}

function sumRows(rows) {
  return rows.reduce(
    (acc, r) => ({
      web_visits: acc.web_visits + (Number(r.web_visits) || 0),
      api_searches: acc.api_searches + (Number(r.api_searches) || 0),
      cabinet_syncs: acc.cabinet_syncs + (Number(r.cabinet_syncs) || 0)
    }),
    { web_visits: 0, api_searches: 0, cabinet_syncs: 0 }
  );
}

/**
 * Admin-only aggregate stats router (GET /api/admin/stats).
 * @param {import('node:sqlite').DatabaseSync} db
 */
function createStatsRouter(db) {
  const router = express.Router();
  ensureDailyStatsTable(db);

  router.get('/admin/stats', (req, res) => {
    const adminKey = config.ADMIN_API_KEY;
    const provided = req.get('X-Admin-Key') || '';
    if (!adminKey || !timingSafeEquals(provided, adminKey)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const todayKey = utcDateKey();
    const d7 = new Date();
    d7.setUTCDate(d7.getUTCDate() - 6);
    const key7 = utcDateKey(d7);

    const d30 = new Date();
    d30.setUTCDate(d30.getUTCDate() - 29);
    const key30 = utcDateKey(d30);

    const todayRow = db
      .prepare('SELECT date_key, web_visits, api_searches, cabinet_syncs FROM daily_stats WHERE date_key = ?')
      .get(todayKey) || {
        date_key: todayKey,
        web_visits: 0,
        api_searches: 0,
        cabinet_syncs: 0
      };

    const last30Rows = db
      .prepare(`
        SELECT date_key, web_visits, api_searches, cabinet_syncs
        FROM daily_stats
        WHERE date_key >= ?
        ORDER BY date_key DESC
      `)
      .all(key30);

    const last7Rows = last30Rows.filter((r) => r.date_key >= key7);

    const allTimeRow = db
      .prepare(`
        SELECT
          COALESCE(SUM(web_visits), 0) AS web_visits,
          COALESCE(SUM(api_searches), 0) AS api_searches,
          COALESCE(SUM(cabinet_syncs), 0) AS cabinet_syncs
        FROM daily_stats
      `)
      .get();

    let reviewsSummary = { total: 0, avg_rating: null, recent_7_days: 0 };
    try {
      const rAll = db
        .prepare('SELECT COUNT(*) AS total, ROUND(AVG(rating), 2) AS avg_rating FROM user_reviews')
        .get();
      const r7 = db
        .prepare("SELECT COUNT(*) AS recent FROM user_reviews WHERE date(created_at) >= ?")
        .get(key7);
      reviewsSummary = {
        total: Number(rAll?.total) || 0,
        avg_rating: rAll?.avg_rating ?? null,
        recent_7_days: Number(r7?.recent) || 0
      };
    } catch (_) {}

    let totalDrugs = 0;
    try {
      const dCount = db.prepare('SELECT COUNT(*) AS total FROM drugs').get();
      totalDrugs = Number(dCount?.total) || 0;
    } catch (_) {}

    return res.json({
      privacy_mode: 'zero_pii_aggregate_only',
      generated_at: new Date().toISOString(),
      today: todayRow,
      last_7_days: sumRows(last7Rows),
      last_30_days: sumRows(last30Rows),
      all_time: {
        web_visits: Number(allTimeRow?.web_visits) || 0,
        api_searches: Number(allTimeRow?.api_searches) || 0,
        cabinet_syncs: Number(allTimeRow?.cabinet_syncs) || 0
      },
      reviews: reviewsSummary,
      catalog: { total_drugs: totalDrugs },
      daily: last30Rows
    });
  });

  return router;
}

module.exports = {
  createStatsRouter,
  recordDailyMetric,
  isLikelyBot,
  ensureDailyStatsTable
};
