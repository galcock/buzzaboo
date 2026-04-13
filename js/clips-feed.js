/**
 * Buzzaboo Clips Feed Controller
 * Manages the clips browsing page (clips.html) with two display modes:
 * - Desktop: grid layout with hover previews and modal playback
 * - Mobile: vertical reels with scroll-snap and auto-play
 */

class ClipsFeed {
  constructor() {
    // DOM references
    this.clipsGrid = null;
    this.clipsReels = null;
    this.clipsEmpty = null;
    this.clipModal = null;
    this.clipModalVideo = null;
    this.clipModalClose = null;

    // State
    this.isMobile = false;
    this.isLoading = false;
    this.hasMore = true;
    this.lastDoc = null;
    this.pageSize = 20;
    this.clips = [];

    // Blob URL cache for cleanup
    this.blobUrls = new Map();

    // IntersectionObserver for mobile reels auto-play
    this.reelObserver = null;

    // Currently playing modal clip ID
    this.activeModalClipId = null;

    // Bound handlers for cleanup
    this._onScroll = this._handleScroll.bind(this);
    this._onResize = this._handleResize.bind(this);
    this._onKeyDown = this._handleKeyDown.bind(this);
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  init() {
    this.clipsGrid = document.getElementById('clipsGrid');
    this.clipsReels = document.getElementById('clipsReels');
    this.clipsEmpty = document.getElementById('clipsEmpty');
    this.clipModal = document.getElementById('clipModal');
    this.clipModalVideo = document.getElementById('clipModalVideo');
    this.clipModalClose = document.getElementById('clipModalClose');

    this.isMobile = window.innerWidth <= 768;
    this._setupView();
    this._bindEvents();
    this.loadClips(false);
  }

  /** @private */
  _setupView() {
    if (this.isMobile) {
      if (this.clipsGrid) this.clipsGrid.style.display = 'none';
      if (this.clipsReels) this.clipsReels.style.display = '';
      this._initReelObserver();
    } else {
      if (this.clipsGrid) this.clipsGrid.style.display = '';
      if (this.clipsReels) this.clipsReels.style.display = 'none';
    }
  }

  /** @private */
  _bindEvents() {
    // Modal close button
    if (this.clipModalClose) {
      this.clipModalClose.addEventListener('click', () => this.closeClipModal());
    }

    // Close modal on overlay click
    if (this.clipModal) {
      this.clipModal.addEventListener('click', (e) => {
        if (e.target === this.clipModal) {
          this.closeClipModal();
        }
      });
    }

    // Keyboard: Escape closes modal
    document.addEventListener('keydown', this._onKeyDown);

    // Infinite scroll
    const scrollTarget = this.isMobile ? this.clipsReels : this.clipsGrid;
    if (scrollTarget) {
      scrollTarget.addEventListener('scroll', this._onScroll);
    }
    // Also listen on window for desktop grid that may not have its own scrollbar
    window.addEventListener('scroll', this._onScroll);

    // Handle resize to switch between mobile/desktop
    window.addEventListener('resize', this._onResize);
  }

  /** @private */
  _handleKeyDown(e) {
    if (e.key === 'Escape') {
      this.closeClipModal();
    }
  }

  /** @private */
  _handleResize() {
    const wasMobile = this.isMobile;
    this.isMobile = window.innerWidth <= 768;

    if (wasMobile !== this.isMobile) {
      this._setupView();
      this._rerender();
    }
  }

  /** @private */
  _handleScroll() {
    if (this.isLoading || !this.hasMore) return;

    const scrollTarget = this.isMobile ? this.clipsReels : this.clipsGrid;
    let nearBottom = false;

    if (scrollTarget && scrollTarget.scrollHeight > scrollTarget.clientHeight) {
      const remaining = scrollTarget.scrollHeight - scrollTarget.scrollTop - scrollTarget.clientHeight;
      nearBottom = remaining < 300;
    } else {
      // Fall back to window scroll
      const remaining = document.documentElement.scrollHeight - window.scrollY - window.innerHeight;
      nearBottom = remaining < 300;
    }

    if (nearBottom) {
      this.loadClips(true);
    }
  }

  // ============================================
  // DATA LOADING
  // ============================================

  async loadClips(append) {
    if (this.isLoading) return;
    if (append && !this.hasMore) return;

    this.isLoading = true;

    try {
      if (!window.clipService) {
        console.warn('ClipService not available.');
        this._showEmpty();
        return;
      }

      const options = { limit: this.pageSize };
      if (append && this.lastDoc) {
        options.startAfter = this.lastDoc;
      }

      const result = await window.clipService.getClips(options);
      const newClips = result.clips || [];
      this.lastDoc = result.lastDoc || null;

      if (newClips.length < this.pageSize) {
        this.hasMore = false;
      }

      if (!append) {
        this.clips = newClips;
      } else {
        this.clips = this.clips.concat(newClips);
      }

      if (this.clips.length === 0) {
        this._showEmpty();
        return;
      }

      this._hideEmpty();

      if (this.isMobile) {
        this.renderMobileReels(newClips, append);
      } else {
        this.renderDesktopGrid(newClips, append);
      }
    } catch (error) {
      console.error('Failed to load clips:', error);
      if (!append && this.clips.length === 0) {
        this._showEmpty();
      }
    } finally {
      this.isLoading = false;
    }
  }

  /** @private */
  _rerender() {
    // Clean up existing blob URLs
    this._revokeAllBlobUrls();

    if (this.isMobile) {
      if (this.clipsGrid) this.clipsGrid.innerHTML = '';
      if (this.clipsReels) this.clipsReels.innerHTML = '';
      this._initReelObserver();
      if (this.clips.length > 0) {
        this.renderMobileReels(this.clips, false);
      }
    } else {
      if (this.clipsReels) this.clipsReels.innerHTML = '';
      if (this.clipsGrid) this.clipsGrid.innerHTML = '';
      if (this.clips.length > 0) {
        this.renderDesktopGrid(this.clips, false);
      }
    }
  }

  // ============================================
  // DESKTOP GRID RENDERING
  // ============================================

  renderDesktopGrid(clips, append) {
    if (!this.clipsGrid) return;

    if (!append) {
      this.clipsGrid.innerHTML = '';
    }

    const fragment = document.createDocumentFragment();

    clips.forEach((clip) => {
      const card = this._createClipCard(clip);
      fragment.appendChild(card);
    });

    this.clipsGrid.appendChild(fragment);
  }

  /** @private */
  _createClipCard(clip) {
    const card = document.createElement('div');
    card.className = 'clip-card';
    card.dataset.clipId = clip.id;

    // Thumbnail / preview container
    const mediaContainer = document.createElement('div');
    mediaContainer.className = 'clip-card-media';

    const thumbnail = document.createElement('img');
    thumbnail.className = 'clip-card-thumbnail';
    thumbnail.alt = 'Clip thumbnail';
    thumbnail.loading = 'lazy';
    // Prefer cloud thumbnail URL, fall back to local data URL
    if (clip.thumbnailUrl) {
      thumbnail.src = clip.thumbnailUrl;
    } else if (clip.thumbnailDataUrl) {
      thumbnail.src = clip.thumbnailDataUrl;
    }
    mediaContainer.appendChild(thumbnail);

    // Duration badge
    const durationBadge = document.createElement('span');
    durationBadge.className = 'clip-card-duration';
    durationBadge.textContent = this.formatDuration(clip.duration || 0);
    mediaContainer.appendChild(durationBadge);

    // Bottom overlay
    const overlay = document.createElement('div');
    overlay.className = 'clip-card-overlay';

    const heartBtn = document.createElement('button');
    heartBtn.className = 'clip-heart-btn';
    heartBtn.innerHTML = '<span class="heart-icon">&hearts;</span><span class="heart-count">' +
      (clip.hearts || 0) + '</span>';
    heartBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.handleHeart(clip.id, heartBtn);
    });

