/**
 * Buzzaboo Matching Service
 * Firestore-based matchmaking for random video chat
 *
 * Writes to `matchmaking_queue` collection, scores candidates by shared interests,
 * and claims matches atomically via Firestore transactions.
 */

class MatchingService {
  constructor() {
    this.db = null;
    this.userId = null;
    this.queueDocRef = null;
    this.unsubscribeSnapshot = null;
    this.matchRetryTimer = null;
    this.eventHandlers = new Map();
    this.isSearching = false;
  }

  /**
   * Initialize with Firestore reference and current user ID.
   * @param {firebase.firestore.Firestore} db
   * @param {string} userId
   */
  init(db, userId) {
    this.db = db;
    this.userId = userId;
  }

  // ============================================
  // QUEUE MANAGEMENT
  // ============================================

  /**
   * Enter the matchmaking queue and begin searching for a partner.
   * Writes a queue document, starts a snapshot listener for incoming matches,
   * and kicks off an active polling loop that retries every 1s for up to 60s.
   *
   * @param {string[]} interests - User's interest tags
   * @param {'minor'|'adult'} agePool - Age pool for safe matching
   * @returns {Promise<void>}
   */
  async enterQueue(interests, agePool) {
    if (!this.db || !this.userId) {
      throw new Error('MatchingService not initialized. Call init(db, userId) first.');
    }

    if (this.isSearching) {
      console.warn('Already searching for a match.');
      return;
    }

    this.isSearching = true;
    this.queueDocRef = this.db.collection('matchmaking_queue').doc(this.userId);

    const queueEntry = {
      userId: this.userId,
      interests: interests || [],
      agePool: agePool,
      status: 'waiting',
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()
    };

    await this.queueDocRef.set(queueEntry);
    this.emit('searching');

    this.listenForMatch();
    this.startMatchLoop(interests, agePool);
  }

  /**
   * Listen on our own queue document for status changes.
   * If another user matches with us first, we pick it up here.
   */
  listenForMatch() {
    if (!this.queueDocRef) return;

    this.unsubscribeSnapshot = this.queueDocRef.onSnapshot((snapshot) => {
      if (!snapshot.exists) return;

      const data = snapshot.data();
      if (data.status === 'matched' && data.roomName && data.partnerId) {
        this.handleMatchFound(data.roomName, data.partnerId);
      }
    });
  }

  /**
   * Actively poll for a match every 1 second, up to 60 attempts.
   * Stops early if a match is found (either by us or by the snapshot listener).
   *
   * @param {string[]} interests
   * @param {'minor'|'adult'} agePool
   */
  startMatchLoop(interests, agePool) {
    let attempts = 0;
    const maxAttempts = 60;

    this.matchRetryTimer = setInterval(async () => {
      if (!this.isSearching) {
        clearInterval(this.matchRetryTimer);
        this.matchRetryTimer = null;
        return;
      }

      attempts++;
      if (attempts > maxAttempts) {
        clearInterval(this.matchRetryTimer);
        this.matchRetryTimer = null;
        return;
      }

      try {
        await this.attemptMatch(interests, agePool);
      } catch (error) {
        console.error('Match attempt failed:', error);
      }
    }, 1000);
  }

  /**
   * Query the queue for other waiting users in the same age pool,
   * score them by shared interests, and attempt to claim the best
   * candidate via an atomic Firestore transaction.
   *
   * @param {string[]} interests
   * @param {'minor'|'adult'} agePool
   * @returns {Promise<boolean>} Whether a match was successfully claimed
   */
  async attemptMatch(interests, agePool) {
    if (!this.isSearching) return false;

    const candidatesSnapshot = await this.db
      .collection('matchmaking_queue')
      .where('status', '==', 'waiting')
      .where('agePool', '==', agePool)
      .limit(20)
      .get();

    if (candidatesSnapshot.empty) return false;

    // Filter out ourselves and score by shared interests
    const candidates = [];
    candidatesSnapshot.forEach((doc) => {
      if (doc.id === this.userId) return;
      const data = doc.data();
      const sharedCount = this.countSharedInterests(interests, data.interests);
      candidates.push({ doc, data, sharedCount });
    });

    if (candidates.length === 0) return false;

    // Sort by shared interest count descending, then by createdAt ascending (oldest first)
    candidates.sort((a, b) => {
      if (b.sharedCount !== a.sharedCount) return b.sharedCount - a.sharedCount;
      const aTime = a.data.createdAt?.toMillis?.() || 0;
      const bTime = b.data.createdAt?.toMillis?.() || 0;
      return aTime - bTime;
    });

    // Try to claim the best candidate atomically
    for (const candidate of candidates) {
      const claimed = await this.claimMatch(candidate.doc.ref);
      if (claimed) return true;
    }

    return false;
  }

