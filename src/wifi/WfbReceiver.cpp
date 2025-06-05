//
// Created by Talus on 2024/6/10.
//

#include "WfbReceiver.h"

#include <iomanip>
#include <mutex>
#include <set>
#include <sstream>

#include "Rtp.h"
#include "RxFrame.h"
#include "WfbProcessor.h"
#include "WiFiDriver.h"
#include "logger.h"

std::vector<DeviceId> WfbReceiver::GetDeviceList()
{
    std::vector<DeviceId> list;

    // Initialize libusb
    libusb_context *find_ctx;
    libusb_init(&find_ctx);

    // Get a list of USB devices
    libusb_device **devs;
    ssize_t count = libusb_get_device_list(find_ctx, &devs);
    if (count < 0)
    {
        return list;
    }

    // Iterate over devices
    for (ssize_t i = 0; i < count; ++i)
    {
        libusb_device *dev = devs[i];

        libusb_device_descriptor desc{};
        if (libusb_get_device_descriptor(dev, &desc) == 0)
        {
            // Check if the device is using libusb driver
            if (desc.bDeviceClass == LIBUSB_CLASS_PER_INTERFACE)
            {
                uint8_t bus_num = libusb_get_bus_number(dev);
                uint8_t port_num = libusb_get_port_number(dev);

                std::stringstream ss;
                ss << std::setw(4) << std::setfill('0') << std::hex << desc.idVendor << ":";
                ss << std::setw(4) << std::setfill('0') << std::hex << desc.idProduct;
                ss << std::dec << " [" << (int)bus_num << ":" << (int)port_num << "]";

                DeviceId dev_id = {
                    .vendor_id = desc.idVendor,
                    .product_id = desc.idProduct,
                    .display_name = ss.str(),
                    .bus_num = bus_num,
                    .port_num = port_num,
                };

                list.push_back(dev_id);
            }
        }
    }

    // std::sort(list.begin(), list.end(), [](std::string &a, std::string &b) {
    //     static std::vector<std::string> specialStrings = {"0b05:17d2", "0bda:8812", "0bda:881a"};
    //     auto itA = std::find(specialStrings.begin(), specialStrings.end(), a);
    //     auto itB = std::find(specialStrings.begin(), specialStrings.end(), b);
    //     if (itA != specialStrings.end() && itB == specialStrings.end()) {
    //         return true;
    //     }
    //     if (itB != specialStrings.end() && itA == specialStrings.end()) {
    //         return false;
    //     }
    //     return a < b;
    // });

    // Free the list of devices
    libusb_free_device_list(devs, 1);

    // Deinitialize libusb
    libusb_exit(find_ctx);

    return list;
}
extern "C" void init_zig();

bool WfbReceiver::Start(const DeviceId &deviceId, uint8_t channel, int channelWidthMode, const std::string &kPath)
{

    keyPath = kPath;

    if (usbThread)
    {
        return false;
    }

    auto logger = std::make_shared<Logger>();

    int rc = libusb_init(&ctx);
    if (rc < 0)
    {

        return false;
    }

    libusb_set_option(ctx, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_ERROR);

    // Get a list of USB devices
    libusb_device **devs;
    ssize_t count = libusb_get_device_list(ctx, &devs);
    if (count < 0)
    {
        return false;
    }

    libusb_device *target_dev{};

    // Iterate over devices
    for (ssize_t i = 0; i < count; ++i)
    {
        libusb_device *dev = devs[i];
        libusb_device_descriptor desc{};
        if (libusb_get_device_descriptor(dev, &desc) == 0)
        {
            // Check if the device is using libusb driver
            if (desc.bDeviceClass == LIBUSB_CLASS_PER_INTERFACE)
            {
                int bus_num = libusb_get_bus_number(dev);
                int port_num = libusb_get_port_number(dev);

                if (desc.idVendor == deviceId.vendor_id && desc.idProduct == deviceId.product_id &&
                    bus_num == deviceId.bus_num && port_num == deviceId.port_num)
                {
                    target_dev = dev;
                }
            }
        }
    }

    if (!target_dev)
    {

        // Free the list of devices
        libusb_free_device_list(devs, 1);
        libusb_exit(ctx);
        ctx = nullptr;
        return false;
    }

    // This cannot handle multiple devices with the same vendor_id and product_id.
    // devHandle = libusb_open_device_with_vid_pid(ctx, wifiDeviceVid, wifiDevicePid);
    libusb_open(target_dev, &devHandle);

    // Free the list of devices
    libusb_free_device_list(devs, 1);

    if (devHandle == nullptr)
    {
        libusb_exit(ctx);
        ctx = nullptr;

        return false;
    }

    // Check if the kernel driver attached
    if (libusb_kernel_driver_active(devHandle, 0))
    {
        // Detach driver
        rc = libusb_detach_kernel_driver(devHandle, 0);
    }

    rc = libusb_claim_interface(devHandle, 0);
    if (rc < 0)
    {
        libusb_close(devHandle);
        devHandle = nullptr;

        libusb_exit(ctx);
        ctx = nullptr;

        return false;
    }

    usbThread = std::make_shared<std::thread>([=, this]()
                                              {
                                                  WiFiDriver wifi_driver{logger};
                                                  try
                                                  {

                                                      rtlDevice = wifi_driver.CreateRtlDevice(devHandle);
                                                      
                                                        init_zig();
                                                        rtlDevice->Init(
                                                          [](const Packet &p)
                                                          {
                                                              //std::cout << "MY GUY" << std::endl;

                                                              Instance().handle80211Frame(p);
                                                          },
                                                          SelectedChannel{
                                                              .Channel = channel,
                                                              .ChannelOffset = 0,
                                                              .ChannelWidth = static_cast<ChannelWidth_t>(channelWidthMode),
                                                          });
                                                  }

                                                  catch (...)
                                                  {
                                                  }

                                                  auto rc1 = libusb_release_interface(devHandle, 0);
                                                  if (rc1 < 0)
                                                  {
                                                  }

                                                  libusb_close(devHandle);
                                                  libusb_exit(ctx);

                                                  devHandle = nullptr;
                                                  ctx = nullptr;

                                                  usbThread.reset(); });
    /*
        rtlDevice->InitWrite(SelectedChannel{
            .Channel = channel,
            .ChannelOffset = 0,
            .ChannelWidth = static_cast<ChannelWidth_t>(channelWidthMode),
        });
    */
    usbThread->detach();

    return true;
}
extern "C" void handle_data(const uint8_t *data, size_t len, const rx_pkt_attrib *attrib);

