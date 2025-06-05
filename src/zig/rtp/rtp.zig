const std = @import("std");
const h264 = @import("h264.zig");
const h265 = @import("h265.zig");

pub const RtpError = error{
    InvalidPayload,
    UnsupportedCodec,
    CorruptedPacket,
    ShortPacket,
};

pub const CodecType = enum {
    h264,
    h265,
    unknown,
};

pub const ParsedPayload = union(CodecType) {
    h264: h264.H264ParsedPayload,
    h265: h265.H265ParsedPayload,
    unknown: void,
};

pub const RtpHeader = struct {
    version: u2,
    padding: bool,
    extension: bool,
    csrc_count: u4,
    marker: bool,
    payload_type: u7,
    sequence_number: u16,
    timestamp: u32,
    ssrc: u32,
};

fn detectCodec(payload_type: u7, payload: []const u8) CodecType {
    // Common payload types for H.264 and H.265
    switch (payload_type) {
        96...127 => {
            // Dynamic payload types - need to inspect payload
            if (payload.len == 0) return .unknown;

            const nal_type = payload[0] & 0x1F;

            // H.264 NAL unit types (0-23 are valid for H.264)
            if (nal_type <= 23) {
                return .h264;
            }

            // H.265 NAL unit types (32-63 are H.265 specific)
            const h265_type = (payload[0] >> 1) & 0x3F;
            if (h265_type >= 32 and h265_type <= 63) {
                return .h265;
            }

            return .unknown;
        },
        else => return .unknown,
    }
}

pub fn parse(allocator: std.mem.Allocator, packet: []const u8) !ParsedPayload {
    if (packet.len < 12) {
        return RtpError.ShortPacket;
    }

    // Parse RTP header
    const header = RtpHeader{
        .version = @truncate((packet[0] >> 6) & 0x03),
        .padding = (packet[0] & 0x20) != 0,
        .extension = (packet[0] & 0x10) != 0,
        .csrc_count = @truncate(packet[0] & 0x0F),
        .marker = (packet[1] & 0x80) != 0,
        .payload_type = @truncate(packet[1] & 0x7F),
        .sequence_number = std.mem.readInt(u16, packet[2..4], .big),
        .timestamp = std.mem.readInt(u32, packet[4..8], .big),
        .ssrc = std.mem.readInt(u32, packet[8..12], .big),
    };

    // Calculate payload offset
    var payload_offset: usize = 12 + (@as(usize, header.csrc_count) * 4);

    // Handle extension header if present
    if (header.extension) {
        if (packet.len < payload_offset + 4) {
            return RtpError.ShortPacket;
        }
        const ext_length = std.mem.readInt(u16, packet[payload_offset + 2 .. payload_offset + 4][0..2], .big);
        payload_offset += 4 + (@as(usize, ext_length) * 4);
    }

    if (payload_offset >= packet.len) {
        return RtpError.InvalidPayload;
    }

    const payload = packet[payload_offset..];
    const codec = detectCodec(header.payload_type, payload);

    // Use tagged union inline switch to execute codec implementation
    switch (codec) {
        .h264 => {
            const parsed = try h264.parse(allocator, payload);
            return ParsedPayload{ .h264 = parsed };
        },
        .h265 => {
            const parsed = try h265.parse(allocator, payload);
            return ParsedPayload{ .h265 = parsed };
        },
        .unknown => {
            return RtpError.UnsupportedCodec;
        },
    }
}
