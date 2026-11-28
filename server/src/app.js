const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const config = require('./config');
const { createCheckUpdatesRouter } = require('./routes/checkUpdates');
const { createDrugsRouter } = require('./routes/drugs');
const { createSchedulerRouter } = require('./routes/scheduler');
const { createPushRouter } = require('./routes/push');
const { createReviewsRouter } = require('./routes/reviews');
const { createStatsRouter, recordDailyMetric, isLikelyBot } = require('./routes/stats');
const { createSeoRouter } = require('./routes/seo');
const { createB2bRouter } = require('./routes/b2b');
const { IngestionScheduler } = require('./scheduler');

/**
 * Create and configure Express application
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {object} [options]
 * @param {IngestionScheduler} [options.scheduler]
 * @param {boolean} [options.enableRateLimiter=true]
 * @returns {express.Application}
 */
function createApp(db, options = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // Accurate client IP behind Railway / reverse proxies

  const scheduler = options.scheduler || new IngestionScheduler(db);
  const enableRateLimiter = options.enableRateLimiter !== false;

  // 1. Security Headers via Helmet (explicit no-referrer so outbound pharmacy links never receive internal URLs)
  app.use(helmet({
    contentSecurityPolicy: false, // Flutter Web uses CanvasKit WASM + inline bootstrap
    crossOriginEmbedderPolicy: false,
    referrerPolicy: { policy: 'no-referrer' }
  }));

  // 2. CORS: Explicit allowlist for browser origins; native mobile apps send no Origin
  const allowedOrigins = new Set(config.CORS_ALLOWED_ORIGINS);
  app.use(cors({
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.has(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-Key']
  }));

  // 3. Rate Limiting: Abuse and denial-of-service prevention
  if (enableRateLimiter) {
    const apiLimiter = rateLimit({
      windowMs: config.RATE_LIMIT_WINDOW_MS,
      max: config.RATE_LIMIT_MAX_REQUESTS,
      standardHeaders: true,
      legacyHeaders: false,
      message: {
        error: 'Too Many Requests',
        message: 'Rate limit exceeded. Please retry later.'
      }
    });
    app.use('/api', apiLimiter);
  }

  // 4. Request Body Parsing with strict size bounds (+ rawBody capture for Stripe webhook HMAC verification)
  app.use(express.json({
    limit: '64kb',
    verify: (req, res, buf) => {
      if (req.originalUrl === '/api/b2b/stripe-webhook') {
        req.rawBody = buf;
      }
    }
  }));

  // 5. Zero-PII & Privacy Cache-Control headers on API & health endpoints
  app.use(['/api', '/health'], (req, res, next) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    next();
  });

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  });

  // Aggregate zero-PII daily counters (no IPs, cookies, user IDs, or drug names stored)
  app.use('/api/drugs', (req, res, next) => {
    const hasPostQuery = req.method === 'POST' && req.path === '/search' && typeof req.body?.q === 'string' && req.body.q.trim().length > 0;
    if (hasPostQuery) {
      recordDailyMetric(db, 'api_searches');
    }
    next();
  });
  app.use('/api/check-updates', (req, res, next) => {
    if (req.method === 'POST') {
      recordDailyMetric(db, 'cabinet_syncs');
    }
    next();
  });

  // API Routes
  app.use('/api', createCheckUpdatesRouter(db));
  app.use('/api', createDrugsRouter(db));
  app.use('/api', createSchedulerRouter(scheduler));
  app.use('/api', createPushRouter(db));
  app.use('/api', createReviewsRouter(db, { enableRateLimiter }));
  app.use('/api', createStatsRouter(db));
  app.use('/', createB2bRouter(db));


