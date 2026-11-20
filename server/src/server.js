const config = require('./config');
const { getDb, initSchema } = require('./db');
const { createApp } = require('./app');

const db = getDb();
initSchema(db);

const app = createApp(db);

const server = app.listen(config.PORT, () => {
  console.log(`rx_savings_watch server running on port ${config.PORT}`);
});

module.exports = { app, server };
