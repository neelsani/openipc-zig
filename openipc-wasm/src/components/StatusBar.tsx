import React, { useState, useEffect, useRef } from 'react';
import { Loader2, CheckCircle, XCircle, Signal, Video, Wifi, Package } from 'lucide-react';
import { useWebAssemblyContext } from '../contexts/WasmContext';

interface DataPoint {
  timestamp: number;
  value: number;
}

const MiniGraph: React.FC<{ 
  data: DataPoint[], 
  color: string, 
  minVal: number, 
  maxVal: number 
}> = ({ data, color, minVal, maxVal }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || data.length < 2) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width, height } = canvas;
    ctx.clearRect(0, 0, width, height);

    const pointWidth = width / (data.length - 1);
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();

    data.forEach((point, index) => {
      const x = index * pointWidth;
      const normalizedValue = Math.max(0, Math.min(1, (point.value - minVal) / (maxVal - minVal)));
      const y = height - (normalizedValue * height);
      
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    
    ctx.stroke();

    // Enhanced gradient fill
    const gradient = ctx.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, color + '40');
    gradient.addColorStop(1, color + '10');
    
    ctx.fillStyle = gradient;
    ctx.lineTo(width, height);
    ctx.lineTo(0, height);
    ctx.closePath();
    ctx.fill();
  }, [data, color, minVal, maxVal]);

  return (
    <canvas 
      ref={canvasRef}
      width={60}
      height={24}
      className="w-15 h-6 rounded-sm mx-auto"
    />
  );
};

export const StatusBar = () => {
  const { status, isLoading, webCodecsSupported, stats } = useWebAssemblyContext();
  const [rssiHistory, setRssiHistory] = useState<DataPoint[]>([]);
  const [snrHistory, setSnrHistory] = useState<DataPoint[]>([]);
  const [bitrateHistory, setBitrateHistory] = useState<DataPoint[]>([]);

  useEffect(() => {
    const now = Date.now();
    const maxPoints = 20;
    
    setRssiHistory(prev => [...prev, { timestamp: now, value: stats.rssi }].slice(-maxPoints));
    setSnrHistory(prev => [...prev, { timestamp: now, value: stats.snr }].slice(-maxPoints));
    setBitrateHistory(prev => [...prev, { timestamp: now, value: stats.bitrate }].slice(-maxPoints));
  }, [stats.rssi, stats.snr, stats.bitrate]);

  const getSignalBars = (rssi: number) => {
    if (rssi > -50) return { bars: 4, color: 'bg-emerald-500' };
    if (rssi > -60) return { bars: 3, color: 'bg-green-400' };
    if (rssi > -70) return { bars: 2, color: 'bg-yellow-500' };
    return { bars: 1, color: 'bg-red-500' };
  };

  const signal = getSignalBars(stats.rssi);

  const formatValue = (value: number, unit: string) => {
    if (unit === 'dBm') return `${value} ${unit}`;
    if (unit === 'Mbps') return `${value.toFixed(1)} ${unit}`;
    if (unit === 'dB') return `${value.toFixed(1)} ${unit}`;
    if (unit === 'packets') {
      return value > 999 ? `${(value / 1000).toFixed(1)}k` : value.toString();
    }
    return value.toString();
  };

  return (
    <div className="bg-gradient-to-br from-white to-gray-50 border border-gray-200 rounded-lg shadow-sm p-4">
      {/* Header Section */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            {isLoading && <Loader2 className="w-4 h-4 animate-spin text-blue-500" />}
            <span className="text-gray-800 font-medium text-sm">{status}</span>
          </div>
        </div>
        
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-500">WebCodecs</span>
          {webCodecsSupported ? (
            <CheckCircle className="w-4 h-4 text-emerald-500" />
          ) : (
            <XCircle className="w-4 h-4 text-red-500" />
          )}
        </div>
      </div>

      {/* Metrics Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4">
        {/* Signal Strength */}
        <div className="p-3 text-center">
          <div className="flex items-center justify-center gap-2 mb-2">
            <Signal className="w-4 h-4 text-gray-600" />
            <span className="text-xs font-semibold text-gray-700 uppercase tracking-wide">Signal</span>
          </div>
          
          <MiniGraph 
            data={rssiHistory} 
            color="#ef4444" 
            minVal={-90} 
            maxVal={-30} 
          />
          
          <div className="mt-2">
            <div className="text-sm font-mono font-semibold text-gray-800">
              {formatValue(stats.rssi, 'dBm')}
            </div>
            <div className="flex justify-center gap-0.5 mt-2">
              {[1, 2, 3, 4].map((bar) => (
                <div
                  key={bar}
                  className={`w-1 rounded-sm transition-colors ${
                    bar <= signal.bars ? signal.color : 'bg-gray-200'
                  }`}
                  style={{ height: `${bar * 2 + 4}px` }}
                />
              ))}
            </div>
          </div>
        </div>

        {/* Bitrate */}
        <div className="p-3 text-center">
          <div className="flex items-center justify-center gap-2 mb-2">
            <Video className="w-4 h-4 text-blue-600" />
            <span className="text-xs font-semibold text-gray-700 uppercase tracking-wide">Bitrate</span>
          </div>
          
          <MiniGraph 
            data={bitrateHistory} 
            color="#3b82f6" 
            minVal={0} 
            maxVal={20} 
          />
          
          <div className="mt-2">
            <div className="text-sm font-mono font-semibold text-gray-800">
              {formatValue(stats.bitrate, 'Mbps')}
            </div>
            <div className="text-xs text-gray-500 mt-1">
              {stats.bitrate > 10 ? 'High' : stats.bitrate > 5 ? 'Good' : 'Low'}
            </div>
          </div>
        </div>

        {/* SNR */}
        <div className="p-3 text-center">
          <div className="flex items-center justify-center gap-2 mb-2">
            <Wifi className="w-4 h-4 text-teal-600" />
            <span className="text-xs font-semibold text-gray-700 uppercase tracking-wide">SNR</span>
          </div>
          
          <MiniGraph 
            data={snrHistory} 
            color="#06b6d4" 
            minVal={0} 
            maxVal={40} 
          />
          
          <div className="mt-2">
            <div className="text-sm font-mono font-semibold text-gray-800">
              {formatValue(stats.snr, 'dB')}
            </div>
            <div className="text-xs text-gray-500 mt-1">
              {stats.snr > 25 ? 'Excellent' : stats.snr > 15 ? 'Good' : 'Fair'}
            </div>
          </div>
        </div>

        {/* Packets */}
        <div className="p-3 text-center">
          <div className="flex items-center justify-center gap-2 mb-2">
            <Package className="w-4 h-4 text-purple-600" />
            <span className="text-xs font-semibold text-gray-700 uppercase tracking-wide">Packets</span>
          </div>
          
          <div className="w-15 h-6 bg-gradient-to-r from-purple-100 to-purple-200 rounded-sm flex items-center justify-center mx-auto">
            <div className="w-2 h-2 bg-purple-500 rounded-full animate-pulse"></div>
          </div>
          
          <div className="mt-2">
            <div className="text-sm font-mono font-semibold text-gray-800">
              {formatValue(stats.packetCount, 'packets')}
            </div>
            <div className="text-xs text-gray-500 mt-1">
              Total received
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
