/**
 * Buzzaboo Analytics Service
 * Google Analytics 4 integration with event tracking
 */

class AnalyticsService {
  constructor() {
    this.gaId = null;
    this.initialized = false;
    this.debugMode = false;
  }

  /**
   * Initialize Google Analytics 4
   * @param {string} measurementId - GA4 Measurement ID (G-XXXXXXXXXX)
   */
  init(measurementId, options = {}) {
    if (this.initialized) {
      console.warn('Analytics already initialized');
      return;
    }

    this.gaId = measurementId;
    this.debugMode = options.debug || false;

    // Load GA4 script
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
    document.head.appendChild(script);

    // Initialize dataLayer
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    window.gtag = gtag;

    gtag('js', new Date());
    gtag('config', measurementId, {
      send_page_view: true,
      cookie_flags: 'SameSite=None;Secure',
      ...options
    });

    this.initialized = true;
    this.log('Analytics initialized', measurementId);

    // Set up automatic tracking
    this.setupAutoTracking();
  }

  /**
   * Track page view
   */
  trackPageView(pagePath, pageTitle) {
    if (!this.initialized) return;

    window.gtag('event', 'page_view', {
      page_path: pagePath || window.location.pathname,
      page_title: pageTitle || document.title,
      page_location: window.location.href
    });

    this.log('Page view tracked', pagePath);
  }

  /**
   * Track custom event
   */
  trackEvent(eventName, params = {}) {
    if (!this.initialized) return;

    window.gtag('event', eventName, params);
    this.log('Event tracked', eventName, params);
  }

  /**
   * Set up automatic event tracking
   */
  setupAutoTracking() {
    // Track time on page
    let pageStartTime = Date.now();
    window.addEventListener('beforeunload', () => {
      const timeOnPage = Math.round((Date.now() - pageStartTime) / 1000);
      this.trackEvent('time_on_page', {
        seconds: timeOnPage,
        page: window.location.pathname
      });
    });
  }

  // ============================================
  // STREAM-SPECIFIC EVENTS
  // ============================================

  /**
   * Track stream view
   */
  trackStreamView(streamId, streamerName, category) {
    this.trackEvent('stream_view', {
      stream_id: streamId,
      streamer_name: streamerName,
      category: category,
      page: 'stream'
    });
  }

  /**
   * Track stream watch time
   */
  trackStreamWatchTime(streamId, streamerName, durationSeconds) {
    this.trackEvent('stream_watch_time', {
      stream_id: streamId,
      streamer_name: streamerName,
      duration_seconds: durationSeconds,
      engagement_level: this.getEngagementLevel(durationSeconds)
    });
  }

  /**
   * Track when user starts streaming (goes live)
   */
  trackGoLive(streamId, category, title) {
    this.trackEvent('go_live', {
      stream_id: streamId,
      category: category,
      title: title
    });
  }

  /**
   * Track stream end
   */
  trackStreamEnd(streamId, durationMinutes, peakViewers) {
    this.trackEvent('stream_end', {
      stream_id: streamId,
      duration_minutes: durationMinutes,
      peak_viewers: peakViewers
    });
  }

  // ============================================
  // USER ENGAGEMENT EVENTS
  // ============================================

  /**
   * Track sign up
   */
  trackSignUp(method = 'email') {
    this.trackEvent('sign_up', {
      method: method
    });
  }

  /**
   * Track login
   */
  trackLogin(method = 'email') {
    this.trackEvent('login', {
      method: method
    });
  }

  /**
   * Track follow
   */
  trackFollow(streamerName, streamerId) {
    this.trackEvent('follow', {
      streamer_name: streamerName,
      streamer_id: streamerId
    });
  }

  /**
   * Track unfollow
   */
  trackUnfollow(streamerName, streamerId) {
    this.trackEvent('unfollow', {
      streamer_name: streamerName,
      streamer_id: streamerId
    });
  }

  /**
   * Track subscription
   */
  trackSubscription(streamerName, streamerId, tier = 1, value = 0) {
    this.trackEvent('subscribe', {
      streamer_name: streamerName,
      streamer_id: streamerId,
      tier: tier,
      value: value,
      currency: 'USD'
    });

    // Also track as conversion
    this.trackEvent('purchase', {
      transaction_id: `sub_${Date.now()}_${streamerId}`,
      value: value,
      currency: 'USD',
      items: [{
        item_id: `sub_tier_${tier}`,
        item_name: `Subscription Tier ${tier}`,
        item_category: 'Subscription',
        price: value
      }]
    });
  }

