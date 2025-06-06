import { useState, useCallback } from 'react';
import type { VideoStats } from '../types/device';

export const useVideoStats = () => {
  const [stats, setStats] = useState<VideoStats>({
    packetCount: 0,
    frameCount: 0,
    fps: 0,
    codec: 'None',
    resolution: 'No video'
  });

  const updateStats = useCallback((newStats: Partial<VideoStats>) => {
    setStats(prev => ({ ...prev, ...newStats }));
  }, []);

  return {
    stats,
    updateStats
  };
};
