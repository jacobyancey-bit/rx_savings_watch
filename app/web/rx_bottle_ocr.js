/**
 * On-Device Zero-PII Pill Bottle Live Rotate-to-Scan (v6)
 *
 * Designed specifically for curved round prescription vials where the drug name
 * and dosage (mg) wrap around the bottle:
 * - Shows 2 live progress pills: [ Medication ] and [ Dosage (mg) ].
 * - Locks the medication name as soon as it's confirmed (2-of-3 frames),
 *   then invites the user to slowly rotate the bottle to pick up the mg
 *   (or tap "Open Now" immediately).
 * - If both name + mg fit in one frame (flat box/bottle), both lock together.
 * - Single reusable Tesseract.js v5 WASM worker runs 100% locally in the browser;
 *   photo pixels NEVER leave the device and every frame canvas is wiped immediately.
 */
(function () {
  let tesseractLoadPromise = null;
  let workerPromise = null;
  let activeWorker = null;

  const IGNORED_AUTO_WORDS = new Set([
    'TAKE', 'TABLET', 'TABLETS', 'CAPSULE', 'CAPSULES', 'DAILY', 'TWICE',
    'EVERY', 'HOURS', 'MOUTH', 'WATER', 'REFILL', 'REFILLS', 'QUANTITY',
    'FILLED', 'PRESCRIBER', 'DOCTOR', 'PHARMACY', 'WALGREENS', 'WALMART',
    'COSTCO', 'KROGER', 'PUBLIX', 'TARGET', 'SAFEWAY', 'PATIENT', 'ADDRESS',
    'PHONE', 'CAUTION', 'FEDERAL', 'PROHIBITS', 'TRANSFER', 'DISCARD',
    'EXPIRES', 'STORE', 'CHILDREN', 'GENERIC', 'SUBSTITUTED', 'COMMON',
    'BRAND', 'BEFORE', 'NEEDED', 'DIRECTED', 'EXTENDED', 'RELEASE',
    'DELAYED', 'PRESCRIPTION', 'WARNING', 'DROWSINESS', 'ALCOHOL',
  ]);

  const KNOWN_RX_PREFIXES = [
    'AMPHET/DEXTR', 'AMPHET-DEXTR', 'AMPHET', 'DEXTR', 'METHYLPHEN', 'LISDEX',
    'ATORVAST', 'LEVOTHYROX', 'METOPROL', 'LISINOP', 'LOSARTAN', 'AMLODIP',
    'METFORM', 'ROSUVAST', 'ESCITALOP', 'SERTRAL', 'GABAPENT', 'OMEPRAZ',
    'PANTOPRAZ', 'MONTELUK', 'ALBUTER', 'AMOX/CLAV', 'AMOX', 'HYDROCHLOR',
    'HCTZ', 'FLUTIC', 'BUDES', 'EMTRIC', 'TENOF', 'APIXAB', 'RIVAROX',
    'EMPAGLIF', 'SEMAGLUT', 'TIRZEPAT', 'WARFAR', 'ELIQUIS', 'VYVANSE',
    'JORNAY', 'MYDAYIS', 'ADDERALL', 'OZEMPIC', 'JARDIANCE', 'SYNTHROID',
    'SYMBICORT', 'TRUVADA',
  ];

  function loadTesseract() {
    if (window.Tesseract) return Promise.resolve(window.Tesseract);
    if (tesseractLoadPromise) return tesseractLoadPromise;

    tesseractLoadPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js';
      script.async = true;
      script.onload = () => {
        if (window.Tesseract) resolve(window.Tesseract);
        else reject(new Error('Tesseract failed to initialize'));
      };
      script.onerror = () => {
        tesseractLoadPromise = null;
        reject(new Error('Could not load on-device OCR engine'));
      };
      document.head.appendChild(script);
    });
    return tesseractLoadPromise;
  }

  async function getWorker() {
    if (activeWorker) return activeWorker;
    if (workerPromise) return workerPromise;

    workerPromise = (async () => {
      const Tesseract = await loadTesseract();
      const worker = await Tesseract.createWorker('eng');
      try {
        await worker.setParameters({
          tessedit_pageseg_mode: '6',
          load_system_dawg: '0',
          load_freq_dawg: '0',
          tessedit_char_whitelist: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-.% ',
        });
      } catch (_) {}
      activeWorker = worker;
      return worker;
    })();

    try {
      return await workerPromise;
    } catch (err) {
      workerPromise = null;
      activeWorker = null;
      throw err;
    }
  }

  async function resetWorker() {
    const w = activeWorker;
    activeWorker = null;
    workerPromise = null;
    if (w) {
      try {
        await w.terminate();
      } catch (_) {}
    }
  }

  async function recognizeCanvas(canvas) {
    try {
      const worker = await getWorker();
      const res = await worker.recognize(canvas);
      return {
        text: res && res.data && res.data.text ? String(res.data.text) : '',
        confidence: res && res.data && typeof res.data.confidence === 'number' ? res.data.confidence : 0,
      };
    } catch (_) {
      await resetWorker();
      const worker = await getWorker();
      const res = await worker.recognize(canvas);
      return {
        text: res && res.data && res.data.text ? String(res.data.text) : '',
        confidence: res && res.data && typeof res.data.confidence === 'number' ? res.data.confidence : 0,
      };
    }
  }

  function extractStrengthOnly(text, confidence) {
    if (!text || confidence < 30) return null;
    const upper = text.toUpperCase();
    const m = upper.match(/\b(\d{1,4}(?:\.\d{1,2})?)\s*(MG|M6|MQ|MCG|ML|GM|G|%)\b/);
    if (!m) return null;
    const val = parseFloat(m[1]);
    if (!Number.isFinite(val) || val <= 0 || val > 5000) return null;
    let unit = m[2];
    if (unit === 'M6' || unit === 'MQ') unit = 'MG';
    if (unit === 'GM') unit = 'G';
    return unit === '%' ? m[1] + '%' : m[1] + ' ' + unit;
  }

  function levenshtein(a, b) {
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    const prev = new Array(b.length + 1);
    const curr = new Array(b.length + 1);
    for (let j = 0; j <= b.length; j++) prev[j] = j;
    for (let i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
      }
      for (let j = 0; j <= b.length; j++) prev[j] = curr[j];
    }
    return prev[b.length];
  }

  function fuzzyMatchKnownPrefix(upperText) {
    // 1. Direct substring match first
    for (const prefix of KNOWN_RX_PREFIXES) {
      if (upperText.includes(prefix)) return prefix;
    }
    // 2. Fuzzy 1-edit match on individual tokens (handles OCR typos like AMPMET, ANPHET, OEXTR)
    const tokens = upperText
      .replace(/0/g, 'O')
      .replace(/1/g, 'I')
      .replace(/[^A-Z\/\-]/g, ' ')
      .split(/[\s\/\-]+/)
      .filter((t) => t.length >= 5);

    for (const tok of tokens) {
      for (const prefix of KNOWN_RX_PREFIXES) {
        if (prefix.includes('/') || prefix.includes('-')) continue;
        if (Math.abs(tok.length - prefix.length) > 2) continue;
        const maxDist = prefix.length >= 7 ? 2 : 1;
        if (levenshtein(tok.slice(0, prefix.length), prefix) <= maxDist) {
          return prefix;
        }
      }
    }
    return null;
  }

  function extractDrugCandidate(text, confidence) {
    if (!text) return null;
    const trimmed = text.trim();
    if (trimmed.length < 4) return null;
    const upper = trimmed.toUpperCase();

    // 1. Valid NDC code
    if (confidence >= 30) {
      const ndcMatch = trimmed.match(/\b\d{4,5}-\d{3,4}(?:-\d{1,2})?\b/);
      if (ndcMatch) {
        return { key: ndcMatch[0], display: 'NDC ' + ndcMatch[0], isNdc: true };
      }
    }

    // 2. Known pharmacy abbreviation or canonical prefix (with 1-edit OCR typo tolerance!)
    if (confidence >= 22) {
      const matchedPrefix = fuzzyMatchKnownPrefix(upper);
      if (matchedPrefix) {
        const display =
          matchedPrefix === 'AMPHET' || matchedPrefix === 'DEXTR'
            ? 'AMPHET/DEXTR'
            : matchedPrefix;
        return { key: display, display: display, isNdc: false };
      }
    }

    // 3. Explicit "<DRUG> <NUMBER> MG/MCG/ML" line
    if (confidence >= 32) {
      const dosageMatch = trimmed.match(
        /\b([A-Za-z][A-Za-z\-\/]{3,24}(?:\s+[A-Za-z][A-Za-z\-\/]{2,18})?)\s+(\d+(?:\.\d+)?)\s*(MG|M6|MQ|MCG|ML|GM|G|%)\b/i
      );
      if (dosageMatch) {
        const drugPart = dosageMatch[1].trim().toUpperCase();
        const firstWord = drugPart.split(/\s+/)[0];
        if (!IGNORED_AUTO_WORDS.has(firstWord) && firstWord.length >= 4) {
          return { key: firstWord, display: drugPart, isNdc: false };
        }
      }
    }

    // 4. Clean high-confidence medication word (5+ letters)
    if (confidence >= 48) {
      const words = trimmed
        .replace(/[^A-Za-z\-\/\s]/g, ' ')
        .split(/\s+/)
        .filter((w) => /^[A-Za-z][A-Za-z\-\/]{4,24}$/.test(w) && !IGNORED_AUTO_WORDS.has(w.toUpperCase()));
      if (words.length >= 1) {
        const key = words[0].toUpperCase();
        return { key, display: words.slice(0, 2).join(' ').toUpperCase(), isNdc: false };
      }
    }

    return null;
  }

  function enhanceCanvasForOcr(canvas) {
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const data = imageData.data;

    let minL = 255;
    let maxL = 0;
    const grays = new Uint8Array(data.length / 4);
    for (let i = 0, p = 0; i < data.length; i += 4, p++) {
      const g = Math.round(0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
      grays[p] = g;
      if (g < minL) minL = g;
      if (g > maxL) maxL = g;
    }

    const range = Math.max(1, maxL - minL);
    for (let i = 0, p = 0; i < data.length; i += 4, p++) {
      const stretched = ((grays[p] - minL) * 255) / range;
      const boosted = Math.max(0, Math.min(255, Math.round((stretched - 128) * 1.35 + 128)));
      data[i] = data[i + 1] = data[i + 2] = boosted;
    }
    ctx.putImageData(imageData, 0, 0);
    return canvas;
  }

  function wipeCanvas(canvas) {
    if (!canvas) return;
    try {
      const ctx = canvas.getContext('2d');
      if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
      canvas.width = 0;
      canvas.height = 0;
    } catch (_) {}
  }

  function captureGuideBoxCanvas(video, guideBox) {
    const vw = video.videoWidth;
    const vh = video.videoHeight;
    if (!vw || !vh || video.readyState < 2) return null;

    const vRect = video.getBoundingClientRect();
    const bRect = guideBox.getBoundingClientRect();
    if (!vRect.width || !vRect.height || !bRect.width || !bRect.height) return null;

    const scale = Math.max(vRect.width / vw, vRect.height / vh);
    const renderedW = vw * scale;
    const renderedH = vh * scale;
    const offsetX = (renderedW - vRect.width) / 2;
    const offsetY = (renderedH - vRect.height) / 2;

    const padX = bRect.width * 0.04;
    const padY = bRect.height * 0.14;
    const sx = Math.max(0, Math.round((bRect.left - vRect.left - padX + offsetX) / scale));
    const sy = Math.max(0, Math.round((bRect.top - vRect.top - padY + offsetY) / scale));
    const sw = Math.min(vw - sx, Math.round((bRect.width + padX * 2) / scale));
    const sh = Math.min(vh - sy, Math.round((bRect.height + padY * 2) / scale));

    if (sw < 20 || sh < 20) return null;

    const targetW = Math.max(960, Math.min(1300, sw));
    const targetH = Math.round((sh / Math.max(1, sw)) * targetW);

    const canvas = document.createElement('canvas');
    canvas.width = targetW;
    canvas.height = targetH;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(video, sx, sy, sw, sh, 0, 0, targetW, targetH);

    return enhanceCanvasForOcr(canvas);
  }

  function pickCameraImageFallback() {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.setAttribute('capture', 'environment');
      input.style.position = 'fixed';
      input.style.left = '-9999px';
      input.style.top = '-9999px';
      input.style.opacity = '0';

      let settled = false;
      const finish = (file) => {
        if (settled) return;
        settled = true;
        window.removeEventListener('focus', onWindowFocus);
        try {
          input.value = '';
          if (input.parentNode) input.parentNode.removeChild(input);
        } catch (_) {}
        resolve(file || null);
      };

      const onWindowFocus = () => {
        setTimeout(() => {
          if (!settled) {
            const f = input.files && input.files[0];
            if (!f) finish(null);
          }
        }, 600);
      };

      input.addEventListener('change', () => {
        const file = input.files && input.files[0] ? input.files[0] : null;
        finish(file);
      });
      input.addEventListener('cancel', () => finish(null));
      window.addEventListener('focus', onWindowFocus);

      document.body.appendChild(input);
      input.click();
    });
  }

  function fileToCanvas(file) {
    return new Promise((resolve, reject) => {
      const objectUrl = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        try {
          const maxDim = 1600;
          let width = img.naturalWidth || img.width;
          let height = img.naturalHeight || img.height;
          if (width > maxDim || height > maxDim) {
            const scale = maxDim / Math.max(width, height);
            width = Math.round(width * scale);
            height = Math.round(height * scale);
          }
          const canvas = document.createElement('canvas');
          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext('2d', { willReadFrequently: true });
          ctx.drawImage(img, 0, 0, width, height);
          resolve(enhanceCanvasForOcr(canvas));
        } catch (err) {
          reject(err);
        } finally {
          URL.revokeObjectURL(objectUrl);
        }
      };
      img.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        reject(new Error('Could not read photo'));
      };
      img.src = objectUrl;
    });
  }

  function openGuidedAutoScanner() {
    return new Promise(async (resolve) => {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        resolve({ type: 'fallback' });
        return;
      }

      let stream = null;
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: { ideal: 'environment' },
            width: { ideal: 1920 },
            height: { ideal: 1080 },
          },
          audio: false,
        });
      } catch (_) {
        resolve({ type: 'fallback' });
        return;
      }

      const overlay = document.createElement('div');
      overlay.id = 'rx-bottle-viewfinder';
      overlay.style.cssText =
        'position:fixed;inset:0;z-index:999999;background:#000;display:flex;flex-direction:column;' +
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;color:#fff;touch-action:none;';

      const video = document.createElement('video');
      video.autoplay = true;
      video.playsInline = true;
      video.muted = true;
      video.srcObject = stream;
      video.style.cssText =
        'position:absolute;inset:0;width:100%;height:100%;object-fit:cover;';

      const centerWrap = document.createElement('div');
      centerWrap.style.cssText =
        'position:relative;z-index:2;flex:1;display:flex;flex-direction:column;align-items:center;' +
        'justify-content:center;padding:16px;pointer-events:none;';

      const topTip = document.createElement('div');
      topTip.style.cssText =
        'background:rgba(0,0,0,0.78);padding:12px 16px;border-radius:14px;text-align:center;' +
        'max-width:420px;margin-bottom:12px;border:1px solid rgba(255,255,255,0.18);';
      topTip.innerHTML =
        '<div style="font-size:16.5px;font-weight:700;color:#5eead4;margin-bottom:4px;">Hold &amp; slowly rotate bottle</div>' +
        '<div style="font-size:13px;line-height:1.35;color:#f1f5f9;">Reads the drug name first, then rotate slightly for the MG — works on curved bottles!</div>';

      // Two live progress pills: Medication + Dosage
      const pillRow = document.createElement('div');
      pillRow.style.cssText =
        'display:flex;gap:8px;flex-wrap:wrap;justify-content:center;margin-bottom:14px;';

      const drugPill = document.createElement('div');
      drugPill.style.cssText =
        'background:rgba(15,23,42,0.85);border:1.5px solid rgba(255,255,255,0.3);color:#e2e8f0;' +
        'padding:6px 12px;border-radius:999px;font-size:12.5px;font-weight:700;';
      drugPill.textContent = '1. Medication: scanning...';

      const dosePill = document.createElement('div');
      dosePill.style.cssText =
        'background:rgba(15,23,42,0.85);border:1.5px solid rgba(255,255,255,0.3);color:#e2e8f0;' +
        'padding:6px 12px;border-radius:999px;font-size:12.5px;font-weight:700;';
      dosePill.textContent = '2. Dosage (mg): waiting';

      pillRow.appendChild(drugPill);
      pillRow.appendChild(dosePill);

      const guideBox = document.createElement('div');
      guideBox.style.cssText =
        'width:min(88vw,440px);height:118px;border:3px solid #2dd4bf;border-radius:14px;' +
        'box-shadow:0 0 0 9999px rgba(0,0,0,0.62);position:relative;background:transparent;transition:border-color 0.2s ease;';

      const statusBadge = document.createElement('div');
      statusBadge.style.cssText =
        'margin-top:20px;background:rgba(5,120,115,0.92);padding:8px 16px;border-radius:20px;' +
        'font-size:12.5px;font-weight:600;color:#ffffff;text-align:center;max-width:90vw;transition:background 0.2s ease;';
      statusBadge.textContent = 'Starting on-device scanner...';

      centerWrap.appendChild(topTip);
      centerWrap.appendChild(pillRow);
      centerWrap.appendChild(guideBox);
      centerWrap.appendChild(statusBadge);

      const controls = document.createElement('div');
      controls.style.cssText =
        'position:relative;z-index:3;background:rgba(0,0,0,0.86);padding:16px 20px calc(18px + env(safe-area-inset-bottom, 0px));' +
        'display:flex;align-items:center;justify-content:space-between;gap:12px;';

      const cancelBtn = document.createElement('button');
      cancelBtn.type = 'button';
      cancelBtn.textContent = 'Cancel';
      cancelBtn.style.cssText =
        'background:rgba(255,255,255,0.14);color:#fff;border:none;border-radius:12px;' +
        'padding:14px 18px;font-size:15px;font-weight:600;cursor:pointer;min-width:84px;';

      const actionBtn = document.createElement('button');
      actionBtn.type = 'button';
      actionBtn.textContent = 'Snap Now';
      actionBtn.style.cssText =
        'flex:1;max-width:240px;background:#0d9488;color:#fff;border:2px solid #5eead4;border-radius:999px;' +
        'padding:15px 18px;font-size:16px;font-weight:700;cursor:pointer;box-shadow:0 4px 16px rgba(13,148,136,0.45);';

      const fallbackBtn = document.createElement('button');
      fallbackBtn.type = 'button';
      fallbackBtn.textContent = 'Photo';
      fallbackBtn.title = 'Use phone photo picker instead';
      fallbackBtn.style.cssText =
        'background:rgba(255,255,255,0.14);color:#fff;border:none;border-radius:12px;' +
        'padding:14px 16px;font-size:14px;font-weight:600;cursor:pointer;min-width:72px;';

      controls.appendChild(cancelBtn);
      controls.appendChild(actionBtn);
      controls.appendChild(fallbackBtn);

      overlay.appendChild(video);
      overlay.appendChild(centerWrap);
      overlay.appendChild(controls);
      document.body.appendChild(overlay);

      let closed = false;
      let manualBusy = false;
      let autoLoopTimer = null;

      // Rolling consensus + rotate-to-accumulate state
      const recentDrugHits = [];
      let lockedDrug = null;      // { key, display, rawText }
      let lockedStrength = null;  // e.g. "20 MG"

      const markPillLocked = (el, text) => {
        el.style.background = 'rgba(22,163,74,0.92)';
        el.style.borderColor = '#86efac';
        el.style.color = '#ffffff';
        el.textContent = '✓ ' + text;
      };

      const setStateUi = (state, msg) => {
        if (closed) return;
        statusBadge.textContent = msg;
        if (state === 'aim') {
          guideBox.style.borderColor = '#2dd4bf';
          statusBadge.style.background = 'rgba(5,120,115,0.92)';
        } else if (state === 'verifying') {
          guideBox.style.borderColor = '#fbbf24';
          statusBadge.style.background = 'rgba(180,83,9,0.95)';
        } else if (state === 'confirmed') {
          guideBox.style.borderColor = '#4ade80';
          statusBadge.style.background = 'rgba(22,163,74,0.95)';
        }
      };

      const cleanup = () => {
        if (closed) return;
        closed = true;
        if (autoLoopTimer) {
          clearTimeout(autoLoopTimer);
          autoLoopTimer = null;
        }
        try {
          stream.getTracks().forEach((t) => t.stop());
        } catch (_) {}
        try {
          video.srcObject = null;
          if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
        } catch (_) {}
      };

      const finish = (payload) => {
        if (closed) return;
        cleanup();
        resolve(payload);
      };

      const finishCombined = () => {
        const combined =
          (lockedDrug ? lockedDrug.display + '\n' + lockedDrug.rawText : '') +
          (lockedStrength ? '\n' + lockedStrength : '');
        finish({ type: 'text', text: combined.trim() });
      };

      cancelBtn.addEventListener('click', () => finish({ type: 'canceled' }));
      fallbackBtn.addEventListener('click', () => finish({ type: 'fallback' }));

      actionBtn.addEventListener('click', async () => {
        if (closed || manualBusy) return;
        // If drug is already locked, tapping the button opens it immediately!
        if (lockedDrug) {
          finishCombined();
          return;
        }
        manualBusy = true;
        actionBtn.disabled = true;
        actionBtn.textContent = 'Reading...';
        setStateUi('verifying', 'Reading label on-device...');

        const canvas = captureGuideBoxCanvas(video, guideBox);
        if (!canvas) {
          finish({ type: 'fallback' });
          return;
        }
        try {
          const { text } = await recognizeCanvas(canvas);
          const combined = text + (lockedStrength ? '\n' + lockedStrength : '');
          finish({ type: 'text', text: combined });
        } catch (_) {
          finish({ type: 'text', text: '' });
        } finally {
          wipeCanvas(canvas);
        }
      });

      try {
        await video.play();
      } catch (_) {}

      (async () => {
        try {
          await getWorker();
          if (closed) return;
          setStateUi('aim', 'Point at the medication name inside the box');

          const runAutoTick = async () => {
            if (closed || manualBusy) return;
            const canvas = captureGuideBoxCanvas(video, guideBox);
            if (canvas) {
              try {
                const { text, confidence } = await recognizeCanvas(canvas);
                if (!closed && !manualBusy) {
                  // A. Check for dosage strength on ANY frame (even while rotating!)
                  const foundStrength = extractStrengthOnly(text, confidence);
                  if (foundStrength && !lockedStrength) {
                    lockedStrength = foundStrength;
                    markPillLocked(dosePill, foundStrength);
                  }

                  // B. If drug name not locked yet, run 2-of-3 consensus
                  if (!lockedDrug) {
                    const cand = extractDrugCandidate(text, confidence);
                    if (cand) {
                      recentDrugHits.push({ key: cand.key, display: cand.display, isNdc: cand.isNdc, rawText: text });
                      if (recentDrugHits.length > 3) recentDrugHits.shift();

                      const matching = recentDrugHits.filter((h) => h.key === cand.key);
                      if (matching.length >= 2) {
                        lockedDrug = matching[matching.length - 1];
                        markPillLocked(drugPill, lockedDrug.display);

                        // If it's an NDC or we ALREADY have the mg strength, open immediately!
                        if (lockedDrug.isNdc || lockedStrength) {
                          setStateUi(
                            'confirmed',
                            'Confirmed: ' + lockedDrug.display + (lockedStrength ? ' ' + lockedStrength : '') + ' — Opening...'
                          );
                          setTimeout(finishCombined, 260);
                          return;
                        }

                        // Otherwise invite user to rotate slightly for the MG (or tap Open Now!)
                        actionBtn.textContent = 'Open ' + lockedDrug.display + ' Now';
                        actionBtn.style.background = '#16a34a';
                        actionBtn.style.borderColor = '#86efac';
                        setStateUi('verifying', 'Got ' + lockedDrug.display + '! Slowly rotate bottle to show MG (or tap Open)');
                      } else {
                        setStateUi('verifying', 'Hold steady — verifying ' + cand.display + ' (1/2)...');
                      }
                    } else {
                      recentDrugHits.push({ key: null });
                      if (recentDrugHits.length > 3) recentDrugHits.shift();
                      if (!recentDrugHits.some((h) => h.key !== null)) {
                        setStateUi(
                          'aim',
                          lockedStrength
                            ? 'Got ' + lockedStrength + '! Slowly rotate to show medication name'
                            : 'Point at the medication name inside the box'
                        );
                      }
                    }
                  } else if (lockedStrength) {
                    // Both Medication AND Dosage are now locked after rotating!
                    setStateUi(
                      'confirmed',
                      'Confirmed: ' + lockedDrug.display + ' ' + lockedStrength + ' — Opening...'
                    );
                    setTimeout(finishCombined, 260);
                    return;
                  }
                }
              } catch (_) {
              } finally {
                wipeCanvas(canvas);
              }
            }
            if (!closed && !manualBusy) {
              autoLoopTimer = setTimeout(runAutoTick, 650);
            }
          };

          autoLoopTimer = setTimeout(runAutoTick, 700);
        } catch (_) {
          if (!closed) {
            setStateUi('aim', 'Tap "Snap Now" when the drug name is in the box');
          }
        }
      })();
    });
  }

  window.rxBottleOcr = {
    isSupported: function () {
      return typeof document !== 'undefined' && typeof Worker !== 'undefined';
    },

    scanBottle: async function () {
      const viewResult = await openGuidedAutoScanner();
      if (viewResult.type === 'canceled') return '__CANCELED__';
      if (viewResult.type === 'text') return viewResult.text || '';

      const file = await pickCameraImageFallback();
      if (!file) return '__CANCELED__';

      let canvas = null;
      try {
        canvas = await fileToCanvas(file);
        const { text } = await recognizeCanvas(canvas);
        return text || '';
      } finally {
        wipeCanvas(canvas);
      }
    },
  };
})();
