// src/js_library.js
mergeInto(LibraryManager.library, {
    displayFrame: function(data_ptr, data_len, codec_type, is_key_frame) {
        if (!Module.videoSystem) {
            Module.videoSystem = {
                canvas: null,
                ctx: null,
                decoder: null,
                initialized: false
            };
        }
        
        if (!Module.videoSystem.initialized) {
            // Create canvas if it doesn't exist
            Module.videoSystem.canvas = document.getElementById('videoCanvas');
            if (!Module.videoSystem.canvas) {
                Module.videoSystem.canvas = document.createElement('canvas');
                Module.videoSystem.canvas.id = 'videoCanvas';
                Module.videoSystem.canvas.width = 1920;
                Module.videoSystem.canvas.height = 1080;
                Module.videoSystem.canvas.style.border = '1px solid #000';
                document.body.appendChild(Module.videoSystem.canvas);
            }
            Module.videoSystem.ctx = Module.videoSystem.canvas.getContext('2d');
            Module.videoSystem.initialized = true;
        }
        
        // Get frame data from WASM memory
        var frameData = new Uint8Array(Module.HEAPU8.buffer, data_ptr, data_len);
        
        // Initialize decoder if needed
        if (!Module.videoSystem.decoder) {
            var codec = codec_type === 0 ? 'avc1.42E01E' : 'hev1.1.6.L93.B0';
            
            try {
                Module.videoSystem.decoder = new VideoDecoder({
                    output: function(frame) {
                        var canvas = Module.videoSystem.canvas;
                        var ctx = Module.videoSystem.ctx;
                        
                        // Resize canvas if needed
                        if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
                            canvas.width = frame.displayWidth;
                            canvas.height = frame.displayHeight;
                        }
                        
                        // Draw frame
                        ctx.drawImage(frame, 0, 0);
                        frame.close();
                    },
                    error: function(error) {
                        console.error('Video decoder error:', error);
                    }
                });
                
                Module.videoSystem.decoder.configure({
                    codec: codec,
                    codedWidth: 1920,
                    codedHeight: 1080,
                    hardwareAcceleration: 'prefer-hardware'
                });
            } catch (error) {
                console.error('Failed to initialize video decoder:', error);
                return;
            }
        }
        
        // Decode frame
        try {
            var chunk = new EncodedVideoChunk({
                type: is_key_frame ? 'key' : 'delta',
                timestamp: performance.now() * 1000,
                data: frameData.slice() // Create a copy
            });
            
            Module.videoSystem.decoder.decode(chunk);
        } catch (error) {
            console.error('Failed to decode frame:', error);
        }
    },
    updateStatsCallback: function(rssi, snr, packet_count, frame_count, fps) {
        // This will be called from your Zig code
        if (Module.onStatsUpdate) {
            Module.onStatsUpdate(rssi, snr, packet_count, frame_count, fps);
        }
    }
  
});
