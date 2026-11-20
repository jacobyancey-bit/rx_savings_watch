const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest FDA Orange Book ANDA approvals and generic status
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData]
 * @returns {Promise<{ inserted: number }>}
 */
async function ingestOrangeBook(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    const fixturePath = path.join(config.FIXTURES_DIR, 'orange_book_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const findDrugStmt = db.prepare('SELECT id FROM drugs WHERE rxcui = ?');
  const upsertStmt = db.prepare(`
    INSERT INTO generic_status (
      drug_id, source, application_number, applicant, approval_date,
      is_approved_generic, te_code, reference_product_id,
      exclusivity_expiry_date, patent_expiry_date, updated_at
    ) VALUES (
      ?, 'orange_book', ?, ?, ?, ?, ?, ?, ?, ?, datetime('now')
    )
    ON CONFLICT(drug_id, application_number, source) DO UPDATE SET
      applicant = excluded.applicant,
      approval_date = excluded.approval_date,
      is_approved_generic = excluded.is_approved_generic,
      te_code = excluded.te_code,
      reference_product_id = excluded.reference_product_id,
      exclusivity_expiry_date = excluded.exclusivity_expiry_date,
      patent_expiry_date = excluded.patent_expiry_date,
      updated_at = datetime('now')
  `);

  let count = 0;
  for (const item of records) {
    const drugRow = findDrugStmt.get(item.rxcui.toString());
    if (!drugRow) {
      continue; // Drug must exist in drugs table
    }

    upsertStmt.run(
      drugRow.id,
      item.application_number,
      item.applicant || null,
      item.approval_date || null,
      item.is_approved_generic ? 1 : 0,
      item.te_code || null,
      item.reference_product_id || null,
      item.exclusivity_expiry_date || null,
      item.patent_expiry_date || null
    );
    count++;
  }

  return { inserted: count };
}

module.exports = {
  ingestOrangeBook
};
