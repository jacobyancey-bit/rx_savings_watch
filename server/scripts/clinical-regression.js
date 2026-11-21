/**
 * Golden "Tricky Drugs" Clinical Regression Suite
 *
 * Verifies live 6-source cross-referencing against notoriously tricky U.S. medications:
 *   - Multi-salt ER (Mydayis AB2 vs Adderall XR AB1)
 *   - Biologics & biosimilars (Humira)
 *   - Combination therapies (Truvada, Symbicort)
 *   - Narrow-therapeutic-index multi-strength drugs (Synthroid)
 *   - High-volume generics (Lipitor, Warfarin)
 *   - Brand-only patented drugs (Ozempic)
 */
const { getDb, initSchema } = require('../src/db');
const { discoverAndIngestDrug } = require('../src/ingestion/live_feeds');
const { GenericLaunchDetector } = require('../src/detector');

const GOLDEN_CASES = [
  { query: 'Jornay PM', expectLaunch: false, mustIncludeStrength: '60 mg', note: 'Brand-only methylphenidate ER (no TE code — must NOT confuse with Ritalin/Concerta generics!)' },
  { query: 'Mydayis', expectLaunch: true, mustIncludeStrength: '37.5 mg', note: 'Multi-salt ER (AB2) with 12.5-50 mg doses' },
  { query: 'Adderall XR', expectLaunch: true, mustIncludeStrength: '20 mg', note: 'Multi-salt ER (AB1)' },
  { query: 'Vyvanse', expectLaunch: true, mustIncludeStrength: '30 mg', note: 'Recent small-molecule generic launch' },
  { query: 'Truvada', expectLaunch: true, note: '2-ingredient HIV PrEP combination' },
  { query: 'Symbicort', expectLaunch: true, note: 'Combination inhaler / authorized generic' },
  { query: 'Synthroid', expectLaunch: true, note: 'Multi-strength narrow therapeutic index' },
  { query: 'Warfarin', expectLaunch: true, mustIncludeStrength: '5 mg', note: 'Classic multi-strength anticoagulant' },
  { query: 'Ozempic', expectLaunch: false, note: 'Patented brand-only GLP-1 (must NOT false-positive)' },
];

async function main() {
  const db = getDb(':memory:');
  initSchema(db);
  const detector = new GenericLaunchDetector(db);

  let passed = 0;
  let failed = 0;

  console.log('Running Golden Clinical Regression Suite against live FDA/RxNorm/CMS APIs...\n');

  for (const tc of GOLDEN_CASES) {
    const drug = await discoverAndIngestDrug(db, tc.query);
    if (!drug) {
      console.error(`[FAIL] ${tc.query}: Could not resolve drug (${tc.note})`);
      failed++;
      continue;
    }

    const evalRes = detector.evaluateDrug(drug, { persistAlert: false });
    const launchOk = evalRes.launch_detected === tc.expectLaunch;
    const strengthOk = !tc.mustIncludeStrength ||
      (drug.strength || '').toLowerCase().includes(tc.mustIncludeStrength.toLowerCase());

    if (launchOk && strengthOk) {
      console.log(
        `[PASS] ${tc.query} -> ${drug.brand_name || drug.generic_name} | launch=${evalRes.launch_detected} ` +
        `| TE=${evalRes.signal_1_regulatory.signal?.te_code || '-'} | strengths=${drug.strength || '-'}`
      );
      passed++;
    } else {
      console.error(
        `[FAIL] ${tc.query} (${tc.note}): expected launch=${tc.expectLaunch} (got ${evalRes.launch_detected}), ` +
        `expected strength "${tc.mustIncludeStrength || 'any'}" (got "${drug.strength}")`
      );
      failed++;
    }
  }

  console.log(`\nClinical Regression Summary: ${passed}/${GOLDEN_CASES.length} passed, ${failed} failed.`);
  if (failed > 0) process.exitCode = 1;
}

main();
