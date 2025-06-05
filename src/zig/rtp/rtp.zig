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

// rtp.zig - Updated detectCodec function
fn detectCodec(payload_type: u7, rtp_payload: []const u8) CodecType {
    // For dynamic payload types, inspect the actual H.264/H.265 data
    switch (payload_type) {
        96...127 => {
            if (rtp_payload.len == 0) return .unknown;

            // Get NAL unit type from the RTP payload (after RTP header parsing)
            const nal_type = rtp_payload[0] & 0x1F;

            // H.264 RTP-specific types: STAP-A (24) and FU-A (28)
            // Plus regular H.264 NAL types (1-23)
            if (isH264NalType(nal_type)) {
                return .h264;
            }

            // H.265 detection
            if (isH265NalType(rtp_payload[0])) {
                return .h265;
            }

            return .unknown;
        },
        else => return .unknown,
    }
}

// Helper functions matching the C++ implementation
inline fn isH264NalType(nal_type: u8) bool {
    // RTP aggregation and fragmentation types
    if (nal_type == 24 or nal_type == 28) return true;

    // Regular H.264 NAL unit types (1-23)
    if (nal_type >= 1 and nal_type <= 23) return true;

    return false;
}

inline fn isH265NalType(first_byte: u8) bool {
    // H.265 NAL unit type is in bits 1-6 (shifted right by 1)
    const h265_type = (first_byte >> 1) & 0x3F;

    // H.265 RTP payload types: AP (48), FU (49), PACI (50)
    if (h265_type == 48 or h265_type == 49 or h265_type == 50) return true;

    // Regular H.265 NAL unit types (0-40)
    if (h265_type <= 40) return true;

    return false;
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

    // Calculate payload offset (this part looks correct)
    var payload_offset: usize = 12 + (@as(usize, header.csrc_count) * 4);

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

    // THIS is the actual H.264/H.265 payload data (after RTP header)
    const rtp_payload = packet[payload_offset..];

    // NOW detect codec using the actual payload
    const codec = detectCodec(header.payload_type, rtp_payload);

    // Use tagged union inline switch to execute codec implementation
    switch (codec) {
        .h264 => {
            const parsed = try h264.parse(allocator, rtp_payload);
            return ParsedPayload{ .h264 = parsed };
        },
        .h265 => {
            const parsed = try h265.parse(allocator, rtp_payload);
            return ParsedPayload{ .h265 = parsed };
        },
        .unknown => {
            return RtpError.UnsupportedCodec;
        },
    }
}
