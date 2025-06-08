// src/js_library.js

addToLibrary( {
     displayFrame: function(data_ptr, data_len, codec_type, profile, is_key_frame) {
        // Check if we're in a pthread (Web Worker)
        if (typeof importScripts === 'function') {
            // We're in a worker - get frame data and send to main thread
            var frameData = new Uint8Array(Module.HEAPU8.buffer, data_ptr, data_len);
            var frameDataCopy = new Uint8Array(frameData); // Create a copy
            
            self.postMessage({
                cmd: 'callHandler',
                handler: 'displayFrameReact',
                args: [frameDataCopy, codec_type, profile, is_key_frame]
            });
        } 
    },
    onIEEFrame: function(rssi, snr) {
    // Check if we're in a pthread (Web Worker)
    if (typeof importScripts === 'function') {
        // We're in a worker - send message to main thread
        self.postMessage({
            cmd: 'callHandler',
            handler: 'FrameReact',
            args: [rssi, snr]
        });
    } else {
        // We're on main thread - direct call
        console.log(Module);
        if (!Module.FrameReact) {
            return;
        }
        Module.FrameReact(rssi, snr);
    }
    
},
 js_getKeyBuffer: function(lengthPtr) {
    const key = localStorage.getItem('gs.key');
    if (!key) {
      setValue(lengthPtr, 0, 'i32');
      return 0;
    }
    
    try {
      const binaryString = atob(key);
      const length = binaryString.length;
      const buffer = _malloc(length);
      
      if (!buffer) {
        setValue(lengthPtr, 0, 'i32');
        return 0;
      }
      
      const view = new Uint8Array(Module.HEAPU8.buffer, buffer, length);
      for (let i = 0; i < length; i++) {
        view[i] = binaryString.charCodeAt(i);
      }
      
      setValue(lengthPtr, length, 'i32');
      return buffer;
    } catch (e) {
      console.error('Failed to decode key:', e);
      setValue(lengthPtr, 0, 'i32');
      return 0;
    }
  },
  
  js_freeKeyBuffer: function(buffer) {
    if (buffer) {
      _free(buffer);
    }
  },
  
 
  
});
