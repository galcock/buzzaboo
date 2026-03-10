/* ============================================
   BUZZABOO - AI Bot Service
   "Human or AI?" game mode.
   Loads bot profiles from Firestore `bots` collection.
   If no bots exist, game mode auto-disables gracefully.
   Each bot has: name, videoUrl, personality with
   conversation patterns and response generation.
   ============================================ */

class AIBotService {
  constructor() {
    this.bots = [];
    this.botsLoaded = false;
    this.available = false;
    this.activeSession = null;
    this.listeners = {};
    this.typingTimeout = null;
    this.conversationHistory = [];
    this.greetingTimer = null;
    this.responseQueue = [];
    this.processingResponse = false;
  }

  async init() {
    try {
      const db = firebase.firestore();
      const snapshot = await db.collection('bots').where('enabled', '==', true).get();

      this.bots = [];
      snapshot.forEach(doc => {
        this.bots.push({ id: doc.id, ...doc.data() });
      });

      this.botsLoaded = true;
      this.available = this.bots.length > 0;

      if (this.available) {
        console.log(`✓ AI bot service loaded (${this.bots.length} bots available)`);
      } else {
        console.log('✓ AI bot service loaded (no bots configured — game mode disabled)');
      }
    } catch (err) {
      console.error('AI bot service init error:', err);
      this.botsLoaded = true;
      this.available = false;
    }
  }

  isAvailable() {
    return this.available;
  }

  shouldMatchWithBot(gameModeEnabled) {
    if (!this.available) return false;
    if (!gameModeEnabled) return false;
    // 20% chance of bot match when game mode is on
    return Math.random() < 0.20;
  }

  shouldFallbackToBot() {
    // Used when no humans are available in the queue
    return this.available;
  }

  selectBot() {
    if (this.bots.length === 0) return null;
    return this.bots[Math.floor(Math.random() * this.bots.length)];
  }

  async startBotSession(remoteVideoElement, onChatMessage) {
    const bot = this.selectBot();
    if (!bot) return null;

    this.conversationHistory = [];
    this.responseQueue = [];
    this.processingResponse = false;

    this.activeSession = {
      bot,
      remoteVideo: remoteVideoElement,
      onChatMessage,
      startTime: Date.now(),
      messageCount: 0,
      isBot: true
    };

    // Load and play bot video
    if (bot.videoUrl) {
      try {
        remoteVideoElement.src = bot.videoUrl;
        remoteVideoElement.loop = true;
        remoteVideoElement.muted = true; // Bots don't have real audio
        remoteVideoElement.playsInline = true;
        await remoteVideoElement.play();
      } catch (err) {
        console.error('Bot video playback failed:', err);
        // Continue without video — text chat still works
      }
    }

    // Bot sends greeting after a natural delay (1-3 seconds)
    const greetDelay = 1000 + Math.random() * 2000;
    this.greetingTimer = setTimeout(() => {
      this.sendBotMessage(this.generateGreeting(bot));
    }, greetDelay);

    this.emit('sessionStarted', { botId: bot.id, botName: bot.name });
    return this.activeSession;
  }

  handleUserMessage(text) {
    if (!this.activeSession) return;

    this.conversationHistory.push({ role: 'user', text, timestamp: Date.now() });
    this.activeSession.messageCount++;

    // Generate response with natural delay
    const response = this.generateResponse(text, this.activeSession.bot);
    this.queueBotResponse(response);
  }

  queueBotResponse(text) {
    this.responseQueue.push(text);
    if (!this.processingResponse) {
      this.processNextResponse();
    }
  }

