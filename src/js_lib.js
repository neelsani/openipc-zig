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
}

});
