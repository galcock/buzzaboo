/* ============================================
   BUZZABOO - Filter Engine
   Canvas-based video pipeline with real-time filters.
   Sits between raw camera and LiveKit publish track.
   Camera → Canvas (filters) → captureStream() → LiveKit
   ============================================ */

class FilterEngine {
  constructor() {
    this.canvas = null;
    this.ctx = null;
    this.rawVideo = null;
    this.processedStream = null;
    this.animFrameId = null;
    this.running = false;

    this.activeFilter = null;
    this.faceBlurEnabled = false;
    this.blurRadius = 20;
    this.faceDetector = null;
    this.cachedLandmarks = null;
    this.landmarkCacheFrames = 0;
    this.maxLandmarkCacheFrames = 2;

    // Will be set dynamically from source video once loaded (preserves native resolution + aspect ratio)
    this.width = 640;
    this.height = 480;
    this.targetFps = 30;
    this.dimensionsLocked = false;
    this.lastFrameTime = 0;
    this.frameInterval = 1000 / this.targetFps;

    // Matrix rain state
    this.matrixColumns = [];
    this.matrixChars = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789';

    // Glitch state
    this.glitchTimer = 0;
    this.glitchActive = false;
    this.glitchFreezeFrame = null;

    // VHS timestamp
    this.vhsStartTime = Date.now();

    // Temp canvases for pixel operations
    this.tempCanvas = null;
    this.tempCtx = null;

    // Blur canvas for face blur
    this.blurCanvas = null;
    this.blurCtx = null;
  }

  init(rawStream) {
    // Try to read the actual track settings first — preserves native camera aspect ratio
    const videoTrack = rawStream.getVideoTracks()[0];
    if (videoTrack) {
      const settings = videoTrack.getSettings();
      if (settings.width && settings.height) {
        this.width = settings.width;
        this.height = settings.height;
        this.dimensionsLocked = true;
      }
    }

    this.canvas = document.createElement('canvas');
    this.canvas.width = this.width;
    this.canvas.height = this.height;
    this.ctx = this.canvas.getContext('2d', { willReadFrequently: true });

    this.tempCanvas = document.createElement('canvas');
    this.tempCanvas.width = this.width;
    this.tempCanvas.height = this.height;
    this.tempCtx = this.tempCanvas.getContext('2d', { willReadFrequently: true });

    this.blurCanvas = document.createElement('canvas');
    this.blurCanvas.width = this.width;
    this.blurCanvas.height = this.height;
    this.blurCtx = this.blurCanvas.getContext('2d');

    this.rawVideo = document.createElement('video');
    this.rawVideo.srcObject = rawStream;
    this.rawVideo.muted = true;
    this.rawVideo.playsInline = true;
    this.rawVideo.play();

    // Re-sync dimensions once video metadata loads (fallback in case track settings were incomplete)
    this.rawVideo.addEventListener('loadedmetadata', () => {
      if (!this.dimensionsLocked && this.rawVideo.videoWidth && this.rawVideo.videoHeight) {
        this.resizeCanvases(this.rawVideo.videoWidth, this.rawVideo.videoHeight);
        this.dimensionsLocked = true;
      }
    });

    this.processedStream = this.canvas.captureStream(this.targetFps);

    // Copy audio tracks from raw stream
    const audioTracks = rawStream.getAudioTracks();
    audioTracks.forEach(track => this.processedStream.addTrack(track));

    // Init matrix rain columns
    const colCount = Math.floor(this.width / 14);
    this.matrixColumns = Array.from({ length: colCount }, () => ({
      y: Math.random() * this.height,
      speed: 2 + Math.random() * 6,
      chars: []
    }));

    this.running = true;
    this.lastFrameTime = performance.now();
    this.drawFrame();

    return this.processedStream;
  }

  resizeCanvases(w, h) {
    this.width = w;
    this.height = h;
    if (this.canvas) { this.canvas.width = w; this.canvas.height = h; }
    if (this.tempCanvas) { this.tempCanvas.width = w; this.tempCanvas.height = h; }
    if (this.blurCanvas) { this.blurCanvas.width = w; this.blurCanvas.height = h; }
  }

  getProcessedStream() {
    return this.processedStream;
  }

  getCanvas() {
    return this.canvas;
  }

  setFaceDetector(detector) {
    this.faceDetector = detector;
  }

  setFilter(filterName) {
    this.activeFilter = filterName;
    if (filterName === null) {
      this.cachedLandmarks = null;
    }
    if (filterName === 'vhs') {
      this.vhsStartTime = Date.now();
    }
  }

  getFilter() {
    return this.activeFilter;
  }

  setFaceBlur(enabled) {
    this.faceBlurEnabled = enabled;
    if (enabled) {
      this.blurRadius = 20;
    }
  }

  setBlurRadius(radius) {
    this.blurRadius = radius;
  }

  isFaceBlurActive() {
    return this.faceBlurEnabled;
  }

