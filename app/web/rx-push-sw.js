// Rx Savings Watch — Privacy-Preserving Web Push Service Worker
// Filters public generic launch broadcasts strictly against the user's local IndexedDB cabinet.
// The server NEVER knows which medications this browser is watching.

const DB_NAME = 'rx_savings_watch_push_db';
const STORE_NAME = 'cabinet';
const KEY_WATCHED = 'watched_rxcuis';

function readWatchedRxcuis() {
  return new Promise((resolve) => {
    try {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          db.createObjectStore(STORE_NAME);
        }
      };
      req.onsuccess = (e) => {
        const db = e.target.result;
        const tx = db.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const getReq = store.get(KEY_WATCHED);
        getReq.onsuccess = () => resolve(Array.isArray(getReq.result) ? getReq.result : []);
        getReq.onerror = () => resolve([]);
      };
      req.onerror = () => resolve([]);
    } catch (_) {
      resolve([]);
    }
  });
}

self.addEventListener('push', (event) => {
  if (!event.data) return;
  let data;
  try {
    data = event.data.json();
  } catch (_) {
    return;
  }

  event.waitUntil(
    (async () => {
      const watched = await readWatchedRxcuis();
      const rxcui = data.rxcui ? String(data.rxcui) : null;

      // Strictly filter on-device: only notify if the user is watching this medication
      if (data.type !== 'test_local' && (!rxcui || !watched.includes(rxcui))) {
        return;
      }

      const drugName = data.brand_name || data.generic_name || 'Your medication';
      const savingsText = data.savings_pct ? ` (Est. ~${Math.round(data.savings_pct)}% savings)` : '';
      const title = data.type === 'shortage'
        ? `FDA Shortage Alert: ${drugName}`
        : `Generic Available Now: ${drugName}`;
      const body = data.type === 'shortage'
        ? `FDA reported a supply shortage affecting ${drugName}. Tap to view details.`
        : `A verified commercial generic is now available at pharmacies${savingsText}. Tap to view your Doctor Handout.`;

      await self.registration.showNotification(title, {
        body,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: `rx-watch-${rxcui || 'test'}`,
        data: { url: '/' },
      });
    })()
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
