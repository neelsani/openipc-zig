import React, { createContext, useContext, useState, useEffect, useRef, type ReactNode, type RefObject, useCallback } from 'react';
import MainModuleFactory, { type MainModule } from '../wasm';
import type { LinkStats } from '../types/device';



interface WebAssemblyContextType {
  module: MainModule | null;
  isLoading: boolean;
  status: string;
  setStatus: (status: string) => void;
  webCodecsSupported: boolean;
  setCanvas: (canvas: HTMLCanvasElement | null) => void;
  outputLog: string;
  stats: LinkStats;
}

const WebAssemblyContext = createContext<WebAssemblyContextType | undefined>(undefined);

interface WebAssemblyProviderProps {
  children: ReactNode;
  maxLogEntries?: number; // Allow customization of log size
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
  const [stats, setStats] = useState<LinkStats>({
    rssi: 0,
    snr: 0,
    bitrate: 0,
    packetCount: 0,
    frameCount: 0,
    fps: 0,
    codec: undefined,
    resolution: undefined
  });
  
  const outputLogEntriesRef = useRef<string[]>([]);
  const moduleRef = useRef<MainModule | null>(null);

  const addLogEntry = (text: string) => {
    outputLogEntriesRef.current.push(text);
    
    // Remove oldest entries if we exceed the maximum
    if (outputLogEntriesRef.current.length > maxLogEntries) {
      outputLogEntriesRef.current.shift(); // Remove first (oldest) entry
    }
    
    // Update the log string
    setOutputLog(outputLogEntriesRef.current.join('\n'));
  };


const displayFrame = useCallback((frameData: Uint8Array, codec_type: number, is_key_frame: boolean) => {
    const module = moduleRef.current as any;
    if (!module) return;

    if (!module.videoSystem) {
      module.videoSystem = {
        canvas: null,
        ctx: null,
        decoder: null,
        initialized: false,
        currentCodec: -1,
        pendingFrames: [],
        switchingCodec: false
      };
    }
    
    if (!module.videoSystem.initialized) {
      // Create canvas if it doesn't exist
      module.videoSystem.canvas = document.getElementById('videoCanvas');
      if (!module.videoSystem.canvas) {
        module.videoSystem.canvas = document.createElement('canvas');
        module.videoSystem.canvas.id = 'videoCanvas';
        module.videoSystem.canvas.width = 1920;
        module.videoSystem.canvas.height = 1080;
        module.videoSystem.canvas.style.border = '1px solid #000';
        document.body.appendChild(module.videoSystem.canvas);
      }
      module.videoSystem.ctx = module.videoSystem.canvas.getContext('2d');
      module.videoSystem.initialized = true;
    }
    
    // Check if codec changed
    if (module.videoSystem.currentCodec !== codec_type) {
      console.log('Codec change detected:', module.videoSystem.currentCodec, '->', codec_type);
      
      // Close existing decoder
      if (module.videoSystem.decoder) {
        try {
          module.videoSystem.decoder.close();
        } catch (e) {
          console.warn('Error closing decoder:', e);
        }
        module.videoSystem.decoder = null;
      }
      
      module.videoSystem.currentCodec = codec_type;
      module.videoSystem.switchingCodec = true;
      module.videoSystem.pendingFrames = [];
    }
    
    // Initialize decoder if needed
    if (!module.videoSystem.decoder) {
      var codec = codec_type === 0 ? 'avc1.42E01E' : 'hev1.1.6.L93.B0';
      
      try {
        module.videoSystem.decoder = new VideoDecoder({
          output: function(frame) {
            //console.log("runss")
            var canvas = module.videoSystem.canvas;
            var ctx = module.videoSystem.ctx;
            
            // Resize canvas if needed
            if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
              canvas.width = frame.displayWidth;
              canvas.height = frame.displayHeight;
            }
            console.log(frame)
            // Draw frame
            ctx.drawImage(frame, 0, 0);
            frame.close();
            
            // Process any pending frames after successful decode
            if (module.videoSystem.switchingCodec && module.videoSystem.pendingFrames.length > 0) {
              console.log('Processing', module.videoSystem.pendingFrames.length, 'pending frames');
              var pendingFrames = module.videoSystem.pendingFrames.slice();
              module.videoSystem.pendingFrames = [];
              module.videoSystem.switchingCodec = false;
              
              pendingFrames.forEach(function(pendingFrame: any) {
                try {
                  module.videoSystem.decoder.decode(pendingFrame.chunk);
                } catch (e) {
                  console.error('Error decoding pending frame:', e);
                }
              });
            }
          },
          error: function(error) {
            console.error('Video decoder error:', error);
            module.videoSystem.decoder = null;
            module.videoSystem.currentCodec = -1;
            module.videoSystem.switchingCodec = false;
            module.videoSystem.pendingFrames = [];
          }
        });
        
        module.videoSystem.decoder.configure({
          codec: codec,
         
        });
        
        console.log('Decoder configured for codec:', codec);
      } catch (error) {
        console.error('Failed to initialize video decoder:', error);
        return;
      }
    }
    console.log(frameData)
    // Create encoded chunk
    var chunk = new EncodedVideoChunk({
      type: is_key_frame ? 'key' : 'delta',
      timestamp: performance.now() * 1000,
      data: frameData
    });
    
    // Handle codec switching logic
    if (module.videoSystem.switchingCodec) {
      if (is_key_frame) {
        try {
          module.videoSystem.decoder.decode(chunk);
          module.videoSystem.switchingCodec = false;
          console.log('Resumed decoding after codec switch with keyframe');
        } catch (error) {
          console.error('Failed to decode keyframe after codec switch:', error);
        }
      } else {
        module.videoSystem.pendingFrames.push({
          chunk: chunk,
          timestamp: performance.now()
        });
        console.log('Queued frame during codec switch, waiting for keyframe');
      }
    } else {
      try {
        module.videoSystem.decoder.decode(chunk);
      } catch (error) {
        console.error('Failed to decode frame:', error);
        if ((error as any).name === 'InvalidStateError') {
          module.videoSystem.decoder = null;
          module.videoSystem.currentCodec = -1;
        }
      }
    }
  }, []);

  // Initialize WebCodecs support check
  useEffect(() => {
    setWebCodecsSupported(typeof VideoDecoder !== 'undefined');
  }, []);

  // Initialize WebAssembly module once
 useEffect(() => {
  const initializeModule = async () => {
    if (moduleRef.current) return;

    try {
      const moduleConfig = {
        canvas: null,
        print: (text: string) => {
          console.log(text);
          addLogEntry(text);
        },
        printErr: (text: string) => {
          console.error(text);
          addLogEntry(`ERROR: ${text}`);
        },
        setStatus: (text: string) => {
          setStatus(text);
        },
        // Handle custom messages from pthreads
        
        onRuntimeInitialized: () => {
          // Make Module available globally
          if (typeof window !== 'undefined') {
            (window as any).Module = moduleRef.current;
          }
          setIsLoading(false);
          setStatus('Ready - Loading device list...');
        },
       FrameReact: (rssi: number, snr: number) => {
          setStats(prevStats => ({
            ...prevStats,
            rssi: -1 * rssi,
            snr: snr,
            packetCount: prevStats.packetCount + 1,
          }));
        },

        displayFrameReact: (frameData: Uint8Array, codec_type: number, is_key_frame: boolean) => {
          displayFrame(frameData, codec_type ,is_key_frame)
        }
      };

      const wasmModule = await MainModuleFactory(moduleConfig);
      moduleRef.current = wasmModule;
      
      // Also set up a custom message handler after module initialization
      //@ts-ignore
      if (wasmModule.PThread) {
              //@ts-ignore

        const originalReceiveObjectTransfer = wasmModule.PThread.receiveObjectTransfer;
              //@ts-ignore

       
      }
      
      if (typeof window !== 'undefined') {
        (window as any).Module = wasmModule;
      }
      
    } catch (error) {
      console.error('Failed to load WebAssembly module:', error);
      setStatus(`Failed to load WebAssembly module: ${error}`);
      setIsLoading(false);
    }
  };

  initializeModule();
}, [maxLogEntries]);


  // Update canvas when it changes
  useEffect(() => {
    if (moduleRef.current && canvas) {
      try {
        if ('setCanvas' in moduleRef.current) {
          (moduleRef.current as any).setCanvas(canvas);
        }
      } catch (error) {
        console.error('Failed to update canvas:', error);
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

// Convenience hook for components that need to set their canvas
export const useWebAssemblyCanvas = (canvasRef: RefObject<HTMLCanvasElement | null>) => {
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
