//! WiFi Video Receiver - RTP packet processing and video frame handling
//! Supports cross-platform deployment with WebAssembly and native targets

const std = @import("std");
const builtin = @import("builtin");

// Platform-specific imports
const c = @cImport({
    @cInclude("sodium.h");
});

// Core modules
const rtp = @import("zig/rtp/rtp.zig");
const Aggregator = @import("zig/wfbprocessor.zig").Aggregator;
const RxFrame = @import("zig/RxFrame.zig").RxFrame;
const zig_print = @import("zig/utils.zig").zig_print;
const zig_err = @import("zig/utils.zig").zig_err;

// Platform-specific video rendering
const os = switch (builtin.os.tag) {
    .emscripten => @import("os/emscripten.zig"),
    else => @import("os/linux.zig"),
};

// =============================================================================
// Types and Constants
// =============================================================================

/// C-compatible packet attributes structure
pub const RxPktAttrib = extern struct {
    pkt_len: u16,
    physt: bool,
    drvinfo_sz: u8,
    shift_sz: u8,
    qos: bool,
    priority: u8,
    mdata: bool,
    seq_num: u16,
    frag_num: u8,
    mfrag: bool,
    bdecrypted: bool,
    encrypt: u8,
    crc_err: bool,
    icv_err: bool,
    data_rate: u8,
    bw: u8,
    stbc: u8,
    ldpc: u8,
    sgi: u8,
    rssi: [2]u8,
    snr: [2]i8,
    pkt_rpt_type: u32,
};

/// WiFi link configuration
const WifiConfig = struct {
    const link_id: u32 = 7669206;
    const video_radio_port: u8 = 0;
    const video_channel_id: u32 = (link_id << 8) + video_radio_port;
    const video_channel_id_be: u32 = std.mem.nativeToBig(u32, video_channel_id);
    const video_channel_id_bytes: [4]u8 = std.mem.toBytes(video_channel_id_be);
};

// =============================================================================
// Global State
// =============================================================================

var aggregator: ?*Aggregator = null;
var mutex: ?std.Thread.Mutex = null;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

// =============================================================================
// Core Functions
// =============================================================================

/// Initialize the WiFi video receiver system
export fn init_zig() void {
    zig_print("Initializing WiFi video receiver...\n", .{});

    const allocator = switch (builtin.target.os.tag) {
        .emscripten => std.heap.wasm_allocator,
        else => blk: {
            gpa = std.heap.GeneralPurposeAllocator(.{}){};
            break :blk gpa.allocator();
        },
    };

    aggregator = Aggregator.init(allocator, "gs.key", 0, WifiConfig.video_channel_id, &handleRtp) catch |err| {
        zig_err("Failed to initialize aggregator: {any}\n", .{err});
        return;
    };

    mutex = std.Thread.Mutex{};
    zig_print("WiFi video receiver initialized successfully\n", .{});
}

/// Clean up resources
export fn deinit_zig() void {
    if (mutex) |*m| {
        m.lock();
        defer m.unlock();
    }

    if (aggregator) |agg| {
        agg.allocator.destroy(agg);
        aggregator = null;
    }

    if (builtin.target.os.tag != .emscripten) {
        _ = gpa.deinit();
    }

    zig_print("WiFi video receiver deinitialized\n", .{});
}

/// Process incoming packet data
export fn handle_data(data: [*]const u8, len: usize, attrib: *const RxPktAttrib) void {
    _ = attrib; // Packet attributes available if needed for future features

    process_packet(data[0..len]) catch |err| {
        zig_err("Packet processing error: {any}\n", .{err});
    };
}

// =============================================================================
// Internal Functions
// =============================================================================

/// Handle parsed RTP video data
fn handleRtp(data: []const u8) void {
    zig_print("Processing RTP packet: {} bytes\n", .{data.len});

    const parsed_payload = rtp.parse(aggregator.?.allocator, data) catch |err| {
        zig_err("RTP parsing failed: {any}\n", .{err});
        return;
    };

    switch (parsed_payload) {
        .h264 => |frame_data| {
            zig_print("Received H.264 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            os.displayFrame(frame_data.data.ptr, frame_data.data.len, 0, frame_data.is_key_frame);

            // Clean up allocated memory
            var mutable_frame = frame_data;
            mutable_frame.deinit(aggregator.?.allocator);
        },
        .h265 => |frame_data| {
            zig_print("Received H.265 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            os.displayFrame(frame_data.data.ptr, frame_data.data.len, 1, frame_data.is_key_frame);

            // Clean up allocated memory
            var mutable_frame = frame_data;
            mutable_frame.deinit(aggregator.?.allocator);
        },
        .unknown => {
            zig_err("Received packet with unknown codec\n", .{});
        },
    }
}

/// Process raw WiFi packet data
fn process_packet(packet_data: []const u8) !void {
    // Ensure system is initialized
    if (aggregator == null or mutex == null) {
        zig_err("System not initialized - call init_zig() first\n", .{});
        return error.SystemNotInitialized;
    }

    // Validate WiFi frame format
    const frame = RxFrame.init(packet_data);
    if (!frame.isValidWfbFrame()) {
        // Invalid frames are common, don't spam logs
        return;
    }

    zig_print("Processing valid WiFi frame\n", .{});

    // Thread-safe packet processing
    mutex.?.lock();
    defer mutex.?.unlock();

    // Check if packet belongs to our video channel
    if (frame.matchesChannelID(WifiConfig.video_channel_id_bytes)) {
        aggregator.?.process_packet(packet_data, 0, 0, 0);
    }
}
