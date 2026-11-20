const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { runAllIngestions } = require('../src/ingestion');
const { GenericLaunchDetector } = require('../src/detector');
const { evaluateRegulatorySignal, evaluateCommercialSignal, calculateSavings } = require('../src/detector/rules');

test('Detector: requires BOTH signals to trigger a commercial generic launch', () => {
  const db = getDb(':memory:');
  initSchema(db);

  // Setup drug
  const drugId = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name, drug_type)
    VALUES ('999991', 'OnlyRegDrug', 'reg only ingredient', 'small_molecule')
  `).run().lastInsertRowid;

  const drug = db.prepare('SELECT * FROM drugs WHERE id = ?').get(drugId);
  const detector = new GenericLaunchDetector(db);

  // 1. Neither signal satisfied
  let res = detector.evaluateDrug(drug, { persistAlert: false });
  assert.equal(res.launch_detected, false);
  assert.equal(res.signal_1_regulatory.satisfied, false);
  assert.equal(res.signal_2_commercial.satisfied, false);

  // 2. Only Signal 1 (Regulatory Approval) satisfied
  db.prepare(`
    INSERT INTO generic_status (drug_id, source, application_number, approval_date, is_approved_generic)
    VALUES (?, 'orange_book', 'ANDA112233', '2023-01-01', 1)
  `).run(drugId);

  res = detector.evaluateDrug(drug, { persistAlert: false });
  assert.equal(res.signal_1_regulatory.satisfied, true);
  assert.equal(res.signal_2_commercial.satisfied, false);
  assert.equal(res.launch_detected, false, 'Approval alone must NOT trigger commercial launch alert');

  // 3. Only Signal 2 (Commercial) without Signal 1
  const drug2Id = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name, drug_type)
    VALUES ('999992', 'OnlyCommDrug', 'comm only ingredient', 'small_molecule')
  `).run().lastInsertRowid;
  const drug2 = db.prepare('SELECT * FROM drugs WHERE id = ?').get(drug2Id);

  db.prepare(`
    INSERT INTO market_availability (drug_id, source, ndc, marketing_category, marketing_start_date, is_commercialized)
    VALUES (?, 'openfda_ndc', '99999-001-01', 'ANDA', '2023-01-01', 1)
  `).run(drug2Id);

  res = detector.evaluateDrug(drug2, { persistAlert: false });
  assert.equal(res.signal_1_regulatory.satisfied, false);
  assert.equal(res.launch_detected, false, 'Commercial signal alone without FDA approval must NOT trigger');

  // 4. BOTH Signals satisfied -> Launch Triggered!
  db.prepare(`
    INSERT INTO market_availability (drug_id, source, ndc, marketing_category, marketing_start_date, is_commercialized)
    VALUES (?, 'openfda_ndc', '99999-002-01', 'ANDA', '2023-01-10', 1)
  `).run(drugId);

  res = detector.evaluateDrug(drug, { persistAlert: false });
  assert.equal(res.signal_1_regulatory.satisfied, true);
  assert.equal(res.signal_2_commercial.satisfied, true);
  assert.equal(res.launch_detected, true, 'Both signals must trigger launch alert');
  assert.equal(res.lag_days, 9, 'Lag days should be 9 (2023-01-01 to 2023-01-10)');
});

test('Detector: alert persistence and deduplication', () => {
  const db = getDb(':memory:');
  initSchema(db);

  const drugId = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name, drug_type)
    VALUES ('999993', 'DedupBrand', 'dedup generic', 'small_molecule')
  `).run().lastInsertRowid;
  const drug = db.prepare('SELECT * FROM drugs WHERE id = ?').get(drugId);

  db.prepare(`
    INSERT INTO generic_status (drug_id, source, application_number, approval_date, is_approved_generic)
    VALUES (?, 'orange_book', 'ANDA999993', '2023-05-01', 1)
  `).run(drugId);

  db.prepare(`
    INSERT INTO market_availability (drug_id, source, ndc, marketing_category, marketing_start_date, is_commercialized)
    VALUES (?, 'openfda_ndc', '99993-001-01', 'ANDA', '2023-05-05', 1)
  `).run(drugId);

  const detector = new GenericLaunchDetector(db);

  // First evaluation: creates alert
  const res1 = detector.evaluateDrug(drug, { persistAlert: true });
  assert.equal(res1.launch_detected, true);
  assert.equal(res1.alert_created, true);

  const alerts1 = db.prepare('SELECT * FROM alert_events WHERE drug_id = ?').all(drugId);
  assert.equal(alerts1.length, 1);

  // Second evaluation: does not duplicate alert
  const res2 = detector.evaluateDrug(drug, { persistAlert: true });
  assert.equal(res2.launch_detected, true);
  assert.equal(res2.alert_created, false, 'Should not create duplicate alert');

  const alerts2 = db.prepare('SELECT * FROM alert_events WHERE drug_id = ?').all(drugId);
  assert.equal(alerts2.length, 1);
});
