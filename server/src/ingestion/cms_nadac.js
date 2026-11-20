const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest CMS NADAC pricing entries
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData]
 * @returns {Promise<{ inserted: number }>}
 */
async function ingestCmsNadac(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    const fixturePath = path.join(config.FIXTURES_DIR, 'cms_nadac_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const findDrugStmt = db.prepare('SELECT id FROM drugs WHERE rxcui = ?');
  const upsertStmt = db.prepare(`
    INSERT INTO market_availability (
      drug_id, source, ndc, package_description, nadac_per_unit,
      nadac_effective_date, pricing_unit, is_commercialized, updated_at
    ) VALUES (
      ?, 'cms_nadac', ?, ?, ?, ?, ?, 1, datetime('now')
    )
    ON CONFLICT(drug_id, ndc, source) DO UPDATE SET
      package_description = excluded.package_description,
      nadac_per_unit = excluded.nadac_per_unit,
      nadac_effective_date = excluded.nadac_effective_date,
      pricing_unit = excluded.pricing_unit,
      is_commercialized = 1,
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
      item.description || null,
      item.nadac_per_unit !== undefined ? item.nadac_per_unit : null,
      item.effective_date || null,
      item.pricing_unit || 'EA'
    );
    count++;
  }

  return { inserted: count };
}

module.exports = {
  ingestCmsNadac
};
