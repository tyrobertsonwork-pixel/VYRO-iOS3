#!/bin/bash

echo "🚀 Installing VYRO MKV Playback Fix..."
echo "================================================"

# Create directories
echo "📁 Creating directory structure..."
mkdir -p src/services/stream
mkdir -p src/services/plugins
mkdir -p src/services/playback
mkdir -p src/composables
mkdir -p ios/App/App
mkdir -p .github/workflows

# File 1: StreamDetector.ts
echo "📝 Creating StreamDetector.ts..."
cat > src/services/stream/StreamDetector.ts << 'ENDOFFILE'
import { CapacitorHttp } from '@capacitor/core';

export interface StreamInfo {
  url: string;
  container: string;
  mimeType: string;
  fileName?: string;
  headers?: Record<string, string>;
  isSupported: boolean;
  requiresNativePlayer: boolean;
}

export class StreamDetector {
  private static readonly CONTAINER_SIGNATURES: Record<string, number[]> = {
    'mkv': [0x1A, 0x45, 0xDF, 0xA3],
    'mp4': [0x66, 0x74, 0x79, 0x70],
    'avi': [0x52, 0x49, 0x46, 0x46],
    'webm': [0x1A, 0x45, 0xDF, 0xA3],
    'flac': [0x66, 0x4C, 0x61, 0x43],
  };

  private static readonly MIME_TO_CONTAINER: Record<string, string> = {
    'video/x-matroska': 'mkv',
    'video/mkv': 'mkv',
    'video/mp4': 'mp4',
    'video/x-msvideo': 'avi',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'video/x-m4v': 'mp4',
    'audio/flac': 'flac',
    'audio/x-flac': 'flac',
    'application/octet-stream': 'unknown',
  };

  static async detectStream(url: string): Promise<StreamInfo> {
    console.log('[StreamDetector] Analyzing stream:', url);

    try {
      const headResponse = await CapacitorHttp.request({
        url,
        method: 'HEAD',
        headers: {
          'User-Agent': 'VYRO/1.0',
        },
      });

      console.log('[StreamDetector] HEAD response:', {
        status: headResponse.status,
        headers: headResponse.headers,
      });

      const contentType = headResponse.headers['content-type'] || 
                         headResponse.headers['Content-Type'] || '';
      const contentDisposition = headResponse.headers['content-disposition'] || 
                                headResponse.headers['Content-Disposition'] || '';
      
      let fileName: string | undefined;
      const fileNameMatch = contentDisposition.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/);
      if (fileNameMatch && fileNameMatch[1]) {
        fileName = fileNameMatch[1].replace(/['"]/g, '');
      }

      console.log('[StreamDetector] Extracted metadata:', {
        contentType,
        fileName,
      });

      let container = this.MIME_TO_CONTAINER[contentType.split(';')[0].trim()];

      if (!container && fileName) {
        const ext = fileName.split('.').pop()?.toLowerCase();
        if (ext) {
          container = ext;
        }
      }

      if (!container) {
        const urlPath = new URL(url).pathname;
        const ext = urlPath.split('.').pop()?.toLowerCase();
        if (ext && ext.length <= 4) {
          container = ext;
        }
      }

      if (!container || container === 'unknown') {
        console.log('[StreamDetector] Performing content sniffing...');
        container = await this.sniffContainer(url);
      }

      const requiresNativePlayer = this.requiresNativePlayer(container);
      const isSupported = this.isFormatSupported(container);

      const streamInfo: StreamInfo = {
        url,
        container,
        mimeType: contentType || this.containerToMime(container),
        fileName,
        headers: headResponse.headers,
        isSupported,
        requiresNativePlayer,
      };

      console.log('[StreamDetector] Final stream info:', streamInfo);
      return streamInfo;

    } catch (error) {
      console.error('[StreamDetector] Detection failed:', error);
      
      const urlPath = new URL(url).pathname;
      const ext = urlPath.split('.').pop()?.toLowerCase() || 'unknown';
      
      return {
        url,
        container: ext,
        mimeType: this.containerToMime(ext),
        isSupported: this.isFormatSupported(ext),
        requiresNativePlayer: this.requiresNativePlayer(ext),
      };
    }
  }

  private static async sniffContainer(url: string): Promise<string> {
    try {
      const response = await CapacitorHttp.request({
        url,
        method: 'GET',
        headers: {
          'Range': 'bytes=0-16383',
          'User-Agent': 'VYRO/1.0',
        },
        responseType: 'arraybuffer',
      });

      if (response.data) {
        const bytes = new Uint8Array(response.data);
        
        for (const [container, signature] of Object.entries(this.CONTAINER_SIGNATURES)) {
          if (this.matchesSignature(bytes, signature)) {
            console.log(`[StreamDetector] Detected ${container} by signature`);
            return container;
          }
          
          if (container === 'mp4' && bytes.length > 8) {
            if (this.matchesSignature(bytes.slice(4), signature)) {
              console.log('[StreamDetector] Detected mp4 by signature at offset 4');
              return 'mp4';
            }
          }
        }
      }

      return 'unknown';
    } catch (error) {
      console.error('[StreamDetector] Content sniffing failed:', error);
      return 'unknown';
    }
  }

  private static matchesSignature(bytes: Uint8Array, signature: number[]): boolean {
    if (bytes.length < signature.length) return false;
    
    for (let i = 0; i < signature.length; i++) {
      if (bytes[i] !== signature[i]) return false;
    }
    
    return true;
  }

  private static requiresNativePlayer(container: string): boolean {
    const nativeFormats = ['mkv', 'avi', 'flv', 'wmv', 'mov', 'flac'];
    return nativeFormats.includes(container);
  }

  private static isFormatSupported(container: string): boolean {
    const supported = ['mkv', 'mp4', 'm4v', 'mov', 'avi', 'webm', 'flac', 'mp3', 'aac'];
    return supported.includes(container);
  }

  private static containerToMime(container: string): string {
    const mimeMap: Record<string, string> = {
      'mkv': 'video/x-matroska',
      'mp4': 'video/mp4',
      'm4v': 'video/x-m4v',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'webm': 'video/webm',
      'flac': 'audio/flac',
      'mp3': 'audio/mpeg',
      'aac': 'audio/aac',
    };
    
    return mimeMap[container] || 'application/octet-stream';
  }
}
ENDOFFILE

# File 2: AetherEngine.ts
echo "📝 Creating AetherEngine.ts..."
cat > src/services/plugins/AetherEngine.ts << 'ENDOFFILE'
import { registerPlugin } from '@capacitor/core';

export interface AetherEnginePlugin {
  initialize(): Promise<{ initialized: boolean }>;
  
