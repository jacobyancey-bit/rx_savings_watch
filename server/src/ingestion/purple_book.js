const fs = require('node:fs');
const path = require('node:path');
const config = require('../config');

/**
 * Ingest FDA Purple Book biologic approvals & biosimilar designations
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {Array|string} [options.sourceData]
 * @returns {Promise<{ inserted: number }>}
 */
async function ingestPurpleBook(db, options = {}) {
  let records = [];

  if (options.sourceData) {
    if (typeof options.sourceData === 'string') {
      records = JSON.parse(fs.readFileSync(options.sourceData, 'utf8'));
    } else if (Array.isArray(options.sourceData)) {
      records = options.sourceData;
    }
  } else {
    const fixturePath = path.join(config.FIXTURES_DIR, 'purple_book_sample.json');
    if (fs.existsSync(fixturePath)) {
      records = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
    }
  }

  const findDrugStmt = db.prepare('SELECT id FROM drugs WHERE rxcui = ?');
  const upsertStmt = db.prepare(`
    INSERT INTO generic_status (
      drug_id, source, application_number, applicant, approval_date,
      is_approved_generic, biosimilar_status, reference_product_id, updated_at
    ) VALUES (
      ?, 'purple_book', ?, ?, ?, ?, ?, ?, datetime('now')
    )
    ON CONFLICT(drug_id, application_number, source) DO UPDATE SET
      applicant = excluded.applicant,
      approval_date = excluded.approval_date,
      is_approved_generic = excluded.is_approved_generic,
      biosimilar_status = excluded.biosimilar_status,
      reference_product_id = excluded.reference_product_id,
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
      item.application_number,
      item.applicant || null,
      item.approval_date || null,
      item.is_approved_generic ? 1 : 0,
      item.biosimilar_status || null,
      item.reference_product_id || null
    );
    count++;
  }

  return { inserted: count };
}

module.exports = {
  ingestPurpleBook
};
