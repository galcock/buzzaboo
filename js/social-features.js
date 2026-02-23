/* ============================================
   BUZZABOO - Social Features
   Follow, Share, Whispers, Clips, etc.
   ============================================ */

// ============================================
// FOLLOW BUTTON COMPONENT
// ============================================

class FollowButton {
  constructor(targetUserId, options = {}) {
    this.targetUserId = targetUserId;
    this.options = {
      size: options.size || 'md', // sm, md, lg
      style: options.style || 'primary', // primary, secondary, ghost
      showCount: options.showCount !== false,
      ...options
    };
    this.isFollowing = false;
    this.followerCount = 0;
    this.element = null;
  }

  async render(container) {
    const user = firebase.auth().currentUser;
    
    if (user) {
      this.isFollowing = await window.databaseService.isFollowing(user.uid, this.targetUserId);
      const targetUser = await window.databaseService.getUser(this.targetUserId);
      this.followerCount = targetUser?.followers || 0;
    }

    const sizeClass = `btn-${this.options.size}`;
    const styleClass = this.isFollowing ? 'btn-secondary' : 'btn-primary';
    
    this.element = document.createElement('button');
    this.element.className = `btn ${styleClass} ${sizeClass} follow-button`;
    this.element.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
        ${this.isFollowing 
          ? '<path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/>'
          : '<path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>'
        }
      </svg>
      <span>${this.isFollowing ? 'Following' : 'Follow'}</span>
      ${this.options.showCount ? `<span class="follower-count">${this.formatNumber(this.followerCount)}</span>` : ''}
    `;

    this.element.addEventListener('click', () => this.handleClick());

    if (typeof container === 'string') {
      document.getElementById(container)?.appendChild(this.element);
    } else {
      container?.appendChild(this.element);
    }

    return this.element;
  }

  async handleClick() {
    const user = firebase.auth().currentUser;
    
    if (!user) {
      // Show login modal
      window.Toast?.error('Login Required', 'Please log in to follow channels');
      return;
    }

    if (user.uid === this.targetUserId) {
      window.Toast?.error('Error', 'You cannot follow yourself');
      return;
    }

    this.element.disabled = true;

    try {
      if (this.isFollowing) {
        await window.databaseService.unfollowUser(user.uid, this.targetUserId);
        this.isFollowing = false;
        this.followerCount--;
        window.Toast?.success('Unfollowed', 'You are no longer following this channel');
      } else {
        await window.databaseService.followUser(user.uid, this.targetUserId);
        this.isFollowing = true;
        this.followerCount++;
        window.Toast?.success('Following', 'You are now following this channel');
      }

      this.updateUI();
    } catch (error) {
      console.error('Follow error:', error);
      window.Toast?.error('Error', 'Failed to update follow status');
    }

    this.element.disabled = false;
  }

  updateUI() {
    const svg = this.isFollowing
      ? '<path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/>'
      : '<path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>';
    
    this.element.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">${svg}</svg>
      <span>${this.isFollowing ? 'Following' : 'Follow'}</span>
      ${this.options.showCount ? `<span class="follower-count">${this.formatNumber(this.followerCount)}</span>` : ''}
    `;

    this.element.className = `btn ${this.isFollowing ? 'btn-secondary' : 'btn-primary'} btn-${this.options.size} follow-button`;
  }

  formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }
}

// ============================================
// SHARE MENU COMPONENT
// ============================================

class ShareMenu {
  constructor(shareData) {
    this.shareData = shareData;
    this.element = null;
  }

  render(container) {
    this.element = document.createElement('div');
    this.element.className = 'share-menu dropdown';
    
    this.element.innerHTML = `
      <button class="dropdown-trigger btn btn-secondary btn-sm">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
          <path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92 1.61 0 2.92-1.31 2.92-2.92s-1.31-2.92-2.92-2.92z"/>
        </svg>
        Share
      </button>
      <div class="dropdown-menu share-dropdown">
        <div class="share-options">
          <button class="share-option" data-action="copy">
            <div class="share-icon">🔗</div>
            <div class="share-label">Copy Link</div>
          </button>
          <button class="share-option" data-action="twitter">
            <div class="share-icon">𝕏</div>
            <div class="share-label">Twitter</div>
          </button>
          <button class="share-option" data-action="facebook">
            <div class="share-icon">📘</div>
            <div class="share-label">Facebook</div>
          </button>
          <button class="share-option" data-action="reddit">
            <div class="share-icon">🤖</div>
            <div class="share-label">Reddit</div>
          </button>
          <button class="share-option" data-action="discord">
            <div class="share-icon">💬</div>
            <div class="share-label">Discord</div>
          </button>
          <button class="share-option" data-action="email">
            <div class="share-icon">✉️</div>
            <div class="share-label">Email</div>
          </button>
        </div>
      </div>
    `;

    this.bindEvents();

    if (typeof container === 'string') {
      document.getElementById(container)?.appendChild(this.element);
    } else {
      container?.appendChild(this.element);
    }

    return this.element;
  }

