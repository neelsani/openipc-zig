const std = @import("std");

pub const H265Error = error{
    InvalidNalType,
    TruncatedPacket,
    CorruptedPacket,
    OutOfMemory,
};

pub const H265NalType = enum(u6) {
    // VCL NAL unit types
    trail_n = 0,
    trail_r = 1,
    tsa_n = 2,
    tsa_r = 3,
    stsa_n = 4,
    stsa_r = 5,
    radl_n = 6,
    radl_r = 7,
    rasl_n = 8,
    rasl_r = 9,
    rsv_vcl_n10 = 10,
    rsv_vcl_r11 = 11,
    rsv_vcl_n12 = 12,
    rsv_vcl_r13 = 13,
    rsv_vcl_n14 = 14,
    rsv_vcl_r15 = 15,
    bla_w_lp = 16,
    bla_w_radl = 17,
    bla_n_lp = 18,
    idr_w_radl = 19,
    idr_n_lp = 20,
    cra_nut = 21,
    rsv_irap_vcl22 = 22,
    rsv_irap_vcl23 = 23,

    // Non-VCL NAL unit types
    vps_nut = 32,
    sps_nut = 33,
    pps_nut = 34,
    aud_nut = 35,
    eos_nut = 36,
    eob_nut = 37,
    fd_nut = 38,
    prefix_sei_nut = 39,
    suffix_sei_nut = 40,

    // RTP payload specific
    ap = 48,
    fu = 49,
    paci = 50,

    _,
};

pub const H265ParsedPayload = struct {
    nal_type: H265NalType,
    data: []u8,
    is_key_frame: bool,
    is_first_fragment: bool,
    is_last_fragment: bool,

    pub fn deinit(self: *H265ParsedPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const kH265FBit: u8 = 0x80;
const kH265SBit: u8 = 0x80;
const kH265EBit: u8 = 0x40;
const kH265NaluHeaderSize: usize = 2;
const kFuHeaderSize: usize = 3;

fn isKeyFrame(nal_type: H265NalType) bool {
    return switch (nal_type) {
        .bla_w_lp, .bla_w_radl, .bla_n_lp, .idr_w_radl, .idr_n_lp, .cra_nut => true,
        else => false,
    };
}

fn parseSingleNalu(allocator: std.mem.Allocator, payload: []const u8) !H265ParsedPayload {
    if (payload.len < kH265NaluHeaderSize) {
        return H265Error.TruncatedPacket;
    }

    const nal_type: H265NalType = @enumFromInt((payload[0] >> 1) & 0x3F);
    const data = try allocator.dupe(u8, payload);

    return H265ParsedPayload{
        .nal_type = nal_type,
        .data = data,
        .is_key_frame = isKeyFrame(nal_type),
        .is_first_fragment = true,
        .is_last_fragment = true,
    };
}

fn parseFragmentationUnit(allocator: std.mem.Allocator, payload: []const u8) !H265ParsedPayload {
    if (payload.len < kFuHeaderSize) {
        return H265Error.TruncatedPacket;
    }

    const fu_header = payload[2];
    const first_fragment = (fu_header & kH265SBit) != 0;
    const last_fragment = (fu_header & kH265EBit) != 0;
    const original_nal_type: H265NalType = @enumFromInt(fu_header & 0x3F);

    var data: []u8 = undefined;

    if (first_fragment) {
        // Reconstruct original NAL header for first fragment
        data = try allocator.alloc(u8, payload.len - 1);
        // Copy original NAL header structure but with correct type
        data[0] = (payload[0] & 0x81) | (@intFromEnum(original_nal_type) << 1);
        data[1] = payload[1];
        @memcpy(data[2..], payload[kFuHeaderSize..]);
    } else {
        // For subsequent fragments, just copy payload without FU header
        data = try allocator.dupe(u8, payload[kFuHeaderSize..]);
    }

    return H265ParsedPayload{
        .nal_type = original_nal_type,
        .data = data,
        .is_key_frame = isKeyFrame(original_nal_type),
        .is_first_fragment = first_fragment,
        .is_last_fragment = last_fragment,
    };
}

fn parseAggregationPacket(allocator: std.mem.Allocator, payload: []const u8) !H265ParsedPayload {
    // For simplicity, just return the first NALU in the aggregation packet
    if (payload.len < kH265NaluHeaderSize + 2) {
        return H265Error.TruncatedPacket;
    }

    // Skip AP header and get first NALU size
    const nalu_size = std.mem.readInt(u16, payload[kH265NaluHeaderSize .. kH265NaluHeaderSize + 2], .big);
    const nalu_start = kH265NaluHeaderSize + 2;

    if (payload.len < nalu_start + nalu_size) {
        return H265Error.TruncatedPacket;
    }

    const nalu_data = payload[nalu_start .. nalu_start + nalu_size];
    const nal_type: H265NalType = @enumFromInt((nalu_data[0] >> 1) & 0x3F);
    const data = try allocator.dupe(u8, nalu_data);

    return H265ParsedPayload{
        .nal_type = nal_type,
        .data = data,
        .is_key_frame = isKeyFrame(nal_type),
        .is_first_fragment = true,
        .is_last_fragment = true,
    };
}

pub fn parse(allocator: std.mem.Allocator, payload: []const u8) !H265ParsedPayload {
    if (payload.len < kH265NaluHeaderSize) {
        return H265Error.TruncatedPacket;
    }

    // Check F bit
    if ((payload[0] & kH265FBit) != 0) {
        return H265Error.CorruptedPacket;
    }

    const nal_type: H265NalType = @enumFromInt((payload[0] >> 1) & 0x3F);

    switch (nal_type) {
        .fu => {
            return try parseFragmentationUnit(allocator, payload);
        },
        .ap => {
            return try parseAggregationPacket(allocator, payload);
        },
        .paci => {
            // PACI packets are handled similar to single NALU
            return try parseSingleNalu(allocator, payload);
        },
        else => {
            // Single NALU packet
            return try parseSingleNalu(allocator, payload);
        },
    }
}