  processNextResponse() {
    if (this.responseQueue.length === 0 || !this.activeSession) {
      this.processingResponse = false;
      return;
    }

    this.processingResponse = true;
    const text = this.responseQueue.shift();

    // Typing delay: 30-80ms per character + think time
    const thinkTime = 500 + Math.random() * 1500;
    const typingTime = text.length * (30 + Math.random() * 50);
    const totalDelay = thinkTime + Math.min(typingTime, 4000);

    // Show typing indicator
    this.emit('botTyping', true);

    this.typingTimeout = setTimeout(() => {
      this.emit('botTyping', false);
      this.sendBotMessage(text);
      // Process next queued response after a pause
      setTimeout(() => this.processNextResponse(), 300 + Math.random() * 700);
    }, totalDelay);
  }

  sendBotMessage(text) {
    if (!this.activeSession) return;

    this.conversationHistory.push({ role: 'bot', text, timestamp: Date.now() });

    if (this.activeSession.onChatMessage) {
      this.activeSession.onChatMessage(text);
    }

    this.emit('botMessage', { text });
  }

  // ── Response Generation ────────────────────────────────

  generateGreeting(bot) {
    const personality = bot.personality || {};
    const greetings = personality.greetings || [
      'Hey! How are you?',
      'Hi there! Where are you from?',
      'Hello! Nice to meet you 😊',
      'Hey hey! What\'s up?',
      'Hi! Having a good day?'
    ];
    return greetings[Math.floor(Math.random() * greetings.length)];
  }

