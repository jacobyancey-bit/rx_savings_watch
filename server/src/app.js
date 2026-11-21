const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const config = require('./config');
const { createCheckUpdatesRouter } = require('./routes/checkUpdates');
const { createDrugsRouter } = require('./routes/drugs');
const { createSchedulerRouter } = require('./routes/scheduler');
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
  const scheduler = options.scheduler || new IngestionScheduler(db);
  const enableRateLimiter = options.enableRateLimiter !== false;

  // 1. Security Headers via Helmet
  app.use(helmet({
    contentSecurityPolicy: false, // API server does not render inline HTML
    crossOriginEmbedderPolicy: false
  }));

  // 2. CORS: Explicit headers
  app.use(cors());

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

  // 4. Request Body Parsing with strict size bounds
  app.use(express.json({ limit: '64kb' }));

  // 5. Zero-PII & Privacy Cache-Control headers
  app.use((req, res, next) => {
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

  // API Routes
  app.use('/api', createCheckUpdatesRouter(db));
  app.use('/api', createDrugsRouter(db));
  app.use('/api', createSchedulerRouter(scheduler));

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
