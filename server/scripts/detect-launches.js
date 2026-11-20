const { getDb, initSchema, closeDb } = require('../src/db');
const { GenericLaunchDetector } = require('../src/detector');

function main() {
  const db = getDb();
  initSchema(db);

  console.log('Scanning for 2-signal commercial generic launches...');
  const detector = new GenericLaunchDetector(db);
  const results = detector.runAll({ persistAlert: true });

  let detectedCount = 0;
  for (const r of results) {
    if (r.launch_detected) {
      detectedCount++;
      console.log(`\n[LAUNCH DETECTED] ${r.brand_name || r.generic_name} (${r.generic_name})`);
      console.log(`  Confidence: ${(r.confidence_score * 100).toFixed(0)}%`);
      console.log(`  Signal 1 (Regulatory): ${r.signal_1_regulatory.signal.application_number} (${r.signal_1_regulatory.signal.approval_date})`);
      console.log(`  Signal 2 (Commercial): NDC ${r.signal_2_commercial.signal.first_commercial_ndc} (${r.signal_2_commercial.signal.earliest_commercial_date})`);
      console.log(`  Launch Lag Time: ${r.lag_days} days`);
      if (r.savings.savingsPct !== null) {
        console.log(`  Projected Savings: ${r.savings.savingsPct}% (Brand $${r.savings.brandPrice} vs Generic $${r.savings.genericPrice || r.signal_2_commercial.signal.nadac_per_unit})`);
      }
      console.log(`  Alert Saved: ${r.alert_created ? 'YES' : 'ALREADY RECORDED'}`);
    }
  }

  console.log(`\nScan complete. Total commercial generic launches detected: ${detectedCount}`);
  closeDb();
}

main();