  generateResponse(userText, bot) {
    const personality = bot.personality || {};
    const text = userText.toLowerCase().trim();
    const history = this.conversationHistory;

    // Check keyword-matched responses first
    if (personality.responses) {
      for (const [pattern, responses] of Object.entries(personality.responses)) {
        const keywords = pattern.split('|');
        if (keywords.some(kw => text.includes(kw.trim()))) {
          const pool = Array.isArray(responses) ? responses : [responses];
          return this.applyQuirks(pool[Math.floor(Math.random() * pool.length)], personality);
        }
      }
    }

    // Contextual responses based on conversation stage
    const msgCount = history.filter(m => m.role === 'user').length;

    // Location questions
    if (text.match(/where.*from|country|city|location|live/)) {
      const locations = personality.locations || [
        'I\'m from California!', 'I\'m in London, UK', 'Toronto, Canada!',
        'Somewhere in Europe 😄', 'I\'m in New York', 'Australia!'
      ];
      return this.applyQuirks(locations[Math.floor(Math.random() * locations.length)], personality);
    }

    // Age questions
    if (text.match(/how old|age|years old/)) {
      const ages = personality.ages || [
        'I\'m 22!', '19, you?', 'Just turned 24', '21!', 'I\'m 20'
      ];
      return this.applyQuirks(ages[Math.floor(Math.random() * ages.length)], personality);
    }

    // Name questions
    if (text.match(/name|who are you|what.*call/)) {
      if (bot.name) {
        const responses = [
          `I'm ${bot.name}!`, `${bot.name} 😊`, `You can call me ${bot.name}`,
          `It's ${bot.name}, nice to meet you!`
        ];
        return this.applyQuirks(responses[Math.floor(Math.random() * responses.length)], personality);
      }
    }

    // Hobby/interest questions
    if (text.match(/hobby|hobbies|like to do|interests|free time/)) {
      const hobbies = personality.hobbies || [
        'I love music and hiking! What about you?',
        'Gaming and cooking mostly 🎮',
        'I\'m really into photography lately',
        'Reading and going to the gym. Wbu?',
        'I watch way too many movies lol'
      ];
      return this.applyQuirks(hobbies[Math.floor(Math.random() * hobbies.length)], personality);
    }

    // Compliments and positive
    if (text.match(/cute|pretty|beautiful|handsome|nice|cool|awesome/)) {
      const responses = [
        'Aw thank you! 😊', 'That\'s so sweet!', 'You\'re too kind haha',
        'Thanks! You seem really cool too', 'Haha thanks! 😄'
      ];
      return this.applyQuirks(responses[Math.floor(Math.random() * responses.length)], personality);
    }

    // Greetings
    if (text.match(/^(hi|hey|hello|sup|yo|what'?s up|howdy)/)) {
      const responses = [
        'Hey! How\'s it going?', 'Hi! Where are you from?',
        'Hello! Nice to meet you 😊', 'Hey! Having a good day?',
        'Hi there! What are you up to?'
      ];
      return this.applyQuirks(responses[Math.floor(Math.random() * responses.length)], personality);
    }

    // Questions back to user
    if (text.match(/\?$/)) {
      // They asked a question — try to give a simple answer then redirect
      const deflections = [
        'Hmm good question! What do you think?',
        'I\'d say yes! What about you though?',
        'That\'s a tough one... I\'m not sure honestly. Wbu?',
        'Probably! What makes you ask?'
      ];
      return this.applyQuirks(deflections[Math.floor(Math.random() * deflections.length)], personality);
    }

    // Short/agreement responses
    if (text.length < 10) {
      const short = [
        'Haha nice', 'That\'s cool!', 'Oh really?', 'Interesting!',
        'Same honestly', 'I feel that', 'For real 😄'
      ];
      return this.applyQuirks(short[Math.floor(Math.random() * short.length)], personality);
    }

    // Conversation continuers and follow-up questions
    const followUps = personality.followUps || [
      'That\'s really interesting! Tell me more',
      'Oh cool! So what else do you like?',
      'Haha I can relate to that. What do you do for fun?',
      'Nice! Have you always been into that?',
      'That\'s awesome! I wish I could try that',
      'Oh wow, that sounds fun! How long have you been doing that?',
      'I totally get that! What got you into it?',
      'That\'s so cool. I\'ve always wanted to try something like that'
    ];

    return this.applyQuirks(followUps[Math.floor(Math.random() * followUps.length)], personality);
  }

  applyQuirks(text, personality) {
    if (!personality || !personality.quirks) return text;

    let result = text;
    const quirks = personality.quirks;

    // Emoji frequency
    if (quirks.emojiFrequency === 'high' && Math.random() < 0.4) {
      const emojis = ['😊', '😄', '😂', '🔥', '✨', '💯', '🙌', '😁'];
      result += ' ' + emojis[Math.floor(Math.random() * emojis.length)];
    }

    // Typing style
    if (quirks.allLowercase) {
      result = result.toLowerCase();
    }

    // Filler words
    if (quirks.fillerWords && Math.random() < 0.2) {
      const fillers = ['like, ', 'honestly, ', 'ngl, ', 'lowkey, ', 'tbh, '];
      result = fillers[Math.floor(Math.random() * fillers.length)] + result.charAt(0).toLowerCase() + result.slice(1);
    }

    return result;
  }

  // ── Session Management ─────────────────────────────────

  isSessionActive() {
    return this.activeSession !== null;
  }

  getSessionInfo() {
    if (!this.activeSession) return null;
    return {
      isBot: this.activeSession.isBot,
      botName: this.activeSession.bot.name,
      duration: Date.now() - this.activeSession.startTime,
      messageCount: this.activeSession.messageCount
    };
  }

  endBotSession() {
    if (this.typingTimeout) {
      clearTimeout(this.typingTimeout);
      this.typingTimeout = null;
    }
    if (this.greetingTimer) {
      clearTimeout(this.greetingTimer);
      this.greetingTimer = null;
    }

    if (this.activeSession && this.activeSession.remoteVideo) {
      this.activeSession.remoteVideo.pause();
      this.activeSession.remoteVideo.removeAttribute('src');
      this.activeSession.remoteVideo.load();
    }

    const session = this.activeSession;
    this.activeSession = null;
    this.conversationHistory = [];
    this.responseQueue = [];
    this.processingResponse = false;

    this.emit('botTyping', false);
    this.emit('sessionEnded', session ? { botName: session.bot.name } : null);

    return session;
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
    this.endBotSession();
    this.bots = [];
    this.listeners = {};
  }
}

// Export
window.AIBotService = AIBotService;
console.log('✓ AI bot service loaded');
