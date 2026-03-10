/**
 * Buzzaboo LiveKit Service
 * WebRTC video chat via LiveKit — simplified for 1-on-1 random chat
 *
 * SECURITY NOTE: Token generation is done client-side for development.
 * In production, move TokenGenerator to a server-side endpoint to protect the API secret.
 */

const LIVEKIT_CONFIG = {
  serverUrl: 'wss://livekit.buzzaboo.com:443',
  apiKey: 'APILujeXtU8Y5ae',
  apiSecret: 'jXU2ffVOPJWIzkn8gHEihe9vQPoV6zFefsjHd0x6gAdA'
};

class TokenGenerator {
  static base64UrlEncode(str) {
    return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  static async generateToken(identity, roomName, options = {}) {
    const header = { alg: 'HS256', typ: 'JWT' };
    const now = Math.floor(Date.now() / 1000);
    const exp = now + (options.ttl || 86400);

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
        canPublishSources: ['camera', 'microphone'],
        canUpdateOwnMetadata: true
      },
      metadata: JSON.stringify(options.metadata || {}),
      name: options.name || identity
    };

    const headerB64 = this.base64UrlEncode(JSON.stringify(header));
    const payloadB64 = this.base64UrlEncode(JSON.stringify(payload));
    const data = `${headerB64}.${payloadB64}`;

    const encoder = new TextEncoder();
    const keyData = encoder.encode(LIVEKIT_CONFIG.apiSecret);
    const key = await crypto.subtle.importKey(
      'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
    );
    const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
    const signatureB64 = this.base64UrlEncode(
      String.fromCharCode(...new Uint8Array(signature))
    );

    return `${data}.${signatureB64}`;
  }
}

class LiveKitService {
  constructor() {
    this.room = null;
    this.localParticipant = null;
    this.remoteParticipants = new Map();
    this.localVideoTrack = null;
    this.localAudioTrack = null;
    this.eventHandlers = new Map();
    this.isConnected = false;
    this.chatMessages = [];
    this.maxChatHistory = 200;
    this.filterEngine = null;
  }

  setFilterEngine(engine) {
    this.filterEngine = engine;
  }

  async init() {
    if (typeof LivekitClient === 'undefined') {
      console.error('LiveKit SDK not loaded');
      return false;
    }
    console.log('LiveKit Service initialized');
    return true;
  }

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
          resolution: LivekitClient.VideoPresets.h480.resolution
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

  async disconnect() {
    if (this.room) {
      await this.stopAllTracks();
      await this.room.disconnect();
      this.room = null;
      this.localParticipant = null;
      this.remoteParticipants.clear();
      this.isConnected = false;
      this.chatMessages = [];
      this.emit('disconnected');
    }
  }

  setupRoomEventListeners() {
    if (!this.room) return;

    this.room.on(LivekitClient.RoomEvent.ParticipantConnected, (participant) => {
      this.handleParticipantConnected(participant);
    });
    this.room.on(LivekitClient.RoomEvent.ParticipantDisconnected, (participant) => {
      this.handleParticipantDisconnected(participant);
    });
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
    this.room.on(LivekitClient.RoomEvent.DataReceived, (payload, participant) => {
      this.handleDataReceived(payload, participant);
    });
    this.room.on(LivekitClient.RoomEvent.ConnectionQualityChanged, (quality, participant) => {
      this.emit('qualityChanged', { quality, participant });
    });
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
  }

  handleParticipantConnected(participant) {
    this.remoteParticipants.set(participant.sid, participant);
    participant.trackPublications.forEach((publication) => {
      if (publication.isSubscribed && publication.track) {
        this.emit('trackSubscribed', { track: publication.track, publication, participant });
      }
    });
    this.emit('participantConnected', { participant });
  }

  handleParticipantDisconnected(participant) {
    this.remoteParticipants.delete(participant.sid);
    this.emit('participantDisconnected', { participant });
  }

  handleTrackSubscribed(track, publication, participant) {
    this.emit('trackSubscribed', { track, publication, participant });
  }

  handleTrackUnsubscribed(track, publication, participant) {
    this.emit('trackUnsubscribed', { track, publication, participant });
  }

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

