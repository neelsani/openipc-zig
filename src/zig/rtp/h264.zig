const std = @import("std");

pub const H264Error = error{
    InvalidNalType,
    TruncatedFuA,
    CorruptedPacket,
    OutOfMemory,
};

pub const H264NalType = enum(u5) {
    unspecified = 0,
    slice = 1,
    dpa = 2,
    dpb = 3,
    dpc = 4,
    idr = 5,
    sei = 6,
    sps = 7,
    pps = 8,
    aud = 9,
    eoseq = 10,
    eostream = 11,
    filler = 12,
    sps_ext = 13,
    prefix = 14,
    sub_sps = 15,
    dps = 16,
    reserved17 = 17,
    reserved18 = 18,
    aux_slice = 19,
    exten_slice = 20,
    depth_exten_slice = 21,
    reserved22 = 22,
    reserved23 = 23,
    stap_a = 24,
    stap_b = 25,
    mtap16 = 26,
    mtap24 = 27,
    fu_a = 28,
    fu_b = 29,
    reserved30 = 30,
    reserved31 = 31,
};

pub const H264ParsedPayload = struct {
    nal_type: H264NalType,
    data: []u8,
    is_key_frame: bool,
    is_first_fragment: bool,
    is_last_fragment: bool,

    pub fn deinit(self: *H264ParsedPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const kH264FBit: u8 = 0x80;
const kH264NriMask: u8 = 0x60;
const kH264TypeMask: u8 = 0x1F;
const kH264SBit: u8 = 0x80;
const kH264EBit: u8 = 0x40;
const kFuAHeaderSize: usize = 2;

fn parseStapAOrSingleNalu(allocator: std.mem.Allocator, payload: []const u8) !H264ParsedPayload {
    if (payload.len == 0) {
        return H264Error.CorruptedPacket;
    }

    const nal_header = payload[0];
    const nal_type: H264NalType = @enumFromInt(nal_header & kH264TypeMask);

    // For single NALU, copy the entire payload
    const data = try allocator.dupe(u8, payload);

    return H264ParsedPayload{
        .nal_type = nal_type,
        .data = data,
        .is_key_frame = nal_type == .idr,
        .is_first_fragment = true,
        .is_last_fragment = true,
    };
}

fn parseFuaNalu(allocator: std.mem.Allocator, payload: []const u8) !H264ParsedPayload {
    if (payload.len < kFuAHeaderSize) {
        return H264Error.TruncatedFuA;
    }

    const fnri = payload[0] & (kH264FBit | kH264NriMask);
    const original_nal_type: H264NalType = @enumFromInt(payload[1] & kH264TypeMask);
    const first_fragment = (payload[1] & kH264SBit) != 0;
    const last_fragment = (payload[1] & kH264EBit) != 0;

    var data: []u8 = undefined;

    if (first_fragment) {
        // For first fragment, reconstruct original NAL header
        data = try allocator.alloc(u8, payload.len - 1);
        const original_nal_header = fnri | @intFromEnum(original_nal_type);
        data[0] = original_nal_header;
        @memcpy(data[1..], payload[kFuAHeaderSize..]);
    } else {
        // For subsequent fragments, just copy payload without FU-A header
        data = try allocator.dupe(u8, payload[kFuAHeaderSize..]);
    }

    return H264ParsedPayload{
        .nal_type = original_nal_type,
        .data = data,
        .is_key_frame = original_nal_type == .idr,
        .is_first_fragment = first_fragment,
        .is_last_fragment = last_fragment,
    };
}

pub fn parse(allocator: std.mem.Allocator, payload: []const u8) !H264ParsedPayload {
    if (payload.len == 0) {
        return H264Error.CorruptedPacket;
    }

    const nal_type: H264NalType = @enumFromInt(payload[0] & kH264TypeMask);

    switch (nal_type) {
        .fu_a => {
            // Fragmented NAL units (FU-A)
            return try parseFuaNalu(allocator, payload);
        },
        else => {
            // Handle STAP-A and single NALU the same way
            return try parseStapAOrSingleNalu(allocator, payload);
        },
    }
}
