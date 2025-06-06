import  { forwardRef } from 'react';
import type { VideoStats } from '../types/device';
import { Monitor, Activity } from 'lucide-react';

interface VideoCanvasProps {
  stats: VideoStats;
}

export const VideoCanvas = forwardRef<HTMLCanvasElement, VideoCanvasProps>(
  ({ stats }, ref) => {
    return (
      <div className="bg-white rounded-lg shadow-md p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
          <Monitor className="w-5 h-5" />
          Video Stream
        </h3>
        
        <div className="bg-black rounded-lg p-4">
          <canvas
            ref={ref}
            id="videoCanvas"
            width={1920}
            height={1080}
            className="w-full h-auto max-h-96 border-2 border-gray-700 rounded"
          />
          
          <div className="flex justify-between items-center mt-4 text-sm text-gray-300">
            <span className="flex items-center gap-2">
              <Activity className="w-4 h-4" />
              {stats.resolution || 'No video'}
            </span>
            <span>{stats.fps.toFixed(1)} FPS</span>
          </div>
        </div>
      </div>
    );
  }
);

VideoCanvas.displayName = 'VideoCanvas';
