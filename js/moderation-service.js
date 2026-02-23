/**
 * Buzzaboo Moderation Service
 * Handles chat moderation, user bans, timeouts, and mod actions
 */

class ModerationService {
  constructor() {
    this.bannedUsers = new Set();
    this.timedOutUsers = new Map(); // userId -> expiryTime
    this.moderators = new Set();
    this.blockedTerms = new Set([
      // Default blocked terms (can be customized)
      'spam', 'scam', 'hack'
    ]);
    this.chatMode = {
      slowMode: false,
      slowModeSeconds: 5,
      subOnly: false,
      emoteOnly: false,
      followersOnly: false
    };
    this.modActions = [];
    this.currentUser = null;
    this.isStreamer = false;
    this.isModerator = false;
    
    this.loadSettings();
  }

  /**
   * Initialize moderation for current user
   */
  init(userId, role = 'viewer') {
    this.currentUser = userId;
    this.isStreamer = role === 'streamer';
    this.isModerator = role === 'moderator' || this.moderators.has(userId);
  }

  /**
   * Check if user has mod privileges
   */
  canModerate() {
    return this.isStreamer || this.isModerator;
  }

  /**
   * Check if user is banned
   */
  isUserBanned(userId) {
    return this.bannedUsers.has(userId);
  }

  /**
   * Check if user is timed out
   */
  isUserTimedOut(userId) {
    const timeout = this.timedOutUsers.get(userId);
    if (!timeout) return false;
    
    if (Date.now() > timeout) {
      this.timedOutUsers.delete(userId);
      return false;
    }
    return true;
  }

  /**
   * Ban a user permanently
   */
  banUser(userId, username, reason = '') {
    if (!this.canModerate()) {
      console.warn('You do not have permission to ban users');
      return false;
    }

    this.bannedUsers.add(userId);
    this.logAction('ban', userId, username, reason);
    this.saveSettings();
    
    // Emit ban event
    this.emit('userBanned', { userId, username, reason });
    return true;
  }

  /**
   * Unban a user
   */
  unbanUser(userId, username) {
    if (!this.canModerate()) return false;

    this.bannedUsers.delete(userId);
    this.logAction('unban', userId, username);
    this.saveSettings();
    
    this.emit('userUnbanned', { userId, username });
    return true;
  }

  /**
   * Timeout a user for a specified duration (in seconds)
   */
  timeoutUser(userId, username, durationSeconds, reason = '') {
    if (!this.canModerate()) {
      console.warn('You do not have permission to timeout users');
      return false;
    }

    const expiryTime = Date.now() + (durationSeconds * 1000);
    this.timedOutUsers.set(userId, expiryTime);
    this.logAction('timeout', userId, username, reason, durationSeconds);
    
    // Auto-remove after duration
    setTimeout(() => {
      this.timedOutUsers.delete(userId);
      this.emit('timeoutExpired', { userId, username });
    }, durationSeconds * 1000);

    this.emit('userTimedOut', { userId, username, durationSeconds, reason });
    return true;
  }

  /**
   * Assign moderator role to a user
   */
  addModerator(userId, username) {
    if (!this.isStreamer) {
      console.warn('Only the streamer can assign moderators');
      return false;
    }

    this.moderators.add(userId);
    this.logAction('mod_assigned', userId, username);
    this.saveSettings();
    
    this.emit('moderatorAdded', { userId, username });
    return true;
  }

  /**
   * Remove moderator role from a user
   */
  removeModerator(userId, username) {
    if (!this.isStreamer) return false;

    this.moderators.delete(userId);
    this.logAction('mod_removed', userId, username);
    this.saveSettings();
    
    this.emit('moderatorRemoved', { userId, username });
    return true;
  }

  /**
   * Toggle slow mode
   */
  setSlowMode(enabled, seconds = 5) {
    if (!this.canModerate()) return false;

    this.chatMode.slowMode = enabled;
    this.chatMode.slowModeSeconds = seconds;
    this.logAction('slow_mode', null, null, enabled ? `${seconds}s` : 'disabled');
    this.saveSettings();
    
    this.emit('chatModeChanged', { mode: 'slow', enabled, seconds });
    return true;
  }

  /**
   * Toggle subscribers-only mode
   */
  setSubOnlyMode(enabled) {
    if (!this.canModerate()) return false;

    this.chatMode.subOnly = enabled;
    this.logAction('sub_only_mode', null, null, enabled ? 'enabled' : 'disabled');
    this.saveSettings();
    
    this.emit('chatModeChanged', { mode: 'subOnly', enabled });
    return true;
  }

  /**
   * Toggle emote-only mode
   */
  setEmoteOnlyMode(enabled) {
    if (!this.canModerate()) return false;

    this.chatMode.emoteOnly = enabled;
    this.logAction('emote_only_mode', null, null, enabled ? 'enabled' : 'disabled');
    this.saveSettings();
    
    this.emit('chatModeChanged', { mode: 'emoteOnly', enabled });
    return true;
  }

  /**
   * Toggle followers-only mode
   */
  setFollowersOnlyMode(enabled) {
    if (!this.canModerate()) return false;

    this.chatMode.followersOnly = enabled;
    this.logAction('followers_only_mode', null, null, enabled ? 'enabled' : 'disabled');
    this.saveSettings();
    
    this.emit('chatModeChanged', { mode: 'followersOnly', enabled });
    return true;
  }

