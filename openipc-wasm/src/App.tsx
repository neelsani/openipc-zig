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
  const [hasKey, setHasKey] = useState(false);
  const [keyHash, setKeyHash] = useState<string>('');

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
  const computeKeyHash = (base64Key: string): Promise<string> => {
      try {
        // Decode base64 to bytes
        const binaryString = window.atob(base64Key);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        
        // Compute SHA-256 hash using Web Crypto API
        return crypto.subtle.digest('SHA-256', bytes).then(hashBuffer => {
          const hashArray = new Uint8Array(hashBuffer);
          const hashHex = Array.from(hashArray)
            .map(b => b.toString(16).padStart(2, '0'))
            .join('');
          return hashHex.substring(0, 8); // First 8 hex digits
        });
      } catch (error) {
        console.error('Error computing key hash:', error);
        return Promise.resolve('unknown');
      }
    };
  // Check for existing key on mount
useEffect(() => {
    const key = localStorage.getItem('gs.key');
    if (key) {
      setHasKey(true);
      computeKeyHash(key).then(hash => setKeyHash(hash));
    } else {
      setHasKey(false);
      setKeyHash('');
    }
  }, []);

  useEffect(() => {
    if (module) {
      loadDevices();
    }
  }, [module, loadDevices]);

  const handleKeyFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (e) => {
      const arrayBuffer = e.target?.result as ArrayBuffer;
      if (!arrayBuffer) return;

      // Convert ArrayBuffer to base64 string for storage
      const bytes = new Uint8Array(arrayBuffer);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]);
      }
      const base64String = window.btoa(binary);
      localStorage.setItem('gs.key', base64String);
      setHasKey(true);
      
      // Compute and set hash
      computeKeyHash(base64String).then(hash => setKeyHash(hash));
      setStatus('Key loaded successfully');
    };
    reader.readAsArrayBuffer(file);
  };

  const handleRemoveKey = () => {
    localStorage.removeItem('gs.key');
    setHasKey(false);
    setKeyHash('');
    setStatus('Key removed from cache');
  };

  // Early return if module is not loaded
  if (!module) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div>Loading WebAssembly module...</div>
      </div>
    );
  }

  const handleStart = async () => {
    if (!selectedDevice || !module || !selectedChannel || !selectedChannelWidth || !hasKey) return;
    
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
      <div className="max-w-6xl mx-auto p-6">
        <header className="mb-8 text-center">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            OpenIPC Wasm Reciever (RTP/H.264/H.265)
          </h1>
          <StatusBar />
        </header>


        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          {/* Left Column - Controls and Device Selection */}
          <div className="xl:col-span-1 space-y-6">
            {/* Key Management Section */}
           <div className="bg-white rounded-lg shadow p-4">
              <div className="flex items-center justify-between mb-2">
                <label className="block text-sm font-medium text-gray-700">
                  Ground Station Key
                </label>
                {hasKey && (
                  <button
                    onClick={handleRemoveKey}
                    className="text-xs text-red-600 hover:text-red-800 px-2 py-1 border border-red-300 rounded hover:bg-red-50"
                    disabled={isReceiving}
                  >
                    Remove Key
                  </button>
                )}
              </div>
              
              {!hasKey ? (
                <div>
                  <input
                    type="file"
                    accept="*"
                    onChange={handleKeyFileChange}
                    className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-medium file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
                    disabled={isReceiving}
                  />
                  <p className="text-xs text-gray-500 mt-1">
                    Select gs.key file to enable receiver
                  </p>
                </div>
              ) : (
                <div className="flex items-center justify-between">
                  <div className="flex items-center text-sm text-green-600">
                    <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                    </svg>
                    Key loaded
                  </div>
                  <div className="text-xs text-gray-500 font-mono bg-gray-100 px-2 py-1 rounded">
                    {keyHash || 'computing...'}
                  </div>
                </div>
              )}
            </div>


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
                    disabled={isLoading || isReceiving || !hasKey}
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
                    disabled={isLoading || isReceiving || !hasKey}
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
              canStart={!!selectedDevice && !isReceiving && selectedChannel !== null && selectedChannelWidth !== '' && hasKey}
              canStop={isReceiving}
              disabled={isLoading}
            />
            
            <StatsPanel />
          </div>

          {/* Right Column - Video and Console */}
          <div className="xl:col-span-2 space-y-6">
            <VideoCanvas />
            
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
