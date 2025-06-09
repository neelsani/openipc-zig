const std = @import("std");
const Allocator = std.mem.Allocator;
const zig_print = @import("../utils.zig").zig_print;

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

    profile: union(enum) {
        h264: H264Profile,
        h265: H265Profile,
        unknown,
    } = .unknown,
    level: u8 = 0,

    pub fn deinit(self: *DepacketizedFrame, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

// Fixed-size buffer for fragmentation
const MAX_FRAGMENT_SIZE = 64 * 1024;
const MAX_FRAME_SIZE = 1024 * 1024;
const MAX_TEMP_SIZE = 64 * 1024;
const MAX_PARAM_SIZE = 1024;

const FragmentationState = struct {
    buffer: [MAX_FRAGMENT_SIZE]u8,
    buffer_len: usize,
    timestamp: u32,
    is_first: bool,
    nal_type: u8,

    pub fn init() FragmentationState {
        return FragmentationState{
            .buffer = undefined,
            .buffer_len = 0,
            .timestamp = 0,
            .is_first = false,
            .nal_type = 0,
        };
    }

    pub fn reset(self: *FragmentationState) void {
        self.buffer_len = 0;
        self.is_first = false;
    }

    pub fn append(self: *FragmentationState, data: []const u8) !void {
        if (self.buffer_len + data.len > MAX_FRAGMENT_SIZE) {
            return error.BufferOverflow;
        }
        @memcpy(self.buffer[self.buffer_len .. self.buffer_len + data.len], data);
        self.buffer_len += data.len;
    }

    pub fn appendByte(self: *FragmentationState, byte: u8) !void {
        if (self.buffer_len >= MAX_FRAGMENT_SIZE) {
            return error.BufferOverflow;
        }
        self.buffer[self.buffer_len] = byte;
        self.buffer_len += 1;
    }

    pub fn getSlice(self: *const FragmentationState) []const u8 {
        return self.buffer[0..self.buffer_len];
    }
};

const H264Profile = enum(u8) {
    baseline = 66,
    main = 77,
    extended = 88,
    high = 100,
    high10 = 110,
    high422 = 122,
    high444 = 244,
    unknown = 255,
};

const H265Profile = enum(u8) {
    main = 1,
    main10 = 2,
    main_still_picture = 3,
    range_extensions = 4,
    high_throughput = 5,
    screen_content_coding = 9,
    unknown = 255,
};

pub const RtpDepacketizer = struct {
    allocator: Allocator,
    h264_frag_state: FragmentationState,
    h265_frag_state: FragmentationState,

    // Fixed-size parameter set buffers
    sps_h264: [MAX_PARAM_SIZE]u8,
    sps_h264_len: usize,
    pps_h264: [MAX_PARAM_SIZE]u8,
    pps_h264_len: usize,
    vps_h265: [MAX_PARAM_SIZE]u8,
    vps_h265_len: usize,
    sps_h265: [MAX_PARAM_SIZE]u8,
    sps_h265_len: usize,
    pps_h265: [MAX_PARAM_SIZE]u8,
    pps_h265_len: usize,

    // Profile detection cache
    h264_profile: H264Profile = .unknown,
    h265_profile: H265Profile = .unknown,
    h264_level: u8 = 0,
    h265_level: u8 = 0,
    h264_profile_detected: bool = false,
    h265_profile_detected: bool = false,

    // Fixed-size buffers for performance
    frame_buffer: [MAX_FRAME_SIZE]u8,
    frame_buffer_len: usize,
    temp_buffer: [MAX_TEMP_SIZE]u8,
    temp_buffer_len: usize,

    const ANNEX_B_START_CODE = [_]u8{ 0x00, 0x00, 0x00, 0x01 };

    pub fn init(allocator: Allocator) RtpDepacketizer {
        return RtpDepacketizer{
            .allocator = allocator,
            .h264_frag_state = FragmentationState.init(),
            .h265_frag_state = FragmentationState.init(),
            .sps_h264 = undefined,
            .sps_h264_len = 0,
            .pps_h264 = undefined,
            .pps_h264_len = 0,
            .vps_h265 = undefined,
            .vps_h265_len = 0,
            .sps_h265 = undefined,
            .sps_h265_len = 0,
            .pps_h265 = undefined,
            .pps_h265_len = 0,
            .frame_buffer = undefined,
            .frame_buffer_len = 0,
            .temp_buffer = undefined,
            .temp_buffer_len = 0,
        };
    }

    pub fn deinit(self: *RtpDepacketizer) void {
        _ = self;
        // No cleanup needed for stack buffers
    }

    fn resetFrameBuffer(self: *RtpDepacketizer) void {
        self.frame_buffer_len = 0;
    }

    fn resetTempBuffer(self: *RtpDepacketizer) void {
        self.temp_buffer_len = 0;
    }

    fn appendToFrameBuffer(self: *RtpDepacketizer, data: []const u8) !void {
        if (self.frame_buffer_len + data.len > MAX_FRAME_SIZE) {
            return error.BufferOverflow;
        }
        @memcpy(self.frame_buffer[self.frame_buffer_len .. self.frame_buffer_len + data.len], data);
        self.frame_buffer_len += data.len;
    }

    fn appendToTempBuffer(self: *RtpDepacketizer, data: []const u8) !void {
        if (self.temp_buffer_len + data.len > MAX_TEMP_SIZE) {
            return error.BufferOverflow;
        }
        @memcpy(self.temp_buffer[self.temp_buffer_len .. self.temp_buffer_len + data.len], data);
        self.temp_buffer_len += data.len;
    }

    fn getFrameBufferSlice(self: *const RtpDepacketizer) []const u8 {
        return self.frame_buffer[0..self.frame_buffer_len];
    }

    fn getTempBufferSlice(self: *const RtpDepacketizer) []const u8 {
        return self.temp_buffer[0..self.temp_buffer_len];
    }

    fn detectH264Profile(sps_data: []const u8) struct { profile: H264Profile, level: u8 } {
        if (sps_data.len < 4) return .{ .profile = .unknown, .level = 0 };

        const profile_idc = sps_data[1];
        const level_idc = sps_data[3];

        const profile: H264Profile = switch (profile_idc) {
            66 => .baseline,
            77 => .main,
            88 => .extended,
            100 => .high,
            110 => .high10,
            122 => .high422,
            244 => .high444,
            else => .unknown,
        };

        return .{ .profile = profile, .level = level_idc };
    }

    fn detectH265Profile(sps_data: []const u8) struct { profile: H265Profile, level: u8 } {
        if (sps_data.len < 8) return .{ .profile = .unknown, .level = 0 };

        var offset: usize = 3; // Skip NAL header + VPS/layer info
        if (offset >= sps_data.len) return .{ .profile = .unknown, .level = 0 };

        const profile_tier_byte = sps_data[offset];
        const general_profile_idc = profile_tier_byte & 0x1F;

        offset += 10; // Skip profile compatibility flags and constraint flags
        const general_level_idc = if (offset < sps_data.len) sps_data[offset] else 0;

        const profile: H265Profile = switch (general_profile_idc) {
            1 => .main,
            2 => .main10,
            3 => .main_still_picture,
            4 => .range_extensions,
            5 => .high_throughput,
            9 => .screen_content_coding,
            else => .unknown,
        };

        return .{ .profile = profile, .level = general_level_idc };
    }

    fn generateCodecString(self: *RtpDepacketizer, codec: @TypeOf(@as(DepacketizedFrame, undefined).codec)) []const u8 {
        return switch (codec) {
            .h264 => switch (self.h264_profile) {
                .baseline => "avc1.42E01E",
                .main => "avc1.4D401E",
                .extended => "avc1.58401E",
                .high => "avc1.64001E",
                .high10 => "avc1.6E001E",
                .high422 => "avc1.7A001E",
                .high444 => "avc1.F4001E",
                .unknown => "avc1.42E01E",
            },
            .h265 => switch (self.h265_profile) {
                .main => "hev1.1.6.L93.B0",
                .main10 => "hev1.2.4.L93.B0",
                .main_still_picture => "hev1.3.6.L93.B0",
                .range_extensions => "hev1.4.4.L93.B0",
                .high_throughput => "hev1.5.4.L93.B0",
                .screen_content_coding => "hev1.9.4.L93.B0",
                .unknown => "hev1.1.6.L93.B0",
            },
        };
    }

    fn storeH264Sps(self: *RtpDepacketizer, sps_data: []const u8) !void {
        if (sps_data.len > MAX_PARAM_SIZE) return error.BufferOverflow;
        @memcpy(self.sps_h264[0..sps_data.len], sps_data);
        self.sps_h264_len = sps_data.len;

        if (!self.h264_profile_detected) {
            const profile_info = detectH264Profile(sps_data);
            self.h264_profile = profile_info.profile;
            self.h264_level = profile_info.level;
            self.h264_profile_detected = true;
        }
    }

    fn storeH264Pps(self: *RtpDepacketizer, pps_data: []const u8) !void {
        if (pps_data.len > MAX_PARAM_SIZE) return error.BufferOverflow;
        @memcpy(self.pps_h264[0..pps_data.len], pps_data);
        self.pps_h264_len = pps_data.len;
    }

    fn storeH265Vps(self: *RtpDepacketizer, vps_data: []const u8) !void {
        if (vps_data.len > MAX_PARAM_SIZE) return error.BufferOverflow;
        @memcpy(self.vps_h265[0..vps_data.len], vps_data);
        self.vps_h265_len = vps_data.len;
    }

    fn storeH265Sps(self: *RtpDepacketizer, sps_data: []const u8) !void {
        if (sps_data.len > MAX_PARAM_SIZE) return error.BufferOverflow;
        @memcpy(self.sps_h265[0..sps_data.len], sps_data);
        self.sps_h265_len = sps_data.len;

        if (!self.h265_profile_detected) {
            const profile_info = detectH265Profile(sps_data);
            self.h265_profile = profile_info.profile;
            self.h265_level = profile_info.level;
            self.h265_profile_detected = true;
        }
    }

    fn storeH265Pps(self: *RtpDepacketizer, pps_data: []const u8) !void {
        if (pps_data.len > MAX_PARAM_SIZE) return error.BufferOverflow;
        @memcpy(self.pps_h265[0..pps_data.len], pps_data);
        self.pps_h265_len = pps_data.len;
    }

    fn detectCodecFromPayload(payload: []const u8) ?enum { h264, h265 } {
        if (payload.len == 0) return null;

        // H.265 detection first (more specific)
        if (payload.len >= 2) {
            const h265_nal_type = (payload[0] >> 1) & 0x3F;
            if (h265_nal_type == 48 or h265_nal_type == 49 or
                (h265_nal_type >= 32 and h265_nal_type <= 40))
            {
                return .h265;
            }
        }

        // H.264 detection
        const h264_nal_type = payload[0] & 0x1F;
        if (h264_nal_type == 24 or h264_nal_type == 28 or
            (h264_nal_type >= 1 and h264_nal_type <= 12))
        {
            return .h264;
        }

        return null;
    }

    pub fn processRtpPacket(self: *RtpDepacketizer, data: []const u8) !?DepacketizedFrame {
        if (data.len < 12) return null;

        const header = self.parseRtpHeader(data);
        const payload = data[12..];
        if (payload.len == 0) return null;

        const codec = detectCodecFromPayload(payload) orelse return null;

        // Early exit if profile not detected for non-parameter sets
        const first_byte = payload[0];
        const is_param_set = switch (codec) {
            .h264 => (first_byte & 0x1F) >= 7 and (first_byte & 0x1F) <= 8,
            .h265 => ((first_byte >> 1) & 0x3F) >= 32 and ((first_byte >> 1) & 0x3F) <= 34,
        };

        if (!is_param_set) {
            switch (codec) {
                .h264 => if (!self.h264_profile_detected) return null,
                .h265 => if (!self.h265_profile_detected) return null,
            }
        }

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
            49 => self.processH265FragmentationUnit(payload, header),
            48 => self.processH265AggregationPacket(payload, header),
            32 => {
                try self.storeH265Vps(payload);
                return null;
            },
            33 => {
                try self.storeH265Sps(payload);
                return null;
            },
            34 => {
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

            const reconstructed_nal = (fu_indicator & 0xE0) | nal_type;
            try self.h264_frag_state.appendByte(reconstructed_nal);
        }

        try self.h264_frag_state.append(payload[2..]);

        if (end_bit) {
            return try self.createFrame(self.h264_frag_state.getSlice(), self.h264_frag_state.timestamp, nal_type == 5, .h264);
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

            try self.h265_frag_state.appendByte((nal_type << 1) | (payload[0] & 0x01));
            try self.h265_frag_state.appendByte(payload[1]);
        }

        try self.h265_frag_state.append(payload[3..]);

        if (end_bit) {
            const is_keyframe = nal_type >= 16 and nal_type <= 23;
            return try self.createFrame(self.h265_frag_state.getSlice(), self.h265_frag_state.timestamp, is_keyframe, .h265);
        }

        return null;
    }

    fn processH264SingleNalu(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        const nal_type = payload[0] & 0x1F;
        const is_keyframe = nal_type == 5;
        return try self.createFrame(payload, header.timestamp, is_keyframe, .h264);
    }

    fn processH265SingleNalu(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        const nal_type = (payload[0] >> 1) & 0x3F;
        const is_keyframe = nal_type >= 16 and nal_type <= 23;
        return try self.createFrame(payload, header.timestamp, is_keyframe, .h265);
    }

    fn processH264StapA(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        self.resetTempBuffer();

        var offset: usize = 1;
        var is_keyframe = false;

        while (offset < payload.len) {
            if (offset + 2 > payload.len) break;

            const nalu_size = std.mem.readInt(u16, payload[offset .. offset + 2][0..2], .big);
            offset += 2;

            if (offset + nalu_size > payload.len) break;

            const nalu = payload[offset .. offset + nalu_size];
            const nal_type = nalu[0] & 0x1F;

            if (nal_type == 5) is_keyframe = true;

            try self.appendToTempBuffer(&ANNEX_B_START_CODE);
            try self.appendToTempBuffer(nalu);

            offset += nalu_size;
        }

        return try self.createFrameFromBuffer(self.getTempBufferSlice(), header.timestamp, is_keyframe, .h264);
    }

    fn processH265AggregationPacket(self: *RtpDepacketizer, payload: []const u8, header: RtpHeader) !?DepacketizedFrame {
        self.resetTempBuffer();

        var offset: usize = 2;
        var is_keyframe = false;

        while (offset < payload.len) {
            if (offset + 2 > payload.len) break;

            const nalu_size = std.mem.readInt(u16, payload[offset .. offset + 2][0..2], .big);
            offset += 2;

            if (offset + nalu_size > payload.len) break;

            const nalu = payload[offset .. offset + nalu_size];
            const nal_type = (nalu[0] >> 1) & 0x3F;

            if (nal_type >= 16 and nal_type <= 23) is_keyframe = true;

            try self.appendToTempBuffer(&ANNEX_B_START_CODE);
            try self.appendToTempBuffer(nalu);

            offset += nalu_size;
        }

        return try self.createFrameFromBuffer(self.getTempBufferSlice(), header.timestamp, is_keyframe, .h265);
    }

    fn createFrame(self: *RtpDepacketizer, data: []const u8, timestamp: u32, is_keyframe: bool, codec: @TypeOf(@as(DepacketizedFrame, undefined).codec)) !DepacketizedFrame {
        self.resetFrameBuffer();

        if (is_keyframe) {
            switch (codec) {
                .h264 => {
                    if (self.sps_h264_len > 0) {
                        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
                        try self.appendToFrameBuffer(self.sps_h264[0..self.sps_h264_len]);
                    }
                    if (self.pps_h264_len > 0) {
                        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
                        try self.appendToFrameBuffer(self.pps_h264[0..self.pps_h264_len]);
                    }
                },
                .h265 => {
                    if (self.vps_h265_len > 0) {
                        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
                        try self.appendToFrameBuffer(self.vps_h265[0..self.vps_h265_len]);
                    }
                    if (self.sps_h265_len > 0) {
                        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
                        try self.appendToFrameBuffer(self.sps_h265[0..self.sps_h265_len]);
                    }
                    if (self.pps_h265_len > 0) {
                        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
                        try self.appendToFrameBuffer(self.pps_h265[0..self.pps_h265_len]);
                    }
                },
            }
        }

        try self.appendToFrameBuffer(&ANNEX_B_START_CODE);
        try self.appendToFrameBuffer(data);

        const profile_info = switch (codec) {
            .h264 => @as(@TypeOf(@as(DepacketizedFrame, undefined).profile), .{ .h264 = self.h264_profile }),
            .h265 => @as(@TypeOf(@as(DepacketizedFrame, undefined).profile), .{ .h265 = self.h265_profile }),
        };

        const level = switch (codec) {
            .h264 => self.h264_level,
            .h265 => self.h265_level,
        };

        return DepacketizedFrame{
            .data = try self.allocator.dupe(u8, self.getFrameBufferSlice()),
            .timestamp = timestamp,
            .is_keyframe = is_keyframe,
            .codec = codec,
            .profile = profile_info,
            .level = level,
        };
    }

    fn createFrameFromBuffer(self: *RtpDepacketizer, data: []const u8, timestamp: u32, is_keyframe: bool, codec: @TypeOf(@as(DepacketizedFrame, undefined).codec)) !DepacketizedFrame {
        const owned_data = try self.allocator.dupe(u8, data);

        const profile_info = switch (codec) {
            .h264 => @as(@TypeOf(@as(DepacketizedFrame, undefined).profile), .{ .h264 = self.h264_profile }),
            .h265 => @as(@TypeOf(@as(DepacketizedFrame, undefined).profile), .{ .h265 = self.h265_profile }),
        };

        const level = switch (codec) {
            .h264 => self.h264_level,
            .h265 => self.h265_level,
        };

        return DepacketizedFrame{
            .data = owned_data,
            .timestamp = timestamp,
            .is_keyframe = is_keyframe,
            .codec = codec,
            .profile = profile_info,
            .level = level,
        };
    }
};
