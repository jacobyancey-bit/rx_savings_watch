const path = require('node:path');

const isProduction = process.env.NODE_ENV === 'production';

module.exports = {
  PORT: process.env.PORT || 3000,
  DB_PATH: process.env.DB_PATH || path.resolve(__dirname, '../data/rx_savings.db'),
  SCHEMA_PATH: path.resolve(__dirname, 'db/schema.sql'),
  FIXTURES_DIR: path.resolve(__dirname, '../data/fixtures'),

  // Security & Rate Limiting
  // In production, ADMIN_API_KEY MUST be explicitly set via environment variable;
  // otherwise admin endpoints are completely closed (fail-closed).
  ADMIN_API_KEY: process.env.ADMIN_API_KEY || (isProduction ? null : 'dev-admin-secret-key'),
  RATE_LIMIT_WINDOW_MS: 15 * 60 * 1000, // 15 minutes
  RATE_LIMIT_MAX_REQUESTS: 120, // max requests per IP per window
  LIVE_DISCOVERY_MAX_PER_IP: 15, // max outbound FDA/RxNorm discoveries per IP per 15 min
  MAX_RXCUIS_PER_CHECK: 50, // maximum RXCUIs allowed in single check-updates payload

  // Explicit CORS allowlist for browser clients (native mobile clients send no Origin)
  CORS_ALLOWED_ORIGINS: [
    'https://rx.dangling-dice-studios.com',
    'https://dangling-dice-studios.com',
    'https://www.dangling-dice-studios.com',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
  ],

  DETECTOR: {
    CONFIDENCE_THRESHOLD: 0.90,
    MAX_HISTORICAL_DAYS: 3650
  }
};
