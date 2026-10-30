# OpenIPC WiFi Video Receiver

A high-performance WiFi FPV video receiver implemented in Zig with WebAssembly support for browser-based operation and native desktop applications.

## 🚀 Features

- **Cross-Platform**: Works on Windows, Linux, macOS and in web browsers via WebAssembly
- **Video Formats**: H.264 and H.265 codec support
- **WiFi Protocols**: IEEE 802.11 frame processing with FEC (Forward Error Correction)
- **Low Latency**: Optimized RTP packet processing for real-time video streaming
- **WebUSB Support**: Direct USB device access in browsers for RTL8812AU/RTL8814AU adapters
- **Secure**: ChaCha20-Poly1305 encrypted communication
- **Modern UI**: React-based web interface with real-time statistics

## 📺 System Architecture

### Web Browser Flow
```
Air → USB WiFi → WebUSB → JavaScript → WASM(Zig) → RTP Processing → Canvas Rendering
```

### Native Application Flow  
```
Air → USB WiFi → Native Driver → Zig Processing → UDP RTP Output
```

## 🛠️ Building

### Prerequisites

- **Zig**: Version 0.15.0-dev.670+ (specified in `build.zig.zon`)
- **Emscripten**: For WebAssembly builds (automatically managed)
- **Node.js**: Version 20+ for web interface development
- **npm**: Package manager (comes with Node.js)
- **TypeScript**: Global installation required (`npm install -g typescript`)

### Build for WebAssembly (Browser)

```bash
# Install global TypeScript compiler (if not already installed)
npm install -g typescript

# Build the WASM module
zig build -Dtarget=wasm32-emscripten --release=small

# Build the web interface
cd openipc-wasm
npm install
npm run build
```

### Build for Native Desktop

```bash
# Debug build
zig build

# Release build  
zig build -Doptimize=ReleaseFast
```

### Development Server (Web)

```bash
cd openipc-wasm
npm run dev
```

## 🎮 Usage

### Web Interface

1. Open the web application in a modern browser
2. Load your encryption key (`gs.key` file)
3. Connect a compatible WiFi adapter (RTL8812AU/RTL8814AU)
4. Select WiFi channel and bandwidth
5. Click "Start Receiving" to begin video stream

### Native Application

```bash
./zig-out/bin/openipc-zig [options]
```

## 📋 Dependencies

### Core Libraries
- **libusb**: USB device communication
- **libsodium**: Cryptographic operations (ChaCha20-Poly1305)
- **WiFiDriver**: RTL8812AU/RTL8814AU device drivers

### Web Frontend
- **React 19**: Modern UI framework
- **TypeScript**: Type-safe development
- **Vite**: Fast build tooling
- **Tailwind CSS**: Utility-first styling
- **Lucide React**: Modern icon library

## 🏗️ Project Structure

```
├── src/
│   ├── main.zig                 # Core Zig application entry
│   ├── wrapper.cpp              # C++ WebAssembly bindings
│   ├── js_lib.js               # JavaScript library integration
│   ├── wifi/                   # WiFi processing (C++)
│   │   ├── WfbProcessor.cpp    # WFB packet aggregation
│   │   ├── WfbReceiver.cpp     # WiFi frame reception
│   │   ├── fec.c              # Forward Error Correction
│   │   └── Rtp.h              # RTP protocol handling
│   └── zig/                    # Core Zig modules
│       ├── wfbprocessor.zig    # WFB processing logic
│       ├── RxFrame.zig         # Frame parsing
│       ├── rtp/                # RTP handling
│       └── os/                 # Platform abstraction
├── openipc-wasm/              # React web interface
│   ├── src/
│   │   ├── components/        # UI components
│   │   ├── contexts/          # React contexts
│   │   ├── hooks/             # Custom hooks
│   │   └── wasm/              # Generated WASM files
│   └── public/                # Static assets
└── build.zig                  # Build configuration
```

## 🔧 Supported Hardware

### WiFi Adapters
- RTL8812AU based adapters
- RTL8814AU based adapters
- USB 3.0 recommended for optimal performance

### Tested Browsers
- Chrome/Chromium 89+
- Firefox 89+
- Safari 14.1+
- Edge 89+

## 🛡️ Security

- End-to-end encryption using ChaCha20-Poly1305
- Session key exchange with epoch validation
- Channel ID verification for packet filtering

## 📊 Performance

- **Latency**: < 50ms typical (air to display)
- **Throughput**: Up to 50 Mbps video streams
- **Optimal Settings**: 1080p 30fps at 1024 kbps bitrate for best performance
- **Bitrate Limitations**: Video display may have issues above 1024 kbps bitrate
- **FEC Recovery**: Automatic error correction for lost packets
- **Multi-threading**: Parallel processing for optimal performance

### Recommended OpenIPC Settings

For optimal performance with this receiver:
- **Resolution**: 1920x1080 (1080p)
- **Frame Rate**: 30 fps
- **Bitrate**: 1024 kbps (higher bitrates may cause display issues)
- **Encoder**: H.264 or H.265

## 🐛 Troubleshooting

### Common Issues

1. **No devices detected**: Ensure WebUSB is enabled and adapter is supported
2. **Key loading fails**: Verify `gs.key` file format and permissions
3. **Video not displaying**: Check channel settings and signal strength
4. **High latency**: Try different USB ports or reduce channel width

### Debug Mode

Enable debug logging when building:
```bash
zig build -Dlogging=true -Ddebug-logging=true
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**.

See the full license text in the [LICENSE](./LICENSE) file.

### Third-Party Components

The following third-party components are included in this project and are also licensed under GPLv3-compatible licenses:

- **wfb-ng** (WiFi Broadcast next generation) - GPLv3 — see [src/wifi/](src/wifi/) for the embedded source code
- **zfec** (forward error correction library) - GPLv2 or later — see `src/wifi/fec.h` for the copyright notice

All source code in this repository is covered by the GPLv3 license.

## 🔗 Related Projects

- [OpenIPC](https://openipc.org/) - Open IP Camera project
- [wfb-ng](https://github.com/svpcom/wfb-ng) - WiFi Broadcast next generation
- [Emscripten](https://emscripten.org/) - WebAssembly compilation toolchain

## 📞 Support

- Issues: Use GitHub Issues for bug reports and feature requests
- Discussions: GitHub Discussions for general questions
- Documentation: Check the wiki for detailed setup guides