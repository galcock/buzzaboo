/**
 * Buzzaboo LiveKit Service
 * Handles all WebRTC video streaming via LiveKit
 */

// LiveKit Configuration
const LIVEKIT_CONFIG = {
  serverUrl: 'wss://livekit.buzzaboo.com:443',
  apiKey: 'APILujeXtU8Y5ae',
  apiSecret: 'jXU2ffVOPJWIzkn8gHEihe9vQPoV6zFefsjHd0x6gAdA'
};

// JWT Token Generation (client-side for development)
// In production, this should be done server-side
class TokenGenerator {
  static base64UrlEncode(str) {
    return btoa(str)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  }

  static async generateToken(identity, roomName, options = {}) {
    const header = {
      alg: 'HS256',
      typ: 'JWT'
    };

    const now = Math.floor(Date.now() / 1000);
    const exp = now + (options.ttl || 86400); // 24 hours default

    const payload = {
      iss: LIVEKIT_CONFIG.apiKey,
      sub: identity,
      iat: now,
      exp: exp,
      nbf: now,
      video: {
        room: roomName,
        roomJoin: true,
        canPublish: options.canPublish !== false,
        canSubscribe: options.canSubscribe !== false,
        canPublishData: options.canPublishData !== false,
        canPublishSources: options.canPublishSources || ['camera', 'microphone', 'screen_share', 'screen_share_audio'],
        canUpdateOwnMetadata: true
      },
      metadata: JSON.stringify(options.metadata || {}),
      name: options.name || identity
    };

    const headerB64 = this.base64UrlEncode(JSON.stringify(header));
    const payloadB64 = this.base64UrlEncode(JSON.stringify(payload));
    const data = `${headerB64}.${payloadB64}`;

    // Sign with HMAC-SHA256
    const encoder = new TextEncoder();
    const keyData = encoder.encode(LIVEKIT_CONFIG.apiSecret);
    const key = await crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    
    const signature = await crypto.subtle.sign(
      'HMAC',
      key,
      encoder.encode(data)
    );
    
    const signatureB64 = this.base64UrlEncode(
      String.fromCharCode(...new Uint8Array(signature))
    );

    return `${data}.${signatureB64}`;
  }
}

// Quality Presets
const QUALITY_PRESETS = {
  '1080p': {
    width: 1920,
    height: 1080,
    frameRate: 30,
    maxBitrate: 3_000_000
  },
  '720p': {
    width: 1280,
    height: 720,
    frameRate: 30,
    maxBitrate: 1_500_000
  },
  '480p': {
    width: 854,
    height: 480,
    frameRate: 30,
    maxBitrate: 800_000
  },
  '360p': {
    width: 640,
    height: 360,
    frameRate: 30,
    maxBitrate: 400_000
  }
};

/**
 * Main LiveKit Service Class
 */
class LiveKitService {
  constructor() {
    this.room = null;
    this.localParticipant = null;
    this.remoteParticipants = new Map();
    this.localVideoTrack = null;
    this.localAudioTrack = null;
    this.screenShareTrack = null;
    this.dataChannel = null;
    
    this.eventHandlers = new Map();
    this.isConnected = false;
    this.currentQuality = '720p';
    
    // Chat message history
    this.chatMessages = [];
    this.maxChatHistory = 500;
  }

  /**
   * Initialize the LiveKit SDK
   */
  async init() {
    if (typeof LivekitClient === 'undefined') {
      console.error('LiveKit SDK not loaded');
      return false;
    }
    console.log('LiveKit Service initialized');
    return true;
  }

