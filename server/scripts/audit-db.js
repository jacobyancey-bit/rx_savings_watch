/**
 * Read-Only Clinical Database Auditor CLI
 *
 * Scans every drug in the SQLite database against universal pharmacist-verified
 * clinical invariants (ingredient-count parity, strength-to-ingredient parity,
 * duplicate brands, brand/generic placeholders, and NADAC price sanity).
 *
 * Usage:
 *   npm run audit:db
 *   node scripts/audit-db.js --db=./data/rx_savings.db --strict
 */

const path = require('node:path');
const { getDb, closeDb } = require('../src/db');
const { auditDatabase } = require('../src/auditor/clinicalInvariants');

function main() {
  const args = process.argv.slice(2);
  const dbArg = args.find(a => a.startsWith('--db='));
  const strict = args.includes('--strict');
  const dbPath = dbArg ? path.resolve(dbArg.split('=')[1]) : undefined;

  const db = getDb(dbPath);
  try {
    const report = auditDatabase(db);
    console.log(`\nClinical Database Audit Complete: ${report.totalDrugs} drug(s) scanned.`);
    console.log(`  Errors:   ${report.errorCount}`);
    console.log(`  Warnings: ${report.warningCount}`);

    if (report.findings.length > 0) {
      console.log('\nFindings:');
      for (const f of report.findings) {
        const label = f.brand_name ? `${f.brand_name} (${f.generic_name})` : f.generic_name;
        console.log(`  - [rxcui=${f.rxcui}] ${label}`);
        for (const err of f.errors) {
          console.log(`      [ERROR] ${err}`);
        }
        for (const warn of f.warnings) {
          console.log(`      [WARN]  ${warn}`);
        }
      }
    } else {
      console.log('  All records passed every clinical invariant.');
    }

    if (report.errorCount > 0 || (strict && report.warningCount > 0)) {
      process.exitCode = 1;
    }
  } finally {
    closeDb();
  }
}

main();
