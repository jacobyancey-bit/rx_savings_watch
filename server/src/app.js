const express = require('express');
const cors = require('cors');
const { createCheckUpdatesRouter } = require('./routes/checkUpdates');
const { createDrugsRouter } = require('./routes/drugs');

/**
 * Create and configure Express application
 * @param {import('node:sqlite').DatabaseSync} db
 * @returns {express.Application}
 */
function createApp(db) {
  const app = express();

  // Basic middleware
  app.use(cors());
  app.use(express.json());

  // Privacy headers: Ensure no caching of prescription/medication requests
  app.use((req, res, next) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
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
