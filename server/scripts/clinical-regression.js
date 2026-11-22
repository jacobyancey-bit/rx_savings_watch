/**
 * Expanded Golden "Tricky & High-Volume Drugs" Clinical Regression Suite (40 Drugs)
 *
 * Verifies live 6-source cross-referencing against official U.S. government APIs
 * (NLM RxNorm, OpenFDA Drugs@FDA, OpenFDA NDC, CMS NADAC, DailyMed SPL, FDA Shortages)
 * in an isolated :memory: SQLite database (zero impact on production).
 *
 * Categories tested:
 *  - Patented Brand-Only Traps (must NEVER false-positive as Generic Available!)
 *  - Multi-Salt & Complex ER Formulations (Mydayis AB2 vs Adderall XR AB1 vs Jornay PM)
 *  - Combination Therapies & Inhalers / Ophthalmics (Truvada, Symbicort, Advair, Restasis)
 *  - Biologics & Biosimilars (Humira, Enbrel, Stelara)
 *  - High-Spend & Top U.S. Maintenance Generics (Lipitor, Crestor, Synthroid, Warfarin, etc.)
 */
const { getDb, initSchema } = require('../src/db');
const { discoverAndIngestDrug } = require('../src/ingestion/live_feeds');
const { GenericLaunchDetector } = require('../src/detector');

const INTER_DRUG_DELAY_MS = 350;