    const timestamp = document.createElement('span');
    timestamp.className = 'clip-card-time';
    timestamp.textContent = this.formatTimeAgo(clip.createdAt);

    overlay.appendChild(heartBtn);
    overlay.appendChild(timestamp);
    mediaContainer.appendChild(overlay);

    card.appendChild(mediaContainer);

    // Hover: load video preview
    let hoverVideo = null;
    let hoverTimeout = null;

    card.addEventListener('mouseenter', () => {
      hoverTimeout = setTimeout(async () => {
        try {
          hoverVideo = document.createElement('video');
          hoverVideo.className = 'clip-card-preview';
          hoverVideo.muted = true;
          hoverVideo.loop = true;
          hoverVideo.playsInline = true;

          // Prefer cloud URL, fall back to local IndexedDB blob
          if (clip.videoUrl) {
            hoverVideo.src = clip.videoUrl;
          } else {
            const blob = await window.clipService.getClipBlob(clip.id);
            if (!blob) return;
            const url = URL.createObjectURL(blob);
            this.blobUrls.set('hover-' + clip.id, url);
            hoverVideo.src = url;
          }

          mediaContainer.appendChild(hoverVideo);
          hoverVideo.play().catch(() => {});
          thumbnail.style.opacity = '0';
        } catch (err) {
          console.error('Failed to load hover preview:', err);
        }
      }, 300);
    });