  playStream(options: {
    url: string;
    container: string;
    mimeType: string;
    headers?: Record<string, string>;
  }): Promise<{ playing: boolean; method?: string }>;
  
  pause(): Promise<void>;
  resume(): Promise<void>;
  seek(options: { time: number }): Promise<{ seeked: boolean }>;
  stop(): Promise<void>;
  
  getSupportedFormats(): Promise<Record<string, boolean>>;
  
  addListener(
    eventName: 'playerReady' | 'playerError' | 'timeUpdate' | 'debug' | 'error',
    listenerFunc: (data: any) => void
  ): Promise<any>;
  
  removeAllListeners(): Promise<void>;
}

const AetherEngine = registerPlugin<AetherEnginePlugin>('AetherEngine', {
  web: () => import('./AetherEngineWeb').then(m => new m.AetherEngineWeb()),
});

export { AetherEngine };
ENDOFFILE

# File 3: AetherEngineWeb.ts
echo "📝 Creating AetherEngineWeb.ts..."
cat > src/services/plugins/AetherEngineWeb.ts << 'ENDOFFILE'
import { WebPlugin } from '@capacitor/core';
import type { AetherEnginePlugin } from './AetherEngine';

export class AetherEngineWeb extends WebPlugin implements AetherEnginePlugin {
  private videoElement: HTMLVideoElement | null = null;

  async initialize(): Promise<{ initialized: boolean }> {
    console.log('[AetherEngineWeb] Initialize called');
    return { initialized: true };
  }

  async playStream(options: {
    url: string;
    container: string;
    mimeType: string;
    headers?: Record<string, string>;
  }): Promise<{ playing: boolean }> {
    console.log('[AetherEngineWeb] Play stream:', options);
    
    if (this.videoElement) {
      this.videoElement.remove();
    }

    const video = document.createElement('video');
    video.src = options.url;
    video.controls = true;
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.position = 'fixed';
    video.style.top = '0';
    video.style.left = '0';
    video.style.zIndex = '9999';
    video.style.background = '#000';
    
    this.videoElement = video;
    document.body.appendChild(video);
    
    video.addEventListener('loadedmetadata', () => {
      this.notifyListeners('playerReady', {});
    });
    
    video.addEventListener('error', () => {
      this.notifyListeners('playerError', { 
        error: video.error?.message || 'Unknown error' 
      });
    });
    
    video.addEventListener('timeupdate', () => {
      this.notifyListeners('timeUpdate', {
        currentTime: video.currentTime,
        duration: video.duration || 0
      });
    });
    
    try {
      await video.play();
      return { playing: true };
    } catch (err: any) {
      this.notifyListeners('playerError', { error: err.message });
      throw err;
    }
  }

