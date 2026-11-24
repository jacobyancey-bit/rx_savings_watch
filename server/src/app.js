const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const config = require('./config');
const { createCheckUpdatesRouter } = require('./routes/checkUpdates');
const { createDrugsRouter } = require('./routes/drugs');
const { createSchedulerRouter } = require('./routes/scheduler');
const { createPushRouter } = require('./routes/push');
const { createReviewsRouter } = require('./routes/reviews');
const { createStatsRouter, recordDailyMetric, isLikelyBot } = require('./routes/stats');
const { createSeoRouter } = require('./routes/seo');
const { createB2bRouter } = require('./routes/b2b');
const { IngestionScheduler } = require('./scheduler');

/**
 * Create and configure Express application
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {IngestionScheduler} [options.scheduler]
 * @param {boolean} [options.enableRateLimiter=true]
 * @returns {express.Application}
 */
function createApp(db, options = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // Accurate client IP behind Railway / reverse proxies

  const scheduler = options.scheduler || new IngestionScheduler(db);
  const enableRateLimiter = options.enableRateLimiter !== false;

  // 1. Security Headers via Helmet (explicit no-referrer so outbound pharmacy links never receive internal URLs)
  app.use(helmet({
    contentSecurityPolicy: false, // Flutter Web uses CanvasKit WASM + inline bootstrap
    crossOriginEmbedderPolicy: false,
    referrerPolicy: { policy: 'no-referrer' }
  }));

  // 2. CORS: Explicit allowlist for browser origins; native mobile apps send no Origin
  const allowedOrigins = new Set(config.CORS_ALLOWED_ORIGINS);
  app.use(cors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.has(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-Key']
  }));

  // 3. Rate Limiting: Abuse and denial-of-service prevention
  if (enableRateLimiter) {
    const apiLimiter = rateLimit({
      windowMs: config.RATE_LIMIT_WINDOW_MS,
      max: config.RATE_LIMIT_MAX_REQUESTS,
      standardHeaders: true,
      legacyHeaders: false,
      message: {
        error: 'Too Many Requests',
        message: 'Rate limit exceeded. Please retry later.'
      }
    });
    app.use('/api', apiLimiter);
  }

  // 4. Request Body Parsing with strict size bounds (+ rawBody capture for Stripe webhook HMAC verification)
  app.use(express.json({
    limit: '64kb',
    verify: (req, res, buf) => {
      if (req.originalUrl === '/api/b2b/stripe-webhook') {
        req.rawBody = buf;
      }
    }
  }));

  // 5. Zero-PII & Privacy Cache-Control headers on API & health endpoints
  app.use(['/api', '/health'], (req, res, next) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    next();
  });

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  });

  // Aggregate zero-PII daily counters (no IPs, cookies, user IDs, or drug names stored)
  app.use('/api/drugs', (req, res, next) => {
    const hasGetQuery = req.method === 'GET' && typeof req.query.q === 'string' && req.query.q.trim().length > 0;
    const hasPostQuery = req.method === 'POST' && req.path === '/search' && typeof req.body?.q === 'string' && req.body.q.trim().length > 0;
    if (hasGetQuery || hasPostQuery) {
      recordDailyMetric(db, 'api_searches');
    }
    next();
  });
  app.use('/api/check-updates', (req, res, next) => {
    if (req.method === 'POST') {
      recordDailyMetric(db, 'cabinet_syncs');
    }
    next();
  });

  // API Routes
  app.use('/api', createCheckUpdatesRouter(db));
  app.use('/api', createDrugsRouter(db));
  app.use('/api', createSchedulerRouter(scheduler));
  app.use('/api', createPushRouter(db));
  app.use('/api', createReviewsRouter(db, { enableRateLimiter }));
  app.use('/api', createStatsRouter(db));
  app.use('/', createB2bRouter(db));

  // Catch-all 404 for unknown /api/* routes (prevents info leakage)
  app.use('/api', (req, res) => {
    res.status(404).json({ error: 'Not Found' });
  });

  // Server-rendered SEO pages (/robots.txt, /sitemap.xml, /medications, /medications/:slug)
  app.use('/', createSeoRouter(db));

  // Serve Flutter Web App at '/' if built into server/public
  const webPublicDir = path.join(__dirname, '..', 'public');
  if (fs.existsSync(webPublicDir)) {
    app.get('/', (req, res) => {
      if (!isLikelyBot(req.get('user-agent'))) {
        recordDailyMetric(db, 'web_visits');
      }
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.sendFile(path.join(webPublicDir, 'index.html'));
    });
    app.use(express.static(webPublicDir, {
      setHeaders: (res, filePath) => {
        if (filePath.endsWith('.html') || filePath.endsWith('rx_bottle_ocr.js') || filePath.endsWith('rx_push_bridge.js')) {
          res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        }
      }
    }));
  }

  // Error handling middleware
  app.use((err, req, res, next) => {
    console.error('Unhandled server error:', err);
    res.status(500).json({ error: 'Internal Server Error' });
  });

  return app;
}

module.exports = {
  createApp
};
