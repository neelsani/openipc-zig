#include <iostream>
#include <vector>
#include "WfbReceiver.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/bind.h>
#else
#include <chrono>
#include <thread>
// Mock for non-Emscripten builds
#define EMSCRIPTEN_KEEPALIVE
#endif

WfbReceiver &receiver = WfbReceiver::Instance();

extern "C"
{

	void startReceiver(uint8_t i, ChannelWidth_t channelWidth, uint8_t channel)
	{

		std::vector<DeviceId>
			devices = WfbReceiver::GetDeviceList();
		if (devices.empty())
		{
			std::cerr << "No devices found!" << std::endl;
			return;
		}
		// std::cout << "Hello" << std::endl;
		const DeviceId &selectedDevice = devices[i];

		std::string keyPath = "gs.key";

		if (!receiver.Start(selectedDevice, channel, channelWidth, keyPath))
		{
			std::cout << "Failed to start receiver!" << std::endl;
		}
		std::cout << "Exiting startReciever" << std::endl;
	}

	void stopReceiver()
	{
		receiver.Stop();
		std::this_thread::sleep_for(std::chrono::seconds(1));
	}

	void sendRaw()
	{
		std::cout << "Sending" << std::endl;
		uint8_t beacon_frame[] = {
			0x00, 0x00, 0x0d, 0x00, 0x00, 0x80, 0x08, 0x00, 0x08, 0x00, 0x37,
			0x00, 0x01, // radiotap header
			0x08, 0x01, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x57,
			0x42, 0x75, 0x05, 0xd6, 0x00, 0x57, 0x42, 0x75, 0x05, 0xd6, 0x00,
			0x80, 0x00, // 80211 header
			0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x24, 0x4f,
			0xa0, 0xc5, 0x4a, 0xbb, 0x6a, 0x55, 0x03, 0x72, 0xf8, 0x4d, 0xc4,
			0x9d, 0x1a, 0x51, 0xb7, 0x3f, 0x98, 0xf1, 0xe7, 0x46, 0x4d, 0x1c,
			0x21, 0x86, 0x15, 0x21, 0x02, 0xf4, 0x88, 0x63, 0xff, 0x51, 0x66,
			0x34, 0xf2, 0x16, 0x71, 0xf5, 0x76, 0x0b, 0x35, 0xc0, 0xe1, 0x44,
			0xcd, 0xce, 0x4e, 0x35, 0xd9, 0x85, 0x9a, 0xcf, 0x4d, 0x48, 0x4c,
			0x8f, 0x28, 0x6f, 0x10, 0xb0, 0xa9, 0x5d, 0xbf, 0xcb, 0x6f};

		receiver.sendRaw(beacon_frame, sizeof(beacon_frame));
	}
}

#ifdef __EMSCRIPTEN__

EMSCRIPTEN_BINDINGS(device_module)
{
	emscripten::value_object<DeviceId>("DeviceId")
		.field("vendor_id", &DeviceId::vendor_id)
		.field("product_id", &DeviceId::product_id)
		.field("display_name", &DeviceId::display_name)
		.field("bus_num", &DeviceId::bus_num)
		.field("port_num", &DeviceId::port_num);

	emscripten::register_vector<DeviceId>("DeviceIdVector");

	emscripten::function("getDeviceList", &WfbReceiver::GetDeviceList);
	emscripten::function("startReceiver", &startReceiver);
	emscripten::function("stopReceiver", &stopReceiver);
	emscripten::function("sendRaw", &sendRaw);

	emscripten::enum_<ChannelWidth_t>("ChannelWidth")
		.value("CHANNEL_WIDTH_20", CHANNEL_WIDTH_20)
		.value("CHANNEL_WIDTH_40", CHANNEL_WIDTH_40)
		.value("CHANNEL_WIDTH_80", CHANNEL_WIDTH_80)
		.value("CHANNEL_WIDTH_160", CHANNEL_WIDTH_160)
		.value("CHANNEL_WIDTH_80_80", CHANNEL_WIDTH_80_80)
		.value("CHANNEL_WIDTH_5", CHANNEL_WIDTH_5)
		.value("CHANNEL_WIDTH_10", CHANNEL_WIDTH_10)
		.value("CHANNEL_WIDTH_MAX", CHANNEL_WIDTH_MAX);
}
#endif

int main(int argc, char *argv[])
{
#ifndef __EMSCRIPTEN__
	if (argc > 3 || (argc == 2 && std::string(argv[1]) == "-h"))
	{
		std::cout << "Usage: " << argv[0] << " [channel_width] [channel]" << std::endl;
		std::cout << "Defaults: channel_width=0, channel=161" << std::endl;
		return argc > 3 ? 1 : 0;
	}

	int arg1 = (argc >= 2) ? std::atoi(argv[1]) : 0;
	int arg2 = (argc >= 3) ? std::atoi(argv[2]) : 161;

	startReceiver(1, static_cast<ChannelWidth_t>(arg1), arg2);
	std::cin.get();
	stopReceiver();
	std::cout << "HELLO" << std::endl;
	std::this_thread::sleep_for(std::chrono::seconds(1));
#endif

	return 0;
}
