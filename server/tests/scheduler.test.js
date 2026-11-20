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
  assert.equal(scheduler.timers.length, 2);

  scheduler.stop();
  assert.equal(scheduler.isRunning, false);
  assert.equal(scheduler.timers.length, 0);
});
