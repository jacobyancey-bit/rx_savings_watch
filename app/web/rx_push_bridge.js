// Rx Savings Watch — Zero-PII Web Push Browser Bridge
(function () {
  const DB_NAME = 'rx_savings_watch_push_db';
  const STORE_NAME = 'cabinet';
  const KEY_WATCHED = 'watched_rxcuis';
  const SW_PATH = '/rx-push-sw.js';
  const SW_SCOPE = '/rx-push/';

  function openDb() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          db.createObjectStore(STORE_NAME);
        }
      };
      req.onsuccess = (e) => resolve(e.target.result);
      req.onerror = (e) => reject(e.target.error);
    });
  }

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  async function getRegistration() {
    if (!('serviceWorker' in navigator)) return null;
    const existing = await navigator.serviceWorker.getRegistration(SW_SCOPE);
    if (existing) return existing;
    return await navigator.serviceWorker.register(SW_PATH, { scope: SW_SCOPE });
  }

  window.rxPush = {
    isSupported: function () {
      return Boolean(
        'serviceWorker' in navigator &&
        'PushManager' in window &&
        'Notification' in window
      );
    },

    getStatus: async function () {
      if (!this.isSupported()) return 'unsupported';
      if (Notification.permission === 'denied') return 'denied';
      try {
        const reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
        if (!reg) return 'unsubscribed';
        const sub = await reg.pushManager.getSubscription();
        return sub ? 'subscribed' : 'unsubscribed';
      } catch (_) {
        return 'unsubscribed';
      }
    },

    syncWatchedRxcuis: async function (rxcuisJson) {
      try {
        const list = JSON.parse(rxcuisJson || '[]');
        const db = await openDb();
        const tx = db.transaction(STORE_NAME, 'readwrite');
        tx.objectStore(STORE_NAME).put(Array.isArray(list) ? list : [], KEY_WATCHED);
        return true;
      } catch (_) {
        return false;
      }
    },

    subscribe: async function (apiBaseUrl) {
      if (!this.isSupported()) return 'unsupported';
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') return 'denied';

      const reg = await getRegistration();
      if (!reg) return 'error';
      await navigator.serviceWorker.ready;

      const keyRes = await fetch(apiBaseUrl + '/api/push/vapid-public-key');
      if (!keyRes.ok) return 'error';
      const { publicKey } = await keyRes.json();

      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(publicKey),
        });
      }

      const subJson = sub.toJSON();
      const postRes = await fetch(apiBaseUrl + '/api/push/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          endpoint: subJson.endpoint,
          keys: subJson.keys,
        }),
      });
      return postRes.ok ? 'subscribed' : 'error';
    },

    unsubscribe: async function (apiBaseUrl) {
      if (!this.isSupported()) return 'unsupported';
      try {
        const reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
        if (!reg) return 'unsubscribed';
        const sub = await reg.pushManager.getSubscription();
        if (sub) {
          const endpoint = sub.endpoint;
          await sub.unsubscribe();
          await fetch(apiBaseUrl + '/api/push/unsubscribe', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ endpoint }),
          }).catch(() => {});
        }
        return 'unsubscribed';
      } catch (_) {
        return 'error';
      }
    },

    showLocalTestNotification: async function () {
      if (!('Notification' in window)) return false;
      const permission = Notification.permission === 'granted'
        ? 'granted'
        : await Notification.requestPermission();
      if (permission !== 'granted') return false;

      const title = 'Rx Savings Watch — Alerts Active!';
      const opts = {
        body: 'You will be notified privately on this device whenever a generic launches for your watched medications.',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
      };

      // Try direct Notification API first on desktop browsers (instant popup without SW activation delay),
      // falling back to Service Worker showNotification (required on Android Chrome).
      try {
        new Notification(title, opts);
        return true;
      } catch (_) {
        try {
          const reg = await getRegistration();
          if (!reg) return false;
          await reg.showNotification(title, opts);
          return true;
        } catch (__) {
          return false;
        }
      }
    },

    printHandout: function (title, bodyHtml) {
      try {
        const win = window.open('', '_blank', 'width=760,height=900');
        if (!win) return false;
        win.document.open();
        win.document.write(
          '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' +
          title +
          '</title><style>' +
          'body{font-family:Arial,Helvetica,sans-serif;color:#111;background:#fff;padding:32px;line-height:1.55;font-size:17px;}' +
          'h1{margin:0 0 6px;font-size:24px;color:#057873;}' +
          '.sub{color:#444;margin:0 0 20px;font-size:14px;}' +
          '.box{border:2px solid #057873;border-radius:12px;padding:18px;margin-bottom:18px;}' +
          '.row{margin:8px 0;} .label{font-weight:bold;color:#333;}' +
          '.note{background:#f3f7f6;border-left:4px solid #057873;padding:14px;margin-bottom:18px;}' +
          '.disc{font-size:13px;color:#555;border-top:1px solid #ccc;padding-top:12px;margin-top:24px;}' +
          '@media print{body{padding:12px;}}' +
          '</style></head><body>' +
          bodyHtml +
          '</body></html>'
        );
        win.document.close();
        win.focus();
        setTimeout(() => win.print(), 250);
        return true;
      } catch (_) {
        return false;
      }
    },

    clearUrlHash: function () {
      try {
        if (window.location && window.location.hash) {
          window.history.replaceState(
            null,
            '',
            window.location.pathname + window.location.search
          );
        }
      } catch (_) {}
    },
  };
})();
