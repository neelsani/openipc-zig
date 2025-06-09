import { useEffect, useRef, useState } from 'react';
import { Monitor, Activity, Maximize, Minimize } from 'lucide-react';
import { useWebAssemblyContext } from '../contexts/WasmContext';

export const VideoCanvas = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const { stats, setCanvas } = useWebAssemblyContext();
  
  useEffect(() => {
    console.log("setting canvas")
    if (canvasRef.current) {
      setCanvas(canvasRef.current);
    }
  }, [setCanvas]);

  const toggleFullscreen = async () => {
    const container = containerRef.current;
    if (!container) return;

    if (!document.fullscreenElement) {
      try {
        await container.requestFullscreen();
        setIsFullscreen(true);
      } catch (error) {
        console.error('Error entering fullscreen:', error);
      }
    } else {
      await document.exitFullscreen();
      setIsFullscreen(false);
    }
  };

  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };

    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
  }, []);

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
        <Monitor className="w-5 h-5" />
        Video Stream
      </h3>
      
      <div 
        ref={containerRef}
        className={`
          relative bg-black rounded-lg overflow-hidden
          ${isFullscreen 
            ? 'fixed inset-0 z-50 w-screen h-screen rounded-none' 
            : 'p-4'
          }
        `}
      >
        {/* Canvas element */}
        <canvas
          ref={canvasRef}
          id="videoCanvas"
          width={1920}
          height={1080}
          className={`
            relative z-10 border-2 border-gray-700
            ${isFullscreen 
              ? 'absolute inset-0 w-full h-full max-w-none max-h-none border-none rounded-none object-cover' 
              : 'w-full h-auto max-h-96 rounded'
            }
          `}
        />
        
        {/* Fullscreen toggle button */}
        <button
          onClick={toggleFullscreen}
          className={`
            absolute p-2 bg-black bg-opacity-50 text-white rounded 
            hover:bg-opacity-75 transition-all duration-200 z-20
            ${isFullscreen ? 'top-4 right-4' : 'top-2 right-2'}
          `}
        >
          {isFullscreen ? <Minimize className="w-4 h-4" /> : <Maximize className="w-4 h-4" />}
        </button>
        
        {/* Stats overlay */}
        <div className={`
          flex justify-between items-center text-sm text-gray-300 z-20
          ${isFullscreen 
            ? 'absolute bottom-4 left-4 right-4 bg-black bg-opacity-70 p-4 rounded-lg' 
            : 'mt-4'
          }
        `}>
          <span className="flex items-center gap-2">
            <Activity className="w-4 h-4" />
            {stats.resolution || 'No video'}
          </span>
          <span>{stats.fps.toFixed(1)} FPS</span>
        </div>
      </div>
    </div>
  );
};