  async pause(): Promise<void> {
    if (this.videoElement) {
      this.videoElement.pause();
    }
  }

  async resume(): Promise<void> {
    if (this.videoElement) {
      await this.videoElement.play();
    }
  }

  async seek(options: { time: number }): Promise<{ seeked: boolean }> {
    if (this.videoElement) {
      this.videoElement.currentTime = options.time;
      return { seeked: true };
    }
    return { seeked: false };
  }

  async stop(): Promise<void> {
    if (this.videoElement) {
      this.videoElement.pause();
      this.videoElement.remove();
      this.videoElement = null;
    }
  }

  async getSupportedFormats(): Promise<Record<string, boolean>> {
    return {
      mp4: true,
      webm: true,
      mkv: false,
    };
  }
}
ENDOFFILE

# File 4: PlaybackService.ts
echo "📝 Creating PlaybackService.ts..."
cat > src/services/playback/PlaybackService.ts << 'ENDOFFILE'
import { AetherEngine } from '../plugins/AetherEngine';
import { StreamDetector, StreamInfo } from '../stream/StreamDetector';

export class PlaybackService {
  private static instance: PlaybackService;
  private currentStream: StreamInfo | null = null;
  private isPlaying = false;
  private listenersSetup = false;

  private constructor() {
    this.setupListeners();
  }

  static getInstance(): PlaybackService {
    if (!PlaybackService.instance) {
      PlaybackService.instance = new PlaybackService();
    }
    return PlaybackService.instance;
  }

  private setupListeners() {
    if (this.listenersSetup) return;
    this.listenersSetup = true;

    AetherEngine.addListener('playerReady', () => {
      console.log('[PlaybackService] Player ready');
      this.isPlaying = true;
    });

    AetherEngine.addListener('playerError', (data) => {
      console.error('[PlaybackService] Player error:', data);
      this.handlePlaybackError(data.error);
    });

    AetherEngine.addListener('timeUpdate', (data) => {
      this.updateProgress(data.currentTime, data.duration);
    });

    AetherEngine.addListener('debug', (data) => {
      console.log('[PlaybackService]', data.message);
    });
  }

  async playStream(url: string): Promise<void> {
    try {
      console.log('[PlaybackService] Starting playback for:', url);

      const streamInfo = await StreamDetector.detectStream(url);
      this.currentStream = streamInfo;

      console.log('[PlaybackService] Stream detected:', {
        container: streamInfo.container,
        mimeType: streamInfo.mimeType,
        requiresNative: streamInfo.requiresNativePlayer,
        supported: streamInfo.isSupported
      });

      if (!streamInfo.isSupported) {
        throw new Error(`Unsupported format: ${streamInfo.container}`);
      }

      await this.playWithNativePlayer(streamInfo);

    } catch (error) {
      console.error('[PlaybackService] Playback failed:', error);
      throw error;
    }
  }

  private async playWithNativePlayer(streamInfo: StreamInfo): Promise<void> {
    try {
      console.log('[PlaybackService] Using native player');

      await AetherEngine.initialize();

      const result = await AetherEngine.playStream({
        url: streamInfo.url,
        container: streamInfo.container,
        mimeType: streamInfo.mimeType,
        headers: streamInfo.headers || {}
      });

      console.log('[PlaybackService] Native playback started:', result);
    } catch (error) {
      console.error('[PlaybackService] Native playback failed:', error);
      throw new Error(`Native playback failed: ${error}`);
    }
  }

  async pause(): Promise<void> {
    if (this.isPlaying) {
      await AetherEngine.pause();
      this.isPlaying = false;
    }
  }

  async resume(): Promise<void> {
    if (!this.isPlaying) {
      await AetherEngine.resume();
      this.isPlaying = true;
    }
  }

  async seek(time: number): Promise<void> {
    await AetherEngine.seek({ time });
  }

