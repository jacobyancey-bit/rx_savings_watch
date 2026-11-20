const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, initSchema } = require('../src/db');

test('Schema: initializes normalized tables and pragmas', () => {
  const db = getDb(':memory:');
  initSchema(db);

  // Check pragmas
  const fkCheck = db.prepare('PRAGMA foreign_keys').get();
  assert.equal(fkCheck.foreign_keys, 1, 'Foreign keys pragma must be ON');

  // Check all required normalized tables exist
  const tables = db.prepare(`
    SELECT name FROM sqlite_master 
    WHERE type='table' AND name NOT LIKE 'sqlite_%'
  `).all().map(t => t.name);

  const requiredTables = [
    'drugs',
    'generic_status',
    'market_availability',
    'drug_shortages',
    'alert_events'
  ];

  for (const table of requiredTables) {
    assert.ok(tables.includes(table), `Table ${table} must exist`);
  }
});

test('Schema: enforces unique constraints and foreign keys', () => {
  const db = getDb(':memory:');
  initSchema(db);

  // Insert a drug
  const insertDrug = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name, drug_type)
    VALUES (?, ?, ?, ?)
  `);
  insertDrug.run('111111', 'TestBrand', 'test generic', 'small_molecule');

  // Attempt duplicate RXCUI
  assert.throws(() => {
    insertDrug.run('111111', 'DuplicateBrand', 'another generic', 'small_molecule');
  }, /UNIQUE constraint failed/);

  // Check constraint on drug_type
  assert.throws(() => {
    insertDrug.run('222222', 'BadDrug', 'bad type', 'invalid_type');
  }, /CHECK constraint failed/);

  // Foreign key constraint on generic_status
  const insertStatus = db.prepare(`
    INSERT INTO generic_status (drug_id, source, application_number)
    VALUES (?, 'orange_book', 'ANDA999999')
  `);
  assert.throws(() => {
    insertStatus.run(999999); // non-existent drug_id
  }, /FOREIGN KEY constraint failed/);
});

test('Schema: cascade deletion on drug removal', () => {
  const db = getDb(':memory:');
  initSchema(db);

  const drugRes = db.prepare(`
    INSERT INTO drugs (rxcui, brand_name, generic_name)
    VALUES ('333333', 'DeleteMe', 'delete generic')
  `).run();
  const drugId = drugRes.lastInsertRowid;

  db.prepare(`
    INSERT INTO generic_status (drug_id, source, application_number)
    VALUES (?, 'orange_book', 'ANDA123456')
  `).run(drugId);

  db.prepare(`
    INSERT INTO market_availability (drug_id, source, ndc)
    VALUES (?, 'openfda_ndc', '12345-678-90')
  `).run(drugId);

  // Delete drug
  db.prepare('DELETE FROM drugs WHERE id = ?').run(drugId);

  const statusCount = db.prepare('SELECT count(*) as count FROM generic_status WHERE drug_id = ?').get(drugId);
  const marketCount = db.prepare('SELECT count(*) as count FROM market_availability WHERE drug_id = ?').get(drugId);

  assert.equal(statusCount.count, 0, 'Generic status must cascade delete');
  assert.equal(marketCount.count, 0, 'Market availability must cascade delete');
});
