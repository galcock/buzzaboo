/* ============================================
   BUZZABOO - Database Service (Firestore)
   Real-time database wrapper for social features
   ============================================ */

class DatabaseService {
  constructor() {
    this.db = null;
    this.auth = null;
    this.listeners = new Map();
    this.cache = new Map();
  }

  async init(firebaseConfig) {
    try {
      // Initialize Firebase if not already done
      if (!window.firebase?.apps?.length) {
        firebase.initializeApp(firebaseConfig);
      }
      
      this.db = firebase.firestore();
      this.auth = firebase.auth();
      
      // Enable offline persistence
      await this.db.enablePersistence({ synchronizeTabs: true }).catch(err => {
        if (err.code === 'failed-precondition') {
          console.warn('Persistence failed: Multiple tabs open');
        } else if (err.code === 'unimplemented') {
          console.warn('Persistence not available in this browser');
        }
      });
      
      console.log('✓ Database service initialized');
      return true;
    } catch (error) {
      console.error('Database init error:', error);
      return false;
    }
  }

  // ============================================
  // USER OPERATIONS
  // ============================================

  async createUser(uid, data) {
    const userData = {
      uid,
      username: data.username,
      displayName: data.displayName,
      email: data.email,
      avatar: data.avatar || `https://i.pravatar.cc/150?u=${uid}`,
      bio: data.bio || '',
      verified: false,
      partner: false,
      followers: 0,
      following: 0,
      totalViews: 0,
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    };

    await this.db.collection('users').doc(uid).set(userData, { merge: true });
    return userData;
  }

  async getUser(uid) {
    const cached = this.cache.get(`user_${uid}`);
    if (cached && Date.now() - cached.timestamp < 60000) {
      return cached.data;
    }

    const doc = await this.db.collection('users').doc(uid).get();
    if (doc.exists) {
      const data = { id: doc.id, ...doc.data() };
      this.cache.set(`user_${uid}`, { data, timestamp: Date.now() });
      return data;
    }
    return null;
  }

