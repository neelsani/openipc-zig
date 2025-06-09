import React, { useState, useEffect, useRef } from 'react';
import { Loader2, CheckCircle, XCircle, Signal, Video, Wifi, Package } from 'lucide-react';
import { useWebAssemblyContext } from '../contexts/WasmContext';

interface DataPoint {
  timestamp: number;
  value: number;
}

interface MetricConfig {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  color: string;
  minVal: number;
  maxVal: number;
  unit: string;
  iconColor: string;
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

    // Draw line
    const pointWidth = width / (data.length - 1);
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.beginPath();

    data.forEach((point, index) => {
      const x = index * pointWidth;
      const normalizedValue = Math.max(0, Math.min(1, (point.value - minVal) / (maxVal - minVal)));
      const y = height - (normalizedValue * height);
      
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    
    ctx.stroke();

    // Fill area under curve
    const gradient = ctx.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, color + '20');
    gradient.addColorStop(1, color + '05');
    
    ctx.fillStyle = gradient;
    ctx.lineTo(width, height);
    ctx.lineTo(0, height);
    ctx.closePath();
    ctx.fill();
  }, [data, color, minVal, maxVal]);

  return (
    <canvas 
      ref={canvasRef}
      width={80}
      height={24}
      className="w-20 h-6 rounded"
    />
  );
};

const MetricCard: React.FC<{
  config: MetricConfig;
  value: number;
  history: DataPoint[];
  getQualityLabel: (value: number) => string;
}> = ({ config, value, history, getQualityLabel }) => {
  const Icon = config.icon;
  
  return (
    <div className="text-center">
      <div className="flex items-center justify-center gap-2 mb-2">
        <Icon className={`w-4 h-4 ${config.iconColor}`} />
        <span className="text-sm font-medium text-gray-700">{config.label}</span>
      </div>
      
      <div className="flex justify-center mb-2">
        <MiniGraph 
          data={history} 
          color={config.color} 
          minVal={config.minVal} 
          maxVal={config.maxVal} 
        />
      </div>
      
      <div>
        <div className="text-sm font-mono font-semibold text-gray-800">
          {formatValue(value, config.unit)}
        </div>
        <div className="text-xs text-gray-500">
          {getQualityLabel(value)}
        </div>
      </div>
    </div>
  );
};

const SignalBars: React.FC<{ rssi: number }> = ({ rssi }) => {
  const getSignalBars = (rssi: number) => {
    if (rssi > -50) return { bars: 4, color: 'bg-green-500' };
    if (rssi > -60) return { bars: 3, color: 'bg-yellow-500' };
    if (rssi > -70) return { bars: 2, color: 'bg-orange-500' };
    return { bars: 1, color: 'bg-red-500' };
  };

  const signal = getSignalBars(rssi);

  return (
    <div className="flex justify-center items-end gap-1 mt-1" style={{ height: '16px' }}>
      {[1, 2, 3, 4].map((bar) => (
        <div
          key={bar}
          className={`w-1.5 rounded-sm transition-colors ${
            bar <= signal.bars ? signal.color : 'bg-gray-200'
          }`}
          style={{ height: `${bar * 3 + 4}px` }}
        />
      ))}
    </div>
  );
};

const formatValue = (value: number, unit: string): string => {
  switch (unit) {
    case 'dBm':
      return `${value} ${unit}`;
    case 'Mbps':
      return `${value.toFixed(3)} ${unit}`;
    case 'dB':
      return `${value.toFixed(1)} ${unit}`;
    case 'packets':
      return value > 999 ? `${(value / 1000).toFixed(1)}k` : value.toString();
    default:
      return value.toString();
  }
};

