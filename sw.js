/**
 * Buzzaboo Service Worker
 * Provides offline support and caching for the PWA
 */

const CACHE_NAME = 'buzzaboo-v1';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/browse.html',
  '/stream.html',
  '/profile.html',
  '/dashboard.html',
  '/shorts.html',
  '/multiview.html',
  '/styles.css',
  '/app.js',
  '/manifest.json',
  '/assets/icons/icon-192x192.png',
  '/assets/icons/icon-512x512.png'
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('Caching static assets');
        return cache.addAll(STATIC_ASSETS);
      })
      .then(() => self.skipWaiting())
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch event - serve from cache, fallback to network
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Skip external requests
  if (url.origin !== location.origin) {
    // For external images, try network first, cache as fallback
    if (request.destination === 'image') {
      event.respondWith(
        fetch(request)
          .then((response) => {
            const responseClone = response.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(request, responseClone);
            });
            return response;
          })
          .catch(() => caches.match(request))
      );
    }
    return;
  }

  // For HTML pages, try network first (for fresh content)
  if (request.destination === 'document') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseClone);
          });
          return response;
        })
        .catch(() => caches.match(request))
    );
    return;
  }

  // For static assets, try cache first
  event.respondWith(
    caches.match(request)
      .then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }
        return fetch(request).then((response) => {
          // Cache the fetched response
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseClone);
          });
          return response;
        });
      })
  );
});

// Handle push notifications
self.addEventListener('push', (event) => {
  let data = {
    title: 'Buzzaboo',
    body: 'New notification',
    icon: '/assets/icons/icon-192x192.png',
    badge: '/assets/icons/badge-72x72.png',
    url: '/'
  };

  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: data.icon || '/assets/icons/icon-192x192.png',
    badge: data.badge || '/assets/icons/badge-72x72.png',
    vibrate: [200, 100, 200],
    tag: data.type || 'default',
    data: {
      dateOfArrival: Date.now(),
      url: data.url || '/',
      type: data.type || 'default'
    },
    requireInteraction: data.type === 'stream_live',
    actions: data.type === 'stream_live' ? [
      { action: 'watch', title: 'Watch Now', icon: '/assets/icons/play.png' },
      { action: 'dismiss', title: 'Dismiss' }
    ] : []
  };

  event.waitUntil(
    self.registration.showNotification(data.title || 'Buzzaboo', options)
  );
});

// Handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const url = event.notification.data.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Check if there's already a window open
        for (let client of clientList) {
          if (client.url === url && 'focus' in client) {
            return client.focus();
          }
        }
        // Open new window if none found
        if (clients.openWindow) {
          return clients.openWindow(url);
        }
      })
  );

  // Send message to all clients about the notification click
  clients.matchAll().then((clients) => {
    clients.forEach((client) => {
      client.postMessage({
        type: 'notification-click',
        url: url,
        data: event.notification.data
      });
    });
  });
});

// Background sync for offline actions
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-chat') {
    event.waitUntil(syncChatMessages());
  }
});

async function syncChatMessages() {
  // Sync any pending chat messages when back online
  const cache = await caches.open(CACHE_NAME);
  const pendingMessages = await cache.match('pending-messages');
  
  if (pendingMessages) {
    const messages = await pendingMessages.json();
    // Send messages to server
    // await fetch('/api/chat/sync', { method: 'POST', body: JSON.stringify(messages) });
    await cache.delete('pending-messages');
  }
}

console.log('Buzzaboo Service Worker loaded');
