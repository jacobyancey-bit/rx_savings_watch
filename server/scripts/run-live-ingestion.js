const fs = require('node:fs');
const path = require('node:path');
const { getDb, initSchema, closeDb } = require('../src/db');
const { runLiveIngestion } = require('../src/ingestion/live_feeds');
const { GenericLaunchDetector } = require('../src/detector');

async function main() {
  const args = process.argv.slice(2);
  const limitArg = args.find(a => a.startsWith('--limit='));
  const drugArg = args.find(a => a.startsWith('--drug='));

  const seedPath = path.join(__dirname, '..', 'data', 'live_seed_drugs.json');
  let seedList = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

  if (drugArg) {
    const q = drugArg.split('=')[1].toLowerCase();
    seedList = seedList.filter(
      d => (d.brand_name || '').toLowerCase().includes(q) || (d.generic_name || '').toLowerCase().includes(q)
    );
    if (seedList.length === 0) {
      seedList = [{ brand_name: drugArg.split('=')[1], generic_name: drugArg.split('=')[1], drug_type: 'small_molecule' }];
    }
  } else if (limitArg) {
    const limit = Number.parseInt(limitArg.split('=')[1], 10);
    if (limit > 0) seedList = seedList.slice(0, limit);
  }

  const db = getDb();
  initSchema(db);

  console.log(`Starting live 6-source U.S. government cross-reference for ${seedList.length} medications...`);
  console.log('Sources: NLM RxNorm | OpenFDA Drugs@FDA | OpenFDA NDC | CMS NADAC 2026 | NLM DailyMed | FDA Shortages\n');

  try {
    const summary = await runLiveIngestion(db, seedList);
    console.log('Live cross-reference ingestion complete:');
    console.log(`  - Medications cross-referenced: ${summary.drugsProcessed} (skipped: ${summary.drugsSkipped})`);
    console.log(`  - FDA Approvals / TE Codes:     ${summary.regulatoryRecords}`);
    console.log(`  - Finished Commercial NDCs:     ${summary.ndcRecords}`);
    console.log(`  - CMS NADAC 2026 Price Rows:    ${summary.nadacRecords}`);
    console.log(`  - NLM DailyMed SPL Labels:      ${summary.dailyMedRecords}`);
    console.log(`  - Live FDA Shortages Matched:   ${summary.shortagesMatched}`);
    console.log(`  - Price Anomalies Rejected:     ${summary.anomaliesRejected}`);

    console.log('\nRunning 2-signal commercial generic launch detector...');
    const detector = new GenericLaunchDetector(db);
    const detections = detector.runAll({ persistAlert: true });
    const launched = detections.filter(d => d.launch_detected);
    console.log(`Total drugs with verified commercial generics/biosimilars: ${launched.length} / ${detections.length}`);
  } catch (err) {
    console.error('Live ingestion failed:', err);
    process.exitCode = 1;
  } finally {
    closeDb();
  }
}

main();