  async stop(): Promise<void> {
    await AetherEngine.stop();
    this.isPlaying = false;
    this.currentStream = null;
  }

  private handlePlaybackError(error: string) {
    console.error('[PlaybackService] Playback error:', error);
    
    window.dispatchEvent(new CustomEvent('playback-error', {
      detail: { error }
    }));
  }

  private updateProgress(currentTime: number, duration: number) {
    window.dispatchEvent(new CustomEvent('playback-progress', {
      detail: { currentTime, duration }
    }));
  }

  getCurrentStream(): StreamInfo | null {
    return this.currentStream;
  }

  isCurrentlyPlaying(): boolean {
    return this.isPlaying;
  }
}
ENDOFFILE

# File 5: useVideoPlayer.ts
echo "📝 Creating useVideoPlayer.ts..."
cat > src/composables/useVideoPlayer.ts << 'ENDOFFILE'
import { ref, onUnmounted } from 'vue';
import { PlaybackService } from '../services/playback/PlaybackService';

export function useVideoPlayer() {
  const isPlaying = ref(false);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const currentTime = ref(0);
  const duration = ref(0);

  const playbackService = PlaybackService.getInstance();

  const playStream = async (url: string) => {
    try {
      isLoading.value = true;
      error.value = null;
      
      await playbackService.playStream(url);
      
      isLoading.value = false;
      isPlaying.value = true;
    } catch (err: any) {
      isLoading.value = false;
      error.value = err.message || 'Failed to play stream';
      console.error('Video playback error:', err);
    }
  };

  const pause = async () => {
    await playbackService.pause();
    isPlaying.value = false;
  };

  const resume = async () => {
    await playbackService.resume();
    isPlaying.value = true;
  };

  const seek = async (time: number) => {
    await playbackService.seek(time);
  };

  const stop = async () => {
    await playbackService.stop();
    isPlaying.value = false;
    currentTime.value = 0;
  };

  const handleProgress = (event: Event) => {
    const customEvent = event as CustomEvent;
    currentTime.value = customEvent.detail.currentTime;
    duration.value = customEvent.detail.duration;
  };

  const handleError = (event: Event) => {
    const customEvent = event as CustomEvent;
    error.value = customEvent.detail.error;
    isPlaying.value = false;
  };

  window.addEventListener('playback-progress', handleProgress);
  window.addEventListener('playback-error', handleError);

  onUnmounted(() => {
    window.removeEventListener('playback-progress', handleProgress);
    window.removeEventListener('playback-error', handleError);
    stop();
  });

  return {
    isPlaying,
    isLoading,
    error,
    currentTime,
    duration,
    playStream,
    pause,
    resume,
    seek,
    stop
  };
}
ENDOFFILE

# File 6: AetherEnginePlugin.swift
echo "📝 Creating AetherEnginePlugin.swift..."
cat > ios/App/App/AetherEnginePlugin.swift << 'ENDOFFILE'
import Foundation
import Capacitor
import AVFoundation
import AVKit

@objc(AetherEnginePlugin)
public class AetherEnginePlugin: CAPPlugin {
    private var playerViewController: AVPlayerViewController?
    private var player: AVPlayer?
    private var currentStreamInfo: StreamInfo?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    
    struct StreamInfo {
        let url: URL
        let container: String
        let mimeType: String
        let headers: [String: String]?
    }
    
    @objc func initialize(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.logDebug("Initializing AetherEngine")
            call.resolve(["initialized": true])
        }
    }
    
    @objc func playStream(_ call: CAPPluginCall) {
        guard let urlString = call.getString("url") else {
            call.reject("URL is required")
            return
        }
        
        guard let url = URL(string: urlString) else {
            call.reject("Invalid URL format")
            return
        }
        
        let container = call.getString("container") ?? "unknown"
        let mimeType = call.getString("mimeType") ?? "application/octet-stream"
        let headers = call.getObject("headers") as? [String: String]
        
        let streamInfo = StreamInfo(
            url: url,
            container: container,
            mimeType: mimeType,
            headers: headers
        )
        
        self.logDebug("""
            Playing stream:
            URL: (urlString)
            Container: (container)
            MIME: (mimeType)
            Headers: (headers?.description ?? "none")
        """)
        
        DispatchQueue.main.async {
            self.playStreamInternal(streamInfo, call: call)
        }
    }
    