  /**
   * Track bits/tip
   */
  trackTip(streamerName, streamerId, amount) {
    this.trackEvent('tip', {
      streamer_name: streamerName,
      streamer_id: streamerId,
      amount: amount,
      currency: 'USD'
    });
  }

  // ============================================
  // CONTENT INTERACTION EVENTS
  // ============================================

  /**
   * Track clip creation
   */
  trackClipCreated(streamId, streamerName) {
    this.trackEvent('clip_created', {
      stream_id: streamId,
      streamer_name: streamerName
    });
  }

  /**
   * Track clip view
   */
  trackClipView(clipId, streamerName) {
    this.trackEvent('clip_view', {
      clip_id: clipId,
      streamer_name: streamerName
    });
  }

  /**
   * Track short view
   */
  trackShortView(shortId, streamerName) {
    this.trackEvent('short_view', {
      short_id: shortId,
      streamer_name: streamerName
    });
  }

  /**
   * Track share
   */
  trackShare(contentType, contentId, method) {
    this.trackEvent('share', {
      content_type: contentType,
      content_id: contentId,
      method: method
    });
  }

  /**
   * Track chat message sent
   */
  trackChatMessage(streamId) {
    this.trackEvent('chat_message', {
      stream_id: streamId
    });
  }

  // ============================================
  // MULTIVIEW & FEATURES
  // ============================================

  /**
   * Track multiview usage
   */
  trackMultiviewStart(streamCount) {
    this.trackEvent('multiview_start', {
      stream_count: streamCount
    });
  }

  /**
   * Track watch party
   */
  trackWatchParty(streamId, participantCount) {
    this.trackEvent('watch_party_start', {
      stream_id: streamId,
      participant_count: participantCount
    });
  }

  /**
   * Track AI highlight generation
   */
  trackAIHighlight(streamId, highlightType) {
    this.trackEvent('ai_highlight_generated', {
      stream_id: streamId,
      highlight_type: highlightType
    });
  }

  /**
   * Track prediction participation
   */
  trackPrediction(streamId, predictionId, pointsWagered) {
    this.trackEvent('prediction_placed', {
      stream_id: streamId,
      prediction_id: predictionId,
      points_wagered: pointsWagered
    });
  }

  // ============================================
  // SEARCH & DISCOVERY
  // ============================================

  /**
   * Track search
   */
  trackSearch(query, resultCount) {
    this.trackEvent('search', {
      search_term: query,
      result_count: resultCount
    });
  }

  /**
   * Track category browse
   */
  trackCategoryBrowse(categoryName) {
    this.trackEvent('category_browse', {
      category: categoryName
    });
  }

  // ============================================
  // SETTINGS & PREFERENCES
  // ============================================

  /**
   * Track theme change
   */
  trackThemeChange(theme) {
    this.trackEvent('theme_change', {
      theme: theme
    });
  }

  /**
   * Track email preferences update
   */
  trackEmailPreferences(preferences) {
    this.trackEvent('email_preferences_updated', preferences);
  }

  /**
   * Track report submission
   */
  trackReport(contentType, reason) {
    this.trackEvent('report_submitted', {
      content_type: contentType,
      reason: reason
    });
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /**
   * Get engagement level based on watch time
   */
  getEngagementLevel(seconds) {
    if (seconds < 60) return 'low';
    if (seconds < 300) return 'medium';
    if (seconds < 1800) return 'high';
    return 'very_high';
  }

  /**
   * Set user ID (for authenticated users)
   */
  setUserId(userId) {
    if (!this.initialized) return;
    
    window.gtag('config', this.gaId, {
      user_id: userId
    });
    
    this.log('User ID set', userId);
  }

  /**
   * Set user properties
   */
  setUserProperties(properties) {
    if (!this.initialized) return;
    
    window.gtag('set', 'user_properties', properties);
    this.log('User properties set', properties);
  }

  /**
   * Debug logging
   */
  log(message, ...args) {
    if (this.debugMode) {
      console.log(`[Analytics] ${message}`, ...args);
    }
  }
}

// Create global instance
window.AnalyticsService = new AnalyticsService();

// Auto-initialize if GA ID is in meta tag
document.addEventListener('DOMContentLoaded', () => {
  const gaMeta = document.querySelector('meta[name="ga-measurement-id"]');
  if (gaMeta && gaMeta.content) {
    window.AnalyticsService.init(gaMeta.content, {
      debug: window.location.hostname === 'localhost'
    });
  }
});
