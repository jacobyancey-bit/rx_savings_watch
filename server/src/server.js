const fs = require('node:fs');
const path = require('node:path');
const config = require('./config');
const { getDb, initSchema } = require('./db');
const { createApp } = require('./app');
const { runLiveIngestion } = require('./ingestion/live_feeds');
const { GenericLaunchDetector } = require('./detector');
const { IngestionScheduler } = require('./scheduler');

const db = getDb();
initSchema(db);

const scheduler = new IngestionScheduler(db);
const app = createApp(db, { scheduler });

const server = app.listen(config.PORT, () => {
  console.log(`rx_savings_watch server running on port ${config.PORT}`);
  scheduler.start();

  // Auto-seed on first boot when mounted onto a fresh persistent volume
  try {
    const count = db.prepare('SELECT COUNT(*) AS total FROM drugs').get().total;
    if (count === 0) {
      const candidates = [
        path.resolve(__dirname, '../seed/live_seed_drugs.json'),
        path.resolve(__dirname, '../data/live_seed_drugs.json'),
      ];
      const seedPath = candidates.find(p => fs.existsSync(p));
      if (seedPath) {
        const seedList = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
        console.log(`[Boot] Fresh database detected. Running live 6-source seed for ${seedList.length} medications in background...`);
        runLiveIngestion(db, seedList)
          .then(summary => {
            const detector = new GenericLaunchDetector(db);
            detector.runAll({ persistAlert: true });
            console.log(`[Boot] Live auto-seed complete: ${summary.drugsProcessed} drugs, ${summary.nadacRecords} NADAC prices, ${summary.shortagesMatched} shortages.`);
          })
          .catch(err => console.error('[Boot] Live auto-seed error:', err.message));
      }
    } else {
      // Kick off one gentle rolling audit 15s after boot so existing cached drugs
      // immediately benefit from updated FDA/CMS accuracy rules
      const bootAuditTimer = setTimeout(() => {
        scheduler.runRollingLiveAudit({ batchSize: 50, delayMs: 400 })
          .catch(err => console.error('[Boot] Rolling audit error:', err.message));
      }, 15000);
      bootAuditTimer.unref?.();
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
