import React from 'react';
import { Play, Square } from 'lucide-react';

interface ControlPanelProps {
  onStart: () => void;
  onStop: () => void;
  canStart: boolean;
  canStop: boolean;
  disabled: boolean;
}

export const ControlPanel: React.FC<ControlPanelProps> = ({
  onStart,
  onStop,
  canStart,
  canStop,
  disabled
}) => {
  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Controls</h3>
      
      <div className="flex gap-3">
        <button
          onClick={onStart}
          disabled={!canStart || disabled}
          className="flex-1 bg-green-500 hover:bg-green-600 disabled:bg-gray-300 text-white px-4 py-3 rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
        >
          <Play className="w-5 h-5" />
          Start Receiver
        </button>
        
        <button
          onClick={onStop}
          disabled={!canStop || disabled}
          className="flex-1 bg-red-500 hover:bg-red-600 disabled:bg-gray-300 text-white px-4 py-3 rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
        >
          <Square className="w-5 h-5" />
          Stop Receiver
        </button>
      </div>
    </div>
  );
};
