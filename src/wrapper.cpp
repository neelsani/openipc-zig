#include <iostream>
#include <vector>
#include "WfbReceiver.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#else
// Mock for non-Emscripten builds
#define EMSCRIPTEN_KEEPALIVE
#endif

WfbReceiver &receiver = WfbReceiver::Instance();

extern "C"
{
	EMSCRIPTEN_KEEPALIVE
	void startReceiver()
	{
		std::vector<DeviceId> devices = WfbReceiver::GetDeviceList();
		if (devices.empty())
		{
			std::cerr << "No devices found!" << std::endl;
			return;
		}
		std::cout << "Hello" << std::endl;
		const DeviceId &selectedDevice = devices[0];
		uint8_t channel = 161;
		int channelWidth = 1;
		std::string keyPath = "gs.key";

		if (!receiver.Start(selectedDevice, channel, channelWidth, keyPath))
		{
			std::cout << "Failed to start receiver!" << std::endl;
		}
		std::cout << "Hello" << std::endl;
	}

	EMSCRIPTEN_KEEPALIVE
	void stopReceiver()
	{
		receiver.Stop();
	}
}

int main()
{
// In WASM, main() doesn't need to block. Control is via JS.
#ifndef __EMSCRIPTEN__
	// Original blocking code for native builds
	startReceiver();
	std::cin.get();
	stopReceiver();
#endif

	return 0;
}