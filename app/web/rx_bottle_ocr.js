/**
 * On-Device Zero-PII Pill Bottle Scanner (v4 — Industry-Standard Auto-Capture)
 *
 * Implements the standard mobile document/label auto-capture pipeline:
 * 1. Motion stability gate (frame-to-frame thumbnail diff) — waits until hand is steady.
 * 2. Focus sharpness gate (Laplacian edge variance) — skips blurry/autofocus-hunting frames.
 * 3. Temporal consensus (2 agreeing frames required) — eliminates single-frame OCR misreads.
 * 4. Visual state machine: Teal (aim) -> Amber (verifying 1/2) -> Green (confirmed 2/2).
 *
 * Privacy guarantee:
 * - Single reusable Tesseract.js v5 WebAssembly worker runs 100% locally in the browser.
 * - Photo pixels NEVER leave the device and every frame canvas is wiped immediately.
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

  /**
   * Computes a tiny 64x24 grayscale thumbnail for fast motion stability & sharpness checks.
   */
  function analyzeFrameQuality(canvas, prevThumb) {
    const tw = 64;
    const th = 24;
    const small = document.createElement('canvas');
    small.width = tw;
    small.height = th;
    const sctx = small.getContext('2d', { willReadFrequently: true });
    sctx.drawImage(canvas, 0, 0, tw, th);
    const pixels = sctx.getImageData(0, 0, tw, th).data;
    wipeCanvas(small);

    const thumb = new Uint8Array(tw * th);
    for (let i = 0, p = 0; i < pixels.length; i += 4, p++) {
      thumb[p] = pixels[i]; // already grayscale after enhanceCanvasForOcr
    }

    // 1. Motion stability: mean absolute pixel difference vs previous frame
    let motionDiff = 0;
    if (prevThumb && prevThumb.length === thumb.length) {
      let sum = 0;
      for (let i = 0; i < thumb.length; i++) {
        sum += Math.abs(thumb[i] - prevThumb[i]);
      }
      motionDiff = sum / thumb.length;
    }

    // 2. Focus sharpness: Laplacian edge variance on interior pixels
    let lapSum = 0;
    let lapSqSum = 0;
    let count = 0;
    for (let y = 1; y < th - 1; y++) {
      for (let x = 1; x < tw - 1; x++) {
        const idx = y * tw + x;
        const lap =
          -4 * thumb[idx] +
          thumb[idx - 1] +
          thumb[idx + 1] +
          thumb[idx - tw] +
          thumb[idx + tw];
        lapSum += lap;
        lapSqSum += lap * lap;
        count++;
      }
    }
    const mean = lapSum / Math.max(1, count);
    const sharpness = lapSqSum / Math.max(1, count) - mean * mean;

    return { thumb, motionDiff, sharpness };
  }

  /**
   * Extracts a normalized consensus key + display label from an OCR result.
   * Returns null if confidence or text quality is too weak for auto-capture.
   */
  function extractConsensusCandidate(text, confidence) {
    if (!text) return null;
    const trimmed = text.trim();
    if (trimmed.length < 4) return null;
    const upper = trimmed.toUpperCase();

    // Extract normalized strength if present
    const strMatch = upper.match(/\b(\d+(?:\.\d+)?)\s*(MG|M6|MQ|MCG|ML|GM|G|%)\b/);
    let strength = '';
    if (strMatch) {
      let u = strMatch[2];
      if (u === 'M6' || u === 'MQ') u = 'MG';
      strength = strMatch[1] + ' ' + u;
    }

    // 1. Known pharmacy abbreviation or canonical prefix (requires confidence >= 40)
    if (confidence >= 40) {
      for (const prefix of KNOWN_RX_PREFIXES) {
        if (upper.includes(prefix)) {
          const display = strength ? prefix + ' ' + strength : prefix;
          return { key: prefix, display, hasStrength: Boolean(strength) };
        }
      }
    }

    // 2. Explicit "<DRUG> <NUMBER> MG/MCG/ML" line (requires confidence >= 45)
    if (confidence >= 45) {
      const dosageMatch = trimmed.match(
        /\b([A-Za-z][A-Za-z\-\/]{3,24}(?:\s+[A-Za-z][A-Za-z\-\/]{2,18})?)\s+(\d+(?:\.\d+)?)\s*(MG|M6|MQ|MCG|ML|GM|G|%)\b/i
      );
      if (dosageMatch) {
        const drugPart = dosageMatch[1].trim().toUpperCase();
        const firstWord = drugPart.split(/\s+/)[0];
        if (!IGNORED_AUTO_WORDS.has(firstWord) && firstWord.length >= 4) {
          const unit = (dosageMatch[3].toUpperCase() === 'M6' || dosageMatch[3].toUpperCase() === 'MQ')
            ? 'MG'
            : dosageMatch[3].toUpperCase();
          const disp = drugPart + ' ' + dosageMatch[2] + ' ' + unit;
          return { key: firstWord, display: disp, hasStrength: true };
        }
      }
    }

    // 3. Valid NDC code (requires confidence >= 45)
    if (confidence >= 45) {
      const ndcMatch = trimmed.match(/\b\d{4,5}-\d{3,4}(?:-\d{1,2})?\b/);
      if (ndcMatch) {
        return { key: ndcMatch[0], display: 'NDC ' + ndcMatch[0], hasStrength: true };
      }
    }

    // 4. Clean high-confidence medication word (requires confidence >= 60)
    if (confidence >= 60) {
      const words = trimmed
        .replace(/[^A-Za-z\-\/\s]/g, ' ')
        .split(/\s+/)
        .filter((w) => /^[A-Za-z][A-Za-z\-\/]{4,24}$/.test(w) && !IGNORED_AUTO_WORDS.has(w.toUpperCase()));
      if (words.length >= 1) {
        const key = words[0].toUpperCase();
        const disp = words.slice(0, 2).join(' ').toUpperCase() + (strength ? ' ' + strength : '');
        return { key, display: disp, hasStrength: Boolean(strength) };
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
        'background:rgba(0,0,0,0.76);padding:12px 16px;border-radius:14px;text-align:center;' +
        'max-width:420px;margin-bottom:18px;border:1px solid rgba(255,255,255,0.18);';
      topTip.innerHTML =
        '<div style="font-size:17px;font-weight:700;color:#5eead4;margin-bottom:4px;">Hold MEDICATION NAME + MG steady</div>' +
        '<div style="font-size:13.5px;line-height:1.35;color:#f1f5f9;">Auto-captures once focused and verified across 2 steady frames.</div>';

      const guideBox = document.createElement('div');
      guideBox.style.cssText =
        'width:min(88vw,440px);height:118px;border:3px solid #2dd4bf;border-radius:14px;' +
        'box-shadow:0 0 0 9999px rgba(0,0,0,0.62);position:relative;background:transparent;transition:border-color 0.2s ease;';

      const exampleHint = document.createElement('div');
      exampleHint.style.cssText =
        'position:absolute;bottom:-32px;left:0;right:0;text-align:center;font-size:12.5px;' +
        'color:#e2e8f0;text-shadow:0 1px 3px #000;font-weight:600;';
      exampleHint.textContent = 'Frame drug name + strength (e.g. AMPHET/DEXTR 20 MG)';
      guideBox.appendChild(exampleHint);

      const statusBadge = document.createElement('div');
      statusBadge.style.cssText =
        'margin-top:46px;background:rgba(5,120,115,0.92);padding:8px 16px;border-radius:20px;' +
        'font-size:12.5px;font-weight:600;color:#ffffff;text-align:center;max-width:90vw;transition:background 0.2s ease;';
      statusBadge.textContent = 'Starting on-device scanner...';

      centerWrap.appendChild(topTip);
      centerWrap.appendChild(guideBox);
      centerWrap.appendChild(statusBadge);

      const controls = document.createElement('div');
      controls.style.cssText =
        'position:relative;z-index:3;background:rgba(0,0,0,0.85);padding:16px 20px calc(18px + env(safe-area-inset-bottom, 0px));' +
        'display:flex;align-items:center;justify-content:space-between;gap:12px;';

      const cancelBtn = document.createElement('button');
      cancelBtn.type = 'button';
      cancelBtn.textContent = 'Cancel';
      cancelBtn.style.cssText =
        'background:rgba(255,255,255,0.14);color:#fff;border:none;border-radius:12px;' +
        'padding:14px 18px;font-size:15px;font-weight:600;cursor:pointer;min-width:86px;';

      const snapBtn = document.createElement('button');
      snapBtn.type = 'button';
      snapBtn.textContent = 'Snap Now';
      snapBtn.style.cssText =
        'flex:1;max-width:220px;background:#0d9488;color:#fff;border:2px solid #5eead4;border-radius:999px;' +
        'padding:15px 22px;font-size:17px;font-weight:700;cursor:pointer;box-shadow:0 4px 16px rgba(13,148,136,0.45);';

      const fallbackBtn = document.createElement('button');
      fallbackBtn.type = 'button';
      fallbackBtn.textContent = 'Photo';
      fallbackBtn.title = 'Use phone photo picker instead';
      fallbackBtn.style.cssText =
        'background:rgba(255,255,255,0.14);color:#fff;border:none;border-radius:12px;' +
        'padding:14px 16px;font-size:14px;font-weight:600;cursor:pointer;min-width:74px;';

      controls.appendChild(cancelBtn);
      controls.appendChild(snapBtn);
      controls.appendChild(fallbackBtn);

      overlay.appendChild(video);
      overlay.appendChild(centerWrap);
      overlay.appendChild(controls);
      document.body.appendChild(overlay);

      let closed = false;
      let manualBusy = false;
      let autoLoopTimer = null;
      let prevThumb = null;
      let lastCandidateKey = null;
      let lastCandidateText = '';
      let consecutiveMatches = 0;

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

      cancelBtn.addEventListener('click', () => finish({ type: 'canceled' }));
      fallbackBtn.addEventListener('click', () => finish({ type: 'fallback' }));

      snapBtn.addEventListener('click', async () => {
        if (closed || manualBusy) return;
        manualBusy = true;
        snapBtn.disabled = true;
        snapBtn.textContent = 'Reading...';
        setStateUi('verifying', 'Reading label on-device...');

        const canvas = captureGuideBoxCanvas(video, guideBox);
        if (!canvas) {
          finish({ type: 'fallback' });
          return;
        }
        try {
          const { text } = await recognizeCanvas(canvas);
          finish({ type: 'text', text });
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
          setStateUi('aim', 'Hold bottle steady inside box...');

          const runAutoTick = async () => {
            if (closed || manualBusy) return;
            const canvas = captureGuideBoxCanvas(video, guideBox);
            if (canvas) {
              try {
                // Gate 1 & 2: Motion stability + Focus sharpness check BEFORE OCR
                const { thumb, motionDiff, sharpness } = analyzeFrameQuality(canvas, prevThumb);
                const hadPrev = prevThumb !== null;
                prevThumb = thumb;

                if (hadPrev && motionDiff > 11) {
                  consecutiveMatches = 0;
                  lastCandidateKey = null;
                  setStateUi('aim', 'Hold steady — camera is moving...');
                } else if (sharpness < 180) {
                  consecutiveMatches = 0;
                  lastCandidateKey = null;
                  setStateUi('aim', 'Focusing... Move bottle slightly back in good light');
                } else {
                  // Gate 3: Run OCR & require 2-frame temporal consensus
                  const { text, confidence } = await recognizeCanvas(canvas);
                  if (!closed && !manualBusy) {
                    const cand = extractConsensusCandidate(text, confidence);
                    if (cand) {
                      if (cand.key === lastCandidateKey) {
                        consecutiveMatches++;
                        // Prefer whichever of the 2 agreeing frames also captured the mg strength
                        const bestText = cand.hasStrength ? text : (lastCandidateText || text);
                        if (consecutiveMatches >= 2) {
                          setStateUi('confirmed', 'Confirmed: ' + cand.display + ' — Opening...');
                          setTimeout(() => finish({ type: 'text', text: bestText }), 240);
                          return;
                        }
                      } else {
                        lastCandidateKey = cand.key;
                        lastCandidateText = text;
                        consecutiveMatches = 1;
                        setStateUi('verifying', 'Hold steady — verifying ' + cand.display + '...');
                      }
                    } else {
                      consecutiveMatches = 0;
                      lastCandidateKey = null;
                      setStateUi('aim', 'Align medication name & mg inside the box');
                    }
                  }
                }
              } catch (_) {
              } finally {
                wipeCanvas(canvas);
              }
            }
            if (!closed && !manualBusy) {
              autoLoopTimer = setTimeout(runAutoTick, 700);
            }
          };

          // Allow 900ms for initial camera exposure & autofocus before first check
          autoLoopTimer = setTimeout(runAutoTick, 900);
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
