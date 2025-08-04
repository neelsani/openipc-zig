import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import MainModuleFactory, { type MainModule } from '../wasm';
import type { LinkStats } from '../types/device';

// Frame buffer pool for memory optimization
class FramePool {
  private pool: Uint8Array[] = [];
  private readonly maxPoolSize = 8;

  getFrame(size: number): Uint8Array {
    const pooledFrame = this.pool.find(frame => frame.length >= size);
    if (pooledFrame) {
      this.pool = this.pool.filter(frame => frame !== pooledFrame);
      return pooledFrame.subarray(0, size);
    }
    return new Uint8Array(size);
  }

  returnFrame(frame: Uint8Array): void {
    if (this.pool.length < this.maxPoolSize && frame.length > 1024) {
      this.pool.push(frame);
    }
  }
}

// Separate video system management
class VideoSystem {
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private decoder: VideoDecoder | null = null;
  private currentCodec: number = -1;
  private currentProfile: number = -1;
  private pendingFrames: Array<{ chunk: EncodedVideoChunk; timestamp: number }> = [];
  private switchingCodec: boolean = false;
  private initialized: boolean = false;
  private framePool: FramePool = new FramePool();
  private readonly maxPendingFrames = 3; // Reduce pending frame buffer

  // Profile enum mappings from your Zig code
  private readonly H264Profile = {
    baseline: 66,
    main: 77,
    extended: 88,
    high: 100,
    high10: 110,
    high422: 122,
    high444: 244,
    unknown: 255,
  } as const;

  private readonly H265Profile = {
    main: 1,
    main10: 2,
    main_still_picture: 3,
    range_extensions: 4,
    high_throughput: 5,
    screen_content_coding: 9,
    unknown: 255,
  } as const;

  async initialize(): Promise<void> {
    if (this.initialized) return;

    this.canvas = this.getOrCreateCanvas();
    this.ctx = this.canvas.getContext('2d');
    this.initialized = true;
  }

  private getOrCreateCanvas(): HTMLCanvasElement {
    let canvas = document.getElementById('videoCanvas') as HTMLCanvasElement;
    if (!canvas) {
      canvas = document.createElement('canvas');
      canvas.id = 'videoCanvas';
      canvas.width = 1920;
      canvas.height = 1080;
      canvas.style.border = '1px solid #000';
      document.body.appendChild(canvas);
    }
    return canvas;
  }

  private getCodecStringFromProfile(codecType: number, profile: number): string {
    if (codecType === 0) { // H.264
      switch (profile) {
        case this.H264Profile.baseline:
          return 'avc1.42E01E'; // Constrained Baseline Profile
        case this.H264Profile.main:
          return 'avc1.4D401E'; // Main Profile
        case this.H264Profile.extended:
          return 'avc1.58401E'; // Extended Profile
        case this.H264Profile.high:
          return 'avc1.64001E'; // High Profile
        case this.H264Profile.high10:
          return 'avc1.6E001E'; // High 10 Profile
        case this.H264Profile.high422:
          return 'avc1.7A001E'; // High 4:2:2 Profile
        case this.H264Profile.high444:
          return 'avc1.F4001E'; // High 4:4:4 Profile
        default:
          console.warn(`Unknown H.264 profile: ${profile}, using baseline`);
          return 'avc1.42E01E'; // Default to baseline
      }
    } else if (codecType === 1) { // H.265
      switch (profile) {
        case this.H265Profile.main:
          return 'hev1.1.6.L93.B0'; // Main Profile
        case this.H265Profile.main10:
          return 'hev1.2.4.L93.B0'; // Main 10 Profile
        case this.H265Profile.main_still_picture:
          return 'hev1.3.6.L93.B0'; // Main Still Picture Profile
        case this.H265Profile.range_extensions:
          return 'hev1.4.4.L93.B0'; // Range Extensions Profile
        case this.H265Profile.high_throughput:
          return 'hev1.5.4.L93.B0'; // High Throughput Profile
        case this.H265Profile.screen_content_coding:
          return 'hev1.9.4.L93.B0'; // Screen Content Coding Profile
        default:
          console.warn(`Unknown H.265 profile: ${profile}, using main`);
          return 'hev1.1.6.L93.B0'; // Default to main
      }
    }

    throw new Error(`Unsupported codec type: ${codecType}`);
  }

