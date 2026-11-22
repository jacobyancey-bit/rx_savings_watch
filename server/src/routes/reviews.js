const express = require('express');
const crypto = require('node:crypto');
const rateLimit = require('express-rate-limit');
const config = require('../config');

const ALLOWED_CATEGORIES = new Set(['general', 'feature', 'caregiver', 'bug']);
const ALLOWED_PLATFORMS = new Set(['web', 'android', 'ios', 'unknown']);
const CATEGORY_LABELS = {
  general: 'General Review',
  feature: 'Feature Idea',
  caregiver: 'Caregiver Feedback',
  bug: 'Bug Report'
};

function sanitizeMessage(raw) {
  return String(raw || '')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim();
}

function timingSafeEquals(a, b) {
  if (!a || !b) return false;
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

async function forwardReviewEmail({ rating, category, message, platform, createdAt }) {
  const apiKey = (process.env.RESEND_API_KEY || '').trim();
  if (!apiKey) return false;

  const toEmail = (process.env.REVIEW_TO_EMAIL || 'support@danglingdicestudios.com').trim();
  const fromEmail = (process.env.REVIEW_FROM_EMAIL || 'Rx Savings Watch <onboarding@resend.dev>').trim();
  const stars = '★'.repeat(rating) + '☆'.repeat(5 - rating);
  const categoryLabel = CATEGORY_LABELS[category] || 'General Review';

  const textBody = [
    `New Private Review — Rx Savings Watch`,
    `-------------------------------------`,
    `Rating:   ${stars} (${rating}/5)`,
    `Category: ${categoryLabel}`,
    `Platform: ${platform}`,
    `Time:     ${createdAt}`,
    ``,
    `Message:`,
    message,
    ``,
    `Note: Reviews are stored privately and never displayed publicly.`
  ].join('\n');

  try {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [toEmail],
        subject: `Rx Savings Watch Review (${stars} - ${categoryLabel})`,
        text: textBody
      }),
      signal: AbortSignal.timeout(8000)
    });

    if (!resp.ok) {
      const errText = await resp.text().catch(() => '');
      console.warn(`[reviews] Resend delivery failed (${resp.status}): ${errText.slice(0, 200)}`);
      return false;
    }
    return true;
  } catch (err) {
    console.warn(`[reviews] Resend delivery error: ${err.message}`);
    return false;
  }
}

/**
 * Private user review & feedback router.
 * Stores reviews privately in SQLite and forwards them to support@danglingdicestudios.com
 * when RESEND_API_KEY is configured. Never exposes a public GET endpoint.
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {boolean} [options.enableRateLimiter=true]
 */
function createReviewsRouter(db, options = {}) {
  const router = express.Router();
  const enableRateLimiter = options.enableRateLimiter !== false;

  // Ensure table exists even on existing persistent SQLite volumes
  db.exec(`
    CREATE TABLE IF NOT EXISTS user_reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
      category TEXT NOT NULL DEFAULT 'general',
      message TEXT NOT NULL,
      platform TEXT NOT NULL DEFAULT 'unknown',
      emailed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  const reviewLimiter = enableRateLimiter
    ? rateLimit({
        windowMs: 60 * 60 * 1000, // 1 hour
        max: 3, // Max 3 review submissions per IP per hour
        standardHeaders: true,
        legacyHeaders: false,
        message: {
          error: 'Too Many Requests',
          message: 'You have already submitted feedback recently. Please try again later.'
        }
      })
    : (req, res, next) => next();

  router.post('/reviews', reviewLimiter, async (req, res) => {
    try {
      const body = req.body || {};

      // Honeypot check: silently accept without saving/emailing if a bot fills hidden field
      if (body.website && String(body.website).trim().length > 0) {
        return res.status(201).json({ success: true });
      }

      const rating = Number(body.rating);
      if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
        return res.status(400).json({ error: 'Rating must be an integer between 1 and 5.' });
      }

      const rawCategory = String(body.category || 'general').toLowerCase().trim();
      const category = ALLOWED_CATEGORIES.has(rawCategory) ? rawCategory : 'general';

      const rawPlatform = String(body.platform || 'unknown').toLowerCase().trim();
      const platform = ALLOWED_PLATFORMS.has(rawPlatform) ? rawPlatform : 'unknown';

      const message = sanitizeMessage(body.message);
      if (message.length < 3 || message.length > 1000) {
        return res.status(400).json({
          error: 'Review message must be between 3 and 1000 characters.'
        });
      }

      const insertStmt = db.prepare(`
        INSERT INTO user_reviews (rating, category, message, platform, emailed)
        VALUES (?, ?, ?, ?, 0)
      `);
      const result = insertStmt.run(rating, category, message, platform);
      const createdAt = new Date().toISOString();

      const emailed = await forwardReviewEmail({
        rating,
        category,
        message,
        platform,
        createdAt
      });

      if (emailed && result.lastInsertRowid) {
        db.prepare('UPDATE user_reviews SET emailed = 1 WHERE id = ?').run(result.lastInsertRowid);
      }

      return res.status(201).json({
        success: true,
        emailed
      });
    } catch (err) {
      console.error('[reviews] Error saving review:', err);
      return res.status(500).json({ error: 'Could not save review right now.' });
    }
  });

  // Strictly admin-only read endpoint (never public)
  router.get('/admin/reviews', (req, res) => {
    const adminKey = config.ADMIN_API_KEY;
    const provided = req.get('X-Admin-Key') || '';
    if (!adminKey || !timingSafeEquals(provided, adminKey)) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
    const rows = db.prepare(`
      SELECT id, rating, category, message, platform, emailed, created_at
      FROM user_reviews
      ORDER BY id DESC
      LIMIT ?
    `).all(limit);

    return res.json({ reviews: rows, count: rows.length });
  });

  return router;
}

module.exports = {
  createReviewsRouter
};