  /**
   * Connect to a LiveKit room
   */
  async connect(roomName, identity, options = {}) {
    try {
      const token = await TokenGenerator.generateToken(identity, roomName, {
        canPublish: options.canPublish !== false,
        canSubscribe: true,
        canPublishData: true,
        name: options.displayName || identity,
        metadata: options.metadata
      });

      this.room = new LivekitClient.Room({
        adaptiveStream: true,
        dynacast: true,
        videoCaptureDefaults: {
          resolution: LivekitClient.VideoPresets.h720.resolution
        },
        publishDefaults: {
          simulcast: true,
          videoSimulcastLayers: [
            LivekitClient.VideoPresets.h180,
            LivekitClient.VideoPresets.h360,
            LivekitClient.VideoPresets.h720
          ]
        }
      });

      this.setupRoomEventListeners();

      await this.room.connect(LIVEKIT_CONFIG.serverUrl, token);
      
      this.localParticipant = this.room.localParticipant;
      this.isConnected = true;
      
      console.log(`Connected to room: ${roomName} as ${identity}`);
      this.emit('connected', { roomName, identity });
      
      return true;
    } catch (error) {
      console.error('Failed to connect to room:', error);
      this.emit('error', { type: 'connection', error });
      return false;
    }
  }

  /**
   * Disconnect from the current room
   */
  async disconnect() {
    if (this.room) {
      await this.stopAllTracks();
      await this.room.disconnect();
      this.room = null;
      this.localParticipant = null;
      this.remoteParticipants.clear();
      this.isConnected = false;
      this.emit('disconnected');
    }
  }

  /**
   * Setup room event listeners
   */
  setupRoomEventListeners() {
    if (!this.room) return;

    // Participant events
    this.room.on(LivekitClient.RoomEvent.ParticipantConnected, (participant) => {
      this.handleParticipantConnected(participant);
    });

    this.room.on(LivekitClient.RoomEvent.ParticipantDisconnected, (participant) => {
      this.handleParticipantDisconnected(participant);
    });

    // Track events
    this.room.on(LivekitClient.RoomEvent.TrackSubscribed, (track, publication, participant) => {
      this.handleTrackSubscribed(track, publication, participant);
    });

    this.room.on(LivekitClient.RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
      this.handleTrackUnsubscribed(track, publication, participant);
    });

    this.room.on(LivekitClient.RoomEvent.TrackMuted, (publication, participant) => {
      this.emit('trackMuted', { publication, participant });
    });

    this.room.on(LivekitClient.RoomEvent.TrackUnmuted, (publication, participant) => {
      this.emit('trackUnmuted', { publication, participant });
    });

    // Data channel events
    this.room.on(LivekitClient.RoomEvent.DataReceived, (payload, participant) => {
      this.handleDataReceived(payload, participant);
    });

    // Connection quality
    this.room.on(LivekitClient.RoomEvent.ConnectionQualityChanged, (quality, participant) => {
      this.emit('qualityChanged', { quality, participant });
    });

    // Room state changes
    this.room.on(LivekitClient.RoomEvent.Disconnected, (reason) => {
      this.isConnected = false;
      this.emit('disconnected', { reason });
    });

    this.room.on(LivekitClient.RoomEvent.Reconnecting, () => {
      this.emit('reconnecting');
    });

    this.room.on(LivekitClient.RoomEvent.Reconnected, () => {
      this.emit('reconnected');
    });

