const path = require('node:path');

module.exports = {
  PORT: process.env.PORT || 3000,
  DB_PATH: process.env.DB_PATH || path.resolve(__dirname, '../data/rx_savings.db'),
  SCHEMA_PATH: path.resolve(__dirname, 'db/schema.sql'),
  FIXTURES_DIR: path.resolve(__dirname, '../data/fixtures'),
  
  // Security & Rate Limiting
  ADMIN_API_KEY: process.env.ADMIN_API_KEY || 'dev-admin-secret-key',
  RATE_LIMIT_WINDOW_MS: 15 * 60 * 1000, // 15 minutes
  RATE_LIMIT_MAX_REQUESTS: 120, // max requests per window
  MAX_RXCUIS_PER_CHECK: 50, // maximum RXCUIs allowed in single check-updates payload

  // Feed source endpoints (with reasonable timeouts)
  FEEDS: {
    RXNAV_BASE_URL: process.env.RXNAV_BASE_URL || 'https://rxnav.nlm.nih.gov/REST',
    OPENFDA_BASE_URL: process.env.OPENFDA_BASE_URL || 'https://api.fda.gov/drug',
    CMS_NADAC_BASE_URL: process.env.CMS_NADAC_BASE_URL || 'https://data.medicaid.gov/resource/ta73-22vg.json',
    FDA_SHORTAGES_URL: process.env.FDA_SHORTAGES_URL || 'https://api.fda.gov/drug/shortages.json',
    ORANGE_BOOK_DATA_URL: process.env.ORANGE_BOOK_DATA_URL || 'https://www.fda.gov/media/71473/download',
    PURPLE_BOOK_DATA_URL: process.env.PURPLE_BOOK_DATA_URL || 'https://purplebooksearch.fda.gov/api/downloads'
  },
  
  DETECTOR: {
    CONFIDENCE_THRESHOLD: 0.90,
    MAX_HISTORICAL_DAYS: 3650
  }
};
