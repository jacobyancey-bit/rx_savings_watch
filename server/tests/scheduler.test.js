const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const { IngestionScheduler } = require('../src/scheduler');

test('Scheduler: runFullCycle ingests feeds and triggers launch detection', async () => {
  const db = getDb(':memory:');
  initSchema(db);

  const scheduler = new IngestionScheduler(db);

  // Run full cycle
  const result = await scheduler.runFullCycle();

  assert.ok(result.ingestion.rxnorm.inserted >= 5);
  assert.ok(result.ingestion.orange_book.inserted >= 4);
  assert.ok(result.ingestion.purple_book.inserted >= 3);
  assert.ok(result.detection.length >= 5);

  // Verify that launch alerts were created for Vyvanse, Humira, Truvada
  const alerts = db.prepare("SELECT * FROM alert_events WHERE event_type = 'commercial_generic_launch'").all();
  assert.equal(alerts.length, 3, 'Should have created exactly 3 verified launch alerts');
  assert.ok(scheduler.lastSyncTimes.full);
});

test('Scheduler: start and stop daemon timers', () => {
  const db = getDb(':memory:');
  initSchema(db);

  const scheduler = new IngestionScheduler(db, {
    shortagesIntervalMs: 100000,
    nadacIntervalMs: 500000
  });

  assert.equal(scheduler.isRunning, false);
  scheduler.start();
  assert.equal(scheduler.isRunning, true);
  assert.equal(scheduler.timers.length, 3);

  scheduler.stop();
  assert.equal(scheduler.isRunning, false);
  assert.equal(scheduler.timers.length, 0);
});

test('Scheduler: rolling live audit rotates across 120 drugs in 50-drug batches with zero redundancy', async () => {
  const db = getDb(':memory:');
  initSchema(db);

  // Seed 120 stale drugs (updated 48 hours ago) so all are eligible for rolling audit
  const insertDrug = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name, updated_at)
    VALUES (?, ?, ?, datetime('now', '-48 hours'))
  `);
  for (let i = 1; i <= 120; i++) {
    insertDrug.run(String(100000 + i), `BrandDrug${i}`, `genericdrug${i}`);
  }

  const scheduler = new IngestionScheduler(db, { rollingAuditBatchSize: 50 });

  // Simulate realistic discovery: drug #5 returns null (unreachable) and drug #10 throws an error
  // to prove failed/null drugs still rotate to the back instead of getting polled redundantly.
  const mockDiscover = async (database, query) => {
    if (query === 'BrandDrug5') return null;
    if (query === 'BrandDrug10') throw new Error('Simulated transient FDA timeout');
    return database.prepare('SELECT * FROM drugs WHERE brand_name = ?').get(query);
  };
  const mockShortages = async () => ({ matched: 0 });

  // Cycle 1: must audit drugs 1..50
  const c1 = await scheduler.runRollingLiveAudit({
    batchSize: 50,
    delayMs: 0,
    minAgeHours: 12,
    discoverFn: mockDiscover,
    shortagesFn: mockShortages,
  });
  assert.equal(c1.auditedRxcuis.length, 50);
  assert.equal(c1.refreshed, 48); // 50 - 1 null - 1 error
  assert.equal(c1.errors, 1);

  // Cycle 2: must audit drugs 51..100 with ZERO overlap from Cycle 1
  const c2 = await scheduler.runRollingLiveAudit({
    batchSize: 50,
    delayMs: 0,
    minAgeHours: 12,
    discoverFn: mockDiscover,
    shortagesFn: mockShortages,
  });
  assert.equal(c2.auditedRxcuis.length, 50);
  const c1Set = new Set(c1.auditedRxcuis);
  for (const rxcui of c2.auditedRxcuis) {
    assert.equal(c1Set.has(rxcui), false, `Redundant re-poll detected for RXCUI ${rxcui} in Cycle 2`);
  }

  // Cycle 3: must audit remaining drugs 101..120 with ZERO overlap from Cycles 1 & 2
  const c3 = await scheduler.runRollingLiveAudit({
    batchSize: 50,
    delayMs: 0,
    minAgeHours: 12,
    discoverFn: mockDiscover,
    shortagesFn: mockShortages,
  });
  assert.equal(c3.auditedRxcuis.length, 20);
  const seenSoFar = new Set([...c1.auditedRxcuis, ...c2.auditedRxcuis]);
  for (const rxcui of c3.auditedRxcuis) {
    assert.equal(seenSoFar.has(rxcui), false, `Redundant re-poll detected for RXCUI ${rxcui} in Cycle 3`);
  }

  // Cycle 4 immediately afterward: all 120 drugs are fresh (< 12h old), so ZERO redundant API calls!
  const c4 = await scheduler.runRollingLiveAudit({
    batchSize: 50,
    delayMs: 0,
    minAgeHours: 12,
    discoverFn: mockDiscover,
    shortagesFn: mockShortages,
  });
  assert.equal(c4.auditedRxcuis.length, 0);
  assert.equal(c4.refreshed, 0);
});
