import { useState, useCallback } from 'react';
import type { Device } from '../types/device';
import { useWebAssemblyContext } from '../contexts/WasmContext';

export const useDeviceManager = (
  
) => {
  const [devices, setDevices] = useState<Device[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<Device | null>(null);
  const {module, setStatus} = useWebAssemblyContext()
  const loadDevices = useCallback(async () => {
    if (!module) return;

    try {
      const deviceList = await module.getDeviceList();
      const deviceArray: Device[] = [];

      for (let i = 0; i < deviceList.size(); i++) {
        const device = deviceList.get(i);
        if (device != undefined) {
          deviceArray.push({
            index: i,
            vendor_id: device.vendor_id,
            product_id: device.product_id,
            display_name: device.display_name.toString(),
            bus_num: device.bus_num,
            port_num: device.port_num
        });
        }
        
      }

      deviceList.delete();
      setDevices(deviceArray);

      if (deviceArray.length > 0) {
        setStatus('Select a device to continue');
      } else {
        setStatus('No devices detected - Click Request Device');
      }
    } catch (error) {
      console.error('Error loading devices:', error);
      setDevices([]);
      setStatus('Error loading devices');
    }
  }, [module, setStatus]);

  const selectDevice = useCallback((device: Device) => {
    setSelectedDevice(device);
    setStatus(`Device selected: ${device.display_name}`);
  }, [setStatus]);

  const requestDevice = useCallback(async () => {
    try {
        
      if (!navigator.usb) {
        alert('WebUSB is not supported in this browser');
        return;
      } 

      const device = await navigator.usb.requestDevice({
        filters: []
      });

      if (device) {
        window.location.reload();
      }
    } catch (error) {
      console.error('Device request failed:', error);
      alert('Device request failed: ' + (error as Error).message);
    }
  }, []);

  return {
    devices,
    selectedDevice,
    selectDevice,
    requestDevice,
    loadDevices
  };
};