  needsFaceDetection() {
    const faceFilters = ['sunglasses', 'devilhorns', 'angelhalo', 'neonoutline', 'cartooneyes', 'pixelretro'];
    return this.faceBlurEnabled || (this.activeFilter && faceFilters.includes(this.activeFilter));
  }

  async drawFrame() {
    if (!this.running) return;

    const now = performance.now();
    const elapsed = now - this.lastFrameTime;

    if (elapsed >= this.frameInterval) {
      this.lastFrameTime = now - (elapsed % this.frameInterval);

      if (this.rawVideo.readyState >= 2) {
        // Lazily resize canvas to match actual video dimensions — prevents stretching
        const vw = this.rawVideo.videoWidth;
        const vh = this.rawVideo.videoHeight;
        if (vw && vh && (vw !== this.width || vh !== this.height)) {
          this.resizeCanvases(vw, vh);
        }
        // Draw raw video at native 1:1 ratio — no stretching
        this.ctx.drawImage(this.rawVideo, 0, 0, this.width, this.height);

        // Detect face if needed
        if (this.needsFaceDetection() && this.faceDetector && this.faceDetector.isReady()) {
          if (this.landmarkCacheFrames <= 0) {
            const landmarks = await this.faceDetector.detectFace(this.rawVideo);
            if (landmarks) {
              this.cachedLandmarks = landmarks;
            }
            this.landmarkCacheFrames = this.maxLandmarkCacheFrames;
          } else {
            this.landmarkCacheFrames--;
          }
        }

        // Apply face blur
        if (this.faceBlurEnabled && this.blurRadius > 0) {
          this.applyFaceBlur();
        }

        // Apply active filter
        if (this.activeFilter) {
          this.applyFilter(this.activeFilter);
        }
      }
    }

    this.animFrameId = requestAnimationFrame(() => this.drawFrame());
  }

  applyFilter(name) {
    switch (name) {
      case 'vhs': this.filterVHS(); break;
      case 'nightvision': this.filterNightVision(); break;
      case 'thermal': this.filterThermal(); break;
      case 'matrix': this.filterMatrix(); break;
      case 'comicbook': this.filterComicBook(); break;
      case 'glitch': this.filterGlitch(); break;
      case 'sunglasses': this.filterSunglasses(); break;
      case 'devilhorns': this.filterDevilHorns(); break;
      case 'angelhalo': this.filterAngelHalo(); break;
      case 'neonoutline': this.filterNeonOutline(); break;
      case 'cartooneyes': this.filterCartoonEyes(); break;
      case 'pixelretro': this.filterPixelRetro(); break;
    }
  }

  // ── Face Blur ──────────────────────────────────────────

  applyFaceBlur() {
    if (!this.cachedLandmarks) {
      // No face detected — blur entire center region as fallback
      const cx = this.width / 2;
      const cy = this.height / 2;
      const r = Math.min(this.width, this.height) * 0.25;
      this.blurRegion(cx - r, cy - r, r * 2, r * 2);
      return;
    }

    const bbox = this.getFaceBBox(this.cachedLandmarks);
    // Expand bbox slightly
    const pad = bbox.width * 0.15;
    this.blurRegion(bbox.x - pad, bbox.y - pad, bbox.width + pad * 2, bbox.height + pad * 2);
  }

  blurRegion(x, y, w, h) {
    x = Math.max(0, Math.floor(x));
    y = Math.max(0, Math.floor(y));
    w = Math.min(this.width - x, Math.floor(w));
    h = Math.min(this.height - y, Math.floor(h));
    if (w <= 0 || h <= 0) return;

    const iterations = Math.ceil(this.blurRadius / 4);
    const scale = Math.max(1, Math.floor(this.blurRadius / 2));

    // Downscale then upscale for blur effect
    const smallW = Math.max(1, Math.floor(w / scale));
    const smallH = Math.max(1, Math.floor(h / scale));

    this.blurCtx.clearRect(0, 0, this.blurCanvas.width, this.blurCanvas.height);

    // Draw region small
    this.blurCtx.drawImage(this.canvas, x, y, w, h, 0, 0, smallW, smallH);

    // Draw small back to large (pixelated blur)
    for (let i = 0; i < iterations; i++) {
      this.blurCtx.drawImage(this.blurCanvas, 0, 0, smallW, smallH, 0, 0, w, h);
      this.blurCtx.drawImage(this.blurCanvas, 0, 0, w, h, 0, 0, smallW, smallH);
    }

    // Final upscale and draw back
    this.ctx.imageSmoothingEnabled = true;
    this.ctx.imageSmoothingQuality = 'low';
    this.ctx.drawImage(this.blurCanvas, 0, 0, smallW, smallH, x, y, w, h);
  }

  // ── Full-Frame Filters ─────────────────────────────────

  filterVHS() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;
    const imageData = ctx.getImageData(0, 0, w, h);
    const data = imageData.data;

