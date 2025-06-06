import { useState, useEffect } from 'react';

import { useDeviceManager } from './hooks/useDeviceManager.ts';
import { useVideoStats } from './hooks/useVideoStats.ts';
import { DeviceSelector } from './components/DeviceSelector';
import { StatusBar } from './components/StatusBar.tsx';
import { ControlPanel } from './components/ControlPanel.tsx';
import { StatsPanel } from './components/StatsPanel.tsx';
import { VideoCanvas } from './components/VideoCanvas.tsx';
import { OutputConsole } from './components/OutputConsole.tsx';
import { useWebAssemblyContext } from './contexts/WasmContext.tsx';

function App() {
  const [isReceiving, setIsReceiving] = useState(false);
  DeviceSelector
  const { 
    module, 
    isLoading, 
    status, 
    setStatus,
    webCodecsSupported,
    outputLog,
  } = useWebAssemblyContext();
  


  const {
    devices,
    selectedDevice,
    selectDevice,
    requestDevice,
    loadDevices
  } = useDeviceManager();
  
  const { stats, updateStats } = useVideoStats();

  useEffect(() => {
    if (module) {
      loadDevices();
    }
  }, [module, loadDevices]);

  const handleStart = async () => {
    if (!selectedDevice || !module) return;
    
    setIsReceiving(true);
    setStatus('Starting receiver...');
    
    try {
      updateStats({ packetCount: 0, frameCount: 0, fps: 0 });
      
      module.startReceiver(selectedDevice.index)
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

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto p-6">
        <header className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            OpenIPC Wasm Reciever (RTP/H.264/H.265)
          </h1>
          <StatusBar 
            status={status} 
            isLoading={isLoading} 
            webCodecsSupported={webCodecsSupported}
          />
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
            
            <ControlPanel
              onStart={handleStart}
              onStop={handleStop}
              canStart={!!selectedDevice && !isReceiving}
              canStop={isReceiving}
              disabled={isLoading}
            />
            
            <StatsPanel stats={stats} />
          </div>

          {/* Right Column - Video and Console */}
          <div className="xl:col-span-2 space-y-6">
            <VideoCanvas 
              stats={stats}
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