export const StatusBar: React.FC = () => {
  const { status, isLoading, webCodecsSupported, stats } = useWebAssemblyContext();
  
  // State for metric histories
  const [rssiHistory, setRssiHistory] = useState<DataPoint[]>([]);
  const [snrHistory, setSnrHistory] = useState<DataPoint[]>([]);
  const [rtpBitrateHistory, setRtpBitrateHistory] = useState<DataPoint[]>([]);
  const [videoBitrateHistory, setVideoBitrateHistory] = useState<DataPoint[]>([]);

  // Metric configurations
  const metrics: Record<string, MetricConfig> = {
    signal: {
      icon: Signal,
      label: 'Signal',
      color: '#ef4444',
      minVal: -127,
      maxVal: 0,
      unit: 'dBm',
      iconColor: 'text-gray-600'
    },
    rtp: {
      icon: Wifi,
      label: 'RTP',
      color: '#3b82f6',
      minVal: 0,
      maxVal: 20,
      unit: 'Mbps',
      iconColor: 'text-blue-600'
    },
    video: {
      icon: Video,
      label: 'Video',
      color: '#8b5cf6',
      minVal: 0,
      maxVal: 20,
      unit: 'Mbps',
      iconColor: 'text-purple-600'
    },
    snr: {
      icon: Package,
      label: 'SNR',
      color: '#06b6d4',
      minVal: 0,
      maxVal: 40,
      unit: 'dB',
      iconColor: 'text-teal-600'
    }
  };

  // Quality assessment functions
  const getQualityLabels = {
    rtp: (value: number) => value > 10 ? 'High' : value > 5 ? 'Good' : 'Low',
    video: (value: number) => value > 10 ? 'High' : value > 5 ? 'Good' : 'Low',
    snr: (value: number) => value > 25 ? 'Excellent' : value > 15 ? 'Good' : 'Fair'
  };

  // Update metric histories
  useEffect(() => {
    const now = Date.now();
    const maxPoints = 20;
    
    const updateHistory = (setter: React.Dispatch<React.SetStateAction<DataPoint[]>>, value: number) => {
      setter(prev => [...prev, { timestamp: now, value }].slice(-maxPoints));
    };

    updateHistory(setRssiHistory, stats.rssi);
    updateHistory(setSnrHistory, stats.snr);
    updateHistory(setRtpBitrateHistory, stats.rtp_bitrate);
    updateHistory(setVideoBitrateHistory, stats.video_bitrate);
  }, [stats.rssi, stats.snr, stats.rtp_bitrate, stats.video_bitrate]);

  return (
    <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-4">
      <div className="flex items-center justify-between">
        
        {/* Status Section */}
        <div >
          {isLoading && <Loader2 className=" animate-spin text-blue-500" />}
          <span className="text-gray-800 font-medium">{status}</span>
        </div>

        {/* Metrics Grid */}
        <div className="grid grid-cols-4 gap-12">
          
          {/* Signal Strength - Special handling for bars */}
          <div className="text-center">
            <div className="flex items-center justify-center gap-2 mb-2">
              <Signal className="w-4 h-4 text-gray-600" />
              <span className="text-sm font-medium text-gray-700">Signal</span>
            </div>
            
            <div className="flex justify-center mb-2">
              <MiniGraph 
                data={rssiHistory} 
                color={metrics.signal.color} 
                minVal={metrics.signal.minVal} 
                maxVal={metrics.signal.maxVal} 
              />
            </div>
            
            <div>
              <div className="text-sm font-mono font-semibold text-gray-800">
                {formatValue(stats.rssi, 'dBm')}
              </div>
              <SignalBars rssi={stats.rssi} />
            </div>
          </div>

          {/* RTP Bitrate */}
          <MetricCard
            config={metrics.rtp}
            value={stats.rtp_bitrate}
            history={rtpBitrateHistory}
            getQualityLabel={getQualityLabels.rtp}
          />

          {/* Video Bitrate */}
          <MetricCard
            config={metrics.video}
            value={stats.video_bitrate}
            history={videoBitrateHistory}
            getQualityLabel={getQualityLabels.video}
          />

          {/* SNR */}
          <MetricCard
            config={metrics.snr}
            value={stats.snr}
            history={snrHistory}
            getQualityLabel={getQualityLabels.snr}
          />

        </div>

        {/* WebCodecs Status */}
        <div className="flex items-center gap-2">
          <span className="text-sm text-gray-600">WebCodecs</span>
          {webCodecsSupported ? (
            <CheckCircle className="w-4 h-4 text-green-500" />
          ) : (
            <XCircle className="w-4 h-4 text-red-500" />
          )}
        </div>

      </div>
    </div>
  );
};
