const { getDb, initSchema, closeDb } = require('../src/db');
const config = require('../src/config');

console.log(`Initializing SQLite database at: ${config.DB_PATH}`);
const db = getDb();
initSchema(db);
console.log('Database schema successfully initialized with tables:');
const tables = db.prepare(`
  SELECT name FROM sqlite_master 
  WHERE type='table' AND name NOT LIKE 'sqlite_%'
  ORDER BY name
`).all();

for (const t of tables) {
  console.log(`  - ${t.name}`);
}

closeDb();
console.log('Initialization complete.');
