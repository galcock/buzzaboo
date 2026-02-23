/* ============================================
   BUZZABOO - Notifications Service
   In-app notifications + Web Push API
   ============================================ */

class NotificationsService {
  constructor() {
    this.permission = 'default';
    this.registration = null;
    this.unreadCount = 0;
    this.preferences = this.loadPreferences();
    this.listeners = [];
  }

  async init() {
    // Check notification permission
    if ('Notification' in window) {
      this.permission = Notification.permission;
    }

    // Get service worker registration
    if ('serviceWorker' in navigator) {
      this.registration = await navigator.serviceWorker.ready;
    }

    // Load user preferences
    this.preferences = this.loadPreferences();
    
    console.log('✓ Notifications service initialized');
  }

  // ============================================
  // PERMISSION MANAGEMENT
  // ============================================

  async requestPermission() {
    if (!('Notification' in window)) {
      console.warn('This browser does not support notifications');
      return false;
    }

    if (this.permission === 'granted') {
      return true;
    }

    const permission = await Notification.requestPermission();
    this.permission = permission;
    
    if (permission === 'granted') {
      console.log('✓ Notification permission granted');
      await this.subscribeToPush();
      return true;
    }
    
    return false;
  }

  hasPermission() {
    return this.permission === 'granted';
  }

  // ============================================
  // WEB PUSH SUBSCRIPTION
  // ============================================

  async subscribeToPush() {
    if (!this.registration) {
      console.warn('Service worker not registered');
      return null;
    }

    try {
      // VAPID public key (you'll need to generate this)
      const vapidPublicKey = 'YOUR_VAPID_PUBLIC_KEY_HERE';
      
      const subscription = await this.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(vapidPublicKey)
      });

      // Save subscription to backend/database
      await this.saveSubscription(subscription);
      