  bindEvents() {
    this.element.querySelectorAll('.share-option').forEach(option => {
      option.addEventListener('click', () => {
        const action = option.dataset.action;
        this.handleShare(action);
        
        // Close dropdown
        this.element.querySelector('.dropdown-menu').classList.remove('active');
      });
    });
  }

  async handleShare(platform) {
    const { url, title, text } = this.shareData;

    switch (platform) {
      case 'copy':
        await this.copyToClipboard(url);
        window.Toast?.success('Link Copied', 'Share link copied to clipboard');
        break;
      
      case 'twitter':
        const twitterUrl = `https://twitter.com/intent/tweet?text=${encodeURIComponent(text || title)}&url=${encodeURIComponent(url)}`;
        window.open(twitterUrl, '_blank', 'width=550,height=420');
        break;
      
      case 'facebook':
        const fbUrl = `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(url)}`;
        window.open(fbUrl, '_blank', 'width=550,height=420');
        break;
      
      case 'reddit':
        const redditUrl = `https://reddit.com/submit?url=${encodeURIComponent(url)}&title=${encodeURIComponent(title)}`;
        window.open(redditUrl, '_blank', 'width=550,height=600');
        break;
      
      case 'discord':
        await this.copyToClipboard(url);
        window.Toast?.success('Link Copied', 'Paste this link in Discord');
        break;
      
      case 'email':
        const emailUrl = `mailto:?subject=${encodeURIComponent(title)}&body=${encodeURIComponent(text + '\n\n' + url)}`;
        window.location.href = emailUrl;
        break;
    }
  }

  async copyToClipboard(text) {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text);
    } else {
      // Fallback for older browsers
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }
  }
}

// ============================================
// WHISPER / DM SYSTEM
// ============================================

class WhisperBox {
  constructor(recipientId, recipientName) {
    this.recipientId = recipientId;
    this.recipientName = recipientName;
    this.messages = [];
    this.element = null;
  }

  render(container) {
    this.element = document.createElement('div');
    this.element.className = 'whisper-box glass-card';
    
    this.element.innerHTML = `
      <div class="whisper-header">
        <div class="whisper-title">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/>
          </svg>
          Whisper to ${this.recipientName}
        </div>
        <button class="whisper-close btn btn-ghost btn-icon btn-sm">✕</button>
      </div>
      <div class="whisper-messages"></div>
      <div class="whisper-input">
        <input type="text" placeholder="Type a message..." class="form-input">
        <button class="btn btn-primary btn-sm">Send</button>
      </div>
    `;

    this.bindEvents();
    this.loadMessages();

    if (typeof container === 'string') {
      document.getElementById(container)?.appendChild(this.element);
    } else {
      container?.appendChild(this.element);
    }

    return this.element;
  }