void WfbReceiver::handle80211Frame(const Packet &packet)
{
    handle_data(packet.Data.data(), packet.Data.size(), &packet.RxAtrib); // give zig data then transfer control to c++ for backup
    RxFrame frame(packet.Data);
    if (!frame.IsValidWfbFrame())
    {
        // std::cout << "Not Valid Frame" << std::endl;

        return;
    }
    // std::cout << "Valid Frame" << std::endl;
    static int8_t rssi[2] = {1, 1};
    static uint8_t antenna[4] = {1, 1, 1, 1};

    static uint32_t link_id = 7669206; // sha1 hash of link_domain="default"
    static uint8_t video_radio_port = 0;
    static uint64_t epoch = 0;

    static uint32_t video_channel_id_f = (link_id << 8) + video_radio_port;
    static uint32_t video_channel_id_be = htobe32(video_channel_id_f);

    static auto *video_channel_id_be8 = reinterpret_cast<uint8_t *>(&video_channel_id_be);

    static std::mutex agg_mutex;
    static std::unique_ptr<Aggregator> video_aggregator = std::make_unique<Aggregator>(
        keyPath.c_str(),
        epoch,
        video_channel_id_f,
        [](uint8_t *payload, uint16_t packet_size)
        { Instance().handleRtp(payload, packet_size); });

    std::lock_guard lock(agg_mutex);
    if (frame.MatchesChannelID(video_channel_id_be8))
    {
        video_aggregator->process_packet(packet.Data.data() + sizeof(ieee80211_header),
                                         packet.Data.size() - sizeof(ieee80211_header) - 4,
                                         0,
                                         antenna,
                                         rssi);
    }
    else
    {
        int a = 1;
    }
}

#ifdef __linux__
#define INVALID_SOCKET (-1)
#endif

static volatile bool playing = false;

#define GET_H264_NAL_UNIT_TYPE(buffer_ptr) (buffer_ptr[0] & 0x1F)

inline bool isH264(const uint8_t *data)
{
    auto h264NalType = GET_H264_NAL_UNIT_TYPE(data);
    return h264NalType == 24 || h264NalType == 28;
}

void WfbReceiver::handleRtp(uint8_t *payload, uint16_t packet_size)
{

    if (rtlDevice->should_stop)
    {
        return;
    }
    if (packet_size < 12)
    {
        return;
    }

    auto *header = (RtpHeader *)payload;
}
void WfbReceiver::sendRaw(uint8_t *payload, uint16_t packet_size)
{
    bool rc = rtlDevice->send_packet(payload, packet_size);
}
void WfbReceiver::Stop() const
{
    playing = false;
    if (rtlDevice)
    {
        rtlDevice->should_stop = true;
    }
}

WfbReceiver::WfbReceiver()
{
}

WfbReceiver::~WfbReceiver()
{

    Stop();
}
