import React from 'react';
import type { Device } from '../types/device';
import { Wifi, UsbIcon, Plus } from 'lucide-react';

interface DeviceSelectorProps {
  devices: Device[];
  selectedDevice: Device | null;
  onSelectDevice: (device: Device) => void;
  onRequestDevice: () => void;
  isLoading: boolean;
}

export const DeviceSelector: React.FC<DeviceSelectorProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
  onRequestDevice,
  isLoading
}) => {
  if (devices.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow-md p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
          <UsbIcon className="w-5 h-5" />
          Device Selection
        </h3>
        <div className="text-center py-8">
          <UsbIcon className="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <p className="text-gray-500 mb-4">No devices detected</p>
          <button
            onClick={onRequestDevice}
            disabled={isLoading}
            className="bg-orange-500 hover:bg-orange-600 disabled:bg-gray-300 text-white px-6 py-2 rounded-lg font-medium transition-colors flex items-center gap-2 mx-auto"
          >
            <Plus className="w-4 h-4" />
            Request Device
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-md p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900 flex items-center gap-2">
          <Wifi className="w-5 h-5" />
          Available Devices ({devices.length})
        </h3>
        
        <button
          onClick={onRequestDevice}
          disabled={isLoading}
          className="bg-orange-500 hover:bg-orange-600 disabled:bg-gray-300 text-white px-4 py-2 rounded-lg font-medium transition-colors flex items-center gap-2 text-sm"
          title="Add another device"
        >
          <Plus className="w-4 h-4" />
          Add Device
        </button>
      </div>
      
      <div className="space-y-2">
        {devices.map((device) => (
          <div
            key={device.index}
            className={`p-4 rounded-lg border-2 cursor-pointer transition-all ${
              selectedDevice?.index === device.index
                ? 'border-blue-500 bg-blue-50'
                : 'border-gray-200 hover:border-gray-300 hover:bg-gray-50'
            }`}
            onClick={() => onSelectDevice(device)}
          >
            <div className="flex items-center gap-3">
              <input
                type="radio"
                name="device-selection"
                checked={selectedDevice?.index === device.index}
                onChange={() => onSelectDevice(device)}
                className="text-blue-600"
              />
              <div className="flex-1">
                <div className="font-medium text-gray-900">
                  {device.display_name}
                </div>
                <div className="text-sm text-gray-500 mt-1">
                  Vendor: 0x{device.vendor_id.toString(16).toUpperCase().padStart(4, '0')} | 
                  Product: 0x{device.product_id.toString(16).toUpperCase().padStart(4, '0')}
                </div>
                <div className="text-xs text-gray-400 mt-1">
                  Bus: {device.bus_num} | Port: {device.port_num}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