  private getCodecConfig(codecType: number, profile: number) {
    const codecString = this.getCodecStringFromProfile(codecType, profile);

    const baseConfig: VideoDecoderConfig = {
      codec: codecString,
      hardwareAcceleration: 'prefer-software' as const,

    };

    // Special handling for H.265 hardware acceleration
    if (codecType === 1) {
      baseConfig.hardwareAcceleration = 'prefer-hardware';
    }

    console.log(`Generated codec config: ${codecString} for codec ${codecType}, profile ${profile}`);
    return baseConfig;
  }

  private async createDecoder(codecType: number, profile: number): Promise<VideoDecoder> {
    const config = this.getCodecConfig(codecType, profile);

    // Check codec support first
    const support = await VideoDecoder.isConfigSupported(config);
    if (!support.supported) {
      throw new Error(`Codec not supported: ${config.codec} (codec: ${codecType}, profile: ${profile})`);
    }

    console.log(`Creating decoder with codec: ${config.codec}`);
    return new VideoDecoder({
      output: (frame) => this.handleFrame(frame),
      error: (error) => this.handleDecoderError(error)
    });
  }

  private async handleFrame(frame: VideoFrame): Promise<void> {
    if (!this.canvas || !this.ctx) {
      frame.close();
      return;
    }

    try {
      // Resize canvas if needed
      if (this.canvas.width !== frame.displayWidth || this.canvas.height !== frame.displayHeight) {
        this.canvas.width = frame.displayWidth;
        this.canvas.height = frame.displayHeight;
      }

      // Use requestAnimationFrame for smoother rendering
      requestAnimationFrame(() => {
        if (this.ctx) {
          this.ctx.drawImage(frame, 0, 0);
        }
        frame.close();
      });

      // Process pending frames after successful decode
      this.processPendingFrames();
    } catch (error) {
      console.error('Error handling frame:', error);
      frame.close();
    }
  }

  private handleDecoderError(error: DOMException): void {
    console.error('Video decoder error:', error);
    this.cleanup();
  }

  private processPendingFrames(): void {
    if (!this.switchingCodec || this.pendingFrames.length === 0) return;

    console.log('Processing', this.pendingFrames.length, 'pending frames');
    const pendingFrames = this.pendingFrames.slice();
    this.pendingFrames = [];
    this.switchingCodec = false;

    pendingFrames.forEach(({ chunk }) => {
      try {
        this.decoder?.decode(chunk);
      } catch (e) {
        console.error('Error decoding pending frame:', e);
      }
    });
  }

  async processFrame(frameData: Uint8Array, codecType: number, profile: number, isKeyFrame: boolean): Promise<void> {
    if (!this.initialized) {
      await this.initialize();
    }

    // Handle codec or profile changes
    if (this.currentCodec !== codecType || this.currentProfile !== profile) {
      await this.switchCodec(codecType, profile);
    }

    // Frame dropping logic for high bitrate scenarios
    if (this.pendingFrames.length > this.maxPendingFrames) {
      console.warn(`Dropping frames, pending: ${this.pendingFrames.length}`);
      // Keep only keyframes when overwhelmed
      this.pendingFrames = this.pendingFrames.filter(f => f.chunk.type === 'key');
    }

    // Ensure decoder exists
    if (!this.decoder) {
      this.decoder = await this.createDecoder(codecType, profile);
      await this.decoder.configure(this.getCodecConfig(codecType, profile));
    }

    // Create a copy of frame data to avoid memory issues
    const frameCopy = this.framePool.getFrame(frameData.length);
    frameCopy.set(frameData);

    const chunk = new EncodedVideoChunk({
      type: isKeyFrame ? 'key' : 'delta',
      timestamp: performance.now() * 1000,
      data: frameCopy
    });

    // Handle codec switching logic
    if (this.switchingCodec) {
      if (isKeyFrame) {
        try {
          this.decoder.decode(chunk);
          this.switchingCodec = false;
          console.log('Resumed decoding after codec/profile switch with keyframe');
        } catch (error) {
          console.error('Failed to decode keyframe after codec/profile switch:', error);
          throw error;
        }
      } else {
        this.pendingFrames.push({ chunk, timestamp: performance.now() });
        console.log('Queued frame during codec/profile switch, waiting for keyframe');
      }
    } else {
      try {
        this.decoder.decode(chunk);
      } catch (error) {
        console.error('Failed to decode frame:', error);
        if ((error as any).name === 'InvalidStateError') {
          this.cleanup();
        }
        throw error;
      }
    }
  }

