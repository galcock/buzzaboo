/* ============================================
   BUZZABOO - Scoring Service
   Points, streaks, stats, and leaderboard.
   Only active for logged-in (Firebase Auth) users.
   Anonymous users see prompts to log in.
   ============================================ */

class ScoringService {
  constructor() {
    this.userId = null;
    this.isAuthenticated = false;
    this.stats = null;
    this.unsubscribe = null;
    this.listeners = {};
    this.defaultStats = {
      score: 0,
      correctGuesses: 0,
      wrongGuesses: 0,
      currentStreak: 0,
      bestStreak: 0,
      totalChats: 0,
      totalClipHearts: 0,
      longestChat: 0,
      gamesPlayed: 0
    };
  }

  async init(userId, isAuthenticated) {
    this.userId = userId;
    this.isAuthenticated = isAuthenticated;

    if (!isAuthenticated) {
      this.stats = { ...this.defaultStats };
      return;
    }

    try {
      const db = firebase.firestore();
      const userRef = db.collection('users').doc(userId);
      const doc = await userRef.get();

      if (doc.exists && doc.data().stats) {
        this.stats = { ...this.defaultStats, ...doc.data().stats };
      } else {
        this.stats = { ...this.defaultStats };
        // Initialize stats in Firestore
        await userRef.set({ stats: this.stats }, { merge: true });
      }

      // Real-time listener for score updates (e.g., clip hearts from other users)
      this.unsubscribe = userRef.onSnapshot((snap) => {
        if (snap.exists && snap.data().stats) {
          const newStats = { ...this.defaultStats, ...snap.data().stats };
          const oldScore = this.stats ? this.stats.score : 0;
          this.stats = newStats;

          // Notify if score changed externally (e.g., someone hearted your clip)
          if (newStats.score !== oldScore) {
            this.emit('scoreChanged', { score: newStats.score, delta: newStats.score - oldScore });
          }
        }
      });

      console.log('✓ Scoring service initialized', this.stats);
    } catch (err) {
      console.error('Scoring init error:', err);
      this.stats = { ...this.defaultStats };
    }
  }

  getStats() {
    return this.stats ? { ...this.stats } : { ...this.defaultStats };
  }

  getScore() {
    return this.stats ? this.stats.score : 0;
  }

  getStreak() {
    return this.stats ? this.stats.currentStreak : 0;
  }

  getStreakMultiplier() {
    const streak = this.getStreak();
    if (streak >= 7) return 3;
    if (streak >= 4) return 2;
    if (streak >= 2) return 1.5;
    return 1;
  }

  async recordGuess(correct) {
    if (!this.isAuthenticated || !this.stats) return { points: 0, correct };

    this.stats.gamesPlayed++;

    let points;
    if (correct) {
      this.stats.correctGuesses++;
      this.stats.currentStreak++;
      if (this.stats.currentStreak > this.stats.bestStreak) {
        this.stats.bestStreak = this.stats.currentStreak;
      }
      const multiplier = this.getStreakMultiplier();
      points = Math.floor(10 * multiplier);
      this.stats.score += points;
    } else {
      this.stats.wrongGuesses++;
      points = -5;
      this.stats.score = Math.max(0, this.stats.score + points);
      this.stats.currentStreak = 0;
    }

    await this.saveStats();
    this.emit('guessRecorded', {
      correct,
      points,
      streak: this.stats.currentStreak,
      multiplier: this.getStreakMultiplier(),
      totalScore: this.stats.score
    });

    return { points, correct, streak: this.stats.currentStreak, totalScore: this.stats.score };
  }

  async recordChat(durationSeconds) {
    if (!this.isAuthenticated || !this.stats) return;

    this.stats.totalChats++;
    if (durationSeconds > this.stats.longestChat) {
      this.stats.longestChat = durationSeconds;
    }

    // Bonus for long chats
    let points = 0;
    if (durationSeconds >= 300) { // 5 minutes
      points = 5;
      this.stats.score += points;
      this.emit('scoreChanged', { score: this.stats.score, delta: points, reason: 'Long chat bonus (+5)' });
    }

    await this.saveStats();
    return points;
  }

  async recordClipHeart(clipOwnerId) {
    if (!clipOwnerId) return;

    try {
      const db = firebase.firestore();
      const ownerRef = db.collection('users').doc(clipOwnerId);
      const ownerDoc = await ownerRef.get();

      if (ownerDoc.exists) {
        const ownerStats = ownerDoc.data().stats || { ...this.defaultStats };
        ownerStats.totalClipHearts = (ownerStats.totalClipHearts || 0) + 1;
        ownerStats.score = (ownerStats.score || 0) + 2;
        await ownerRef.update({ stats: ownerStats });
      }
    } catch (err) {
      console.error('Error recording clip heart:', err);
    }
  }

  async getLeaderboard(limit = 50) {
    try {
      const db = firebase.firestore();
      const snapshot = await db.collection('users')
        .where('stats.score', '>', 0)
        .orderBy('stats.score', 'desc')
        .limit(limit)
        .get();

      const leaderboard = [];
      let rank = 1;
      snapshot.forEach(doc => {
        const data = doc.data();
        const stats = data.stats || {};
        const totalGuesses = (stats.correctGuesses || 0) + (stats.wrongGuesses || 0);
        leaderboard.push({
          rank: rank++,
          userId: doc.id,
          displayName: data.displayName || 'Anonymous',
          score: stats.score || 0,
          bestStreak: stats.bestStreak || 0,
          correctPct: totalGuesses > 0 ? Math.round((stats.correctGuesses / totalGuesses) * 100) : 0,
          gamesPlayed: stats.gamesPlayed || 0
        });
      });

      return leaderboard;
    } catch (err) {
      console.error('Leaderboard query error:', err);
      return [];
    }
  }

  async getUserRank() {
    if (!this.isAuthenticated || !this.stats || this.stats.score <= 0) return null;

    try {
      const db = firebase.firestore();
      const higherCount = await db.collection('users')
        .where('stats.score', '>', this.stats.score)
        .get();

      return higherCount.size + 1;
    } catch (err) {
      return null;
    }
  }

  async saveStats() {
    if (!this.isAuthenticated || !this.userId) return;

    try {
      const db = firebase.firestore();
      await db.collection('users').doc(this.userId).update({
        stats: this.stats
      });
    } catch (err) {
      console.error('Error saving stats:', err);
    }
  }

  // ── Event System ───────────────────────────────────────

  on(event, callback) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(callback);
  }

  off(event, callback) {
    if (!this.listeners[event]) return;
    this.listeners[event] = this.listeners[event].filter(cb => cb !== callback);
  }

  emit(event, data) {
    if (!this.listeners[event]) return;
    this.listeners[event].forEach(cb => cb(data));
  }

  destroy() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    this.listeners = {};
    this.stats = null;
  }
}

// Export
window.ScoringService = ScoringService;
console.log('✓ Scoring service loaded');
