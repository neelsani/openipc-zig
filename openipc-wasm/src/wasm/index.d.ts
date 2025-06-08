// TypeScript bindings for emscripten-generated code.  Automatically generated at compile time.
declare namespace RuntimeExports {
    /**
     * @param {string|null=} returnType
     * @param {Array=} argTypes
     * @param {Arguments|Array=} args
     * @param {Object=} opts
     */
    function ccall(ident: any, returnType?: (string | null) | undefined, argTypes?: any[] | undefined, args?: (Arguments | any[]) | undefined, opts?: any | undefined): any;
    /**
     * @param {string=} returnType
     * @param {Array=} argTypes
     * @param {Object=} opts
     */
    function cwrap(ident: any, returnType?: string | undefined, argTypes?: any[] | undefined, opts?: any | undefined): (...args: any[]) => any;
    /**
     * Given a pointer 'ptr' to a null-terminated UTF8-encoded string in the
     * emscripten HEAP, returns a copy of that string as a Javascript String object.
     *
     * @param {number} ptr
     * @param {number=} maxBytesToRead - An optional length that specifies the
     *   maximum number of bytes to read. You can omit this parameter to scan the
     *   string until the first 0 byte. If maxBytesToRead is passed, and the string
     *   at [ptr, ptr+maxBytesToReadr[ contains a null byte in the middle, then the
     *   string will cut short at that byte index (i.e. maxBytesToRead will not
     *   produce a string of exact length [ptr, ptr+maxBytesToRead[) N.B. mixing
     *   frequent uses of UTF8ToString() with and without maxBytesToRead may throw
     *   JS JIT optimizations off, so it is worth to consider consistently using one
     * @return {string}
     */
    function UTF8ToString(ptr: number, maxBytesToRead?: number | undefined): string;
    function lengthBytesUTF8(str: any): number;
    function stringToUTF8(str: any, outPtr: any, maxBytesToWrite: any): any;
    namespace PThread {
        let unusedWorkers: any[];
        let runningWorkers: any[];
        let tlsInitFunctions: any[];
        let pthreads: {};
        let nextWorkerID: number;
        function init(): void;
        function initMainThread(): void;
        function terminateAllThreads(): void;
        function returnWorkerToPool(worker: any): void;
        function threadInitTLS(): void;
        function loadWasmModuleToWorker(worker: any): any;
        function loadWasmModuleToAllWorkers(onMaybeReady: any): any;
        function allocateUnusedWorker(): void;
        function getNewWorker(): any;
    }
    let HEAPU8: any;
}
interface WasmModule {
  _main(_0: number, _1: number): number;
}

type EmbindString = ArrayBuffer|Uint8Array|Uint8ClampedArray|Int8Array|string;
export interface ClassHandle {
  isAliasOf(other: ClassHandle): boolean;
  delete(): void;
  deleteLater(): this;
  isDeleted(): boolean;
  // @ts-ignore - If targeting lower than ESNext, this symbol might not exist.
  [Symbol.dispose](): void;
  clone(): this;
}
export type DeviceId = {
  vendor_id: number,
  product_id: number,
  display_name: EmbindString,
  bus_num: number,
  port_num: number
};

export interface DeviceIdVector extends ClassHandle {
  push_back(_0: DeviceId): void;
  resize(_0: number, _1: DeviceId): void;
  size(): number;
  get(_0: number): DeviceId | undefined;
  set(_0: number, _1: DeviceId): boolean;
}

export interface ChannelWidthValue<T extends number> {
  value: T;
}
export type ChannelWidth = ChannelWidthValue<0>|ChannelWidthValue<1>|ChannelWidthValue<2>|ChannelWidthValue<3>|ChannelWidthValue<4>|ChannelWidthValue<5>|ChannelWidthValue<6>|ChannelWidthValue<7>;

interface EmbindModule {
  DeviceIdVector: {
    new(): DeviceIdVector;
  };
  getDeviceList(): DeviceIdVector;
  stopReceiver(): void;
  sendRaw(): void;
  startReceiver(_0: number, _1: ChannelWidth, _2: number): void;
  ChannelWidth: {CHANNEL_WIDTH_20: ChannelWidthValue<0>, CHANNEL_WIDTH_40: ChannelWidthValue<1>, CHANNEL_WIDTH_80: ChannelWidthValue<2>, CHANNEL_WIDTH_160: ChannelWidthValue<3>, CHANNEL_WIDTH_80_80: ChannelWidthValue<4>, CHANNEL_WIDTH_5: ChannelWidthValue<5>, CHANNEL_WIDTH_10: ChannelWidthValue<6>, CHANNEL_WIDTH_MAX: ChannelWidthValue<7>};
}

export type MainModule = WasmModule & typeof RuntimeExports & EmbindModule;
export default function MainModuleFactory (options?: unknown): Promise<MainModule>;
