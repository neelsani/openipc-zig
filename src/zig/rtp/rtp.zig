const std = @import("std");
const Allocator = std.mem.Allocator;

// NAL Unit types for H.264
const H264NalType = enum(u8) {
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
    fill = 12,
    stap_a = 24,
    stap_b = 25,
    mtap16 = 26,
    mtap24 = 27,
    fu_a = 28,
    fu_b = 29,
};

// NAL Unit types for H.265
const H265NalType = enum(u8) {
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
    idr_w_radl = 19,
    idr_n_lp = 20,
    cra_nut = 21,
    vps = 32,
    sps = 33,
    pps = 34,
    aud = 35,
    eos_nut = 36,
    eob_nut = 37,
    fd_nut = 38,
    sei_prefix = 39,
    sei_suffix = 40,
    ap = 48,
    fu = 49,
    paci = 50,
};

const RtpHeader = struct {
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

const DepacketizedFrame = struct {
    data: []u8,
    timestamp: u32,
    is_keyframe: bool,
    codec: enum(u32) { h264 = 0, h265 = 1 },

    pub fn deinit(self: *DepacketizedFrame, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

const FragmentationState = struct {
    buffer: std.ArrayList(u8),
    timestamp: u32,
    is_first: bool,
    nal_type: u8,

    pub fn init(allocator: Allocator) FragmentationState {
        return FragmentationState{
            .buffer = std.ArrayList(u8).init(allocator),
            .timestamp = 0,
            .is_first = false,
            .nal_type = 0,
        };
    }

    pub fn deinit(self: *FragmentationState) void {
        self.buffer.deinit();
    }

    pub fn reset(self: *FragmentationState) void {
        self.buffer.clearRetainingCapacity();
        self.is_first = false;
    }
};

pub const RtpDepacketizer = struct {
    allocator: Allocator,
    h264_frag_state: FragmentationState,
    h265_frag_state: FragmentationState,
    sps_h264: ?[]u8,
    pps_h264: ?[]u8,
    vps_h265: ?[]u8,
    sps_h265: ?[]u8,
    pps_h265: ?[]u8,

    const ANNEX_B_START_CODE = [_]u8{ 0x00, 0x00, 0x00, 0x01 };

    pub fn init(allocator: Allocator) RtpDepacketizer {
        return RtpDepacketizer{
            .allocator = allocator,
            .h264_frag_state = FragmentationState.init(allocator),
            .h265_frag_state = FragmentationState.init(allocator),
            .sps_h264 = null,
            .pps_h264 = null,
            .vps_h265 = null,
            .sps_h265 = null,
            .pps_h265 = null,
        };
    }

    pub fn deinit(self: *RtpDepacketizer) void {
        self.h264_frag_state.deinit();
        self.h265_frag_state.deinit();
        if (self.sps_h264) |sps| self.allocator.free(sps);
        if (self.pps_h264) |pps| self.allocator.free(pps);
        if (self.vps_h265) |vps| self.allocator.free(vps);
        if (self.sps_h265) |sps| self.allocator.free(sps);
        if (self.pps_h265) |pps| self.allocator.free(pps);
    }

    fn detectCodecFromPayload(payload: []const u8) ?enum { h264, h265 } {
        if (payload.len == 0) return null;

        // H.264 detection - check NAL unit type
        const h264_nal_type = payload[0] & 0x1F;

        // H.264 RTP packetization types
        if (h264_nal_type == 24 or h264_nal_type == 28) { // STAP-A or FU-A
            return .h264;
        }

        // H.265 detection - check NAL unit type (first 6 bits after forbidden_zero_bit)
        if (payload.len >= 2) {
            const h265_nal_type = (payload[0] >> 1) & 0x3F;

            // H.265 RTP packetization types
            if (h265_nal_type == 48 or h265_nal_type == 49) { // AP or FU
                return .h265;
            }

            // H.265 single NAL units
            if (h265_nal_type <= 40) {
                return .h265;
            }
        }

        return null;
    }

    pub fn processRtpPacket(self: *RtpDepacketizer, data: []const u8) !?DepacketizedFrame {
        if (data.len < 12) return null;

        const header = self.parseRtpHeader(data);
        const payload = data[12..];

        // Auto-detect codec from payload instead of relying on payload type
        const codec = detectCodecFromPayload(payload) orelse return null;

        return switch (codec) {
            .h264 => self.processH264Packet(payload, header),
            .h265 => self.processH265Packet(payload, header),
        };
    }

    fn parseRtpHeader(self: *RtpDepacketizer, data: []const u8) RtpHeader {
        _ = self;
        return RtpHeader{
            .version = @truncate((data[0] >> 6) & 0x03),
            .padding = (data[0] & 0x20) != 0,
            .extension = (data[0] & 0x10) != 0,
            .csrc_count = @truncate(data[0] & 0x0F),
            .marker = (data[1] & 0x80) != 0,
            .payload_type = @truncate(data[1] & 0x7F),
            .sequence_number = std.mem.readInt(u16, data[2..4], .big),
            .timestamp = std.mem.readInt(u32, data[4..8], .big),
            .ssrc = std.mem.readInt(u32, data[8..12], .big),
        };
    }

    fn processH264Packet(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        if (payload.len == 0) return null;

        const nal_type: H264NalType = @enumFromInt(payload[0] & 0x1F);

        return switch (nal_type) {
            .fu_a => self.processH264FragmentationUnit(payload, header),
            .stap_a => self.processH264StapA(payload, header),
            .sps => {
                try self.storeH264Sps(payload);
                return null;
            },
            .pps => {
                try self.storeH264Pps(payload);
                return null;
            },
            else => self.processH264SingleNalu(payload, header),
        };
    }

    fn processH265Packet(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        if (payload.len < 2) return null;

        const nal_type: u8 = (payload[0] >> 1) & 0x3F;

        return switch (nal_type) {
            49 => self.processH265FragmentationUnit(payload, header), // FU
            48 => self.processH265AggregationPacket(payload, header), // AP
            32 => { // VPS
                try self.storeH265Vps(payload);
                return null;
            },
            33 => { // SPS
                try self.storeH265Sps(payload);
                return null;
            },
            34 => { // PPS
                try self.storeH265Pps(payload);
                return null;
            },
            else => self.processH265SingleNalu(payload, header),
        };
    }

    fn processH264FragmentationUnit(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        if (payload.len < 2) return null;

        const fu_indicator = payload[0];
        const fu_header = payload[1];
        const start_bit = (fu_header & 0x80) != 0;
        const end_bit = (fu_header & 0x40) != 0;
        const nal_type = fu_header & 0x1F;

        if (start_bit) {
            self.h264_frag_state.reset();
            self.h264_frag_state.timestamp = header.timestamp;
            self.h264_frag_state.is_first = true;
            self.h264_frag_state.nal_type = nal_type;

            // Reconstruct NAL header
            const reconstructed_nal = (fu_indicator & 0xE0) | nal_type;
            try self.h264_frag_state.buffer.append(reconstructed_nal);
        }

        // Append fragment data
        try self.h264_frag_state.buffer.appendSlice(payload[2..]);

        if (end_bit) {
            return try self.createFrame(self.h264_frag_state.buffer.items, self.h264_frag_state.timestamp, nal_type == 5, // IDR frame
                .h264);
        }

        return null;
    }

    fn processH265FragmentationUnit(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        if (payload.len < 3) return null;

        const fu_header = payload[2];
        const start_bit = (fu_header & 0x80) != 0;
        const end_bit = (fu_header & 0x40) != 0;
        const nal_type = fu_header & 0x3F;

        if (start_bit) {
            self.h265_frag_state.reset();
            self.h265_frag_state.timestamp = header.timestamp;
            self.h265_frag_state.is_first = true;
            self.h265_frag_state.nal_type = nal_type;

            // Reconstruct NAL header (2 bytes for H.265)
            try self.h265_frag_state.buffer.append((nal_type << 1) | (payload[0] & 0x01));
            try self.h265_frag_state.buffer.append(payload[1]);
        }

        // Append fragment data
        try self.h265_frag_state.buffer.appendSlice(payload[3..]);

        if (end_bit) {
            const is_keyframe = nal_type >= 16 and nal_type <= 23; // IRAP pictures
            return try self.createFrame(self.h265_frag_state.buffer.items, self.h265_frag_state.timestamp, is_keyframe, .h265);
        }

        return null;
    }

    fn processH264SingleNalu(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        const nal_type = payload[0] & 0x1F;
        const is_keyframe = nal_type == 5; // IDR
        return try self.createFrame(payload, header.timestamp, is_keyframe, .h264);
    }

    fn processH265SingleNalu(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        const nal_type = (payload[0] >> 1) & 0x3F;
        const is_keyframe = nal_type >= 16 and nal_type <= 23;
        return try self.createFrame(payload, header.timestamp, is_keyframe, .h265);
    }

    fn processH264StapA(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var offset: usize = 1; // Skip STAP-A header
        var is_keyframe = false;

        while (offset < payload.len) {
            if (offset + 2 > payload.len) break;

            const nalu_size = std.mem.readInt(u16, payload[offset .. offset + 2][0..2], .big);
            offset += 2;

            if (offset + nalu_size > payload.len) break;

            const nalu = payload[offset .. offset + nalu_size];
            const nal_type = nalu[0] & 0x1F;

            if (nal_type == 5) is_keyframe = true;

            try result.appendSlice(&ANNEX_B_START_CODE);
            try result.appendSlice(nalu);

            offset += nalu_size;
        }

        return try self.createFrameFromBuffer(result.items, header.timestamp, is_keyframe, .h264);
    }

    fn processH265AggregationPacket(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var offset: usize = 2; // Skip AP header
        var is_keyframe = false;

        while (offset < payload.len) {
            if (offset + 2 > payload.len) break;

            const nalu_size = std.mem.readInt(u16, payload[offset .. offset + 2][0..2], .big);
            offset += 2;

            if (offset + nalu_size > payload.len) break;

            const nalu = payload[offset .. offset + nalu_size];
            const nal_type = (nalu[0] >> 1) & 0x3F;

            if (nal_type >= 16 and nal_type <= 23) is_keyframe = true;

            try result.appendSlice(&ANNEX_B_START_CODE);
            try result.appendSlice(nalu);

            offset += nalu_size;
        }

        return try self.createFrameFromBuffer(result.items, header.timestamp, is_keyframe, .h265);
    }

    fn createFrame(self: *RtpDepacketizer, data: []const u8, timestamp: u32, is_keyframe: bool, codec: @TypeOf(@as(DepacketizedFrame, undefined).codec)) !DepacketizedFrame {
        var frame_data = std.ArrayList(u8).init(self.allocator);

        // Add parameter sets for keyframes
        if (is_keyframe) {
            switch (codec) {
                .h264 => {
                    if (self.sps_h264) |sps| {
                        try frame_data.appendSlice(&ANNEX_B_START_CODE);
                        try frame_data.appendSlice(sps);
                    }
                    if (self.pps_h264) |pps| {
                        try frame_data.appendSlice(&ANNEX_B_START_CODE);
                        try frame_data.appendSlice(pps);
                    }
                },
                .h265 => {
                    if (self.vps_h265) |vps| {
                        try frame_data.appendSlice(&ANNEX_B_START_CODE);
                        try frame_data.appendSlice(vps);
                    }
                    if (self.sps_h265) |sps| {
                        try frame_data.appendSlice(&ANNEX_B_START_CODE);
                        try frame_data.appendSlice(sps);
                    }
                    if (self.pps_h265) |pps| {
                        try frame_data.appendSlice(&ANNEX_B_START_CODE);
                        try frame_data.appendSlice(pps);
                    }
                },
            }
        }

        try frame_data.appendSlice(&ANNEX_B_START_CODE);
        try frame_data.appendSlice(data);

        return DepacketizedFrame{
            .data = try frame_data.toOwnedSlice(),
            .timestamp = timestamp,
            .is_keyframe = is_keyframe,
            .codec = codec,
        };
    }

    fn createFrameFromBuffer(self: *RtpDepacketizer, data: []const u8, timestamp: u32, is_keyframe: bool, codec: @TypeOf(@as(DepacketizedFrame, undefined).codec)) !DepacketizedFrame {
        const owned_data = try self.allocator.dupe(u8, data);
        return DepacketizedFrame{
            .data = owned_data,
            .timestamp = timestamp,
            .is_keyframe = is_keyframe,
            .codec = codec,
        };
    }

    fn storeH264Sps(self: *RtpDepacketizer, sps_data: []const u8) !void {
        if (self.sps_h264) |old_sps| self.allocator.free(old_sps);
        self.sps_h264 = try self.allocator.dupe(u8, sps_data);
    }

    fn storeH264Pps(self: *RtpDepacketizer, pps_data: []const u8) !void {
        if (self.pps_h264) |old_pps| self.allocator.free(old_pps);
        self.pps_h264 = try self.allocator.dupe(u8, pps_data);
    }

    fn storeH265Vps(self: *RtpDepacketizer, vps_data: []const u8) !void {
        if (self.vps_h265) |old_vps| self.allocator.free(old_vps);
        self.vps_h265 = try self.allocator.dupe(u8, vps_data);
    }

    fn storeH265Sps(self: *RtpDepacketizer, sps_data: []const u8) !void {
        if (self.sps_h265) |old_sps| self.allocator.free(old_sps);
        self.sps_h265 = try self.allocator.dupe(u8, sps_data);
    }

    fn storeH265Pps(self: *RtpDepacketizer, pps_data: []const u8) !void {
        if (self.pps_h265) |old_pps| self.allocator.free(old_pps);
        self.pps_h265 = try self.allocator.dupe(u8, pps_data);
    }
};