  /**
   * Atomically claim a match between this user and a candidate.
   * Both queue documents are updated to 'matched' with a shared room name.
   * Uses a Firestore transaction to prevent double-matching.
   *
   * @param {firebase.firestore.DocumentReference} candidateRef
   * @returns {Promise<boolean>} Whether the claim succeeded
   */
  async claimMatch(candidateRef) {
    const roomName = crypto.randomUUID();

    try {
      await this.db.runTransaction(async (transaction) => {
        const candidateSnap = await transaction.get(candidateRef);
        const selfSnap = await transaction.get(this.queueDocRef);

        if (!candidateSnap.exists || !selfSnap.exists) {
          throw new Error('Queue document missing');
        }

        const candidateData = candidateSnap.data();
        const selfData = selfSnap.data();

        // Both must still be waiting — otherwise someone else already matched them
        if (candidateData.status !== 'waiting' || selfData.status !== 'waiting') {
          throw new Error('One or both users no longer waiting');
        }

        const now = firebase.firestore.FieldValue.serverTimestamp();

        transaction.update(candidateRef, {
          status: 'matched',
          roomName: roomName,
          partnerId: this.userId,
          matchedAt: now,
          updatedAt: now
        });

        transaction.update(this.queueDocRef, {
          status: 'matched',
          roomName: roomName,
          partnerId: candidateSnap.id,
          matchedAt: now,
          updatedAt: now
        });
      });

      return true;
    } catch (error) {
      // Transaction failure is expected when another user claims first
      return false;
    }
  }

  /**
   * Called when a match is confirmed, either from our own transaction
   * or from the snapshot listener detecting another user's transaction.
   *
   * @param {string} roomName
   * @param {string} partnerId
   */
  handleMatchFound(roomName, partnerId) {
    if (!this.isSearching) return;

    this.stopSearching();
    this.emit('matched', { roomName, partnerId });
  }

  /**
   * Leave the matchmaking queue. Deletes the queue document,
   * stops the snapshot listener, and cancels the retry loop.
   *
   * @returns {Promise<void>}
   */
  async leaveQueue() {
    this.stopSearching();

    if (this.queueDocRef) {
      try {
        await this.queueDocRef.delete();
      } catch (error) {
        console.error('Error deleting queue document:', error);
      }
      this.queueDocRef = null;
    }
  }

  /**
   * Stop all active searching without deleting the queue document.
   */
  stopSearching() {
    this.isSearching = false;

    if (this.unsubscribeSnapshot) {
      this.unsubscribeSnapshot();
      this.unsubscribeSnapshot = null;
    }

    if (this.matchRetryTimer) {
      clearInterval(this.matchRetryTimer);
      this.matchRetryTimer = null;
    }
  }

  // ============================================
  // REPORTING
  // ============================================

  /**
   * Report a partner for misconduct.
   *
   * @param {string} partnerId - The user ID of the reported partner
   * @param {string} reason - Description of the report reason
   * @returns {Promise<{success: boolean, error?: string}>}
   */
  async reportPartner(partnerId, reason) {
    if (!this.db || !this.userId) {
      return { success: false, error: 'MatchingService not initialized.' };
    }

    try {
      await this.db.collection('reports').add({
        reporterId: this.userId,
        reportedUserId: partnerId,
        reason: reason,
        createdAt: firebase.firestore.FieldValue.serverTimestamp()
      });
      return { success: true };
    } catch (error) {
      console.error('Error submitting report:', error);
      return { success: false, error: error.message };
    }
  }

  // ============================================
  // HELPERS
  // ============================================

  /**
   * Count the number of shared interests between two arrays.
   *
   * @param {string[]} a
   * @param {string[]} b
   * @returns {number}
   */
  countSharedInterests(a, b) {
    if (!a || !b || a.length === 0 || b.length === 0) return 0;
    const setB = new Set(b);
    let count = 0;
    for (const interest of a) {
      if (setB.has(interest)) count++;
    }
    return count;
  }

  // ============================================
  // EVENT SYSTEM
  // ============================================

  on(event, handler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event).add(handler);
    return () => this.off(event, handler);
  }

  off(event, handler) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) handlers.delete(handler);
  }

  emit(event, data) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => {
        try { handler(data); }
        catch (error) { console.error(`Error in event handler for ${event}:`, error); }
      });
    }
  }
}

const matchingService = new MatchingService();
window.matchingService = matchingService;
window.MatchingService = MatchingService;
