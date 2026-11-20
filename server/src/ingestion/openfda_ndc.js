const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest OpenFDA NDC Directory listings
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData]
 * @returns {Promise<{ inserted: number }>}
 */
async function ingestOpenFdaNdc(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    const fixturePath = path.join(config.FIXTURES_DIR, 'openfda_ndc_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const findDrugStmt = db.prepare('SELECT id FROM drugs WHERE rxcui = ?');
  const upsertStmt = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, labeler_name, marketing_category,
      marketing_start_date, is_commercialized, package_description, updated_at
    ) VALUES (
      ?, 'openfda_ndc', ?, ?, ?, ?, ?, ?, datetime('now')
    )
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      labeler_name = excluded.labeler_name,
      marketing_category = excluded.marketing_category,
      marketing_start_date = excluded.marketing_start_date,
      is_commercialized = excluded.is_commercialized,
      package_description = excluded.package_description,
      updated_at = datetime('now')
  `);

  let count = 0;
  for (const item of records) {
    const drugRow = findDrugStmt.get(item.rxcui.toString());
    if (!drugRow) {
      continue;
    }

    upsertStmt.run(
      drugRow.id,
      item.ndc,
      item.labeler_name || null,
      item.marketing_category || null,
      item.marketing_start_date || null,
      item.is_commercialized !== undefined ? (item.is_commercialized ? 1 : 0) : 1,
      item.package_description || null
    );
    count++;
  }

  return { inserted: count };
}

module.exports = {
  ingestOpenFdaNdc
};