    // Active speakers
    this.room.on(LivekitClient.RoomEvent.ActiveSpeakersChanged, (speakers) => {
      this.emit('activeSpeakersChanged', { speakers });
    });
  }

  /**
   * Handle participant connected
   */
  handleParticipantConnected(participant) {
    console.log(`Participant connected: ${participant.identity}`);
    this.remoteParticipants.set(participant.sid, participant);
    
    // Subscribe to existing tracks
    participant.trackPublications.forEach((publication) => {
      if (publication.isSubscribed && publication.track) {
        this.emit('trackSubscribed', { 
          track: publication.track, 
          publication, 
          participant 
        });
      }
    });
    
    this.emit('participantConnected', { participant });
  }

  /**
   * Handle participant disconnected
   */
  handleParticipantDisconnected(participant) {
    console.log(`Participant disconnected: ${participant.identity}`);
    this.remoteParticipants.delete(participant.sid);
    this.emit('participantDisconnected', { participant });
  }

  /**
   * Handle track subscribed
   */
  handleTrackSubscribed(track, publication, participant) {
    console.log(`Track subscribed: ${track.kind} from ${participant.identity}`);
    this.emit('trackSubscribed', { track, publication, participant });
  }

  /**
   * Handle track unsubscribed
   */
  handleTrackUnsubscribed(track, publication, participant) {
    console.log(`Track unsubscribed: ${track.kind} from ${participant.identity}`);
    this.emit('trackUnsubscribed', { track, publication, participant });
  }

  /**
   * Handle data received (chat messages, etc.)
   */
  handleDataReceived(payload, participant) {
    try {
      const decoder = new TextDecoder();
      const data = JSON.parse(decoder.decode(payload));
      
      if (data.type === 'chat') {
        const message = {
          id: data.id || Date.now(),
          senderId: participant?.sid || 'system',
          senderName: participant?.identity || data.senderName || 'System',
          text: data.text,
          timestamp: data.timestamp || Date.now(),
          badges: data.badges || []
        };
        
        this.chatMessages.push(message);
        if (this.chatMessages.length > this.maxChatHistory) {
          this.chatMessages.shift();
        }
        
        this.emit('chatMessage', message);
      } else {
        this.emit('dataReceived', { data, participant });
      }
    } catch (error) {
      console.error('Error parsing received data:', error);
    }
  }

  // ============================================
  // MEDIA CONTROLS
  // ============================================

  /**
   * Start publishing camera video
   */
  async enableCamera(options = {}) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }

    try {
      const preset = QUALITY_PRESETS[options.quality || this.currentQuality];
      
      await this.localParticipant.setCameraEnabled(true, {
        resolution: {
          width: preset.width,
          height: preset.height,
          frameRate: preset.frameRate
        }
      });
      
      this.localVideoTrack = this.localParticipant.getTrackPublication(
        LivekitClient.Track.Source.Camera
      )?.track;
      
      this.emit('cameraEnabled', { track: this.localVideoTrack });
      return this.localVideoTrack;
    } catch (error) {
      console.error('Failed to enable camera:', error);
      this.emit('error', { type: 'camera', error });
      throw error;
    }
  }

  /**
   * Stop publishing camera video
   */
  async disableCamera() {
    if (this.localParticipant) {
      await this.localParticipant.setCameraEnabled(false);
      this.localVideoTrack = null;
      this.emit('cameraDisabled');
    }
  }

  /**
   * Toggle camera on/off
   */
  async toggleCamera() {
    if (this.localVideoTrack) {
      await this.disableCamera();
      return false;
    } else {
      await this.enableCamera();
      return true;
    }
  }

  /**
   * Start publishing microphone audio
   */
  async enableMicrophone() {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }

    try {
      await this.localParticipant.setMicrophoneEnabled(true);
      
      this.localAudioTrack = this.localParticipant.getTrackPublication(
        LivekitClient.Track.Source.Microphone
      )?.track;
      
      this.emit('microphoneEnabled', { track: this.localAudioTrack });
      return this.localAudioTrack;
    } catch (error) {
      console.error('Failed to enable microphone:', error);
      this.emit('error', { type: 'microphone', error });
      throw error;
    }
  }

  /**
   * Stop publishing microphone audio
   */
  async disableMicrophone() {
    if (this.localParticipant) {
      await this.localParticipant.setMicrophoneEnabled(false);
      this.localAudioTrack = null;
      this.emit('microphoneDisabled');
    }
  }

  /**
   * Toggle microphone on/off
   */
  async toggleMicrophone() {
    if (this.localAudioTrack) {
      await this.disableMicrophone();
      return false;
    } else {
      await this.enableMicrophone();
      return true;
    }
  }

  /**
   * Start screen sharing
   */
  async enableScreenShare(options = {}) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }

    try {
      await this.localParticipant.setScreenShareEnabled(true, {
        audio: options.audio !== false,
        contentHint: options.contentHint || 'detail',
        resolution: options.resolution || LivekitClient.VideoPresets.h1080.resolution
      });
      
      this.screenShareTrack = this.localParticipant.getTrackPublication(
        LivekitClient.Track.Source.ScreenShare
      )?.track;
      
      this.emit('screenShareEnabled', { track: this.screenShareTrack });
      return this.screenShareTrack;
    } catch (error) {
      console.error('Failed to enable screen share:', error);
      this.emit('error', { type: 'screenShare', error });
      throw error;
    }
  }

  /**
   * Stop screen sharing
   */
  async disableScreenShare() {
    if (this.localParticipant) {
      await this.localParticipant.setScreenShareEnabled(false);
      this.screenShareTrack = null;
      this.emit('screenShareDisabled');
    }
  }

  /**
   * Toggle screen share on/off
   */
  async toggleScreenShare() {
    if (this.screenShareTrack) {
      await this.disableScreenShare();
      return false;
    } else {
      await this.enableScreenShare();
      return true;
    }
  }

  /**
   * Stop all local tracks
   */
  async stopAllTracks() {
    await this.disableCamera();
    await this.disableMicrophone();
    await this.disableScreenShare();
  }

  /**
   * Set video quality
   */
  async setQuality(quality) {
    if (!QUALITY_PRESETS[quality]) {
      throw new Error(`Invalid quality preset: ${quality}`);
    }
    
    this.currentQuality = quality;
    
    // If camera is active, restart with new quality
    if (this.localVideoTrack) {
      await this.disableCamera();
      await this.enableCamera({ quality });
    }
    
    this.emit('qualityChanged', { quality });
  }

  /**
   * Switch camera device
   */
  async switchCamera(deviceId) {
    if (this.localParticipant && this.localVideoTrack) {
      const publication = this.localParticipant.getTrackPublication(
        LivekitClient.Track.Source.Camera
      );
      if (publication?.track) {
        await publication.track.restartTrack({
          deviceId
        });
      }
    }
  }

  /**
   * Switch microphone device
   */
  async switchMicrophone(deviceId) {
    if (this.localParticipant && this.localAudioTrack) {
      const publication = this.localParticipant.getTrackPublication(
        LivekitClient.Track.Source.Microphone
      );
      if (publication?.track) {
        await publication.track.restartTrack({
          deviceId
        });
      }
    }
  }

  // ============================================
  // DATA CHANNEL / CHAT
  // ============================================

  /**
   * Send a chat message via data channel
   */
  async sendChatMessage(text, options = {}) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }

    const message = {
      type: 'chat',
      id: Date.now(),
      text: text,
      timestamp: Date.now(),
      badges: options.badges || []
    };

    const encoder = new TextEncoder();
    const data = encoder.encode(JSON.stringify(message));
    
    await this.localParticipant.publishData(data, {
      reliable: true
    });

    // Add to local history
    const localMessage = {
      ...message,
      senderId: this.localParticipant.sid,
      senderName: this.localParticipant.identity,
      isOwn: true
    };
    
    this.chatMessages.push(localMessage);
    if (this.chatMessages.length > this.maxChatHistory) {
      this.chatMessages.shift();
    }
    
    this.emit('chatMessage', localMessage);
    return localMessage;
  }

  /**
   * Send arbitrary data to all participants
   */
  async sendData(data, options = {}) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }

    const encoder = new TextEncoder();
    const payload = encoder.encode(JSON.stringify(data));
    
    await this.localParticipant.publishData(payload, {
      reliable: options.reliable !== false,
      destinationIdentities: options.destinationIdentities
    });
  }

  /**
   * Get chat history
   */
  getChatHistory() {
    return [...this.chatMessages];
  }

  // ============================================
  // VIDEO ELEMENT HELPERS
  // ============================================

  /**
   * Attach a track to a video/audio element
   */
  attachTrack(track, element) {
    if (track && element) {
      track.attach(element);
      return true;
    }
    return false;
  }

  /**
   * Detach a track from all elements
   */
  detachTrack(track) {
    if (track) {
      track.detach();
      return true;
    }
    return false;
  }

  /**
   * Attach local video to element
   */
  attachLocalVideo(element) {
    if (this.localVideoTrack) {
      return this.attachTrack(this.localVideoTrack, element);
    }
    return false;
  }

  /**
   * Get all remote video tracks
   */
  getRemoteVideoTracks() {
    const tracks = [];
    
    this.remoteParticipants.forEach((participant) => {
      participant.trackPublications.forEach((publication) => {
        if (publication.track && publication.track.kind === 'video') {
          tracks.push({
            track: publication.track,
            participant: participant,
            source: publication.source
          });
        }
      });
    });
    
    return tracks;
  }

  /**
   * Get participant by identity
   */
  getParticipant(identity) {
    for (const [sid, participant] of this.remoteParticipants) {
      if (participant.identity === identity) {
        return participant;
      }
    }
    return null;
  }

  // ============================================
  // DEVICE MANAGEMENT
  // ============================================

  /**
   * Get available media devices
   */
  static async getDevices() {
    const devices = await navigator.mediaDevices.enumerateDevices();
    return {
      videoInputs: devices.filter(d => d.kind === 'videoinput'),
      audioInputs: devices.filter(d => d.kind === 'audioinput'),
      audioOutputs: devices.filter(d => d.kind === 'audiooutput')
    };
  }

  /**
   * Check if camera/mic permissions are granted
   */
  static async checkPermissions() {
    const permissions = {
      camera: false,
      microphone: false
    };

    try {
      const cameraPermission = await navigator.permissions.query({ name: 'camera' });
      permissions.camera = cameraPermission.state === 'granted';
    } catch (e) {
      // Some browsers don't support permissions API for camera
    }

    try {
      const micPermission = await navigator.permissions.query({ name: 'microphone' });
      permissions.microphone = micPermission.state === 'granted';
    } catch (e) {
      // Some browsers don't support permissions API for microphone
    }

    return permissions;
  }

  /**
   * Request media permissions
   */
  static async requestPermissions(video = true, audio = true) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ 
        video, 
        audio 
      });
      // Stop all tracks immediately, we just needed permissions
      stream.getTracks().forEach(track => track.stop());
      return true;
    } catch (error) {
      console.error('Failed to get permissions:', error);
      return false;
    }
  }

  // ============================================
  // ROOM INFO
  // ============================================

  /**
   * Get room information
   */
  getRoomInfo() {
    if (!this.room) return null;
    
    return {
      name: this.room.name,
      sid: this.room.sid,
      metadata: this.room.metadata,
      numParticipants: this.remoteParticipants.size + 1,
      isConnected: this.isConnected
    };
  }

  /**
   * Get list of participants
   */
  getParticipants() {
    const participants = [];
    
    if (this.localParticipant) {
      participants.push({
        sid: this.localParticipant.sid,
        identity: this.localParticipant.identity,
        name: this.localParticipant.name,
        isLocal: true,
        isSpeaking: this.localParticipant.isSpeaking,
        connectionQuality: this.localParticipant.connectionQuality
      });
    }
    
    this.remoteParticipants.forEach((participant) => {
      participants.push({
        sid: participant.sid,
        identity: participant.identity,
        name: participant.name,
        isLocal: false,
        isSpeaking: participant.isSpeaking,
        connectionQuality: participant.connectionQuality
      });
    });
    
    return participants;
  }

  // ============================================
  // EVENT SYSTEM
  // ============================================

  /**
   * Subscribe to an event
   */
  on(event, handler) {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, new Set());
    }
    this.eventHandlers.get(event).add(handler);
    return () => this.off(event, handler);
  }

  /**
   * Unsubscribe from an event
   */
  off(event, handler) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.delete(handler);
    }
  }

  /**
   * Emit an event
   */
  emit(event, data) {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => {
        try {
          handler(data);
        } catch (error) {
          console.error(`Error in event handler for ${event}:`, error);
        }
      });
    }
  }
}

// Export singleton instance
const livekitService = new LiveKitService();

// Also export the class and config for flexibility
window.LiveKitService = LiveKitService;
window.livekitService = livekitService;
window.TokenGenerator = TokenGenerator;
window.LIVEKIT_CONFIG = LIVEKIT_CONFIG;
window.QUALITY_PRESETS = QUALITY_PRESETS;
