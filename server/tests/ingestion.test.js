const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');
const {
  ingestRxNorm,
  ingestOrangeBook,
  ingestPurpleBook,
  ingestOpenFdaNdc,
  ingestCmsNadac,
  ingestFdaShortages,
  runAllIngestions
} = require('../src/ingestion');

test('Ingestion: individual feeds ingest records accurately', async () => {
  const db = getDb(':memory:');
  initSchema(db);

  // 1. RxNorm
  const rxRes = await ingestRxNorm(db);
  assert.ok(rxRes.inserted >= 5, 'RxNorm should ingest at least 5 drugs');
  const drugsCount = db.prepare('SELECT count(*) as c FROM drugs').get();
  assert.equal(drugsCount.c, rxRes.inserted);

  // 2. Orange Book
  const obRes = await ingestOrangeBook(db);
  assert.ok(obRes.inserted >= 4, 'Orange Book should ingest ANDA records');

  // 3. Purple Book
  const pbRes = await ingestPurpleBook(db);
  assert.ok(pbRes.inserted >= 3, 'Purple Book should ingest biosimilar records');

  // 4. OpenFDA NDC
  const ndcRes = await ingestOpenFdaNdc(db);
  assert.ok(ndcRes.inserted >= 5, 'OpenFDA should ingest NDC directory records');

  // 5. CMS NADAC
  const nadacRes = await ingestCmsNadac(db);
  assert.ok(nadacRes.inserted >= 5, 'CMS NADAC should ingest price records');

  // 6. FDA Shortages
  const shortagesRes = await ingestFdaShortages(db);
  assert.ok(shortagesRes.inserted >= 2, 'FDA Shortages should ingest shortage records');
});

test('Ingestion: idempotent re-ingestion does not duplicate unique rows', async () => {
  const db = getDb(':memory:');
  initSchema(db);

  // Run ingestion twice
  await runAllIngestions(db);
  const count1 = db.prepare('SELECT count(*) as c FROM generic_status').get().c;

  await runAllIngestions(db);
  const count2 = db.prepare('SELECT count(*) as c FROM generic_status').get().c;

  assert.equal(count1, count2, 'Re-ingestion must be idempotent and not duplicate records');
});
