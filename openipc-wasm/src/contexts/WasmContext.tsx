import React, { createContext, useContext, useState, useEffect, useRef, type ReactNode, type RefObject } from 'react';
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
  updateStats: (newStats: Partial<LinkStats>) => void;
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

  const updateStats = (newStats: Partial<LinkStats>) => {
    setStats(prevStats => ({
      ...prevStats,
      ...newStats
    }));
  };

  // Initialize WebCodecs support check
  useEffect(() => {
    setWebCodecsSupported(typeof VideoDecoder !== 'undefined');
  }, []);

  // Initialize WebAssembly module once
  useEffect(() => {
    const initializeModule = async () => {
      if (moduleRef.current) return; // Prevent re-initialization

      try {
        const moduleConfig = {
          canvas: null, // Will be set later via setCanvas
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
          onRuntimeInitialized: () => {
            setIsLoading(false);
            setStatus('Ready - Loading device list...');
          }
        };

        const wasmModule = await MainModuleFactory(moduleConfig);
        moduleRef.current = wasmModule;
      } catch (error) {
        console.error('Failed to load WebAssembly module:', error);
        setStatus(`Failed to load WebAssembly module: ${error}`);
        setIsLoading(false);
      }
    };

    initializeModule();
  }, [maxLogEntries]); // Include maxLogEntries in dependency array

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
    updateStats
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
