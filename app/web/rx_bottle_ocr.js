/**
 * On-Device Zero-PII Pill Bottle Camera OCR for Mobile & Desktop Web
 *
 * Privacy guarantee:
 * - Captures photo directly via browser camera input (<input capture="environment">).
 * - Runs Tesseract.js WebAssembly OCR 100% locally inside the user's browser.
 * - Photo bytes NEVER leave the device or touch any server.
 * - Immediately clears canvas & revokes object URLs in `finally`.
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

  function pickCameraImage() {
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
        // Fallback for browsers that don't fire `cancel` when user closes the camera
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

  function preprocessToCanvas(file) {
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

          // Convert to high-contrast grayscale for cleaner pharmacy label OCR
          const imageData = ctx.getImageData(0, 0, width, height);
          const data = imageData.data;
          for (let i = 0; i < data.length; i += 4) {
            const gray = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
            const boosted = Math.max(0, Math.min(255, (gray - 128) * 1.25 + 128));
            data[i] = data[i + 1] = data[i + 2] = boosted;
          }
          ctx.putImageData(imageData, 0, 0);
          resolve(canvas);
        } catch (err) {
          reject(err);
        } finally {
          URL.revokeObjectURL(objectUrl);
        }
      };
      img.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        reject(new Error('Could not read camera photo'));
      };
      img.src = objectUrl;
    });
  }

  window.rxBottleOcr = {
    isSupported: function () {
      return typeof document !== 'undefined' && typeof Worker !== 'undefined';
    },

    scanBottle: async function () {
      const file = await pickCameraImage();
      if (!file) return '__CANCELED__';

      let canvas = null;
      try {
        const [Tesseract, processedCanvas] = await Promise.all([
          loadTesseract(),
          preprocessToCanvas(file),
        ]);
        canvas = processedCanvas;

        const result = await Tesseract.recognize(canvas, 'eng');
        return (result && result.data && result.data.text) ? String(result.data.text) : '';
      } finally {
        // Immediately wipe image pixels from memory
        if (canvas) {
          try {
            const ctx = canvas.getContext('2d');
            if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
            canvas.width = 0;
            canvas.height = 0;
          } catch (_) {}
        }
      }
    },
  };
})();
