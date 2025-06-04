#include <cassert>
#include <memory>

#include <libusb.h>

#include "FrameParser.h"
#include "RtlUsbAdapter.h"
#include "WiFiDriver.h"

#define USB_VENDOR_ID 0x0B05
#define USB_PRODUCT_ID 0x17D2

void listAllUsbDevices(std::shared_ptr<Logger> logger, libusb_context *ctx)
{
	libusb_device **devs;
	ssize_t cnt = libusb_get_device_list(ctx, &devs);
	if (cnt < 0)
	{
		logger->error("Failed to get device list: {}", libusb_error_name(cnt));
		return;
	}

	logger->debug("Found {} USB devices", cnt);

	for (ssize_t i = 0; i < cnt; i++)
	{
		libusb_device *dev = devs[i];
		libusb_device_descriptor desc;

		int rc = libusb_get_device_descriptor(dev, &desc);
		if (rc < 0)
		{
			logger->error("Failed to get device descriptor: {}", libusb_error_name(rc));
			continue;
		}

		uint8_t bus = libusb_get_bus_number(dev);
		uint8_t address = libusb_get_device_address(dev);

		logger->debug("Device {:03d}: VID {:04x}:PID {:04x} (Bus {:03d}, Addr {:03d})",
					  i, desc.idVendor, desc.idProduct, bus, address);

		// Print more details if it's our target device
		if (desc.idVendor == USB_VENDOR_ID && desc.idProduct == USB_PRODUCT_ID)
		{
			logger->debug("  -> This is our target device!");
		}
	}

	libusb_free_device_list(devs, 1);
}

int main()
{
	libusb_context *ctx;
	int rc;

	auto logger = std::make_shared<Logger>();
	logger->info("HELLO");
	logger->info("HELLO1");
	rc = libusb_init(&ctx);
	if (rc < 0)
	{
		return rc;
	}
	listAllUsbDevices(logger, ctx);
	libusb_set_option(ctx, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_DEBUG);
	logger->info("HELLO1");
	libusb_device_handle *dev_handle =
		libusb_open_device_with_vid_pid(ctx, USB_VENDOR_ID, USB_PRODUCT_ID);
	if (dev_handle == NULL)
	{
		logger->info("Cannot find device {:04x}:{:04x}", USB_VENDOR_ID,
					 USB_PRODUCT_ID);
		libusb_exit(ctx);
		return 1;
	}
	logger->info("HANDLE GOTTED HOORAY1");
	// Check if the kernel driver attached
	if (libusb_kernel_driver_active(dev_handle, 0))
	{
		rc = libusb_detach_kernel_driver(dev_handle, 0); // detach driver
	}

	rc = libusb_claim_interface(dev_handle, 0);
	assert(rc == 0);
	logger->info("AFTER ASSERT YAY before wifi");
	WiFiDriver wifi_driver(logger);
	logger->info("AFTER ASSERT YAY after wifi");
	auto rtlDevice = wifi_driver.CreateRtlDevice(dev_handle);
	logger->info("RTL Created");
	auto packetProcessor = [logger](const Packet &packet)
	{
		// Now “logger” is in scope here, because we captured it.
		// logger->error("Got a packet of length {}", packet.RxAtrib.pkt_len);
		logger->info("GOTTED~!");
		// …do whatever else you like with `packet` and `logger`…
	};
	rtlDevice->Init(packetProcessor, SelectedChannel{
										 .Channel = 36,
										 .ChannelOffset = 0,
										 .ChannelWidth = CHANNEL_WIDTH_20,
									 });

	logger->info("HELLO");
	libusb_close(dev_handle);
	logger->info("HELLO");
	libusb_exit(ctx);

	return 0;
}