  private async switchCodec(newCodecType: number, newProfile: number): Promise<void> {
    console.log('Codec/Profile change detected:',
      `${this.currentCodec}/${this.currentProfile} -> ${newCodecType}/${newProfile}`);

    // Close existing decoder
    if (this.decoder) {
      try {
        this.decoder.close();
      } catch (e) {
        console.warn('Error closing decoder:', e);
      }
      this.decoder = null;
    }

    this.currentCodec = newCodecType;
    this.currentProfile = newProfile;
    this.switchingCodec = true;
    this.pendingFrames = [];
  }

  private cleanup(): void {
    if (this.decoder) {
      try {
        this.decoder.close();
      } catch (e) {
        console.warn('Error closing decoder during cleanup:', e);
      }
      this.decoder = null;
    }
    this.currentCodec = -1;
    this.currentProfile = -1;
    this.switchingCodec = false;
    this.pendingFrames = [];
  }

  destroy(): void {
    this.cleanup();
    this.initialized = false;
  }
}


// Improved context with better error handling
interface WebAssemblyContextType {
  module: MainModule | null;
  isLoading: boolean;
  status: string;
  setStatus: (status: string) => void;
  webCodecsSupported: boolean;
  setCanvas: (canvas: HTMLCanvasElement | null) => void;
  outputLog: string;
  stats: LinkStats;
  error: string | null;
}

const WebAssemblyContext = createContext<WebAssemblyContextType | undefined>(undefined);

interface WebAssemblyProviderProps {
  children: React.ReactNode;
  maxLogEntries?: number;
}