  /**
   * Add blocked term
   */
  addBlockedTerm(term) {
    if (!this.canModerate()) return false;

    this.blockedTerms.add(term.toLowerCase());
    this.logAction('term_blocked', null, null, term);
    this.saveSettings();
    
    this.emit('blockedTermAdded', { term });
    return true;
  }

  /**
   * Remove blocked term
   */
  removeBlockedTerm(term) {
    if (!this.canModerate()) return false;

    this.blockedTerms.delete(term.toLowerCase());
    this.logAction('term_unblocked', null, null, term);
    this.saveSettings();
    
    this.emit('blockedTermRemoved', { term });
    return true;
  }

  /**
   * Check if message contains blocked terms
   */
  containsBlockedTerms(message) {
    const lowerMessage = message.toLowerCase();
    return Array.from(this.blockedTerms).some(term => lowerMessage.includes(term));
  }

  /**
   * Delete a chat message
   */
  deleteMessage(messageId, userId, username, reason = '') {
    if (!this.canModerate()) return false;

    this.logAction('message_deleted', userId, username, reason);
    this.emit('messageDeleted', { messageId, userId, username, reason });
    return true;
  }

  /**
   * Check if user can send message based on chat mode
   */
  canUserSendMessage(userId, isSubscriber = false, isFollower = false) {
    if (this.isUserBanned(userId)) {
      return { allowed: false, reason: 'You are banned from this chat' };
    }

    if (this.isUserTimedOut(userId)) {
      return { allowed: false, reason: 'You are timed out' };
    }

    if (this.chatMode.subOnly && !isSubscriber && !this.canModerate()) {
      return { allowed: false, reason: 'This chat is in subscribers-only mode' };
    }

    if (this.chatMode.followersOnly && !isFollower && !isSubscriber && !this.canModerate()) {
      return { allowed: false, reason: 'This chat is in followers-only mode' };
    }

    return { allowed: true };
  }

  /**
   * Validate message (check for blocked terms, emote-only mode)
   */
  validateMessage(message) {
    if (this.containsBlockedTerms(message)) {
      return { valid: false, reason: 'Message contains blocked terms' };
    }

    if (this.chatMode.emoteOnly && !this.isEmoteOnlyMessage(message)) {
      return { valid: false, reason: 'This chat is in emote-only mode' };
    }

    return { valid: true };
  }

  /**
   * Check if message is emote-only (simplified check)
   */
  isEmoteOnlyMessage(message) {
    // Simple check: only emojis and common emote syntax
    const emotePattern = /^[\p{Emoji}\s:]+$/u;
    return emotePattern.test(message);
  }

  /**
   * Log moderation action
   */
  logAction(action, userId, username, details = '', duration = null) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      action,
      userId,
      username,
      moderator: this.currentUser,
      details,
      duration
    };

    this.modActions.unshift(logEntry);
    
    // Keep last 500 actions
    if (this.modActions.length > 500) {
      this.modActions = this.modActions.slice(0, 500);
    }

    this.saveActions();
  }

  /**
   * Get moderation action logs
   */
  getActionLogs(limit = 50) {
    return this.modActions.slice(0, limit);
  }

  /**
   * Event emitter
   */
  emit(event, data) {
    const customEvent = new CustomEvent(`moderation:${event}`, { detail: data });
    document.dispatchEvent(customEvent);
  }

  /**
   * Save settings to localStorage
   */
  saveSettings() {
    const settings = {
      bannedUsers: Array.from(this.bannedUsers),
      moderators: Array.from(this.moderators),
      blockedTerms: Array.from(this.blockedTerms),
      chatMode: this.chatMode
    };

    localStorage.setItem('buzzaboo_mod_settings', JSON.stringify(settings));
  }

  /**
   * Load settings from localStorage
   */
  loadSettings() {
    try {
      const saved = localStorage.getItem('buzzaboo_mod_settings');
      if (saved) {
        const settings = JSON.parse(saved);
        this.bannedUsers = new Set(settings.bannedUsers || []);
        this.moderators = new Set(settings.moderators || []);
        this.blockedTerms = new Set(settings.blockedTerms || []);
        this.chatMode = settings.chatMode || this.chatMode;
      }
    } catch (e) {
      console.error('Failed to load moderation settings', e);
    }
  }

  /**
   * Save action logs to localStorage
   */
  saveActions() {
    try {
      localStorage.setItem('buzzaboo_mod_actions', JSON.stringify(this.modActions));
    } catch (e) {
      console.error('Failed to save mod actions', e);
    }
  }

  /**
   * Load action logs from localStorage
   */
  loadActions() {
    try {
      const saved = localStorage.getItem('buzzaboo_mod_actions');
      if (saved) {
        this.modActions = JSON.parse(saved);
      }
    } catch (e) {
      console.error('Failed to load mod actions', e);
    }
  }

  /**
   * Export moderation data
   */
  exportData() {
    return {
      bannedUsers: Array.from(this.bannedUsers),
      moderators: Array.from(this.moderators),
      blockedTerms: Array.from(this.blockedTerms),
      chatMode: this.chatMode,
      actions: this.modActions
    };
  }
}

// Create global instance
window.ModerationService = new ModerationService();
