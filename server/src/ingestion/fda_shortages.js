const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest FDA Drug Shortages
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData]
 * @returns {Promise<{ inserted: number }>}
 */
async function ingestFdaShortages(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    const fixturePath = path.join(config.FIXTURES_DIR, 'fda_shortages_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const findDrugByRxcui = db.prepare('SELECT id FROM drugs WHERE rxcui = ?');
  const findDrugByName = db.prepare('SELECT id FROM drugs WHERE generic_name LIKE ?');
  
  const insertStmt = db.prepare(`
    INSERT INTO drug_shortages (
      drug_id, generic_name, dosage_form, status, reason,
      shortage_start_date, shortage_resolved_date, updated_at
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, datetime('now')
    )
  `);

  let count = 0;
  for (const item of records) {
    let drugId = null;
    if (item.rxcui) {
      const drugRow = findDrugByRxcui.get(item.rxcui.toString());
      if (drugRow) drugId = drugRow.id;
    }
    if (!drugId && item.generic_name) {
      const drugRow = findDrugByName.get(`%${item.generic_name}%`);
      if (drugRow) drugId = drugRow.id;
    }

    insertStmt.run(
      drugId,
      item.generic_name,
      item.dosage_form || null,
      item.status,
      item.reason || null,
      item.shortage_start_date || null,
      item.shortage_resolved_date || null
    );
    count++;
  }

  return { inserted: count };
}

module.exports = {
  ingestFdaShortages
};