export const WebAssemblyProvider: React.FC<WebAssemblyProviderProps> = ({
  children,
  maxLogEntries = 100
}) => {
  const [isLoading, setIsLoading] = useState(true);
  const [status, setStatus] = useState('Loading WebAssembly...');
  const [webCodecsSupported, setWebCodecsSupported] = useState(false);
  const [outputLog, setOutputLog] = useState('');
  const [canvas, setCanvas] = useState<HTMLCanvasElement | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [stats, setStats] = useState<LinkStats>({
    rssi: 0,
    snr: 0,
    rtp_bitrate: 0,
    video_bitrate: 0,
    packetCount: 0,
    frameCount: 0,
    fps: 0,
    codec: undefined,
    resolution: undefined
  });

  const outputLogEntriesRef = useRef<string[]>([]);
  const moduleRef = useRef<MainModule | null>(null);
  const videoSystemRef = useRef<VideoSystem | null>(null);

  const addLogEntry = useCallback((text: string) => {
    outputLogEntriesRef.current.push(text);

    if (outputLogEntriesRef.current.length > maxLogEntries) {
      outputLogEntriesRef.current.shift();
    }

    setOutputLog(outputLogEntriesRef.current.join('\n'));
  }, [maxLogEntries]);

  const displayFrame = useCallback(async (frameData: Uint8Array, codecType: number, profile: number, isKeyFrame: boolean) => {
    try {
      if (!videoSystemRef.current) {
        videoSystemRef.current = new VideoSystem();
      }

      await videoSystemRef.current.processFrame(frameData, codecType, profile, isKeyFrame);

      // Update stats
      setStats(prevStats => ({
        ...prevStats,
        frameCount: prevStats.frameCount + 1,
        codec: codecType === 0 ? 'H.264' : 'H.265'
      }));

    } catch (error) {
      console.error('Frame processing error:', error);
      setError(`Frame processing failed: ${error}`);
    }
  }, []);

  const handleIEEFrame = useCallback((rssi: number, snr: number) => {
    setStats(prevStats => ({
      ...prevStats,
      rssi: rssi,
      snr: snr,
      packetCount: prevStats.packetCount + 1,
    }));
  }, []);
  const onBitrate = useCallback((rtp_bitrate: number, video_bitrate: number) => {
    setStats(prevStats => ({
      ...prevStats,
      rtp_bitrate: rtp_bitrate,
      video_bitrate: video_bitrate,

    }));
  }, []);

  // Initialize WebCodecs support check
  useEffect(() => {
    const checkSupport = async () => {
      const supported = typeof VideoDecoder !== 'undefined';
      setWebCodecsSupported(supported);

      if (supported) {
        // Test basic codec support
        try {
          const h264Support = await VideoDecoder.isConfigSupported({
            codec: 'avc1.42C00D'
          });
          console.log('H.264 support:', h264Support.supported);
        } catch (e) {
          console.warn('Error checking codec support:', e);
        }
      }
    };

    checkSupport();
  }, []);

  // Initialize WebAssembly module
  useEffect(() => {
    const initializeModule = async () => {
      if (moduleRef.current) return;

      try {
        setError(null);

        const moduleConfig = {
          canvas: null,
          print: addLogEntry,
          printErr: (text: string) => {
            console.error(text);
            addLogEntry(`ERROR: ${text}`);
          },
          setStatus,
          onRuntimeInitialized: () => {
            if (typeof window !== 'undefined') {
              (window as any).Module = moduleRef.current;
            }
            setIsLoading(false);
            setStatus('Ready - Loading device list...');
          },
          onIEEFrameReact: handleIEEFrame,
          displayFrameReact: displayFrame,
          onBitrateReact: onBitrate,
        };

        const wasmModule = await MainModuleFactory(moduleConfig);
        moduleRef.current = wasmModule;

        if (typeof window !== 'undefined') {
          (window as any).Module = wasmModule;
        }

      } catch (error) {
        console.error('Failed to load WebAssembly module:', error);
        setError(`Failed to load WebAssembly module: ${error}`);
        setStatus(`Failed to load WebAssembly module: ${error}`);
        setIsLoading(false);
      }
    };

    initializeModule();

    // Cleanup on unmount
    return () => {
      if (videoSystemRef.current) {
        videoSystemRef.current.destroy();
        videoSystemRef.current = null;
      }
    };
  }, [addLogEntry, displayFrame, handleIEEFrame]);

  // Update canvas when it changes
  useEffect(() => {
    if (moduleRef.current && canvas) {
      try {
        if ('setCanvas' in moduleRef.current) {
          (moduleRef.current as any).setCanvas(canvas);
        }
      } catch (error) {
        console.error('Failed to update canvas:', error);
        setError(`Failed to update canvas: ${error}`);
      }
    }
  }, [canvas]);

  const contextValue: WebAssemblyContextType = {
    module: moduleRef.current,
    isLoading,
    status,
    setStatus,
    webCodecsSupported,
    setCanvas,
    outputLog,
    stats,
    error,
  };

  return (
    <WebAssemblyContext.Provider value={contextValue}>
      {children}
    </WebAssemblyContext.Provider>
  );
};

export const useWebAssemblyContext = (): WebAssemblyContextType => {
  const context = useContext(WebAssemblyContext);
  if (context === undefined) {
    throw new Error('useWebAssemblyContext must be used within a WebAssemblyProvider');
  }
  return context;
};

export const useWebAssemblyCanvas = (canvasRef: React.RefObject<HTMLCanvasElement | null>) => {
  const { setCanvas, ...rest } = useWebAssemblyContext();

  useEffect(() => {
    if (canvasRef.current) {
      setCanvas(canvasRef.current);
    }

    return () => {
      setCanvas(null);
    };
  }, [canvasRef, setCanvas]);

  return rest;
};