    private func playStreamInternal(_ streamInfo: StreamInfo, call: CAPPluginCall) {
        self.cleanup()
        
        self.currentStreamInfo = streamInfo
        
        let asset: AVURLAsset
        
        if let headers = streamInfo.headers, !headers.isEmpty {
            self.logDebug("Creating asset with custom headers")
            asset = AVURLAsset(url: streamInfo.url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
        } else {
            asset = AVURLAsset(url: streamInfo.url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
        }
        
        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "playable", error: &error)
            
            DispatchQueue.main.async {
                if status == .loaded {
                    self.logDebug("Asset loaded successfully")
                    
                    if let tracks = asset.tracks(withMediaType: .video) as? [AVAssetTrack] {
                        for (index, track) in tracks.enumerated() {
                            self.logDebug("""
                                Video Track (index):
                                - Format: (track.mediaType.rawValue)
                                - Duration: (track.timeRange.duration.seconds)s
                                - Natural Size: (track.naturalSize)
                                - Frame Rate: (track.nominalFrameRate)
                            """)
                        }
                    }
                    
                    if let tracks = asset.tracks(withMediaType: .audio) as? [AVAssetTrack] {
                        for (index, track) in tracks.enumerated() {
                            self.logDebug("""
                                Audio Track (index):
                                - Format: (track.mediaType.rawValue)
                                - Duration: (track.timeRange.duration.seconds)s
                            """)
                        }
                    }
                    
                    let playerItem = AVPlayerItem(asset: asset)
                    
                    self.statusObservation = playerItem.observe(.status, options: [.new, .initial]) { [weak self] item, _ in
                        self?.handlePlayerItemStatusChange(item)
                    }
                    
                    self.player = AVPlayer(playerItem: playerItem)
                    
                    self.playerViewController = AVPlayerViewController()
                    self.playerViewController?.player = self.player
                    self.playerViewController?.allowsPictureInPicturePlayback = true
                    self.playerViewController?.showsPlaybackControls = true
                    
                    if let rootViewController = self.bridge?.viewController {
                        self.playerViewController?.modalPresentationStyle = .fullScreen
                        rootViewController.present(self.playerViewController!, animated: true) {
                            self.logDebug("Player presented, starting playback")
                            self.player?.play()
                            call.resolve(["playing": true])
                        }
                    } else {
                        self.logError("No root view controller available")
                        call.reject("Failed to present player")
                    }
                    
                    self.setupTimeObserver()
                    
                } else if status == .failed {
                    let errorMsg = error?.localizedDescription ?? "Unknown error"
                    self.logError("Asset loading failed: (errorMsg)")
                    
                    if streamInfo.container == "mkv" {
                        self.logDebug("Attempting alternative MKV playback method")
                        self.tryAlternativeMKVPlayback(streamInfo, call: call)
                    } else {
                        call.reject("Playback failed: (errorMsg)")
                    }
                } else {
                    self.logError("Asset status: (status.rawValue)")
                    call.reject("Asset not ready")
                }
            }
        }
    }
    
    private func tryAlternativeMKVPlayback(_ streamInfo: StreamInfo, call: CAPPluginCall) {
        self.logDebug("Attempting direct playback for MKV")
        
        let player = AVPlayer(url: streamInfo.url)
        self.player = player
        
        self.playerViewController = AVPlayerViewController()
        self.playerViewController?.player = player
        self.playerViewController?.allowsPictureInPicturePlayback = true
        self.playerViewController?.showsPlaybackControls = true
        
        if let rootViewController = self.bridge?.viewController {
            self.playerViewController?.modalPresentationStyle = .fullScreen
            rootViewController.present(self.playerViewController!, animated: true) {
                self.logDebug("Direct MKV player presented")
                player.play()
                call.resolve(["playing": true, "method": "direct"])
            }
            
            self.setupTimeObserver()
        } else {
            call.reject("Failed to present player")
        }
    }
    
