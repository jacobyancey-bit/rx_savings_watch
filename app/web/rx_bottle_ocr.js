/**
 * On-Device Zero-PII Pill Bottle Camera OCR with Live Guided Viewfinder
 *
 * Privacy guarantee:
 * - Opens a live rear-camera viewfinder with a focused horizontal guide box
 *   so users frame ONLY the medication name & strength (excluding personal PII).
 * - Crops strictly to the guide box before running Tesseract.js WASM OCR
 *   100% locally inside the browser.
 * - Photo bytes NEVER leave the device or touch any server.
 * - Immediately stops camera tracks and wipes canvas pixels in `finally`.
 */
(function () {
  let tesseractLoadPromise = null;

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

  function enhanceCanvasForOcr(canvas) {
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const data = imageData.data;

    // Compute min/max luminance for adaptive contrast stretch (handles dim light & bottle glare)
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

  /**
   * Opens a full-screen live camera viewfinder with a centered teal guide box.
   * Resolves to:
   *  - { type: 'canvas', canvas } when user snaps the framed label
   *  - { type: 'fallback' } if user taps "Use Phone Camera" or live stream fails
   *  - { type: 'canceled' } if user taps Cancel
   */
  function openGuidedViewfinder() {
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

      // Start pre-loading Tesseract in the background while user lines up the bottle!
      loadTesseract().catch(() => {});

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

      // Dark vignette layer with cutout effect via huge box-shadow on the guide box
      const centerWrap = document.createElement('div');
      centerWrap.style.cssText =
        'position:relative;z-index:2;flex:1;display:flex;flex-direction:column;align-items:center;' +
        'justify-content:center;padding:16px;pointer-events:none;';

      const topTip = document.createElement('div');
      topTip.style.cssText =
        'background:rgba(0,0,0,0.72);padding:12px 16px;border-radius:14px;text-align:center;' +
        'max-width:420px;margin-bottom:18px;border:1px solid rgba(255,255,255,0.18);';
      topTip.innerHTML =
        '<div style="font-size:17px;font-weight:700;color:#5eead4;margin-bottom:4px;">Line up the MEDICATION NAME here</div>' +
        '<div style="font-size:13.5px;line-height:1.35;color:#f1f5f9;">Hold the bottle flat in bright light so ONLY the drug name &amp; strength fill the teal box below.</div>';

      const guideBox = document.createElement('div');
      guideBox.style.cssText =
        'width:min(88vw,440px);height:112px;border:3px solid #2dd4bf;border-radius:14px;' +
        'box-shadow:0 0 0 9999px rgba(0,0,0,0.62);position:relative;background:transparent;';

      // Subtle corner/example label inside guide box
      const exampleHint = document.createElement('div');
      exampleHint.style.cssText =
        'position:absolute;bottom:-32px;left:0;right:0;text-align:center;font-size:12.5px;' +
        'color:#e2e8f0;text-shadow:0 1px 3px #000;font-weight:600;';
      exampleHint.textContent = 'Example: ATORVASTATIN 20 MG  or  JORNAY PM 40 MG';
      guideBox.appendChild(exampleHint);

      const privacySub = document.createElement('div');
      privacySub.style.cssText =
        'margin-top:46px;background:rgba(5,120,115,0.88);padding:7px 14px;border-radius:20px;' +
        'font-size:12px;font-weight:600;color:#ffffff;text-align:center;';
      privacySub.textContent = 'Keep your name & address outside the box • Photo auto-deleted';

      centerWrap.appendChild(topTip);
      centerWrap.appendChild(guideBox);
      centerWrap.appendChild(privacySub);

      // Bottom controls bar
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
      snapBtn.textContent = 'Snap Label';
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
      const cleanup = () => {
        if (closed) return;
        closed = true;
        try {
          stream.getTracks().forEach((t) => t.stop());
        } catch (_) {}
        try {
          video.srcObject = null;
          if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
        } catch (_) {}
      };

      cancelBtn.addEventListener('click', () => {
        cleanup();
        resolve({ type: 'canceled' });
      });

      fallbackBtn.addEventListener('click', () => {
        cleanup();
        resolve({ type: 'fallback' });
      });

      snapBtn.addEventListener('click', () => {
        try {
          const vw = video.videoWidth;
          const vh = video.videoHeight;
          if (!vw || !vh) {
            cleanup();
            resolve({ type: 'fallback' });
            return;
          }

          // Map the guideBox viewport rectangle onto the object-fit:cover video frame
          const vRect = video.getBoundingClientRect();
          const bRect = guideBox.getBoundingClientRect();
          const scale = Math.max(vRect.width / vw, vRect.height / vh);
          const renderedW = vw * scale;
          const renderedH = vh * scale;
          const offsetX = (renderedW - vRect.width) / 2;
          const offsetY = (renderedH - vRect.height) / 2;

          // Slight 8% padding around box so tall letters aren't clipped
          const padX = bRect.width * 0.04;
          const padY = bRect.height * 0.12;
          const sx = Math.max(0, Math.round((bRect.left - vRect.left - padX + offsetX) / scale));
          const sy = Math.max(0, Math.round((bRect.top - vRect.top - padY + offsetY) / scale));
          const sw = Math.min(vw - sx, Math.round((bRect.width + padX * 2) / scale));
          const sh = Math.min(vh - sy, Math.round((bRect.height + padY * 2) / scale));

          // Upscale crop to at least 1000px wide for sharper Tesseract recognition
          const targetW = Math.max(1000, Math.min(1600, sw));
          const targetH = Math.round((sh / Math.max(1, sw)) * targetW);

          const canvas = document.createElement('canvas');
          canvas.width = targetW;
          canvas.height = targetH;
          const ctx = canvas.getContext('2d', { willReadFrequently: true });
          ctx.drawImage(video, sx, sy, sw, sh, 0, 0, targetW, targetH);

          enhanceCanvasForOcr(canvas);
          cleanup();
          resolve({ type: 'canvas', canvas });
        } catch (_) {
          cleanup();
          resolve({ type: 'fallback' });
        }
      });

      try {
        await video.play();
      } catch (_) {}
    });
  }

  window.rxBottleOcr = {
    isSupported: function () {
      return typeof document !== 'undefined' && typeof Worker !== 'undefined';
    },

    scanBottle: async function () {
      const viewResult = await openGuidedViewfinder();
      if (viewResult.type === 'canceled') return '__CANCELED__';

      let canvas = null;
      try {
        if (viewResult.type === 'canvas') {
          canvas = viewResult.canvas;
          const Tesseract = await loadTesseract();
          const result = await Tesseract.recognize(canvas, 'eng');
          return result && result.data && result.data.text ? String(result.data.text) : '';
        }

        // Fallback to native file/camera input if live stream was unavailable or user chose Photo
        const file = await pickCameraImageFallback();
        if (!file) return '__CANCELED__';

        const [Tesseract, processedCanvas] = await Promise.all([
          loadTesseract(),
          fileToCanvas(file),
        ]);
        canvas = processedCanvas;
        const result = await Tesseract.recognize(canvas, 'eng');
        return result && result.data && result.data.text ? String(result.data.text) : '';
      } finally {
        wipeCanvas(canvas);
      }
    },
  };
})();
