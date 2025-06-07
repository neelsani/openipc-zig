import { useState, useEffect } from 'react';

import { useDeviceManager } from './hooks/useDeviceManager.ts';
import { DeviceSelector } from './components/DeviceSelector';
import { StatusBar } from './components/StatusBar.tsx';
import { ControlPanel } from './components/ControlPanel.tsx';
import { StatsPanel } from './components/StatsPanel.tsx';
import { VideoCanvas } from './components/VideoCanvas.tsx';
import { OutputConsole } from './components/OutputConsole.tsx';
import { useWebAssemblyContext } from './contexts/WasmContext.tsx';

function App() {
  const [isReceiving, setIsReceiving] = useState(false);
  const [selectedChannel, setSelectedChannel] = useState<number | null>(161);
  const [selectedChannelWidth, setSelectedChannelWidth] = useState<string>('CHANNEL_WIDTH_20');
  
  const { 
    module, 
    isLoading, 
    setStatus,
    outputLog,
  } = useWebAssemblyContext();
  
  const {
    devices,
    selectedDevice,
    selectDevice,
    requestDevice,
    loadDevices
  } = useDeviceManager();
  

  useEffect(() => {
    if (module) {
      loadDevices();
    }
  }, [module, loadDevices]);

  // Early return if module is not loaded
  if (!module) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div>Loading WebAssembly module...</div>
      </div>
    );
  }

  const handleStart = async () => {
    if (!selectedDevice || !module || !selectedChannel || !selectedChannelWidth) return;
    
    setIsReceiving(true);
    setStatus('Starting receiver...');
    
    try {
      
      module.startReceiver(
        selectedDevice.index, 
        module.ChannelWidth[selectedChannelWidth as keyof typeof module.ChannelWidth], 
        selectedChannel
      );
      setStatus('Receiver started - Waiting for video...');
    } catch (error) {
      console.error('Failed to start receiver:', error);
      setStatus('Start failed - see console');
      setIsReceiving(false);
    }
  };

  const handleStop = async () => {
    if (!module) return;
    
    setStatus('Stopping receiver...');
    
    try {
      module.stopReceiver();
      
      setStatus('Receiver stopped');
      setIsReceiving(false);
    } catch (error) {
      console.error('Failed to stop receiver:', error);
      setStatus('Stop failed - see console');
    }
  };

  const channelOptions = Array.from({length: 177}, (_, i) => i + 1);
  const channelWidthKeys = (Object.keys(module.ChannelWidth) as Array<keyof typeof module.ChannelWidth>).filter(val=>typeof val === 'string' && val.startsWith('CHANNEL_WIDTH_'));
  
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto p-6">
        <header className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            OpenIPC Wasm Reciever (RTP/H.264/H.265)
          </h1>
          <StatusBar />
        </header>

        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          {/* Left Column - Controls and Device Selection */}
          <div className="xl:col-span-1 space-y-6">
            <DeviceSelector
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={selectDevice}
              onRequestDevice={requestDevice}
              isLoading={isLoading}
            />
         {module ? (
  <>
    {/* Channel Selector */}
    <div className="bg-white rounded-lg shadow p-4">
      <label className="block text-sm font-medium text-gray-700 mb-2">
        Channel Selection
      </label>
      <select
        value={selectedChannel || ''}
        onChange={(e) => setSelectedChannel(e.target.value ? Number(e.target.value) : null)}
        className="border rounded p-2 w-full"
        disabled={isLoading || isReceiving}
      >
        <option value="">Select a channel...</option>
        {channelOptions.map((channel) => (
          <option key={channel} value={channel}>
            Channel {channel}
          </option>
        ))}
      </select>
    </div>

    {/* Channel Width Selector */}
    <div className="bg-white rounded-lg shadow p-4">
      <label className="block text-sm font-medium text-gray-700 mb-2">
        Channel Width
      </label>
      <select
        value={selectedChannelWidth}
        onChange={(e) => setSelectedChannelWidth(e.target.value)}
        className="border rounded p-2 w-full"
        disabled={isLoading || isReceiving}
      >
        <option value="">Select channel width...</option>
        {channelWidthKeys.map((width) => (
          <option key={width} value={width}>
            {width}
          </option>
        ))}
      </select>
    </div>
  </>
) : null}
            <ControlPanel
              onStart={handleStart}
              onStop={handleStop}
              canStart={!!selectedDevice && !isReceiving && selectedChannel !== null && selectedChannelWidth !== ''}
              canStop={isReceiving}
              disabled={isLoading}
            />
            
            <StatsPanel />
          </div>

          {/* Right Column - Video and Console */}
          <div className="xl:col-span-2 space-y-6">
            <VideoCanvas 
              
            />
            
            <OutputConsole 
              output={outputLog}
              className="h-80"
            />
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