// Public Privacy Policy page synced with docs/play_store/privacy_policy.md
  app.get('/privacy', (req, res) => {
    const policyHtmlPath = path.join(__dirname, '..', '..', 'docs', 'play_store', 'privacy_policy.md');
    let lastUpdated = 'November 27, 2026';
    if (fs.existsSync(policyHtmlPath)) {
      const md = fs.readFileSync(policyHtmlPath, 'utf8');
      const m = md.match(/\*\*Effective date:\*\*\s*([^\r\n]+)/i);
      if (m) lastUpdated = m[1].trim();
    }
    res.type('text/html; charset=utf-8').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>Rx Savings Watch â€” Privacy Policy | Dangling Dice Studiosâ„¢</title>
  <style>
    :root {
      --brand: #0F5132;
      --brand-hover: #0A3622;
      --canvas: #FAF9F6;
      --surface: #FFFFFF;
      --subtle: #F3F2EE;
      --ink: #11181C;
      --muted: #59636E;
      --border: #E5E4E0;
      --savings-bg: #ECFDF5;
      --savings-text: #065F46;
      --savings-border: #A7F3D0;
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: var(--sans);
      background: var(--canvas);
      color: var(--ink);
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
    }
    header {
      background: var(--canvas);
      border-bottom: 1px solid var(--border);
      padding: 14px 24px;
    }
    .nav {
      max-width: 820px;
      margin: 0 auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      text-decoration: none;
      color: var(--ink);
      font-weight: 600;
      font-size: 15px;
      letter-spacing: -0.02em;
    }
    .brand-mark {
      font-family: var(--mono);
      background: var(--brand);
      color: #FFFFFF;
      padding: 3px 7px;
      border-radius: 5px;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.04em;
    }
    main {
      max-width: 820px;
      margin: 32px auto 64px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 36px 36px;
    }
    @media (max-width: 640px) {
      main { margin: 16px; padding: 24px 20px; }
    }
    h1 {
      margin: 0 0 8px;
      color: var(--ink);
      font-size: 28px;
      font-weight: 600;
      letter-spacing: -0.03em;
      line-height: 1.15;
    }
    h2 {
      color: var(--ink);
      font-size: 18px;
      font-weight: 600;
      letter-spacing: -0.02em;
      margin-top: 28px;
      margin-bottom: 8px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
    }
    p, li { max-width: 66ch; font-size: 15px; }
    .meta {
      font-family: var(--mono);
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 20px;
    }
    .box {
      background: var(--savings-bg);
      border-left: 4px solid var(--brand);
      border-top: 1px solid var(--savings-border);
      border-right: 1px solid var(--savings-border);
      border-bottom: 1px solid var(--savings-border);
      color: var(--savings-text);
      border-radius: 6px;
      padding: 14px 16px;
      margin: 18px 0;
      font-size: 14px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 16px 0;
      font-size: 13.5px;
      border: 1px solid var(--border);
    }
    th, td {
      border-bottom: 1px solid var(--border);
      border-right: 1px solid var(--border);
      padding: 10px 12px;
      text-align: left;
      vertical-align: top;
    }
    th {
      background: var(--subtle);
      color: var(--ink);
      font-family: var(--mono);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    ul { padding-left: 20px; }
    li { margin-bottom: 6px; }
    a { color: var(--brand); font-weight: 600; text-decoration: underline; text-underline-offset: 2px; }
    a:hover { color: var(--brand-hover); }
    code {
      font-family: var(--mono);
      font-size: 12.5px;
      background: var(--subtle);
      border: 1px solid var(--border);
      padding: 1px 5px;
      border-radius: 4px;
    }
    footer {
      margin-top: 32px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
      font-size: 12.5px;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <a class="brand" href="/">
        <span class="brand-mark">RX</span>
        <span>Rx Savings Watch</span>
      </a>
      <a href="/" style="font-size:13.5px;text-decoration:none;">&larr; Back to App</a>
    </div>
  </header>
  <main>
    <h1>Privacy Policy</h1>
    <div class="meta">EFFECTIVE: ${lastUpdated.toUpperCase()} &bull; DANGLING DICE STUDIOS&trade; &bull; <a href="mailto:support@danglingdicestudios.com">SUPPORT@DANGLINGDICESTUDIOS.COM</a></div>
    <div class="box">This policy explains what information the Rx Savings Watch app (Android) and website (rx.dangling-dice-studios.com) handle, why, and the choices you have. <strong>Rx Savings Watch is an independent app and is not affiliated with, endorsed by, or representing the FDA, NIH/NLM, CMS, HHS, or any government agency.</strong></div>
    <h2>1. The short version</h2>
    <ul>
      <li><strong>No accounts.</strong> You never create an account, log in, or give us your name, email, or phone number to use the app.</li>
      <li><strong>Your medication list stays on your device.</strong> Your medication cabinets, reminders, refill dates, supplements, notes, and settings are stored only on your phone (or in your browser on the website).</li>
      <li><strong>Some lookups need our server.</strong> To check for generic launches, shortages, and prices, the app sends public drug codes to our server. These requests carry no name, account, or device ID.</li>
      <li><strong>No ad networks, no analytics SDKs, no cookies, no selling of data.</strong></li>
    </ul>
    <h2>2. Information stored only on your device</h2>
    <p>Medication cabinets and caregiver cabinet names, medication reminders and "Taken Today" status, refill dates and supply information, OTC and supplement lists, the copay amount you type into the savings calculator, your saved ZIP code, and your app settings stay strictly on your device. Erase all of it anytime in <strong>Settings &rarr; Erase My Medication List</strong> or by uninstalling the app.</p>
    <h2>3. Information sent to our server</h2>
    <table>
      <thead><tr><th>What is sent</th><th>When</th><th>Why</th><th>Stored?</th></tr></thead>
      <tbody>
        <tr><td><strong>Drug codes (RxNorm RxCUIs)</strong> + decoy common codes</td><td>Checking for updates</td><td>Return current FDA generic, shortage, and price info</td><td>No.</td></tr>
        <tr><td><strong>Medication search terms</strong></td><td>Searching for a drug</td><td>Find the drug in catalog or public FDA/NLM databases</td><td>No. Search text is never saved.</td></tr>
        <tr><td><strong>A drug code</strong></td><td>Opening savings options</td><td>Return pharmacy &amp; savings links</td><td>No.</td></tr>
        <tr><td><strong>Data-quality reports</strong> (drug code + fixed issue category)</td><td>Only if you report a problem</td><td>Fix catalog errors</td><td>Yes, with no info about who sent it.</td></tr>
        <tr><td><strong>Your 5-digit ZIP code</strong> (never your medication)</td><td>Only if you enter a ZIP</td><td>List licensed pharmacies from the public CMS NPI Registry</td><td>No. Results cached by ZIP up to 24h, not linked to you.</td></tr>
        <tr><td><strong>Sponsored pharmacy taps</strong> (pharmacy + Call/Transfer/Website)</td><td>Tapping a sponsored listing</td><td>Give sponsoring pharmacies a total count of taps</td><td>Only as a running total per pharmacy.</td></tr>
        <tr><td><strong>Reviews &amp; feedback</strong> (rating, category, message, platform)</td><td>Only if you submit a review</td><td>Read and respond to feedback</td><td>Yes. Stored privately &amp; emailed to support inbox via Resend. Never public.</td></tr>
      </tbody>
    </table>
    <p><strong>Please do not include your name, contact details, or personal health details in a review message.</strong> We also keep plain daily aggregate counts (e.g., total searches/day) with no user information.</p>
    <h2>4. IP addresses and network information</h2>
    <p>Our server and hosting provider (Railway) receive your IP address when connecting. We use it only temporarily in memory for rate limiting, abuse prevention, and preventing duplicate counts of sponsored-pharmacy taps (up to 24h). We never store IP addresses in our database or link them to drug codes, searches, ZIP codes, or reviews.</p>
    <h2>5. Camera and the QR transfer scanner (Android)</h2>
    <p>Camera images are processed on-device and never saved or uploaded by us. The scanner uses <strong>Google ML Kit</strong>, which may send diagnostic/usage info (device model, OS/app version, performance metrics, error codes, and a per-installation identifier) to Google only when you use the scanner (<a href="https://developers.google.com/ml-kit/android-data-disclosure" target="_blank" rel="noopener noreferrer">ML Kit data disclosure</a>). Cabinet transfer links (<code>â€¦/#import=â€¦</code>) keep drug codes in the URL <code>#</code> fragment, which browsers never send to any server.</p>
    <h2>6. Website-only features</h2>
    <ul>
      <li><strong>Browser notifications (optional):</strong> Stores a push subscription endpoint/keys solely to send public generic-launch alerts (identical for everyone).</li>
      <li><strong>Tip jar:</strong> Handled by Buy Me a Coffee under its own privacy policy.</li>
      <li><strong>Pharmacy &amp; clinic partner program (businesses only):</strong> Business contact info, service ZIPs, optional NPI verification (CMS NPI Registry), and Stripe billing (we never receive full card details).</li>
    </ul>
    <h2>7. Advertising</h2>
    <p>The app shows <strong>"Sponsored Local Partner (Ad)"</strong> listings for local pharmacies paying a flat monthly fee for specific ZIP codes, chosen only by ZIP â€” never by medications or user profiles. No ad networks, advertising IDs, or tracking.</p>
    <h2>8. Links to other websites</h2>
    <p>External pharmacy/savings sites (GoodRx, SingleCare, Cost Plus Drugs, Amazon Pharmacy) and government sources are governed by their own privacy policies. We send no personal/device IDs and use <code>Referrer-Policy: no-referrer</code>. As an Amazon Associate, we earn from qualifying purchases.</p>
    <h2>9. Service providers and public data sources</h2>
    <p>Railway (hosting), Resend (review emails), Google ML Kit (Android QR scanner), Stripe (B2B partner billing), QR Server (partner counter flyer QR images), and public U.S. government data services (openFDA, Drugs@FDA, NLM RxNorm &amp; DailyMed, CMS NADAC, CMS NPI Registry). We never sell or rent personal information or share it for cross-context behavioral advertising.</p>
    <h2>10. Security, Retention, Deletion &amp; Your Rights</h2>
    <p>All traffic uses HTTPS. On-device data stays until you erase it. Reviews stay until no longer needed or until you email <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a> to delete them (see <a href="/data-deletion">Data Deletion Instructions</a>). Depending on where you live (e.g., California, EU/UK), you may have rights to access, correct, or delete personal information â€” email us and we will respond within the time required by law.</p>
    <h2>11. Health Information, Children &amp; Contact</h2>
    <p>Rx Savings Watch is a consumer information tool â€” not a HIPAA-covered entity or medical advice. Not directed to children under 13. Changes update the effective date above. Contact: Dangling Dice Studios&trade; â€” <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a>.</p>
    <footer><a href="/">Rx Savings Watch</a> &middot; <a href="/data-deletion">Data Deletion</a> &middot; <a href="https://dangling-dice-studios.com/">Dangling Dice Studios&trade;</a></footer>
  </main>
</body>
</html>`);
  });

  // Public Google Play Data Deletion instructions page (zero accounts / local-first storage)
  app.get('/data-deletion', (req, res) => {
    res.type('text/html; charset=utf-8').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>Data Deletion â€” Rx Savings Watch (Dangling Dice Studios)</title>
  <style>
    :root { --brand: #0F5132; --canvas: #FAF9F6; --surface: #FFFFFF; --ink: #11181C; --muted: #59636E; --border: #E5E4E0; --savings-bg: #ECFDF5; --savings-text: #065F46; --savings-border: #A7F3D0; --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: var(--sans); background: var(--canvas); color: var(--ink); line-height: 1.6; }
    header { background: var(--canvas); border-bottom: 1px solid var(--border); padding: 14px 24px; }
    .nav { max-width: 780px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; }
    .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--ink); font-weight: 600; font-size: 15px; }
    .brand-mark { background: var(--brand); color: #fff; font-family: var(--mono); font-size: 11px; font-weight: 700; padding: 3px 7px; border-radius: 5px; }
    main { max-width: 780px; margin: 32px auto; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 32px 28px; }
    h1 { margin-top: 0; color: var(--ink); font-size: 26px; letter-spacing: -0.02em; }
    h2 { color: var(--brand); font-size: 17px; margin-top: 24px; }
    .box { background: var(--savings-bg); border-left: 4px solid var(--brand); border-top: 1px solid var(--savings-border); border-right: 1px solid var(--savings-border); border-bottom: 1px solid var(--savings-border); color: var(--savings-text); border-radius: 6px; padding: 14px 16px; margin: 16px 0; font-size: 14px; }
    a { color: var(--brand); font-weight: 600; }
    footer { margin-top: 28px; padding-top: 16px; border-top: 1px solid var(--border); font-size: 12.5px; color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <a class="brand" href="/"><span class="brand-mark">RX</span><span>Rx Savings Watch</span></a>
      <a href="/" style="font-size:13.5px;text-decoration:none;">&larr; Back to App</a>
    </div>
  </header>
  <main>
    <h1>Data Deletion Instructions</h1>
    <p><strong>Developer:</strong> Dangling Dice Studios&trade; &nbsp;|&nbsp; <strong>App:</strong> Rx Savings Watch (Android &amp; Web)</p>
    <div class="box"><strong>No User Accounts or Cloud Profiles:</strong> Rx Savings Watch does not create user accounts and does not store your medication cabinet, reminders, refill dates, or ZIP code on any remote server. All medication data stays strictly on your own device.</div>
    <h2>1. Delete All On-Device App Data Immediately</h2>
    <ol>
      <li>Open <strong>Rx Savings Watch</strong>.</li>
      <li>Go to <strong>Settings &rarr; Your Device Data</strong>.</li>
      <li>Tap <strong>Erase My Medication List</strong> and confirm. This immediately and permanently deletes all saved medications, caregiver cabinets, refill dates, reminders, and local preferences from your device.</li>
      <li>Alternatively, uninstalling the Android app (or clearing site data in your web browser) permanently deletes all local app data.</li>
    </ol>
    <h2>2. Delete Optional Web Push Subscriptions or Feedback</h2>
    <ul>
      <li><strong>Browser Push Alerts:</strong> Toggle off in <strong>Settings &rarr; Turn Off Browser Alerts</strong> to immediately remove your anonymous push endpoint from our server.</li>
      <li><strong>In-App Feedback / Review Submissions:</strong> Email <a href="mailto:support@danglingdicestudios.com?subject=Rx%20Savings%20Watch%20Data%20Deletion%20Request">support@danglingdicestudios.com</a> with the date/details of your message and we will delete it within 7 days.</li>
    </ul>
    <h2>3. Data Retention Summary</h2>
    <p>Transient network requests (anonymous medication lookups or 5-digit ZIP pharmacy lookups) are processed solely to return results and are not linked to any user profile. Aggregate daily server counters contain no personal identifiers, IP addresses, or medication names.</p>
    <footer><a href="/">Return to Rx Savings Watch</a> &middot; <a href="/privacy">Privacy Policy</a> &middot; Contact: <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a></footer>
  </main>
</body>
</html>`);
  });

  // Catch-all 404 for unknown /api/* routes (prevents info leakage)
  app.use('/api', (req, res) => {
    res.status(404).json({ error: 'Not Found' });
  });

  // Server-rendered SEO pages (/robots.txt, /sitemap.xml, /medications, /medications/:slug)
  app.use('/', createSeoRouter(db));

  // Serve Flutter Web App at '/' if built into server/public
  const webPublicDir = path.join(__dirname, '..', 'public');
  if (fs.existsSync(webPublicDir)) {
    app.get('/', (req, res) => {
      if (!isLikelyBot(req.get('user-agent'))) {
        recordDailyMetric(db, 'web_visits');
      }
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.sendFile(path.join(webPublicDir, 'index.html'));
    });
    app.use(express.static(webPublicDir, {
      setHeaders: (res, filePath) => {
        if (filePath.endsWith('.html') || filePath.endsWith('rx_bottle_ocr.js') || filePath.endsWith('rx_push_bridge.js')) {
          res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        }
      }
    }));
  }

  // Error handling middleware
  app.use((err, req, res, next) => {
    console.error('Unhandled server error:', err);
    res.status(500).json({ error: 'Internal Server Error' });
  });

  return app;
}

module.exports = {
  createApp
};
      <tbody>
        <tr><td><strong>Drug codes (RxNorm RxCUIs)</strong> + decoy common codes</td><td>Checking for updates</td><td>Return current FDA generic, shortage, and price info</td><td>No.</td></tr>
        <tr><td><strong>Medication search terms</strong></td><td>Searching for a drug</td><td>Find the drug in catalog or public FDA/NLM databases</td><td>No. Search text is never saved.</td></tr>
        <tr><td><strong>A drug code</strong></td><td>Opening savings options</td><td>Return pharmacy &amp; savings links</td><td>No.</td></tr>
        <tr><td><strong>Data-quality reports</strong> (drug code + fixed issue category)</td><td>Only if you report a problem</td><td>Fix catalog errors</td><td>Yes, with no info about who sent it.</td></tr>
        <tr><td><strong>Your 5-digit ZIP code</strong> (never your medication)</td><td>Only if you enter a ZIP</td><td>List licensed pharmacies from the public CMS NPI Registry</td><td>No. Results cached by ZIP up to 24h, not linked to you.</td></tr>
        <tr><td><strong>Sponsored pharmacy taps</strong> (pharmacy + Call/Transfer/Website)</td><td>Tapping a sponsored listing</td><td>Give sponsoring pharmacies a total count of taps</td><td>Only as a running total per pharmacy.</td></tr>
        <tr><td><strong>Reviews &amp; feedback</strong> (rating, category, message, platform)</td><td>Only if you submit a review</td><td>Read and respond to feedback</td><td>Yes. Stored privately &amp; emailed to support inbox via Resend. Never public.</td></tr>
      </tbody>
    </table>
    <p><strong>Please do not include your name, contact details, or personal health details in a review message.</strong> We also keep plain daily aggregate counts (e.g., total searches/day) with no user information.</p>
    <h2>4. IP addresses and network information</h2>
    <p>Our server and hosting provider (Railway) receive your IP address when connecting. We use it only temporarily in memory for rate limiting, abuse prevention, and preventing duplicate counts of sponsored-pharmacy taps (up to 24h). We never store IP addresses in our database or link them to drug codes, searches, ZIP codes, or reviews.</p>
    <h2>5. Camera and the QR transfer scanner (Android)</h2>
    <p>Camera images are processed on-device and never saved or uploaded by us. The scanner uses <strong>Google ML Kit</strong>, which may send diagnostic/usage info (device model, OS/app version, performance metrics, error codes, and a per-installation identifier) to Google only when you use the scanner (<a href="https://developers.google.com/ml-kit/android-data-disclosure" target="_blank" rel="noopener noreferrer">ML Kit data disclosure</a>). Cabinet transfer links (<code>…/#import=…</code>) keep drug codes in the URL <code>#</code> fragment, which browsers never send to any server.</p>
    <h2>6. Website-only features</h2>
    <ul>
      <li><strong>Browser notifications (optional):</strong> Stores a push subscription endpoint/keys solely to send public generic-launch alerts (identical for everyone).</li>
      <li><strong>Tip jar:</strong> Handled by Buy Me a Coffee under its own privacy policy.</li>
      <li><strong>Pharmacy &amp; clinic partner program (businesses only):</strong> Business contact info, service ZIPs, optional NPI verification (CMS NPI Registry), and Stripe billing (we never receive full card details).</li>
    </ul>
    <h2>7. Advertising</h2>
    <p>The app shows <strong>"Sponsored Local Partner (Ad)"</strong> listings for local pharmacies paying a flat monthly fee for specific ZIP codes, chosen only by ZIP — never by medications or user profiles. No ad networks, advertising IDs, or tracking.</p>
    <h2>8. Links to other websites</h2>
    <p>External pharmacy/savings sites (GoodRx, SingleCare, Cost Plus Drugs, Amazon Pharmacy) and government sources are governed by their own privacy policies. We send no personal/device IDs and use <code>Referrer-Policy: no-referrer</code>. As an Amazon Associate, we earn from qualifying purchases.</p>
    <h2>9. Service providers and public data sources</h2>
    <p>Railway (hosting), Resend (review emails), Google ML Kit (Android QR scanner), Stripe (B2B partner billing), QR Server (partner counter flyer QR images), and public U.S. government data services (openFDA, Drugs@FDA, NLM RxNorm &amp; DailyMed, CMS NADAC, CMS NPI Registry). We never sell or rent personal information or share it for cross-context behavioral advertising.</p>
    <h2>10. Security, Retention, Deletion &amp; Your Rights</h2>
    <p>All traffic uses HTTPS. On-device data stays until you erase it. Reviews stay until no longer needed or until you email <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a> to delete them (see <a href="/data-deletion">Data Deletion Instructions</a>). Depending on where you live (e.g., California, EU/UK), you may have rights to access, correct, or delete personal information — email us and we will respond within the time required by law.</p>
    <h2>11. Health Information, Children &amp; Contact</h2>
    <p>Rx Savings Watch is a consumer information tool — not a HIPAA-covered entity or medical advice. Not directed to children under 13. Changes update the effective date above. Contact: Dangling Dice Studios&trade; — <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a>.</p>
    <footer><a href="/">Rx Savings Watch</a> &middot; <a href="/data-deletion">Data Deletion</a> &middot; <a href="https://dangling-dice-studios.com/">Dangling Dice Studios&trade;</a></footer>
  </main>
</body>
</html>`);
  });

  // Public Google Play Data Deletion instructions page (zero accounts / local-first storage)
  app.get('/data-deletion', (req, res) => {
    res.type('text/html; charset=utf-8').send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="no-referrer">
  <title>Data Deletion — Rx Savings Watch (Dangling Dice Studios)</title>
  <style>
    :root { --brand: #0F5132; --canvas: #FAF9F6; --surface: #FFFFFF; --ink: #11181C; --muted: #59636E; --border: #E5E4E0; --savings-bg: #ECFDF5; --savings-text: #065F46; --savings-border: #A7F3D0; --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: var(--sans); background: var(--canvas); color: var(--ink); line-height: 1.6; }
    header { background: var(--canvas); border-bottom: 1px solid var(--border); padding: 14px 24px; }
    .nav { max-width: 780px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; }
    .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--ink); font-weight: 600; font-size: 15px; }
    .brand-mark { background: var(--brand); color: #fff; font-family: var(--mono); font-size: 11px; font-weight: 700; padding: 3px 7px; border-radius: 5px; }
    main { max-width: 780px; margin: 32px auto; background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 32px 28px; }
    h1 { margin-top: 0; color: var(--ink); font-size: 26px; letter-spacing: -0.02em; }
    h2 { color: var(--brand); font-size: 17px; margin-top: 24px; }
    .box { background: var(--savings-bg); border-left: 4px solid var(--brand); border-top: 1px solid var(--savings-border); border-right: 1px solid var(--savings-border); border-bottom: 1px solid var(--savings-border); color: var(--savings-text); border-radius: 6px; padding: 14px 16px; margin: 16px 0; font-size: 14px; }
    a { color: var(--brand); font-weight: 600; }
    footer { margin-top: 28px; padding-top: 16px; border-top: 1px solid var(--border); font-size: 12.5px; color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <a class="brand" href="/"><span class="brand-mark">RX</span><span>Rx Savings Watch</span></a>
      <a href="/" style="font-size:13.5px;text-decoration:none;">&larr; Back to App</a>
    </div>
  </header>
  <main>
    <h1>Data Deletion Instructions</h1>
    <p><strong>Developer:</strong> Dangling Dice Studios&trade; &nbsp;|&nbsp; <strong>App:</strong> Rx Savings Watch (Android &amp; Web)</p>
    <div class="box"><strong>No User Accounts or Cloud Profiles:</strong> Rx Savings Watch does not create user accounts and does not store your medication cabinet, reminders, refill dates, or ZIP code on any remote server. All medication data stays strictly on your own device.</div>
    <h2>1. Delete All On-Device App Data Immediately</h2>
    <ol>
      <li>Open <strong>Rx Savings Watch</strong>.</li>
      <li>Go to <strong>Settings &rarr; Your Device Data</strong>.</li>
      <li>Tap <strong>Erase My Medication List</strong> and confirm. This immediately and permanently deletes all saved medications, caregiver cabinets, refill dates, reminders, and local preferences from your device.</li>
      <li>Alternatively, uninstalling the Android app (or clearing site data in your web browser) permanently deletes all local app data.</li>
    </ol>
    <h2>2. Delete Optional Web Push Subscriptions or Feedback</h2>
    <ul>
      <li><strong>Browser Push Alerts:</strong> Toggle off in <strong>Settings &rarr; Turn Off Browser Alerts</strong> to immediately remove your anonymous push endpoint from our server.</li>
      <li><strong>In-App Feedback / Review Submissions:</strong> Email <a href="mailto:support@danglingdicestudios.com?subject=Rx%20Savings%20Watch%20Data%20Deletion%20Request">support@danglingdicestudios.com</a> with the date/details of your message and we will delete it within 7 days.</li>
    </ul>
    <h2>3. Data Retention Summary</h2>
    <p>Transient network requests (anonymous medication lookups or 5-digit ZIP pharmacy lookups) are processed solely to return results and are not linked to any user profile. Aggregate daily server counters contain no personal identifiers, IP addresses, or medication names.</p>
    <footer><a href="/">Return to Rx Savings Watch</a> &middot; <a href="/privacy">Privacy Policy</a> &middot; Contact: <a href="mailto:support@danglingdicestudios.com">support@danglingdicestudios.com</a></footer>
  </main>
</body>
</html>`);
  });

  // Catch-all 404 for unknown /api/* routes (prevents info leakage)
  app.use('/api', (req, res) => {
    res.status(404).json({ error: 'Not Found' });
  });

  // Server-rendered SEO pages (/robots.txt, /sitemap.xml, /medications, /medications/:slug)
  app.use('/', createSeoRouter(db));

  // Serve Flutter Web App at '/' if built into server/public
  const webPublicDir = path.join(__dirname, '..', 'public');
  if (fs.existsSync(webPublicDir)) {
    app.get('/', (req, res) => {
      if (!isLikelyBot(req.get('user-agent'))) {
        recordDailyMetric(db, 'web_visits');
      }
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.sendFile(path.join(webPublicDir, 'index.html'));
    });
    app.use(express.static(webPublicDir, {
      setHeaders: (res, filePath) => {
        if (filePath.endsWith('.html') || filePath.endsWith('rx_bottle_ocr.js') || filePath.endsWith('rx_push_bridge.js')) {
          res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        }
      }
    }));
  }

  // Error handling middleware
  app.use((err, req, res, next) => {
    console.error('Unhandled server error:', err);
    res.status(500).json({ error: 'Internal Server Error' });
  });

  return app;
}

module.exports = {
  createApp
};
