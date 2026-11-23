const fs = require('node:fs');
const path = require('node:path');
const config = require('./config');
const { getDb, initSchema } = require('./db');
const { createApp } = require('./app');
const { runLiveIngestion, seedMissingDrugs } = require('./ingestion/live_feeds');
const { GenericLaunchDetector } = require('./detector');
const { IngestionScheduler } = require('./scheduler');

const db = getDb();
initSchema(db);

const scheduler = new IngestionScheduler(db);
const app = createApp(db, { scheduler });

const server = app.listen(config.PORT, () => {
  console.log(`rx_savings_watch server running on port ${config.PORT}`);
  scheduler.start();

  // Auto-seed on first boot or incrementally seed newly added top prescriptions in background
  try {
    const candidates = [
      path.resolve(__dirname, '../seed/live_seed_drugs.json'),
      path.resolve(__dirname, '../data/live_seed_drugs.json'),
    ];
    const seedPath = candidates.find(p => fs.existsSync(p));
    const count = db.prepare('SELECT COUNT(*) AS total FROM drugs').get().total;

    if (count === 0 && seedPath) {
      const seedList = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
      console.log(`[Boot] Fresh database detected. Running live 6-source seed for ${seedList.length} medications in background...`);
      seedMissingDrugs(db, seedList, { delayMs: 350 })
        .then(summary => {
          console.log(`[Boot] Live auto-seed complete: ${summary.seeded}/${summary.missingCount} drugs added (skipped=${summary.skipped}, errors=${summary.errors}).`);
        })
        .catch(err => console.error('[Boot] Live auto-seed error:', err.message));
    } else {
      // Incrementally seed any newly added top U.S. prescriptions missing from SQLite,
      // then kick off a gentle rolling audit so existing cached drugs stay fresh.
      const bootSeedTimer = setTimeout(async () => {
        try {
          if (seedPath) {
            const seedList = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
            const summary = await seedMissingDrugs(db, seedList, { delayMs: 350 });
            if (summary.missingCount > 0) {
              console.log(`[Boot] Incremental seed complete: ${summary.seeded}/${summary.missingCount} new drugs added (skipped=${summary.skipped}, errors=${summary.errors}).`);
            }
          }
          await scheduler.runRollingLiveAudit({ batchSize: 50, delayMs: 400 });
        } catch (err) {
          console.error('[Boot] Background seed/audit error:', err.message);
        }
      }, 5000);
      bootSeedTimer.unref?.();
    }
  } catch (err) {
    console.error('[Boot] Database check error:', err.message);
  }
});

process.on('SIGTERM', () => {
  scheduler.stop();
  server.close();
});

module.exports = { app, server };