      console.log('✓ Push subscription created');
      return subscription;
    } catch (error) {
      console.error('Push subscription error:', error);
      return null;
    }
  }

  async saveSubscription(subscription) {
    const user = firebase.auth().currentUser;
    if (!user) return;

    await firebase.firestore()
      .collection('push_subscriptions')
      .doc(user.uid)
      .set({
        subscription: subscription.toJSON(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp()
      });
  }

  urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding)
      .replace(/\-/g, '+')
      .replace(/_/g, '/');

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  // ============================================
  // IN-APP NOTIFICATIONS
  // ============================================

  async showNotification(notification) {
    // Check if user wants this type of notification
    if (!this.shouldShowNotification(notification.type)) {
      return;
    }

    // Update unread count
    this.unreadCount++;
    this.updateBadge();

    // Trigger listeners
    this.listeners.forEach(listener => listener(notification));

    // Show browser notification if enabled
    if (this.hasPermission() && this.preferences.pushEnabled) {
      await this.showBrowserNotification(notification);
    }

    // Play sound if enabled
    if (this.preferences.soundEnabled) {
      this.playNotificationSound(notification.type);
    }
  }

  async showBrowserNotification(notification) {
    if (!this.registration) return;

    const options = {
      body: notification.message,
      icon: '/assets/icons/icon-192x192.png',
      badge: '/assets/icons/badge-72x72.png',
      tag: notification.type,
      data: {
        url: notification.link || '/',
        notificationId: notification.id
      },
      vibrate: [200, 100, 200],
      requireInteraction: notification.type === 'stream_live'
    };

    await this.registration.showNotification('Buzzaboo', options);
  }

  shouldShowNotification(type) {
    const prefs = this.preferences;
    
    switch (type) {
      case 'stream_live':
        return prefs.streamLive;
      case 'new_follower':
        return prefs.newFollower;
      case 'subscription':
        return prefs.subscription;
      case 'chat_mention':
        return prefs.chatMention;
      case 'whisper':
        return prefs.whisper;
      default:
        return true;
    }
  }

  playNotificationSound(type) {
    // Different sounds for different notification types
    const sounds = {
      stream_live: '/assets/sounds/live.mp3',
      new_follower: '/assets/sounds/follow.mp3',
      subscription: '/assets/sounds/sub.mp3',
      chat_mention: '/assets/sounds/mention.mp3',
      whisper: '/assets/sounds/whisper.mp3',
      default: '/assets/sounds/notification.mp3'
    };

    const soundUrl = sounds[type] || sounds.default;
    const audio = new Audio(soundUrl);
    audio.volume = 0.5;
    audio.play().catch(() => {
      // Audio autoplay might be blocked
    });
  }

  // ============================================
  // BADGE & UI UPDATES
  // ============================================

  updateBadge() {
    // Update notification bell badge
    const badge = document.querySelector('.notification-badge');
    if (badge) {
      badge.textContent = this.unreadCount > 99 ? '99+' : this.unreadCount;
      badge.style.display = this.unreadCount > 0 ? 'flex' : 'none';
    }

    // Update page title
    if (this.unreadCount > 0) {
      document.title = `(${this.unreadCount}) ${document.title.replace(/^\(\d+\)\s/, '')}`;
    } else {
      document.title = document.title.replace(/^\(\d+\)\s/, '');
    }

    // Update favicon badge (optional, requires canvas manipulation)
    this.updateFaviconBadge();
  }

  updateFaviconBadge() {
    if (this.unreadCount === 0) return;

    const favicon = document.querySelector('link[rel="icon"]');
    if (!favicon) return;

    const img = new Image();
    img.src = favicon.href;
    
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = 32;
      canvas.height = 32;
      const ctx = canvas.getContext('2d');
      
      // Draw original icon
      ctx.drawImage(img, 0, 0, 32, 32);
      
      // Draw badge
      ctx.fillStyle = '#ff4444';
      ctx.beginPath();
      ctx.arc(24, 8, 8, 0, 2 * Math.PI);
      ctx.fill();
      
      // Draw count
      ctx.fillStyle = '#ffffff';
      ctx.font = 'bold 12px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(this.unreadCount > 9 ? '9+' : this.unreadCount, 24, 8);
      
      // Update favicon
      favicon.href = canvas.toDataURL('image/png');
    };
  }

  setUnreadCount(count) {
    this.unreadCount = count;
    this.updateBadge();
  }

  clearUnreadCount() {
    this.unreadCount = 0;
    this.updateBadge();
  }

  // ============================================
  // PREFERENCES
  // ============================================

  loadPreferences() {
    const saved = localStorage.getItem('buzzaboo-notification-prefs');
    if (saved) {
      return JSON.parse(saved);
    }
    
    // Default preferences
    return {
      pushEnabled: true,
      soundEnabled: true,
      streamLive: true,
      newFollower: true,
      subscription: true,
      chatMention: true,
      whisper: true
    };
  }

  savePreferences(preferences) {
    this.preferences = { ...this.preferences, ...preferences };
    localStorage.setItem('buzzaboo-notification-prefs', JSON.stringify(this.preferences));
  }

  getPreferences() {
    return { ...this.preferences };
  }

  // ============================================
  // LISTENERS
  // ============================================

  addListener(callback) {
    this.listeners.push(callback);
    return () => {
      this.listeners = this.listeners.filter(l => l !== callback);
    };
  }

  // ============================================
  // REAL-TIME NOTIFICATIONS
  // ============================================

  startListening(userId) {
    if (this.unsubscribeNotifications) {
      this.unsubscribeNotifications();
    }

    this.unsubscribeNotifications = window.databaseService.listenToNotifications(
      userId,
      async (notifications) => {
        // Get unread count
        const unread = notifications.filter(n => !n.read).length;
        this.setUnreadCount(unread);

        // Show notification for new ones
        const lastCheck = this.lastNotificationCheck || 0;
        const newNotifications = notifications.filter(n => {
          const time = n.createdAt?.toMillis() || 0;
          return time > lastCheck;
        });

        for (const notification of newNotifications) {
          await this.showNotification(notification);
        }

        this.lastNotificationCheck = Date.now();
      }
    );
  }

  stopListening() {
    if (this.unsubscribeNotifications) {
      this.unsubscribeNotifications();
      this.unsubscribeNotifications = null;
    }
  }
}