const GOLDEN_CASES = [
  // --- 1. Patented Brand-Only Traps (expectLaunch: false) ---
  { query: 'Jornay PM', expectLaunch: false, mustIncludeStrength: '60 mg', note: 'Brand-only methylphenidate ER (no TE code — must NOT confuse with Ritalin/Concerta)' },
  { query: 'Ozempic', expectLaunch: false, note: 'Patented brand-only GLP-1 (semaglutide)' },
  { query: 'Wegovy', expectLaunch: false, note: 'Patented brand-only weight-loss GLP-1 (semaglutide)' },
  { query: 'Mounjaro', expectLaunch: false, note: 'Patented brand-only GIP/GLP-1 (tirzepatide)' },
  { query: 'Zepbound', expectLaunch: false, note: 'Patented brand-only tirzepatide' },
  { query: 'Eliquis', expectLaunch: false, mustIncludeStrength: '5 mg', note: 'Patented brand-only anticoagulant (apixaban — generics patent-delayed)' },
  { query: 'Jardiance', expectLaunch: false, mustIncludeStrength: '10 mg', note: 'Patented brand-only SGLT2 inhibitor (empagliflozin)' },
  { query: 'Nurtec ODT', expectLaunch: false, note: 'Patented brand-only CGRP migraine ODT (rimegepant)' },
  { query: 'Ubrelvy', expectLaunch: false, note: 'Patented brand-only CGRP migraine tablet (ubrogepant)' },
  { query: 'Dupixent', expectLaunch: false, note: 'Patented brand-only biologic (dupilumab)' },
  { query: 'Skyrizi', expectLaunch: false, note: 'Patented brand-only biologic (risankizumab)' },
  { query: 'Biktarvy', expectLaunch: false, note: 'Patented 3-ingredient HIV combo' },
  { query: 'Trelegy Ellipta', expectLaunch: false, note: 'Patented 3-ingredient COPD/asthma inhaler' },
  { query: 'Vraylar', expectLaunch: false, note: 'Patented brand-only atypical antipsychotic (cariprazine)' },
  { query: 'Trulicity', expectLaunch: false, note: 'Patented brand-only GLP-1 (dulaglutide)' },
  { query: 'Enbrel', expectLaunch: false, note: 'Patent-extended biologic (etanercept — no commercial U.S. biosimilar yet)' },

  // --- 2. Multi-Salt & Complex ADHD / CNS Generics (expectLaunch: true) ---
  { query: 'Mydayis', expectLaunch: true, mustIncludeStrength: '37.5 mg', note: 'Multi-salt 3-bead ER (AB2) with 12.5-50 mg doses' },
  { query: 'Adderall XR', expectLaunch: true, mustIncludeStrength: '20 mg', note: 'Multi-salt 2-bead ER (AB1)' },
  { query: 'Vyvanse', expectLaunch: true, mustIncludeStrength: '30 mg', note: 'Recent high-profile ADHD generic launch (lisdexamfetamine)' },
  { query: 'Concerta', expectLaunch: true, note: 'OROS methylphenidate ER' },
  { query: 'Focalin XR', expectLaunch: true, note: 'Dexmethylphenidate ER' },

  // --- 3. Combination Therapies, Inhalers & Ophthalmics (expectLaunch: true) ---
  { query: 'Truvada', expectLaunch: true, note: '2-ingredient HIV PrEP combination' },
  { query: 'Symbicort', expectLaunch: true, note: 'Combination inhaler / authorized generic' },
  { query: 'Advair Diskus', expectLaunch: true, note: 'Fluticasone/salmeterol dry-powder inhaler' },
  { query: 'Spiriva', expectLaunch: true, note: 'Tiotropium COPD inhaler' },
  { query: 'Restasis', expectLaunch: true, note: 'Cyclosporine ophthalmic emulsion' },
  { query: 'Xalatan', expectLaunch: true, note: 'Latanoprost ophthalmic drops' },

  // --- 4. Top U.S. Maintenance & Specialty Generics (expectLaunch: true) ---
  { query: 'Synthroid', expectLaunch: true, note: 'Narrow-therapeutic-index multi-strength thyroid (levothyroxine)' },
  { query: 'Warfarin', expectLaunch: true, mustIncludeStrength: '5 mg', note: 'Classic multi-strength anticoagulant' },
  { query: 'Lipitor', expectLaunch: true, mustIncludeStrength: '20 mg', note: 'Top-volume statin (atorvastatin)' },
  { query: 'Crestor', expectLaunch: true, mustIncludeStrength: '10 mg', note: 'High-potency statin (rosuvastatin)' },
  { query: 'Plavix', expectLaunch: true, mustIncludeStrength: '75 mg', note: 'Antiplatelet (clopidogrel)' },
  { query: 'Glucophage', expectLaunch: true, note: 'First-line diabetes maintenance (metformin)' },
  { query: 'Prinivil', expectLaunch: true, note: 'ACE inhibitor (lisinopril)' },
  { query: 'Norvasc', expectLaunch: true, note: 'Calcium channel blocker (amlodipine)' },
  { query: 'Cozaar', expectLaunch: true, note: 'ARB blood pressure medication (losartan)' },
  { query: 'Omeprazole', expectLaunch: true, mustIncludeStrength: '20 mg', note: 'PPI acid reducer generic (must NOT collide with combo NDA Talicia!)' },
  { query: 'Neurontin', expectLaunch: true, note: 'Neuropathic pain / seizure (gabapentin)' },
  { query: 'Lyrica', expectLaunch: true, note: 'Pregabalin capsules' },
  { query: 'Celebrex', expectLaunch: true, note: 'COX-2 NSAID (celecoxib)' },
  { query: 'Flomax', expectLaunch: true, note: 'Tamsulosin capsules' },
  { query: 'Aricept', expectLaunch: true, note: 'Donepezil tablets' },
];

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  const db = getDb(':memory:');
  initSchema(db);
  const detector = new GenericLaunchDetector(db);

  let passed = 0;
  let failed = 0;
  const failures = [];

  console.log(`Running Expanded Golden Clinical Regression Suite (${GOLDEN_CASES.length} drugs) against live FDA/RxNorm/CMS APIs...\n`);

  for (let i = 0; i < GOLDEN_CASES.length; i++) {
    const tc = GOLDEN_CASES[i];
    try {
      const drug = await discoverAndIngestDrug(db, tc.query);
      if (!drug) {
        const msg = `[FAIL] ${tc.query}: Could not resolve drug (${tc.note})`;
        console.error(msg);
        failures.push(msg);
        failed++;
      } else {
        const evalRes = detector.evaluateDrug(drug, { persistAlert: false });
        const launchOk = evalRes.launch_detected === tc.expectLaunch;
        const strengthOk = !tc.mustIncludeStrength ||
          (drug.strength || '').toLowerCase().includes(tc.mustIncludeStrength.toLowerCase());

        if (launchOk && strengthOk) {
          console.log(
            `[PASS] (${i + 1}/${GOLDEN_CASES.length}) ${tc.query} -> ${drug.brand_name || drug.generic_name} | launch=${evalRes.launch_detected} ` +
            `| TE=${evalRes.signal_1_regulatory.signal?.te_code || '-'} | strengths=${(drug.strength || '-').slice(0, 48)}`
          );
          passed++;
        } else {
          const msg =
            `[FAIL] (${i + 1}/${GOLDEN_CASES.length}) ${tc.query} (${tc.note}): expected launch=${tc.expectLaunch} (got ${evalRes.launch_detected}), ` +
            `expected strength "${tc.mustIncludeStrength || 'any'}" (got "${drug.strength}")`;
          console.error(msg);
          failures.push(msg);
          failed++;
        }
      }
    } catch (err) {
      const msg = `[FAIL] ${tc.query}: Exception ${err.message}`;
      console.error(msg);
      failures.push(msg);
      failed++;
    }

    if (i < GOLDEN_CASES.length - 1) {
      await sleep(INTER_DRUG_DELAY_MS);
    }
  }

  console.log(`\nClinical Regression Summary: ${passed}/${GOLDEN_CASES.length} passed, ${failed} failed.`);
  if (failures.length > 0) {
    console.error('\nFailed Cases:');
    for (const f of failures) console.error(' - ' + f);
    process.exitCode = 1;
  }
}

main();