    private func handlePlayerItemStatusChange(_ playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            self.logDebug("Player item ready to play")
            self.notifyListeners("playerReady", data: [:])
        case .failed:
            if let error = playerItem.error {
                self.logError("Player item failed: (error.localizedDescription)")
                self.notifyListeners("playerError", data: ["error": error.localizedDescription])
            }
        case .unknown:
            self.logDebug("Player item status unknown")
        @unknown default:
            break
        }
    }
    
    private func setupTimeObserver() {
        guard let player = self.player else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            let currentTime = time.seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            
            self.notifyListeners("timeUpdate", data: [
                "currentTime": currentTime,
                "duration": duration
            ])
        }
    }
    
    @objc func pause(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.player?.pause()
            call.resolve()
        }
    }
    
    @objc func resume(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.player?.play()
            call.resolve()
        }
    }
    
    @objc func seek(_ call: CAPPluginCall) {
        guard let time = call.getDouble("time") else {
            call.reject("Time is required")
            return
        }
        
        DispatchQueue.main.async {
            let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.player?.seek(to: cmTime) { finished in
                call.resolve(["seeked": finished])
            }
        }
    }
    
    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.cleanup()
            call.resolve()
        }
    }
    
    @objc func getSupportedFormats(_ call: CAPPluginCall) {
        let supportedFormats = [
            "mp4": true,
            "m4v": true,
            "mov": true,
            "mkv": true,
            "avi": false,
            "webm": false,
            "flac": true,
            "mp3": true,
            "aac": true
        ]
        
        call.resolve(supportedFormats)
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        statusObservation?.invalidate()
        statusObservation = nil
        
        player?.pause()
        playerViewController?.dismiss(animated: true)
        playerViewController = nil
        player = nil
        currentStreamInfo = nil
    }
    
    private func logDebug(_ message: String) {
        NSLog("[AetherEngine] (message)")
        self.notifyListeners("debug", data: ["message": message])
    }
    
    private func logError(_ message: String) {
        NSLog("[AetherEngine] ERROR: (message)")
        self.notifyListeners("error", data: ["message": message])
    }
    
    deinit {
        cleanup()
    }
}
ENDOFFILE

# File 7: GitHub Actions workflow
echo "📝 Creating build-ios.yml..."
cat > .github/workflows/build-ios.yml << 'ENDOFFILE'
name: Build iOS IPA

on:
  push:
    branches: [ main, feature/native-mpv-mkv-player ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-13
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
        
    - name: Install Node dependencies
      run: npm ci
      
    - name: Build web assets
      run: npm run build
      env:
        NODE_ENV: production
        
    - name: Sync Capacitor
      run: npx cap sync ios
      
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'
        
    - name: Setup Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: '3.0'
        
    - name: Install CocoaPods
      run: |
        cd ios/App
        pod install --repo-update
        
    - name: Build iOS Application
      run: |
        cd ios/App
        xcodebuild clean archive \
          -workspace App.xcworkspace \
          -scheme App \
          -configuration Release \
          -archivePath $PWD/build/App.xcarchive \
          -destination 'generic/platform=iOS' \
          -allowProvisioningUpdates \
          CODE_SIGNING_ALLOWED=NO \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO \
          DEVELOPMENT_TEAM=""
          
    - name: Create IPA Package
      run: |
        cd ios/App
        mkdir -p Payload
        cp -r build/App.xcarchive/Products/Applications/App.app Payload/
        zip -r VYRO-unsigned.ipa Payload
        mv VYRO-unsigned.ipa ../../
        
    - name: Verify IPA Structure
      run: |
        echo "=== IPA Contents ==="
        unzip -l VYRO-unsigned.ipa | head -30
        echo ""
        echo "=== IPA Size ==="
        ls -lh VYRO-unsigned.ipa
        
    - name: Upload IPA Artifact
      uses: actions/upload-artifact@v4
      with:
        name: VYRO-iOS-unsigned-${{ github.sha }}
        path: VYRO-unsigned.ipa
        retention-days: 30
        
    - name: Upload Build Logs (on failure)
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: build-logs-${{ github.sha }}
        path: |
          ios/App/build/
          ios/App/Pods/
        retention-days: 7
ENDOFFILE

echo ""
echo "================================================"
echo "✅ All files created successfully!"
echo ""
echo "📋 Created files:"
echo "  ✓ src/services/stream/StreamDetector.ts"
echo "  ✓ src/services/plugins/AetherEngine.ts"
echo "  ✓ src/services/plugins/AetherEngineWeb.ts"
echo "  ✓ src/services/playback/PlaybackService.ts"
echo "  ✓ src/composables/useVideoPlayer.ts"
echo "  ✓ ios/App/App/AetherEnginePlugin.swift"
echo "  ✓ .github/workflows/build-ios.yml"
echo ""
echo "🎯 Next steps:"
echo "1. Commit these changes: git add . && git commit -m 'Add native MKV playback support'"
echo "2. Push to GitHub: git push"
echo "3. The GitHub Actions workflow will automatically build the IPA"
echo ""
