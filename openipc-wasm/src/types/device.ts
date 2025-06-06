export interface Device {
  index: number;
  vendor_id: number;
  product_id: number;
  display_name: string;
  bus_num: number;
  port_num: number;
}

export interface VideoStats {
  packetCount: number;
  frameCount: number;
  fps: number;
  codec?: string;
  resolution?: string;
}

export interface EmscriptenModule {
  canvas: HTMLCanvasElement;
  print: (text: string) => void;
  printErr: (text: string) => void;
  setStatus: (text: string) => void;
  onRuntimeInitialized: () => void;
  ccall: (name: string, returnType: string, argTypes: string[], args: any[], options?: any) => any;
  getDeviceList: () => any;
  updateVideoResolution?: (width: number, height: number) => void;
}