  async enableCamera(options = {}) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }
    try {
      // If filter engine is active, publish its processed track instead of raw camera
      if (this.filterEngine && this.filterEngine.getProcessedStream()) {
        const processedTrack = this.filterEngine.getProcessedStream().getVideoTracks()[0];
        if (processedTrack) {
          const localTrack = new LivekitClient.LocalVideoTrack(processedTrack, undefined, false);
          await this.localParticipant.publishTrack(localTrack, {
            source: LivekitClient.Track.Source.Camera,
            simulcast: false,
            videoEncoding: { maxBitrate: 800000, maxFramerate: 30 }
          });
          this.localVideoTrack = localTrack;
          this.emit('cameraEnabled', { track: this.localVideoTrack });
          return this.localVideoTrack;
        }
      }

      // Fallback: publish raw camera
      await this.localParticipant.setCameraEnabled(true, {
        resolution: { width: 854, height: 480, frameRate: 30 }
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

  async disableCamera() {
    if (this.localParticipant) {
      await this.localParticipant.setCameraEnabled(false);
      this.localVideoTrack = null;
      this.emit('cameraDisabled');
    }
  }

  async toggleCamera() {
    if (this.localVideoTrack) {
      await this.disableCamera();
      return false;
    } else {
      await this.enableCamera();
      return true;
    }
  }

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

  async disableMicrophone() {
    if (this.localParticipant) {
      await this.localParticipant.setMicrophoneEnabled(false);
      this.localAudioTrack = null;
      this.emit('microphoneDisabled');
    }
  }

  async toggleMicrophone() {
    if (this.localAudioTrack) {
      await this.disableMicrophone();
      return false;
    } else {
      await this.enableMicrophone();
      return true;
    }
  }

  async stopAllTracks() {
    await this.disableCamera();
    await this.disableMicrophone();
  }

  // ============================================
  // DATA CHANNEL / CHAT
  // ============================================

  async sendChatMessage(text) {
    if (!this.room || !this.localParticipant) {
      throw new Error('Not connected to a room');
    }
    const message = { type: 'chat', id: Date.now(), text, timestamp: Date.now() };
    const encoder = new TextEncoder();
    const data = encoder.encode(JSON.stringify(message));
    await this.localParticipant.publishData(data, { reliable: true });

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

  // ============================================
  // HELPERS
  // ============================================

  attachTrack(track, element) {
    if (track && element) {
      track.attach(element);
      return true;
    }
    return false;
  }

  detachTrack(track) {
    if (track) {
      track.detach();
      return true;
    }
    return false;
  }

  attachLocalVideo(element) {
    if (this.localVideoTrack) {
      return this.attachTrack(this.localVideoTrack, element);
    }
    return false;
  }

  getRemoteParticipant() {
    if (this.remoteParticipants.size === 0) return null;
    return this.remoteParticipants.values().next().value;
  }

  getRemoteVideoTracks() {
    const tracks = [];
    this.remoteParticipants.forEach((participant) => {
      participant.trackPublications.forEach((publication) => {
        if (publication.track && publication.track.kind === 'video') {
          tracks.push({ track: publication.track, participant, source: publication.source });
        }
      });
    });
    return tracks;
  }

  getRoomInfo() {
    if (!this.room) return null;
    return {
      name: this.room.name,
      sid: this.room.sid,
      numParticipants: this.remoteParticipants.size + 1,
      isConnected: this.isConnected
    };
  }

  static async getDevices() {
    const devices = await navigator.mediaDevices.enumerateDevices();
    return {
      videoInputs: devices.filter(d => d.kind === 'videoinput'),
      audioInputs: devices.filter(d => d.kind === 'audioinput'),
      audioOutputs: devices.filter(d => d.kind === 'audiooutput')
    };
  }

  static async requestPermissions(video = true, audio = true) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video, audio });
      stream.getTracks().forEach(track => track.stop());
      return true;
    } catch (error) {
      console.error('Failed to get permissions:', error);
      return false;
    }
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

const livekitService = new LiveKitService();
window.LiveKitService = LiveKitService;
window.livekitService = livekitService;
window.TokenGenerator = TokenGenerator;
window.LIVEKIT_CONFIG = LIVEKIT_CONFIG;