  async updateUser(uid, updates) {
    await this.db.collection('users').doc(uid).update({
      ...updates,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    this.cache.delete(`user_${uid}`);
  }

  // ============================================
  // FOLLOW SYSTEM
  // ============================================

  async followUser(followerId, followingId) {
    if (followerId === followingId) {
      throw new Error('Cannot follow yourself');
    }

    const batch = this.db.batch();
    
    // Create follow relationship
    const followRef = this.db.collection('follows').doc(`${followerId}_${followingId}`);
    batch.set(followRef, {
      followerId,
      followingId,
      createdAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    
    // Update follower counts
    const followerRef = this.db.collection('users').doc(followerId);
    batch.update(followerRef, {
      following: firebase.firestore.FieldValue.increment(1)
    });
    
    const followingRef = this.db.collection('users').doc(followingId);
    batch.update(followingRef, {
      followers: firebase.firestore.FieldValue.increment(1)
    });
    
    await batch.commit();
    
    // Create notification
    await this.createNotification(followingId, {
      type: 'new_follower',
      fromUserId: followerId,
      message: 'started following you',
      link: `/profile.html?user=${followerId}`
    });
    
    this.cache.delete(`follows_${followerId}`);
    this.cache.delete(`followers_${followingId}`);
  }

  async unfollowUser(followerId, followingId) {
    const batch = this.db.batch();
    
    // Remove follow relationship
    const followRef = this.db.collection('follows').doc(`${followerId}_${followingId}`);
    batch.delete(followRef);
    
    // Update follower counts
    const followerRef = this.db.collection('users').doc(followerId);
    batch.update(followerRef, {
      following: firebase.firestore.FieldValue.increment(-1)
    });
    
    const followingRef = this.db.collection('users').doc(followingId);
    batch.update(followingRef, {
      followers: firebase.firestore.FieldValue.increment(-1)
    });
    
    await batch.commit();
    
    this.cache.delete(`follows_${followerId}`);
    this.cache.delete(`followers_${followingId}`);
  }

  async isFollowing(followerId, followingId) {
    const doc = await this.db.collection('follows')
      .doc(`${followerId}_${followingId}`)
      .get();
    return doc.exists;
  }

  async getFollowers(userId, limit = 50) {
    const snapshot = await this.db.collection('follows')
      .where('followingId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    const followerIds = snapshot.docs.map(doc => doc.data().followerId);
    return await this.getUsersBatch(followerIds);
  }

  async getFollowing(userId, limit = 50) {
    const snapshot = await this.db.collection('follows')
      .where('followerId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    const followingIds = snapshot.docs.map(doc => doc.data().followingId);
    return await this.getUsersBatch(followingIds);
  }

  async getUsersBatch(userIds) {
    if (!userIds.length) return [];
    
    const users = [];
    // Firestore 'in' queries limited to 10 items
    for (let i = 0; i < userIds.length; i += 10) {
      const batch = userIds.slice(i, i + 10);
      const snapshot = await this.db.collection('users')
        .where(firebase.firestore.FieldPath.documentId(), 'in', batch)
        .get();
      
      snapshot.docs.forEach(doc => {
        users.push({ id: doc.id, ...doc.data() });
      });
    }
    
    return users;
  }

  // ============================================
  // STREAM OPERATIONS
  // ============================================

  async createStream(userId, streamData) {
    const stream = {
      userId,
      title: streamData.title,
      category: streamData.category,
      tags: streamData.tags || [],
      roomName: streamData.roomName,
      thumbnail: streamData.thumbnail,
      isLive: true,
      viewers: 0,
      peakViewers: 0,
      startedAt: firebase.firestore.FieldValue.serverTimestamp(),
      endedAt: null
    };

    const ref = await this.db.collection('streams').add(stream);
    
    // Notify followers
    await this.notifyFollowers(userId, {
      type: 'stream_live',
      streamId: ref.id,
      message: 'is now live!',
      link: `/stream.html?room=${streamData.roomName}`
    });
    
    return { id: ref.id, ...stream };
  }

  async updateStream(streamId, updates) {
    await this.db.collection('streams').doc(streamId).update({
      ...updates,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    });
  }

  async endStream(streamId) {
    const streamRef = this.db.collection('streams').doc(streamId);
    const stream = await streamRef.get();
    
    if (stream.exists) {
      const data = stream.data();
      await streamRef.update({
        isLive: false,
        endedAt: firebase.firestore.FieldValue.serverTimestamp()
      });
      
      // Create VOD entry
      await this.createVOD(data.userId, {
        streamId,
        title: data.title,
        category: data.category,
        thumbnail: data.thumbnail,
        duration: Date.now() - data.startedAt?.toMillis(),
        views: 0,
        peakViewers: data.peakViewers
      });
    }
  }

  async getLiveStreams(limit = 50) {
    const snapshot = await this.db.collection('streams')
      .where('isLive', '==', true)
      .orderBy('viewers', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  listenToStream(streamId, callback) {
    const unsubscribe = this.db.collection('streams')
      .doc(streamId)
      .onSnapshot(doc => {
        if (doc.exists) {
          callback({ id: doc.id, ...doc.data() });
        }
      });
    
    this.listeners.set(`stream_${streamId}`, unsubscribe);
    return unsubscribe;
  }

  // ============================================
  // NOTIFICATIONS
  // ============================================

  async createNotification(userId, notificationData) {
    const notification = {
      userId,
      type: notificationData.type,
      fromUserId: notificationData.fromUserId || null,
      message: notificationData.message,
      link: notificationData.link || null,
      metadata: notificationData.metadata || {},
      read: false,
      createdAt: firebase.firestore.FieldValue.serverTimestamp()
    };

    await this.db.collection('notifications').add(notification);
  }

  async getNotifications(userId, limit = 50) {
    const snapshot = await this.db.collection('notifications')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  async getUnreadCount(userId) {
    const snapshot = await this.db.collection('notifications')
      .where('userId', '==', userId)
      .where('read', '==', false)
      .get();
    
    return snapshot.size;
  }

  async markNotificationRead(notificationId) {
    await this.db.collection('notifications').doc(notificationId).update({
      read: true
    });
  }

  async markAllNotificationsRead(userId) {
    const snapshot = await this.db.collection('notifications')
      .where('userId', '==', userId)
      .where('read', '==', false)
      .get();
    
    const batch = this.db.batch();
    snapshot.docs.forEach(doc => {
      batch.update(doc.ref, { read: true });
    });
    
    await batch.commit();
  }

  listenToNotifications(userId, callback) {
    const unsubscribe = this.db.collection('notifications')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .onSnapshot(snapshot => {
        const notifications = snapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
        callback(notifications);
      });
    
    this.listeners.set(`notifications_${userId}`, unsubscribe);
    return unsubscribe;
  }

  async notifyFollowers(userId, notificationData) {
    // Get followers (in batches)
    const followersSnapshot = await this.db.collection('follows')
      .where('followingId', '==', userId)
      .get();
    
    const batch = this.db.batch();
    let count = 0;
    
    for (const doc of followersSnapshot.docs) {
      const notification = {
        userId: doc.data().followerId,
        type: notificationData.type,
        fromUserId: userId,
        message: notificationData.message,
        link: notificationData.link,
        metadata: notificationData.metadata || {},
        read: false,
        createdAt: firebase.firestore.FieldValue.serverTimestamp()
      };
      
      const notifRef = this.db.collection('notifications').doc();
      batch.set(notifRef, notification);
      
      count++;
      
      // Firestore batch limit is 500
      if (count >= 500) {
        await batch.commit();
        count = 0;
      }
    }
    
    if (count > 0) {
      await batch.commit();
    }
  }

  // ============================================
  // CLIPS
  // ============================================

  async createClip(userId, clipData) {
    const clip = {
      userId,
      streamId: clipData.streamId || null,
      title: clipData.title,
      thumbnail: clipData.thumbnail,
      videoUrl: clipData.videoUrl,
      duration: clipData.duration,
      views: 0,
      likes: 0,
      category: clipData.category || '',
      tags: clipData.tags || [],
      createdAt: firebase.firestore.FieldValue.serverTimestamp()
    };

    const ref = await this.db.collection('clips').add(clip);
    return { id: ref.id, ...clip };
  }

  async getClips(userId, limit = 50) {
    const snapshot = await this.db.collection('clips')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  async getTrendingClips(limit = 50) {
    // Simple trending: highest views in last 7 days
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    
    const snapshot = await this.db.collection('clips')
      .where('createdAt', '>=', weekAgo)
      .orderBy('createdAt', 'desc')
      .orderBy('views', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  async likeClip(clipId, userId) {
    const likeRef = this.db.collection('clips').doc(clipId)
      .collection('likes').doc(userId);
    
    const doc = await likeRef.get();
    
    if (!doc.exists) {
      const batch = this.db.batch();
      
      batch.set(likeRef, {
        userId,
        createdAt: firebase.firestore.FieldValue.serverTimestamp()
      });
      
      batch.update(this.db.collection('clips').doc(clipId), {
        likes: firebase.firestore.FieldValue.increment(1)
      });
      
      await batch.commit();
    }
  }

  async unlikeClip(clipId, userId) {
    const likeRef = this.db.collection('clips').doc(clipId)
      .collection('likes').doc(userId);
    
    const doc = await likeRef.get();
    
    if (doc.exists) {
      const batch = this.db.batch();
      
      batch.delete(likeRef);
      
      batch.update(this.db.collection('clips').doc(clipId), {
        likes: firebase.firestore.FieldValue.increment(-1)
      });
      
      await batch.commit();
    }
  }

  // ============================================
  // VODs
  // ============================================

  async createVOD(userId, vodData) {
    const vod = {
      userId,
      streamId: vodData.streamId,
      title: vodData.title,
      category: vodData.category,
      thumbnail: vodData.thumbnail,
      videoUrl: vodData.videoUrl || null,
      duration: vodData.duration,
      views: 0,
      peakViewers: vodData.peakViewers || 0,
      createdAt: firebase.firestore.FieldValue.serverTimestamp()
    };

    const ref = await this.db.collection('vods').add(vod);
    return { id: ref.id, ...vod };
  }

  async getVODs(userId, limit = 50) {
    const snapshot = await this.db.collection('vods')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  // ============================================
  // ACTIVITY FEED
  // ============================================

  async getActivityFeed(userId, limit = 50) {
    // Get user's following list
    const following = await this.getFollowing(userId, 100);
    const followingIds = following.map(u => u.id);
    
    if (!followingIds.length) return [];
    
    // Get recent activities (clips, streams, etc.)
    const activities = [];
    
    // Recent clips from followed users
    for (let i = 0; i < followingIds.length; i += 10) {
      const batch = followingIds.slice(i, i + 10);
      const clipsSnapshot = await this.db.collection('clips')
        .where('userId', 'in', batch)
        .orderBy('createdAt', 'desc')
        .limit(20)
        .get();
      
      clipsSnapshot.docs.forEach(doc => {
        activities.push({
          id: doc.id,
          type: 'clip',
          ...doc.data()
        });
      });
    }
    
    // Sort by date and limit
    activities.sort((a, b) => {
      const aTime = a.createdAt?.toMillis() || 0;
      const bTime = b.createdAt?.toMillis() || 0;
      return bTime - aTime;
    });
    
    return activities.slice(0, limit);
  }

  // ============================================
  // RECOMMENDATIONS
  // ============================================

  async getRecommendedStreams(userId, limit = 20) {
    // Simple recommendation: streams in categories user watches
    // In production, this would use ML/collaborative filtering
    
    const allStreams = await this.getLiveStreams(100);
    
    // Shuffle and return subset
    const shuffled = allStreams.sort(() => Math.random() - 0.5);
    return shuffled.slice(0, limit);
  }

  async getRecommendedChannels(userId, limit = 10) {
    // Simple: popular channels user doesn't follow yet
    const following = await this.getFollowing(userId);
    const followingIds = new Set(following.map(u => u.id));
    
    const usersSnapshot = await this.db.collection('users')
      .orderBy('followers', 'desc')
      .limit(50)
      .get();
    
    const recommended = usersSnapshot.docs
      .map(doc => ({ id: doc.id, ...doc.data() }))
      .filter(u => !followingIds.has(u.id) && u.id !== userId)
      .slice(0, limit);
    
    return recommended;
  }

  // ============================================
  // CLEANUP
  // ============================================

  unsubscribeAll() {
    this.listeners.forEach(unsubscribe => unsubscribe());
    this.listeners.clear();
  }

  unsubscribe(key) {
    const unsubscribe = this.listeners.get(key);
    if (unsubscribe) {
      unsubscribe();
      this.listeners.delete(key);
    }
  }
}

// Global instance
window.databaseService = new DatabaseService();