    // Desaturate slightly and warm tones
    for (let i = 0; i < data.length; i += 4) {
      const avg = (data[i] * 0.3 + data[i + 1] * 0.59 + data[i + 2] * 0.11);
      data[i] = Math.min(255, data[i] * 0.7 + avg * 0.3 + 15);     // R boost
      data[i + 1] = Math.min(255, data[i + 1] * 0.8 + avg * 0.2);  // G
      data[i + 2] = Math.min(255, data[i + 2] * 0.6 + avg * 0.4);  // B reduce
    }

    // RGB channel offset
    const offset = 3;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const idx = (y * w + x) * 4;
        const shiftIdx = (y * w + Math.min(w - 1, x + offset)) * 4;
        data[idx] = data[shiftIdx]; // Shift red channel right
      }
    }

    ctx.putImageData(imageData, 0, 0);

    // Scan lines
    ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
    for (let y = 0; y < h; y += 3) {
      ctx.fillRect(0, y, w, 1);
    }

    // Random noise band
    if (Math.random() < 0.05) {
      const bandY = Math.random() * h;
      const bandH = 2 + Math.random() * 8;
      ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
      ctx.fillRect(0, bandY, w, bandH);
    }

    // Tracking line
    const trackingY = ((Date.now() / 20) % (h + 40)) - 20;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.fillRect(0, trackingY, w, 3);

    // Timestamp
    const elapsed = Math.floor((Date.now() - this.vhsStartTime) / 1000);
    const hrs = String(Math.floor(elapsed / 3600)).padStart(2, '0');
    const mins = String(Math.floor((elapsed % 3600) / 60)).padStart(2, '0');
    const secs = String(elapsed % 60).padStart(2, '0');
    ctx.font = '16px monospace';
    ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
    ctx.fillText(`REC ${hrs}:${mins}:${secs}`, 15, h - 15);

    // Vignette
    const gradient = ctx.createRadialGradient(w / 2, h / 2, w * 0.3, w / 2, h / 2, w * 0.7);
    gradient.addColorStop(0, 'rgba(0,0,0,0)');
    gradient.addColorStop(1, 'rgba(0,0,0,0.4)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);
  }

  filterNightVision() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;
    const imageData = ctx.getImageData(0, 0, w, h);
    const data = imageData.data;

    for (let i = 0; i < data.length; i += 4) {
      const lum = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
      data[i] = lum * 0.2;                    // R - minimal
      data[i + 1] = Math.min(255, lum * 1.5); // G - boosted
      data[i + 2] = lum * 0.2;                // B - minimal
    }

    // Add noise grain
    for (let i = 0; i < data.length; i += 4) {
      const noise = (Math.random() - 0.5) * 40;
      data[i + 1] = Math.max(0, Math.min(255, data[i + 1] + noise));
    }

    ctx.putImageData(imageData, 0, 0);

    // Scan lines
    ctx.fillStyle = 'rgba(0, 50, 0, 0.1)';
    for (let y = 0; y < h; y += 2) {
      ctx.fillRect(0, y, w, 1);
    }

    // Vignette
    const gradient = ctx.createRadialGradient(w / 2, h / 2, w * 0.25, w / 2, h / 2, w * 0.65);
    gradient.addColorStop(0, 'rgba(0,0,0,0)');
    gradient.addColorStop(1, 'rgba(0,0,0,0.7)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, w, h);

    // Crosshair
    ctx.strokeStyle = 'rgba(0, 255, 0, 0.3)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(w / 2 - 20, h / 2);
    ctx.lineTo(w / 2 + 20, h / 2);
    ctx.moveTo(w / 2, h / 2 - 20);
    ctx.lineTo(w / 2, h / 2 + 20);
    ctx.stroke();
  }

  filterThermal() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;
    const imageData = ctx.getImageData(0, 0, w, h);
    const data = imageData.data;

    for (let i = 0; i < data.length; i += 4) {
      const lum = (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) / 255;
      const color = this.thermalColor(lum);
      data[i] = color[0];
      data[i + 1] = color[1];
      data[i + 2] = color[2];
    }

    ctx.putImageData(imageData, 0, 0);
  }

  thermalColor(t) {
    // Maps 0-1 to thermal palette: black → blue → cyan → green → yellow → red → white
    if (t < 0.15) return [0, 0, Math.floor(t / 0.15 * 180)];
    if (t < 0.3) return [0, Math.floor((t - 0.15) / 0.15 * 255), 180];
    if (t < 0.45) return [0, 255, Math.floor(180 - (t - 0.3) / 0.15 * 180)];
    if (t < 0.6) return [Math.floor((t - 0.45) / 0.15 * 255), 255, 0];
    if (t < 0.75) return [255, Math.floor(255 - (t - 0.6) / 0.15 * 200), 0];
    if (t < 0.9) return [255, Math.floor(55 + (t - 0.75) / 0.15 * 100), Math.floor((t - 0.75) / 0.15 * 100)];
    return [255, Math.floor(155 + (t - 0.9) / 0.1 * 100), Math.floor(100 + (t - 0.9) / 0.1 * 155)];
  }

  filterMatrix() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;

    // Draw video dimmed
    ctx.globalAlpha = 0.15;
    ctx.drawImage(this.rawVideo, 0, 0, w, h);
    ctx.globalAlpha = 1.0;

    // Dark overlay
    ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
    ctx.fillRect(0, 0, w, h);

    // Falling characters
    ctx.font = '14px monospace';
    for (let i = 0; i < this.matrixColumns.length; i++) {
      const col = this.matrixColumns[i];
      const x = i * 14;

      // Draw character
      const char = this.matrixChars[Math.floor(Math.random() * this.matrixChars.length)];
      const brightness = 0.8 + Math.random() * 0.2;
      ctx.fillStyle = `rgba(0, ${Math.floor(200 * brightness)}, 0, ${brightness})`;
      ctx.fillText(char, x, col.y);

      // Bright head character
      ctx.fillStyle = `rgba(180, 255, 180, ${0.9 + Math.random() * 0.1})`;
      ctx.fillText(char, x, col.y);

      // Trail (dimmer characters above)
      for (let j = 1; j < 15; j++) {
        const trailY = col.y - j * 14;
        if (trailY < 0) break;
        const trailChar = this.matrixChars[Math.floor(Math.random() * this.matrixChars.length)];
        const alpha = Math.max(0, 0.6 - j * 0.04);
        ctx.fillStyle = `rgba(0, ${Math.floor(180 - j * 8)}, 0, ${alpha})`;
        ctx.fillText(trailChar, x, trailY);
      }

      col.y += col.speed;
      if (col.y > h + 14) {
        col.y = -14;
        col.speed = 2 + Math.random() * 6;
      }
    }
  }

  filterComicBook() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;
    const imageData = ctx.getImageData(0, 0, w, h);
    const data = imageData.data;

    // Posterize colors (reduce to 5 levels)
    const levels = 5;
    const step = 255 / levels;
    for (let i = 0; i < data.length; i += 4) {
      data[i] = Math.round(data[i] / step) * step;
      data[i + 1] = Math.round(data[i + 1] / step) * step;
      data[i + 2] = Math.round(data[i + 2] / step) * step;
    }

    // Boost saturation
    for (let i = 0; i < data.length; i += 4) {
      const avg = (data[i] + data[i + 1] + data[i + 2]) / 3;
      data[i] = Math.min(255, data[i] + (data[i] - avg) * 0.5);
      data[i + 1] = Math.min(255, data[i + 1] + (data[i + 1] - avg) * 0.5);
      data[i + 2] = Math.min(255, data[i + 2] + (data[i + 2] - avg) * 0.5);
    }

    ctx.putImageData(imageData, 0, 0);

    // Edge detection overlay using Sobel-like approach
    this.tempCtx.drawImage(this.canvas, 0, 0);
    const edgeData = this.tempCtx.getImageData(0, 0, w, h);
    const ed = edgeData.data;
    const outData = ctx.createImageData(w, h);
    const out = outData.data;

    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const idx = (y * w + x) * 4;
        // Simplified Sobel
        const tl = this.luminance(ed, ((y - 1) * w + (x - 1)) * 4);
        const t = this.luminance(ed, ((y - 1) * w + x) * 4);
        const tr = this.luminance(ed, ((y - 1) * w + (x + 1)) * 4);
        const l = this.luminance(ed, (y * w + (x - 1)) * 4);
        const r = this.luminance(ed, (y * w + (x + 1)) * 4);
        const bl = this.luminance(ed, ((y + 1) * w + (x - 1)) * 4);
        const b = this.luminance(ed, ((y + 1) * w + x) * 4);
        const br = this.luminance(ed, ((y + 1) * w + (x + 1)) * 4);

        const gx = -tl - 2 * l - bl + tr + 2 * r + br;
        const gy = -tl - 2 * t - tr + bl + 2 * b + br;
        const mag = Math.sqrt(gx * gx + gy * gy);

        const edge = mag > 30 ? 255 : 0;
        out[idx] = 0;
        out[idx + 1] = 0;
        out[idx + 2] = 0;
        out[idx + 3] = edge > 0 ? 200 : 0;
      }
    }

    // Overlay edges
    this.tempCtx.putImageData(outData, 0, 0);
    ctx.drawImage(this.tempCanvas, 0, 0);

    // Halftone dot pattern overlay
    ctx.fillStyle = 'rgba(0, 0, 0, 0.03)';
    for (let y = 0; y < h; y += 4) {
      for (let x = (y % 8 === 0 ? 0 : 2); x < w; x += 4) {
        ctx.fillRect(x, y, 1, 1);
      }
    }
  }

  luminance(data, idx) {
    return data[idx] * 0.299 + data[idx + 1] * 0.587 + data[idx + 2] * 0.114;
  }

  filterGlitch() {
    const ctx = this.ctx;
    const w = this.width;
    const h = this.height;

    this.glitchTimer++;

    // Random glitch bursts
    if (Math.random() < 0.08) {
      this.glitchActive = true;
      setTimeout(() => { this.glitchActive = false; }, 100 + Math.random() * 200);
    }

    if (this.glitchActive) {
      const imageData = ctx.getImageData(0, 0, w, h);
      const data = imageData.data;

      // RGB channel separation
      const shiftR = Math.floor(Math.random() * 12) - 6;
      const shiftB = Math.floor(Math.random() * 12) - 6;
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const idx = (y * w + x) * 4;
          const rIdx = (y * w + Math.max(0, Math.min(w - 1, x + shiftR))) * 4;
          const bIdx = (y * w + Math.max(0, Math.min(w - 1, x + shiftB))) * 4;
          data[idx] = data[rIdx];
          data[idx + 2] = data[bIdx];
        }
      }

      ctx.putImageData(imageData, 0, 0);

      // Horizontal slice displacement
      const sliceCount = 3 + Math.floor(Math.random() * 8);
      for (let s = 0; s < sliceCount; s++) {
        const sliceY = Math.floor(Math.random() * h);
        const sliceH = 2 + Math.floor(Math.random() * 20);
        const shift = Math.floor(Math.random() * 40) - 20;
        const sliceData = ctx.getImageData(0, sliceY, w, Math.min(sliceH, h - sliceY));
        ctx.putImageData(sliceData, shift, sliceY);
      }

      // Random color blocks
      if (Math.random() < 0.4) {
        const blockX = Math.floor(Math.random() * w);
        const blockY = Math.floor(Math.random() * h);
        const blockW = 20 + Math.floor(Math.random() * 80);
        const blockH = 2 + Math.floor(Math.random() * 15);
        const colors = ['rgba(255,0,0,0.3)', 'rgba(0,255,0,0.3)', 'rgba(0,0,255,0.3)', 'rgba(255,0,255,0.3)'];
        ctx.fillStyle = colors[Math.floor(Math.random() * colors.length)];
        ctx.fillRect(blockX, blockY, blockW, blockH);
      }
    }

    // Subtle persistent scan lines
    ctx.fillStyle = 'rgba(0, 0, 0, 0.04)';
    for (let y = 0; y < h; y += 2) {
      ctx.fillRect(0, y, w, 1);
    }

    // Occasional white noise line
    if (Math.random() < 0.02) {
      const noiseY = Math.floor(Math.random() * h);
      ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
      ctx.fillRect(0, noiseY, w, 1);
    }
  }

  // ── Face Filters (require landmarks) ──────────────────

  filterSunglasses() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const leftEye = this.getEyeCenter(lm, 'left');
    const rightEye = this.getEyeCenter(lm, 'right');
    const eyeDist = Math.sqrt(Math.pow(rightEye.x - leftEye.x, 2) + Math.pow(rightEye.y - leftEye.y, 2));
    const angle = Math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);
    const centerX = (leftEye.x + rightEye.x) / 2;
    const centerY = (leftEye.y + rightEye.y) / 2;

    ctx.save();
    ctx.translate(centerX, centerY);
    ctx.rotate(angle);

    const glassW = eyeDist * 1.6;
    const glassH = eyeDist * 0.55;
    const lensW = eyeDist * 0.58;
    const lensH = eyeDist * 0.48;
    const bridgeW = eyeDist * 0.15;

    // Frame
    ctx.fillStyle = '#1a1a1a';
    ctx.strokeStyle = '#000';
    ctx.lineWidth = 2;

    // Left lens frame
    this.roundRect(ctx, -glassW / 2, -glassH / 2, lensW, lensH, 8);
    ctx.fill();
    ctx.stroke();

    // Right lens frame
    this.roundRect(ctx, glassW / 2 - lensW, -glassH / 2, lensW, lensH, 8);
    ctx.fill();
    ctx.stroke();

    // Bridge
    ctx.beginPath();
    ctx.moveTo(-bridgeW, -glassH / 4);
    ctx.quadraticCurveTo(0, -glassH / 2.5, bridgeW, -glassH / 4);
    ctx.strokeStyle = '#1a1a1a';
    ctx.lineWidth = 3;
    ctx.stroke();

    // Lens gradient (dark reflective)
    const lensGrad = ctx.createLinearGradient(0, -glassH / 2, 0, glassH / 2);
    lensGrad.addColorStop(0, 'rgba(40, 40, 60, 0.85)');
    lensGrad.addColorStop(0.5, 'rgba(20, 20, 40, 0.9)');
    lensGrad.addColorStop(1, 'rgba(50, 50, 70, 0.85)');
    ctx.fillStyle = lensGrad;

    this.roundRect(ctx, -glassW / 2 + 2, -glassH / 2 + 2, lensW - 4, lensH - 4, 6);
    ctx.fill();
    this.roundRect(ctx, glassW / 2 - lensW + 2, -glassH / 2 + 2, lensW - 4, lensH - 4, 6);
    ctx.fill();

    // Lens shine
    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.beginPath();
    ctx.ellipse(-glassW / 2 + lensW * 0.3, -glassH / 4, lensW * 0.15, lensH * 0.2, -0.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(glassW / 2 - lensW * 0.7, -glassH / 4, lensW * 0.15, lensH * 0.2, -0.3, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }

  filterDevilHorns() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const forehead = this.getForeheadCenter(lm);
    const leftEye = this.getEyeCenter(lm, 'left');
    const rightEye = this.getEyeCenter(lm, 'right');
    const eyeDist = Math.sqrt(Math.pow(rightEye.x - leftEye.x, 2) + Math.pow(rightEye.y - leftEye.y, 2));
    const angle = Math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);
    const hornSize = eyeDist * 0.7;

    ctx.save();

    // Left horn
    const lhx = forehead.x - eyeDist * 0.35;
    const lhy = forehead.y - eyeDist * 0.15;
    this.drawHorn(ctx, lhx, lhy, hornSize, angle - 0.4);

    // Right horn
    const rhx = forehead.x + eyeDist * 0.35;
    const rhy = forehead.y - eyeDist * 0.15;
    this.drawHorn(ctx, rhx, rhy, hornSize, angle + 0.4);

    ctx.restore();
  }

  drawHorn(ctx, x, y, size, tilt) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(tilt);

    const grad = ctx.createLinearGradient(0, 0, 0, -size);
    grad.addColorStop(0, '#8B0000');
    grad.addColorStop(0.4, '#CC0000');
    grad.addColorStop(0.8, '#FF2200');
    grad.addColorStop(1, '#FF6600');

    ctx.fillStyle = grad;
    ctx.shadowColor = 'rgba(255, 0, 0, 0.4)';
    ctx.shadowBlur = 10;

    ctx.beginPath();
    ctx.moveTo(-size * 0.2, 0);
    ctx.quadraticCurveTo(-size * 0.15, -size * 0.5, size * 0.05, -size);
    ctx.quadraticCurveTo(size * 0.15, -size * 0.5, size * 0.2, 0);
    ctx.closePath();
    ctx.fill();

    // Shine
    ctx.fillStyle = 'rgba(255, 200, 150, 0.2)';
    ctx.beginPath();
    ctx.moveTo(-size * 0.08, -size * 0.1);
    ctx.quadraticCurveTo(-size * 0.05, -size * 0.5, size * 0.02, -size * 0.85);
    ctx.quadraticCurveTo(size * 0.0, -size * 0.5, size * 0.02, -size * 0.1);
    ctx.closePath();
    ctx.fill();

    ctx.shadowBlur = 0;
    ctx.restore();
  }

  filterAngelHalo() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const forehead = this.getForeheadCenter(lm);
    const leftEye = this.getEyeCenter(lm, 'left');
    const rightEye = this.getEyeCenter(lm, 'right');
    const eyeDist = Math.sqrt(Math.pow(rightEye.x - leftEye.x, 2) + Math.pow(rightEye.y - leftEye.y, 2));
    const angle = Math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);

    const cx = forehead.x;
    const cy = forehead.y - eyeDist * 0.45;
    const rx = eyeDist * 0.55;
    const ry = eyeDist * 0.15;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(angle);

    // Outer glow
    ctx.shadowColor = 'rgba(255, 215, 0, 0.8)';
    ctx.shadowBlur = 25;
    ctx.strokeStyle = 'rgba(255, 223, 100, 0.9)';
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 2);
    ctx.stroke();

    // Inner bright ring
    ctx.shadowBlur = 15;
    ctx.shadowColor = 'rgba(255, 255, 200, 0.6)';
    ctx.strokeStyle = 'rgba(255, 245, 180, 0.95)';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.ellipse(0, 0, rx * 0.85, ry * 0.85, 0, 0, Math.PI * 2);
    ctx.stroke();

    // Sparkle highlights
    const time = Date.now() / 500;
    for (let i = 0; i < 4; i++) {
      const sparkAngle = time + (i * Math.PI / 2);
      const sx = Math.cos(sparkAngle) * rx * 0.9;
      const sy = Math.sin(sparkAngle) * ry * 0.9;
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.shadowColor = 'rgba(255, 255, 200, 1)';
      ctx.shadowBlur = 8;
      ctx.beginPath();
      ctx.arc(sx, sy, 2, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.shadowBlur = 0;
    ctx.restore();
  }

  filterNeonOutline() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const faceContour = this.getFaceContourPoints(lm);
    if (faceContour.length < 3) return;

    // Neon glow colors cycle
    const time = Date.now() / 2000;
    const hue = (time * 60) % 360;

    ctx.save();
    ctx.shadowColor = `hsla(${hue}, 100%, 60%, 0.9)`;
    ctx.shadowBlur = 15;
    ctx.strokeStyle = `hsla(${hue}, 100%, 70%, 0.9)`;
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // Face outline
    ctx.beginPath();
    ctx.moveTo(faceContour[0].x, faceContour[0].y);
    for (let i = 1; i < faceContour.length; i++) {
      ctx.lineTo(faceContour[i].x, faceContour[i].y);
    }
    ctx.closePath();
    ctx.stroke();

    // Double glow layer
    ctx.shadowBlur = 30;
    ctx.strokeStyle = `hsla(${hue}, 100%, 60%, 0.4)`;
    ctx.lineWidth = 6;
    ctx.stroke();

    // Eye outlines
    const leftEyePoints = this.getEyeContour(lm, 'left');
    const rightEyePoints = this.getEyeContour(lm, 'right');

    ctx.shadowBlur = 10;
    ctx.strokeStyle = `hsla(${(hue + 120) % 360}, 100%, 70%, 0.8)`;
    ctx.lineWidth = 2;

    [leftEyePoints, rightEyePoints].forEach(eyePoints => {
      if (eyePoints.length < 3) return;
      ctx.beginPath();
      ctx.moveTo(eyePoints[0].x, eyePoints[0].y);
      for (let i = 1; i < eyePoints.length; i++) {
        ctx.lineTo(eyePoints[i].x, eyePoints[i].y);
      }
      ctx.closePath();
      ctx.stroke();
    });

    // Mouth outline
    const mouthPoints = this.getMouthContour(lm);
    if (mouthPoints.length >= 3) {
      ctx.strokeStyle = `hsla(${(hue + 240) % 360}, 100%, 70%, 0.7)`;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(mouthPoints[0].x, mouthPoints[0].y);
      for (let i = 1; i < mouthPoints.length; i++) {
        ctx.lineTo(mouthPoints[i].x, mouthPoints[i].y);
      }
      ctx.closePath();
      ctx.stroke();
    }

    ctx.shadowBlur = 0;
    ctx.restore();
  }

  filterCartoonEyes() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const leftEye = this.getEyeCenter(lm, 'left');
    const rightEye = this.getEyeCenter(lm, 'right');
    const eyeDist = Math.sqrt(Math.pow(rightEye.x - leftEye.x, 2) + Math.pow(rightEye.y - leftEye.y, 2));
    const eyeSize = eyeDist * 0.38;

    // Get iris positions for gaze direction
    const leftIris = this.getIrisCenter(lm, 'left');
    const rightIris = this.getIrisCenter(lm, 'right');

    [{ eye: leftEye, iris: leftIris }, { eye: rightEye, iris: rightIris }].forEach(({ eye, iris }) => {
      ctx.save();

      // White sclera
      ctx.fillStyle = '#FFFFFF';
      ctx.shadowColor = 'rgba(0, 0, 0, 0.3)';
      ctx.shadowBlur = 8;
      ctx.beginPath();
      ctx.ellipse(eye.x, eye.y, eyeSize, eyeSize * 1.1, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;

      // Outline
      ctx.strokeStyle = '#333';
      ctx.lineWidth = 2;
      ctx.stroke();

      // Pupil (follows gaze)
      const dx = iris.x - eye.x;
      const dy = iris.y - eye.y;
      const maxOffset = eyeSize * 0.25;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const clampedDist = Math.min(dist, maxOffset);
      const angle = Math.atan2(dy, dx);
      const pupilX = eye.x + Math.cos(angle) * clampedDist;
      const pupilY = eye.y + Math.sin(angle) * clampedDist;
      const pupilSize = eyeSize * 0.5;

      // Iris color
      const irisGrad = ctx.createRadialGradient(pupilX, pupilY, pupilSize * 0.3, pupilX, pupilY, pupilSize);
      irisGrad.addColorStop(0, '#2E1A0E');
      irisGrad.addColorStop(0.5, '#5C3A1E');
      irisGrad.addColorStop(1, '#8B6914');
      ctx.fillStyle = irisGrad;
      ctx.beginPath();
      ctx.arc(pupilX, pupilY, pupilSize, 0, Math.PI * 2);
      ctx.fill();

      // Inner pupil
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.arc(pupilX, pupilY, pupilSize * 0.45, 0, Math.PI * 2);
      ctx.fill();

      // Shine
      ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.beginPath();
      ctx.arc(pupilX - pupilSize * 0.2, pupilY - pupilSize * 0.2, pupilSize * 0.18, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(pupilX + pupilSize * 0.1, pupilY + pupilSize * 0.15, pupilSize * 0.08, 0, Math.PI * 2);
      ctx.fill();

      ctx.restore();
    });
  }

  filterPixelRetro() {
    if (!this.cachedLandmarks) return;
    const ctx = this.ctx;
    const lm = this.cachedLandmarks;

    const bbox = this.getFaceBBox(lm);
    const pad = bbox.width * 0.15;
    const x = Math.max(0, Math.floor(bbox.x - pad));
    const y = Math.max(0, Math.floor(bbox.y - pad));
    const w = Math.min(this.width - x, Math.floor(bbox.width + pad * 2));
    const h = Math.min(this.height - y, Math.floor(bbox.height + pad * 2));

    if (w <= 0 || h <= 0) return;

    const pixelSize = 10;
    const imageData = ctx.getImageData(x, y, w, h);
    const data = imageData.data;

    for (let py = 0; py < h; py += pixelSize) {
      for (let px = 0; px < w; px += pixelSize) {
        let r = 0, g = 0, b = 0, count = 0;

        for (let dy = 0; dy < pixelSize && py + dy < h; dy++) {
          for (let dx = 0; dx < pixelSize && px + dx < w; dx++) {
            const idx = ((py + dy) * w + (px + dx)) * 4;
            r += data[idx];
            g += data[idx + 1];
            b += data[idx + 2];
            count++;
          }
        }

        r = Math.floor(r / count);
        g = Math.floor(g / count);
        b = Math.floor(b / count);

        for (let dy = 0; dy < pixelSize && py + dy < h; dy++) {
          for (let dx = 0; dx < pixelSize && px + dx < w; dx++) {
            const idx = ((py + dy) * w + (px + dx)) * 4;
            data[idx] = r;
            data[idx + 1] = g;
            data[idx + 2] = b;
          }
        }
      }
    }

    ctx.putImageData(imageData, x, y);
  }

  // ── Face Landmark Helpers ──────────────────────────────

  getFaceBBox(landmarks) {
    // MediaPipe landmarks are normalized 0-1
    let minX = 1, maxX = 0, minY = 1, maxY = 0;
    // Face oval indices (approximate)
    const faceIndices = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109];

    faceIndices.forEach(i => {
      if (landmarks[i]) {
        minX = Math.min(minX, landmarks[i].x);
        maxX = Math.max(maxX, landmarks[i].x);
        minY = Math.min(minY, landmarks[i].y);
        maxY = Math.max(maxY, landmarks[i].y);
      }
    });

    return {
      x: minX * this.width,
      y: minY * this.height,
      width: (maxX - minX) * this.width,
      height: (maxY - minY) * this.height
    };
  }

  getEyeCenter(landmarks, side) {
    // Left eye: 33, 133, 160, 159, 158, 144, 145, 153
    // Right eye: 362, 263, 387, 386, 385, 373, 374, 380
    const indices = side === 'left'
      ? [33, 133, 160, 159, 158, 144, 145, 153]
      : [362, 263, 387, 386, 385, 373, 374, 380];

    let sumX = 0, sumY = 0, count = 0;
    indices.forEach(i => {
      if (landmarks[i]) {
        sumX += landmarks[i].x;
        sumY += landmarks[i].y;
        count++;
      }
    });

    return {
      x: (sumX / count) * this.width,
      y: (sumY / count) * this.height
    };
  }

  getIrisCenter(landmarks, side) {
    // Left iris: 468, 469, 470, 471, 472 (if available, else use pupil center landmarks)
    // Right iris: 473, 474, 475, 476, 477
    const indices = side === 'left' ? [468, 469, 470, 471, 472] : [473, 474, 475, 476, 477];

    let sumX = 0, sumY = 0, count = 0;
    indices.forEach(i => {
      if (landmarks[i]) {
        sumX += landmarks[i].x;
        sumY += landmarks[i].y;
        count++;
      }
    });

    if (count === 0) return this.getEyeCenter(landmarks, side);

    return {
      x: (sumX / count) * this.width,
      y: (sumY / count) * this.height
    };
  }

  getForeheadCenter(landmarks) {
    // Top of head landmarks: 10, 151, 9, 8
    const indices = [10, 151, 9, 8];
    let sumX = 0, sumY = 0, count = 0;
    indices.forEach(i => {
      if (landmarks[i]) {
        sumX += landmarks[i].x;
        sumY += landmarks[i].y;
        count++;
      }
    });
    return {
      x: (sumX / count) * this.width,
      y: (sumY / count) * this.height
    };
  }

  getFaceContourPoints(landmarks) {
    const indices = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109];

    return indices
      .filter(i => landmarks[i])
      .map(i => ({
        x: landmarks[i].x * this.width,
        y: landmarks[i].y * this.height
      }));
  }

  getEyeContour(landmarks, side) {
    const indices = side === 'left'
      ? [33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7]
      : [362, 398, 384, 385, 386, 387, 388, 466, 263, 249, 390, 373, 374, 380, 381, 382];

    return indices
      .filter(i => landmarks[i])
      .map(i => ({
        x: landmarks[i].x * this.width,
        y: landmarks[i].y * this.height
      }));
  }

  getMouthContour(landmarks) {
    const indices = [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291,
      375, 321, 405, 314, 17, 84, 181, 91, 146];

    return indices
      .filter(i => landmarks[i])
      .map(i => ({
        x: landmarks[i].x * this.width,
        y: landmarks[i].y * this.height
      }));
  }

  // ── Utility ────────────────────────────────────────────

  roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  destroy() {
    this.running = false;
    if (this.animFrameId) {
      cancelAnimationFrame(this.animFrameId);
      this.animFrameId = null;
    }
    if (this.rawVideo) {
      this.rawVideo.pause();
      this.rawVideo.srcObject = null;
      this.rawVideo = null;
    }
    if (this.processedStream) {
      this.processedStream.getTracks().forEach(t => t.stop());
      this.processedStream = null;
    }
    this.canvas = null;
    this.ctx = null;
    this.cachedLandmarks = null;
  }
}

// Export
window.FilterEngine = FilterEngine;
console.log('✓ Filter engine loaded');
