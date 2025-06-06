import { useState, useEffect, useRef, type RefObject } from 'react';
import type { EmscriptenModule } from '../types/device';

export const useWebAssembly = (
  canvasRef: RefObject<HTMLCanvasElement | null>,
  setOutputLog: (log: string) => void
) => {
  const [module, setModule] = useState<EmscriptenModule | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [status, setStatus] = useState('Loading WebAssembly...');
  const [webCodecsSupported, setWebCodecsSupported] = useState(false);
  const outputLogRef = useRef('');

  useEffect(() => {
    setWebCodecsSupported(typeof VideoDecoder !== 'undefined');

   const initializeModule = async () => {
  if (!canvasRef.current) {
    setStatus('Canvas not available');
    setIsLoading(false);
    return;
  }

  try {
    // Direct ES6 import
    const { default: createModule } = await import('../wasm/index.js');
    
    const moduleConfig = {
      canvas: canvasRef.current,
      print: (text: string) => {
        console.log(text);
        outputLogRef.current += text + '\n';
        setOutputLog(outputLogRef.current);
      },
      printErr: (text: string) => {
        console.error(text);
        outputLogRef.current += 'ERROR: ' + text + '\n';
        setOutputLog(outputLogRef.current);
      },
      setStatus: (text: string) => {
        setStatus(text);
      },
      onRuntimeInitialized: () => {
        setIsLoading(false);
        setStatus('Ready - Loading device list...');
      }
    };

    const wasmModule = await createModule(moduleConfig);
    setModule(wasmModule as EmscriptenModule);
    
  } catch (error) {
    console.error('Failed to load WebAssembly module:', error);
    setStatus(`Failed to load WebAssembly module: ${error}`);
    setIsLoading(false);
  }
};


    initializeModule();
  }, [canvasRef, setOutputLog]);

  return {
    module,
    isLoading,
    status,
    setStatus,
    webCodecsSupported
  };
};
