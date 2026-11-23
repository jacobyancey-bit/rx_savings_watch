/**
 * Live Production Catalog Clinical Invariants Auditor
 *
 * Fetches every drug currently stored in the live production API
 * (all 200+ seeded medications plus any user-discovered medications)
 * and runs universal clinical invariants across the entire catalog.
 *
 * Usage:
 *   npm run audit:live
 *   node scripts/audit-live-catalog.js --url=https://rx.dangling-dice-studios.com
 */

const { auditDrugRecord } = require('../src/auditor/clinicalInvariants');

async function main() {
  const args = process.argv.slice(2);
  const urlArg = args.find(a => a.startsWith('--url='));
  const baseUrl = (urlArg ? urlArg.split('=')[1] : 'https://rx.dangling-dice-studios.com').replace(/\/$/, '');

  const allDrugs = [];
  let offset = 0;
  const pageSize = 500;

  while (true) {
    const resp = await fetch(`${baseUrl}/api/drugs?limit=${pageSize}&offset=${offset}`, {
      headers: { 'User-Agent': 'RxSavingsWatch-ClinicalAuditor/1.0' },
      signal: AbortSignal.timeout(15000),
    });
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status} fetching ${baseUrl}/api/drugs`);
    }
    const data = await resp.json();
    const page = data.drugs || [];
    allDrugs.push(...page);
    if (page.length < pageSize || allDrugs.length >= (data.total || 0)) break;
    offset += pageSize;
  }

  const brandSeen = new Map();
  let errorCount = 0;
  const findings = [];

  for (const drug of allDrugs) {
    const { errors } = auditDrugRecord(drug);
    if (drug.brand_name) {
      const key = drug.brand_name.trim().toLowerCase();
      if (brandSeen.has(key)) {
        errors.push(`Duplicate brand_name "${drug.brand_name}" (also on rxcui ${brandSeen.get(key)})`);
      } else {
        brandSeen.set(key, drug.rxcui);
      }
    }
    if (errors.length > 0) {
      errorCount += errors.length;
      findings.push({ drug, errors });
    }
  }

  console.log(`Live Production Catalog Audit (${baseUrl}): ${allDrugs.length} drug(s) audited, ${errorCount} error(s).`);
  for (const f of findings) {
    const label = f.drug.brand_name ? `${f.drug.brand_name} (${f.drug.generic_name})` : f.drug.generic_name;
    console.error(`[FAIL] [rxcui=${f.drug.rxcui}] ${label}`);
    for (const err of f.errors) {
      console.error(`       - ${err}`);
    }
  }

  if (errorCount > 0) {
    process.exitCode = 1;
  }
}

main().catch(err => {
  console.error('Live catalog audit failed:', err.message);
  process.exitCode = 1;
});