    card.addEventListener('mouseleave', () => {
      if (hoverTimeout) {
        clearTimeout(hoverTimeout);
        hoverTimeout = null;
      }
      if (hoverVideo) {
        hoverVideo.pause();
        hoverVideo.remove();
        hoverVideo = null;
      }
      thumbnail.style.opacity = '';

      const hoverUrlKey = 'hover-' + clip.id;
      if (this.blobUrls.has(hoverUrlKey)) {
        URL.revokeObjectURL(this.blobUrls.get(hoverUrlKey));
        this.blobUrls.delete(hoverUrlKey);
      }
    });

    // Click: open modal
    card.addEventListener('click', () => {
      this.openClipModal(clip);
    });

    return card;
  }

  // ============================================
  // MOBILE REELS RENDERING
  // ============================================

  renderMobileReels(clips, append) {
    if (!this.clipsReels) return;

    if (!append) {
      this.clipsReels.innerHTML = '';
    }

    const fragment = document.createDocumentFragment();

    clips.forEach((clip) => {
      const reelItem = this._createReelItem(clip);
      fragment.appendChild(reelItem);
    });

    this.clipsReels.appendChild(fragment);
  }

  /** @private */
  _createReelItem(clip) {
    const item = document.createElement('div');
    item.className = 'clips-reel-item';
    item.dataset.clipId = clip.id;

    // Video element (loaded lazily via IntersectionObserver)
    const video = document.createElement('video');
    video.className = 'reel-video';
    video.playsInline = true;
    video.loop = true;
    video.muted = false;
    video.preload = 'none';
    video.setAttribute('webkit-playsinline', '');
    item.appendChild(video);

    // Side actions container
    const actions = document.createElement('div');
    actions.className = 'reel-actions';

    // Heart button
    const heartBtn = document.createElement('button');
    heartBtn.className = 'clip-heart-btn reel-heart-btn';
    heartBtn.innerHTML = '<span class="heart-icon">&hearts;</span><span class="heart-count">' +
      (clip.hearts || 0) + '</span>';
    heartBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.handleHeart(clip.id, heartBtn);
    });
    actions.appendChild(heartBtn);

    item.appendChild(actions);

    // Observe for auto-play
    if (this.reelObserver) {
      this.reelObserver.observe(item);
    }

    return item;
  }

  /** @private */
  _initReelObserver() {
    if (this.reelObserver) {
      this.reelObserver.disconnect();
    }

    this.reelObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          const item = entry.target;
          const video = item.querySelector('.reel-video');
          if (!video) return;

          if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
            this._loadAndPlayReel(item, video);
          } else {
            video.pause();
          }
        });
      },
      {
        root: this.clipsReels,
        threshold: [0.0, 0.6]
      }
    );
  }

  /** @private */
  async _loadAndPlayReel(item, video) {
    const clipId = item.dataset.clipId;

    // If video already has a source, just play
    if (video.src && video.src !== '') {
      video.play().catch(() => {});
      return;
    }

    try {
      // Find clip data for cloud URL
      const clip = this.clips.find(c => c.id === clipId);

      if (clip && clip.videoUrl) {
        // Use cloud URL
        video.src = clip.videoUrl;
      } else {
        // Fall back to local IndexedDB
        const blob = await window.clipService.getClipBlob(clipId);
        if (!blob) return;
        const url = URL.createObjectURL(blob);
        this.blobUrls.set('reel-' + clipId, url);
        video.src = url;
      }
      video.play().catch(() => {});
    } catch (err) {
      console.error('Failed to load reel video:', err);
    }
  }

  // ============================================
  // CLIP MODAL (Desktop)
  // ============================================

  async openClipModal(clip) {
    if (!this.clipModal || !this.clipModalVideo) return;

    this.activeModalClipId = clip.id;
    this.clipModal.classList.add('active');
    document.body.style.overflow = 'hidden';

    try {
      if (clip.videoUrl) {
        // Use cloud URL directly
        this.clipModalVideo.src = clip.videoUrl;
      } else {
        // Fall back to local IndexedDB
        const blob = await window.clipService.getClipBlob(clip.id);
        if (!blob) {
          console.warn('No video found for clip:', clip.id);
          return;
        }
        const url = URL.createObjectURL(blob);
        this.blobUrls.set('modal-' + clip.id, url);
        this.clipModalVideo.src = url;
      }
      this.clipModalVideo.play().catch(() => {});
    } catch (err) {
      console.error('Failed to load modal video:', err);
    }
  }

  closeClipModal() {
    if (!this.clipModal || !this.clipModalVideo) return;

    this.clipModalVideo.pause();
    this.clipModalVideo.removeAttribute('src');
    this.clipModalVideo.load();

    this.clipModal.classList.remove('active');
    document.body.style.overflow = '';

    // Clean up modal blob URL
    if (this.activeModalClipId) {
      const urlKey = 'modal-' + this.activeModalClipId;
      if (this.blobUrls.has(urlKey)) {
        URL.revokeObjectURL(this.blobUrls.get(urlKey));
        this.blobUrls.delete(urlKey);
      }
      this.activeModalClipId = null;
    }
  }

  // ============================================
  // HEARTS
  // ============================================

  async handleHeart(clipId, buttonEl) {
    if (!window.clipService || !buttonEl) return;
    if (buttonEl.classList.contains('hearted')) return;

    buttonEl.classList.add('hearted');

    const countEl = buttonEl.querySelector('.heart-count');
    if (countEl) {
      const current = parseInt(countEl.textContent, 10) || 0;
      countEl.textContent = current + 1;
    }

    try {
      const success = await window.clipService.heartClip(clipId);
      if (!success) {
        // Revert on failure
        buttonEl.classList.remove('hearted');
        if (countEl) {
          const reverted = parseInt(countEl.textContent, 10) || 1;
          countEl.textContent = Math.max(0, reverted - 1);
        }
      }
    } catch (err) {
      console.error('Failed to heart clip:', err);
      buttonEl.classList.remove('hearted');
      if (countEl) {
        const reverted = parseInt(countEl.textContent, 10) || 1;
        countEl.textContent = Math.max(0, reverted - 1);
      }
    }
  }

  // ============================================
  // FORMATTING HELPERS
  // ============================================

  formatTimeAgo(timestamp) {
    if (!timestamp) return '';

    let date;
    if (timestamp instanceof Date) {
      date = timestamp;
    } else if (timestamp.toDate && typeof timestamp.toDate === 'function') {
      // Firestore Timestamp
      date = timestamp.toDate();
    } else if (typeof timestamp === 'string') {
      date = new Date(timestamp);
    } else if (typeof timestamp === 'number') {
      date = new Date(timestamp);
    } else if (timestamp.seconds) {
      // Firestore Timestamp-like object
      date = new Date(timestamp.seconds * 1000);
    } else {
      return '';
    }

    const now = Date.now();
    const diffMs = now - date.getTime();

    if (diffMs < 0) return 'just now';

    const seconds = Math.floor(diffMs / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    const weeks = Math.floor(days / 7);

    if (seconds < 60) return 'just now';
    if (minutes < 60) return minutes + 'm ago';
    if (hours < 24) return hours + 'h ago';
    if (days < 7) return days + 'd ago';
    if (weeks < 52) return weeks + 'w ago';
    return Math.floor(weeks / 52) + 'y ago';
  }

  formatDuration(seconds) {
    if (!seconds || seconds < 0) return '0:00';

    const totalSeconds = Math.round(seconds);
    const mins = Math.floor(totalSeconds / 60);
    const secs = totalSeconds % 60;
    return mins + ':' + (secs < 10 ? '0' : '') + secs;
  }

  // ============================================
  // EMPTY STATE
  // ============================================

  /** @private */
  _showEmpty() {
    if (this.clipsEmpty) this.clipsEmpty.style.display = '';
    if (this.clipsGrid) this.clipsGrid.style.display = 'none';
    if (this.clipsReels) this.clipsReels.style.display = 'none';
  }

  /** @private */
  _hideEmpty() {
    if (this.clipsEmpty) this.clipsEmpty.style.display = 'none';

    if (this.isMobile) {
      if (this.clipsReels) this.clipsReels.style.display = '';
    } else {
      if (this.clipsGrid) this.clipsGrid.style.display = '';
    }
  }

  // ============================================
  // CLEANUP
  // ============================================

  /** @private */
  _revokeAllBlobUrls() {
    this.blobUrls.forEach((url) => {
      URL.revokeObjectURL(url);
    });
    this.blobUrls.clear();
  }

  destroy() {
    // Remove event listeners
    document.removeEventListener('keydown', this._onKeyDown);
    window.removeEventListener('resize', this._onResize);
    window.removeEventListener('scroll', this._onScroll);

    const scrollTarget = this.isMobile ? this.clipsReels : this.clipsGrid;
    if (scrollTarget) {
      scrollTarget.removeEventListener('scroll', this._onScroll);
    }

    // Disconnect observer
    if (this.reelObserver) {
      this.reelObserver.disconnect();
      this.reelObserver = null;
    }

    // Close modal if open
    this.closeClipModal();

    // Revoke all blob URLs
    this._revokeAllBlobUrls();

    // Clear state
    this.clips = [];
    this.lastDoc = null;
    this.hasMore = true;
    this.isLoading = false;
  }
}

// ============================================
// BOOTSTRAP
// ============================================

const clipsFeed = new ClipsFeed();
window.clipsFeed = clipsFeed;

document.addEventListener('DOMContentLoaded', () => {
  clipsFeed.init();
});
