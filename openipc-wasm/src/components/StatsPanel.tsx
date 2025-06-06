import React from 'react';
import type { VideoStats } from '../types/device';
import { BarChart3, Package, Film, Cpu } from 'lucide-react';

interface StatsPanelProps {
  stats: VideoStats;
}

export const StatsPanel: React.FC<StatsPanelProps> = ({ stats }) => {
  const statItems = [
    {
      label: 'Packets',
      value: stats.packetCount.toLocaleString(),
      icon: Package,
      color: 'text-blue-600'
    },
    {
      label: 'Frames',
      value: stats.frameCount.toLocaleString(),
      icon: Film,
      color: 'text-green-600'
    },
    {
      label: 'Codec',
      value: stats.codec || 'None',
      icon: Cpu,
      color: 'text-purple-600'
    }
  ];

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
        <BarChart3 className="w-5 h-5" />
        Statistics
      </h3>
      
      <div className="space-y-4">
        {statItems.map((item) => (
          <div key={item.label} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <div className="flex items-center gap-3">
              <item.icon className={`w-5 h-5 ${item.color}`} />
              <span className="font-medium text-gray-700">{item.label}</span>
            </div>
            <span className="font-mono text-lg font-semibold text-gray-900">
              {item.value}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};
