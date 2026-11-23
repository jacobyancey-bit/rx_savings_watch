const { DatabaseSync } = require('node:sqlite');
const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

let dbInstance = null;

/**
 * Get or initialize SQLite Database connection
 * @param {string} [customPath] Optional custom DB path or ':memory:'
 * @returns {DatabaseSync}
 */
function getDb(customPath) {
  if (dbInstance && !customPath) {
    return dbInstance;
  }

  const dbPath = customPath || config.DB_PATH;
  
  // Ensure directory exists if writing to file
  if (dbPath !== ':memory:') {
    const dir = path.dirname(dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  const db = new DatabaseSync(dbPath);
  
  // Configure pragmas for performance and data integrity
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec('PRAGMA synchronous = NORMAL;');
  
  if (!customPath) {
    dbInstance = db;
  }
  
  return db;
}

/**
 * Initialize schema if not present
 * @param {DatabaseSync} db
 */
function initSchema(db) {
  const schemaSql = fs.readFileSync(config.SCHEMA_PATH, 'utf8');
  db.exec(schemaSql);

  // Backwards-compatible migrations for existing production SQLite databases
  const cols = db.prepare('PRAGMA table_info(drugs)').all();
  if (!cols.some(c => c.name === 'dosage_options')) {
    db.exec('ALTER TABLE drugs ADD COLUMN dosage_options TEXT;');
  }
  if (!cols.some(c => c.name === 'reference_brands')) {
    db.exec('ALTER TABLE drugs ADD COLUMN reference_brands TEXT;');
  }
}

/**
 * Close the global database connection
 */
function closeDb() {
  if (dbInstance) {
    dbInstance.close();
    dbInstance = null;
  }
}

module.exports = {
  getDb,
  initSchema,
  closeDb
};
