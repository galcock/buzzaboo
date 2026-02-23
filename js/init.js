/* ============================================
   BUZZABOO - Global Initialization
   Initialize all services and features
   ============================================ */

(async function initBuzzaboo() {
  console.log('🐝 Initializing Buzzaboo...');

  // Wait for DOM
  if (document.readyState === 'loading') {
    await new Promise(resolve => {
      document.addEventListener('DOMContentLoaded', resolve);
    });
  }

  try {
    // Initialize Database Service
    if (window.databaseService && window.firebaseConfig) {
      const dbInitialized = await window.databaseService.init(window.firebaseConfig);
      if (dbInitialized) {
        console.log('✓ Database service ready');
      }
    }

    // Initialize Notifications Service
    if (window.notificationsService) {
      await window.notificationsService.init();
      console.log('✓ Notifications service ready');

      // Auto-request permission if not set
      if (Notification.permission === 'default') {
        // Wait a bit before asking
        setTimeout(() => {
          showNotificationPrompt();
        }, 5000);
      }

      // Start listening for notifications if user is logged in
      firebase.auth().onAuthStateChanged((user) => {
        if (user) {
          window.notificationsService.startListening(user.uid);
          console.log('✓ Listening for notifications');
        } else {
          window.notificationsService.stopListening();
        }
      });
    }

    // Render notification bell in header
    const bellContainer = document.getElementById('notification-bell-container');
    if (bellContainer && typeof NotificationBell !== 'undefined') {
      const bell = new NotificationBell('notification-bell-container');
      
      // Refresh when user logs in
      firebase.auth().onAuthStateChanged(async (user) => {
        if (user) {
          await bell.refresh();
        }
      });
    }

    // Initialize social features based on page
    initPageFeatures();

    console.log('✓ Buzzaboo initialized successfully');
  } catch (error) {
    console.error('❌ Initialization error:', error);
  }
})();

// Initialize page-specific features
function initPageFeatures() {
  const page = document.body.dataset.page;

  switch (page) {
    case 'stream':
      initStreamPageSocial();
      break;
    case 'profile':
      initProfilePageSocial();
      break;
    case 'home':
    case 'browse':
      initBrowsePageSocial();
      break;
  }
}

// Stream Page Social Features
function initStreamPageSocial() {
  // Add share button
  const shareContainer = document.getElementById('stream-share-container');
  if (shareContainer) {
    const shareMenu = new ShareMenu({
      url: window.location.href,
      title: document.title,
      text: 'Check out this stream on Buzzaboo!'
    });
    shareMenu.render(shareContainer);
  }

  // Add clip button
  const clipContainer = document.getElementById('stream-clip-container');
  if (clipContainer) {
    const urlParams = new URLSearchParams(window.location.search);
    const streamId = urlParams.get('room') || 'default';
    ClipCreator.renderClipButton(clipContainer, streamId);
  }

  // Add follow button (if viewing another user's stream)
  const followContainer = document.getElementById('stream-follow-container');
  if (followContainer) {
    const urlParams = new URLSearchParams(window.location.search);
    const channel = urlParams.get('channel');
    
    if (channel) {
      // Get streamer data and render follow button
      // This would need to look up the user ID from the username
      // For now, we'll skip this as it needs database lookup
    }
  }
}

// Profile Page Social Features
function initProfilePageSocial() {
  // Add follow button
  const followContainer = document.getElementById('profile-follow-container');
  if (followContainer) {
    const urlParams = new URLSearchParams(window.location.search);
    const username = urlParams.get('user');
    
    if (username) {
      // Look up user and render follow button
      // This needs database lookup - implement in profile.html script
    }
  }

  // Add share button
  const shareContainer = document.getElementById('profile-share-container');
  if (shareContainer) {
    const shareMenu = new ShareMenu({
      url: window.location.href,
      title: document.title,
      text: 'Check out this channel on Buzzaboo!'
    });
    shareMenu.render(shareContainer);
  }
}

// Browse Page Social Features
function initBrowsePageSocial() {
  // Add recommended channels widget
  const recommendedContainer = document.getElementById('recommended-channels-widget');
  if (recommendedContainer) {
    const user = firebase.auth().currentUser;
    if (user) {
      const widget = new RecommendedChannels({ limit: 5 });
      widget.render(recommendedContainer);
    }
  }
}

// Notification permission prompt
function showNotificationPrompt() {
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'default') return;

  // Show a nice UI prompt instead of browser's default
  const prompt = document.createElement('div');
  prompt.className = 'notification-prompt glass-card';
  prompt.style.cssText = `
    position: fixed;
    bottom: 2rem;
    right: 2rem;
    padding: 1.5rem;
    max-width: 350px;
    z-index: 9999;
    box-shadow: 0 4px 20px rgba(0,0,0,0.3);
  `;
  
  prompt.innerHTML = `
    <div style="display: flex; align-items: center; gap: 1rem; margin-bottom: 1rem;">
      <div style="font-size: 2rem;">🔔</div>
      <div>
        <h3 style="margin: 0 0 0.25rem 0; font-size: 1rem;">Enable Notifications?</h3>
        <p style="margin: 0; font-size: 0.85rem; color: var(--text-secondary);">
          Get notified when channels you follow go live
        </p>
      </div>
    </div>
    <div style="display: flex; gap: 0.5rem;">
      <button class="btn btn-primary btn-sm" id="enable-notifications">Enable</button>
      <button class="btn btn-secondary btn-sm" id="dismiss-notifications">Not Now</button>
    </div>
  `;

  document.body.appendChild(prompt);

  document.getElementById('enable-notifications')?.addEventListener('click', async () => {
    const granted = await window.notificationsService.requestPermission();
    if (granted) {
      window.Toast?.success('Notifications Enabled', 'You\'ll now receive push notifications');
    }
    prompt.remove();
  });

  document.getElementById('dismiss-notifications')?.addEventListener('click', () => {
    prompt.remove();
  });

  // Auto-dismiss after 30 seconds
  setTimeout(() => {
    prompt.remove();
  }, 30000);
}

// Handle service worker messages
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'notification-click') {
      // Handle notification click
      const url = event.data.url;
      if (url) {
        window.location.href = url;
      }
    }
  });
}

// Export for global access
window.BuzzabooInit = {
  initPageFeatures,
  showNotificationPrompt
};
