const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest RxNorm drug concepts
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData] Array of records or path to JSON fixture
 * @returns {Promise<{ inserted: number, updated: number }>}
 */
async function ingestRxNorm(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    // Try default fixture file
    const fixturePath = path.join(config.FIXTURES_DIR, 'rxnorm_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const upsertStmt = db.prepare(`
    INSERT INTO drugs (
      rxcui, brand_name, generic_name, active_ingredient, dosage_form, strength, route, drug_type, updated_at
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, ?, datetime('now')
    )
    ON CONFLICT(rxcui) DO UPDATE SET
      brand_name = excluded.brand_name,
      generic_name = excluded.generic_name,
      active_ingredient = excluded.active_ingredient,
      dosage_form = excluded.dosage_form,
      strength = excluded.strength,
      route = excluded.route,
      drug_type = excluded.drug_type,
      updated_at = datetime('now')
  `);

  let count = 0;
  for (const item of records) {
    upsertStmt.run(
      item.rxcui.toString(),
      item.brand_name || null,
      item.generic_name,
      item.active_ingredient || null,
      item.dosage_form || null,
      item.strength || null,
      item.route || null,
      item.drug_type || 'small_molecule'
    );
    count++;
  }

  return { inserted: count, updated: 0 };
}

module.exports = {
  ingestRxNorm
};
