export interface Device {
  index: number;
  vendor_id: number;
  product_id: number;
  display_name: string;
  bus_num: number;
  port_num: number;
}

export interface LinkStats {
  rssi: number,
  snr: number,
  packetCount: number;
  frameCount: number;
  fps: number;
  codec?: string;
  resolution?: string;
}



