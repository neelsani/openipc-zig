// src/wasm/index.d.ts
export interface EmscriptenModule {
  canvas: HTMLCanvasElement;
  print: (text: string) => void;
  printErr: (text: string) => void;
  setStatus: (text: string) => void;
  onRuntimeInitialized: () => void;
  ccall: (name: string, returnType: string, argTypes: string[], args: any[], options?: any) => any;
  cwrap: (name: string, returnType: string, argTypes: string[]) => (...args: any[]) => any;
  getDeviceList: () => any;
  locateFile?: (path: string) => string;
  HEAP8: Int8Array;
  HEAP16: Int16Array;
  HEAP32: Int32Array;
  HEAPU8: Uint8Array;
  HEAPU16: Uint16Array;
  HEAPU32: Uint32Array;
  HEAPF32: Float32Array;
  HEAPF64: Float64Array;
}

// For modularized Emscripten builds
export interface ModuleFactory {
  (moduleOverrides?: Partial<EmscriptenModule>): Promise<EmscriptenModule>;
}

// Default export for the factory function
declare const createModule: ModuleFactory;
export default createModule;
