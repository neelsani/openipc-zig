const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;

const rtp = @import("../rtp/rtp.zig");

extern fn displayFrame(data_ptr: [*]const u8, data_len: usize, codec_type: u32, is_key_frame: bool) void;

pub fn handleRtp(allocator: std.mem.Allocator, data: []const u8) void {
    zig_print("Processing RTP packet: {} bytes\n", .{data.len});

    var parsed_payload = rtp.parse(allocator, data) catch |err| {
        zig_err("RTP parsing failed: {any}\n", .{err});
        return;
    };

    switch (parsed_payload) {
        .h264 => |*frame_data| {
            zig_print("Received H.264 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            displayFrame(frame_data.data.ptr, frame_data.data.len, 0, frame_data.is_key_frame);

            // Clean up allocated memory
            frame_data.deinit(allocator);
        },
        .h265 => |*frame_data| {
            zig_print("Received H.265 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            displayFrame(frame_data.data.ptr, frame_data.data.len, 1, frame_data.is_key_frame);

            // Clean up allocated memory

            frame_data.deinit(allocator);
        },
        .unknown => {
            zig_err("Received packet with unknown codec\n", .{});
        },
    }
}