  bindEvents() {
    const closeBtn = this.element.querySelector('.whisper-close');
    closeBtn?.addEventListener('click', () => this.close());

    const input = this.element.querySelector('.whisper-input input');
    const sendBtn = this.element.querySelector('.whisper-input button');

    const sendMessage = () => {
      const message = input.value.trim();
      if (message) {
        this.sendMessage(message);
        input.value = '';
      }
    };

    sendBtn?.addEventListener('click', sendMessage);
    input?.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        sendMessage();
      }
    });
  }

  async loadMessages() {
    // In production, load from database
    this.renderMessages();
  }

  async sendMessage(text) {
    const user = firebase.auth().currentUser;
    if (!user) return;

    const message = {
      from: user.uid,
      to: this.recipientId,
      text,
      timestamp: new Date()
    };

    this.messages.push(message);
    this.renderMessages();

    // Save to database
    await firebase.firestore().collection('whispers').add({
      ...message,
      timestamp: firebase.firestore.FieldValue.serverTimestamp()
    });

    // Send notification
    await window.databaseService.createNotification(this.recipientId, {
      type: 'whisper',
      fromUserId: user.uid,
      message: `sent you a message: "${text}"`,
      link: '#whispers'
    });
  }

  renderMessages() {
    const container = this.element.querySelector('.whisper-messages');
    const user = firebase.auth().currentUser;

    container.innerHTML = this.messages.map(msg => {
      const isOwn = msg.from === user?.uid;
      return `
        <div class="whisper-message ${isOwn ? 'own' : 'other'}">
          <div class="whisper-message-text">${this.escapeHtml(msg.text)}</div>
          <div class="whisper-message-time">${this.formatTime(msg.timestamp)}</div>
        </div>
      `;
    }).join('');

    container.scrollTop = container.scrollHeight;
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  formatTime(date) {
    const now = new Date();
    const diff = now - date;
    
    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  close() {
    this.element.remove();
  }
}

// ============================================
// CLIP CREATOR
// ============================================

class ClipCreator {
  constructor(streamId, options = {}) {
    this.streamId = streamId;
    this.options = {
      duration: options.duration || 30, // seconds
      ...options
    };
  }

  async createClip() {
    const user = firebase.auth().currentUser;
    if (!user) {
      window.Toast?.error('Login Required', 'Please log in to create clips');
      return null;
    }

    // Show creating toast
    window.Toast?.success('Creating Clip', 'Your clip is being created...');

    try {
      // In production, this would capture the stream segment
      // For now, generate mock clip data
      const clip = await window.databaseService.createClip(user.uid, {
        streamId: this.streamId,
        title: this.generateClipTitle(),
        thumbnail: `https://picsum.photos/seed/clip${Date.now()}/400/225`,
        videoUrl: `#clip-${Date.now()}`,
        duration: this.options.duration,
        category: 'Gaming',
        tags: ['epic', 'highlight']
      });

      window.Toast?.success('Clip Created!', 'Your clip has been saved to your profile');
      
      return clip;
    } catch (error) {
      console.error('Clip creation error:', error);
      window.Toast?.error('Error', 'Failed to create clip');
      return null;
    }
  }

  generateClipTitle() {
    const adjectives = ['Epic', 'Insane', 'Amazing', 'Incredible', 'Clutch'];
    const nouns = ['Play', 'Moment', 'Highlight', 'Move', 'Action'];
    
    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    
    return `${adj} ${noun}`;
  }

  static renderClipButton(container, streamId) {
    const button = document.createElement('button');
    button.className = 'btn btn-secondary btn-sm clip-button';
    button.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
        <path d="M18 3v2h-2V3H8v2H6V3H4v18h2v-2h2v2h8v-2h2v2h2V3h-2zM8 17H6v-2h2v2zm0-4H6v-2h2v2zm0-4H6V7h2v2zm10 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V7h2v2z"/>
      </svg>
      Clip
    `;

    button.addEventListener('click', async () => {
      const creator = new ClipCreator(streamId);
      await creator.createClip();
    });

    if (typeof container === 'string') {
      document.getElementById(container)?.appendChild(button);
    } else {
      container?.appendChild(button);
    }

    return button;
  }
}

// ============================================
// RECOMMENDED CHANNELS WIDGET
// ============================================

class RecommendedChannels {
  constructor(options = {}) {
    this.options = {
      limit: options.limit || 5,
      ...options
    };
    this.channels = [];
  }

  async load() {
    const user = firebase.auth().currentUser;
    if (!user) return;

    this.channels = await window.databaseService.getRecommendedChannels(
      user.uid,
      this.options.limit
    );
  }

  async render(container) {
    await this.load();

    const element = document.createElement('div');
    element.className = 'recommended-channels glass-card';
    
    element.innerHTML = `
      <h3 class="section-title">Recommended Channels</h3>
      <div class="recommended-list">
        ${this.channels.map(channel => `
          <div class="recommended-item">
            <img src="${channel.avatar}" alt="${channel.displayName}" class="recommended-avatar">
            <div class="recommended-info">
              <div class="recommended-name">${channel.displayName}</div>
              <div class="recommended-followers">${this.formatNumber(channel.followers)} followers</div>
            </div>
            <button class="btn btn-primary btn-sm" data-user-id="${channel.id}">Follow</button>
          </div>
        `).join('')}
      </div>
    `;

    // Bind follow buttons
    element.querySelectorAll('button[data-user-id]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const userId = btn.dataset.userId;
        const currentUser = firebase.auth().currentUser;
        if (currentUser) {
          await window.databaseService.followUser(currentUser.uid, userId);
          btn.textContent = 'Following';
          btn.classList.remove('btn-primary');
          btn.classList.add('btn-secondary');
        }
      });
    });

    if (typeof container === 'string') {
      document.getElementById(container)?.appendChild(element);
    } else {
      container?.appendChild(element);
    }

    return element;
  }

  formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }
}

// ============================================
// EXPORTS
// ============================================

window.FollowButton = FollowButton;
window.ShareMenu = ShareMenu;
window.WhisperBox = WhisperBox;
window.ClipCreator = ClipCreator;
window.RecommendedChannels = RecommendedChannels;
