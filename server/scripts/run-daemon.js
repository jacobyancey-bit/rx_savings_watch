const { getDb, initSchema } = require('../src/db');
const { IngestionScheduler } = require('../src/scheduler');

async function main() {
  console.log('='.repeat(70));
  console.log('  Rx Savings Watch - Ingestion & Launch Detector Daemon');
  console.log('='.repeat(70));

  const db = getDb();
  initSchema(db);

  const scheduler = new IngestionScheduler(db);

  // Perform initial full cycle on startup
  try {
    await scheduler.runFullCycle();
  } catch (err) {
    console.error('Initial cycle error:', err);
  }

  // Start continuous scheduler
  scheduler.start();

  console.log('Scheduler daemon is active. Press Ctrl+C to stop.');

  process.on('SIGINT', () => {
    console.log('\nStopping scheduler daemon...');
    scheduler.stop();
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    console.log('\nStopping scheduler daemon...');
    scheduler.stop();
    process.exit(0);
  });
}

main().catch(err => {
  console.error('Fatal scheduler daemon error:', err);
  process.exit(1);
});