// ============================================
// NOTIFICATION UI COMPONENT
// ============================================

class NotificationBell {
  constructor(containerId) {
    this.container = document.getElementById(containerId);
    this.notifications = [];
    this.render();
    this.bindEvents();
  }

  render() {
    this.container.innerHTML = `
      <div class="notification-bell dropdown">
        <button class="dropdown-trigger btn btn-ghost btn-icon" aria-label="Notifications">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2zm-2 1H8v-6c0-2.48 1.51-4.5 4-4.5s4 2.02 4 4.5v6z"/>
          </svg>
          <span class="notification-badge" style="display: none;">0</span>
        </button>
        <div class="dropdown-menu notification-dropdown">
          <div class="notification-header">
            <h3>Notifications</h3>
            <button class="btn btn-ghost btn-sm mark-all-read">Mark all read</button>
          </div>
          <div class="notification-list"></div>
          <div class="notification-footer">
            <a href="/activity.html" class="btn btn-ghost btn-sm btn-block">View all activity</a>
          </div>
        </div>
      </div>
    `;
  }

  bindEvents() {
    const markAllBtn = this.container.querySelector('.mark-all-read');
    if (markAllBtn) {
      markAllBtn.addEventListener('click', async () => {
        const user = firebase.auth().currentUser;
        if (user) {
          await window.databaseService.markAllNotificationsRead(user.uid);
          window.notificationsService.clearUnreadCount();
          await this.refresh();
        }
      });
    }
  }

  async refresh() {
    const user = firebase.auth().currentUser;
    if (!user) return;

    this.notifications = await window.databaseService.getNotifications(user.uid, 20);
    this.renderNotifications();
  }

  renderNotifications() {
    const list = this.container.querySelector('.notification-list');
    if (!list) return;

    if (this.notifications.length === 0) {
      list.innerHTML = `
        <div class="notification-empty">
          <div style="font-size: 3rem; opacity: 0.3;">🔔</div>
          <p>No notifications yet</p>
        </div>
      `;
      return;
    }

    list.innerHTML = this.notifications.map(n => {
      const timeAgo = this.formatTimeAgo(n.createdAt);
      const icon = this.getNotificationIcon(n.type);
      
      return `
        <a href="${n.link || '#'}" 
           class="notification-item ${n.read ? 'read' : 'unread'}"
           data-notification-id="${n.id}">
          <div class="notification-icon">${icon}</div>
          <div class="notification-content">
            <div class="notification-message">${n.message}</div>
            <div class="notification-time">${timeAgo}</div>
          </div>
          ${!n.read ? '<div class="notification-dot"></div>' : ''}
        </a>
      `;
    }).join('');

    // Mark as read on click
    list.querySelectorAll('.notification-item').forEach(item => {
      item.addEventListener('click', async () => {
        const id = item.dataset.notificationId;
        await window.databaseService.markNotificationRead(id);
        item.classList.remove('unread');
        item.classList.add('read');
        item.querySelector('.notification-dot')?.remove();
        
        // Update count
        const unread = list.querySelectorAll('.notification-item.unread').length;
        window.notificationsService.setUnreadCount(unread);
      });
    });
  }

  getNotificationIcon(type) {
    const icons = {
      stream_live: '🔴',
      new_follower: '👤',
      subscription: '⭐',
      chat_mention: '💬',
      whisper: '✉️',
      clip: '🎬',
      default: '🔔'
    };
    return icons[type] || icons.default;
  }

  formatTimeAgo(timestamp) {
    if (!timestamp) return 'Just now';
    
    const seconds = Math.floor((Date.now() - timestamp.toMillis()) / 1000);
    
    if (seconds < 60) return 'Just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
    return `${Math.floor(seconds / 604800)}w ago`;
  }
}

// Global instance
window.notificationsService = new NotificationsService();
