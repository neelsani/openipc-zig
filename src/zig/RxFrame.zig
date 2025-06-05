// File: rx_frame.zig
const std = @import("std");

/// Dummy enum placeholder for RadioPort (fill in as needed).
pub const RadioPort = enum {};

pub const RxFrame = struct {
    data: []const u8,
    dataAsMemory: []const u8,

    /// Same fixed header bytes as in C++.
    pub const dataHeader: [2]u8 = [_]u8{ 0x08, 0x01 };

    /// “Constructor”: store the slice and mirror it in dataAsMemory.
    pub fn init(data: []const u8) RxFrame {
        return RxFrame{
            .data = data,
            .dataAsMemory = data,
        };
    }

    /// Equivalent of `ControlField()` → first 2 bytes.
    pub fn controlField(self: *const RxFrame) []const u8 {
        return self.data[0..2];
    }

    /// Equivalent of `Duration()` → bytes 2–4.
    pub fn duration(self: *const RxFrame) []const u8 {
        return self.data[2..4];
    }

    /// Equivalent of `MacAp()` → bytes 4–10.
    pub fn macAp(self: *const RxFrame) []const u8 {
        return self.data[4..10];
    }

    /// Equivalent of `MacSrcUniqueIdPart()` → byte 10.
    pub fn macSrcUniqueIdPart(self: *const RxFrame) []const u8 {
        return self.data[10..11];
    }

    /// Equivalent of `MacSrcNoncePart1()` → bytes 11–15.
    pub fn macSrcNoncePart1(self: *const RxFrame) []const u8 {
        return self.data[11..15];
    }

    /// Equivalent of `MacSrcRadioPort()` → byte 15.
    pub fn macSrcRadioPort(self: *const RxFrame) []const u8 {
        return self.data[15..16];
    }

    /// Equivalent of `MacDstUniqueIdPart()` → byte 16.
    pub fn macDstUniqueIdPart(self: *const RxFrame) []const u8 {
        return self.data[16..17];
    }

    /// Equivalent of `MacDstNoncePart2()` → bytes 17–21.
    pub fn macDstNoncePart2(self: *const RxFrame) []const u8 {
        return self.data[17..21];
    }

    /// Equivalent of `MacDstRadioPort()` → byte 21.
    pub fn macDstRadioPort(self: *const RxFrame) []const u8 {
        return self.data[21..22];
    }

    /// Equivalent of `SequenceControl()` → bytes 22–24.
    pub fn sequenceControl(self: *const RxFrame) []const u8 {
        return self.data[22..24];
    }

    /// Equivalent of `PayloadSpan()` → bytes 24..(size−4).
    /// (Original C++ used `size() - 28`, i.e. 24 .. (size−4) since total header was 24 + 4)
    pub fn payloadSpan(self: *const RxFrame) []const u8 {
        const total_len = self.data.len;
        // payload runs from index 24 up to total_len − 4
        return self.data[24..(total_len - 4)];
    }

    /// Equivalent of `GetNonce()`: concatenate bytes [11..15) and [17..21) into an [8]u8.
    pub fn getNonce(self: *const RxFrame) [8]u8 {
        var nonce: [8]u8 = undefined;
        _ = std.mem.copy(u8, nonce[0..4], self.data[11..15]);
        _ = std.mem.copy(u8, nonce[4..8], self.data[17..21]);
        return nonce;
    }

    /// Equivalent of `IsValidWfbFrame()`.
    pub fn isValidWfbFrame(self: *const RxFrame) bool {
        if (self.data.len == 0) return false;
        if (!self.isDataFrame()) return false;
        if (self.payloadSpan().len == 0) return false;
        if (!self.hasValidAirGndId()) return false;
        if (!self.hasValidRadioPort()) return false;
        return true;
    }

    /// Equivalent of `GetValidAirGndId()`.
    pub fn getValidAirGndId(self: *const RxFrame) u8 {
        return self.data[10];
    }

    /// Equivalent of `MatchesChannelID(const uint8_t *channel_id)`.
    pub fn matchesChannelID(self: *const RxFrame, channel_id: [4]u8) bool {
        return self.data[10] == 0x57 and
            self.data[11] == 0x42 and
            self.data[12] == channel_id[0] and
            self.data[13] == channel_id[1] and
            self.data[14] == channel_id[2] and
            self.data[15] == channel_id[3] and
            self.data[16] == 0x57 and
            self.data[17] == 0x42 and
            self.data[18] == channel_id[0] and
            self.data[19] == channel_id[1] and
            self.data[20] == channel_id[2] and
            self.data[21] == channel_id[3];
    }

    /// Internal helper: is it a Data frame?  Checks first two bytes == {0x08, 0x01}.
    fn isDataFrame(self: *const RxFrame) bool {
        return self.data.len >= 2 and self.data[0] == RxFrame.dataHeader[0] and self.data[1] == RxFrame.dataHeader[1];
    }

    fn hasValidAirGndId(self: *const RxFrame) bool {
        return self.data.len >= 18 and self.data[10] == self.data[16];
    }

    fn hasValidRadioPort(self: *const RxFrame) bool {
        return self.data.len >= 22 and self.data[15] == self.data[21];
    }
};

/// Zig‐side equivalent of the C++ WifiFrame class.
pub const WifiFrame = struct {
    frameControl: u16,
    durationID: u16,
    receiverAddress: [6]u8,
    transmitterAddress: [6]u8,
    destinationAddress: [6]u8,
    sourceAddress: [6]u8,
    sequenceControl: u16,

    /// The C++ version commented out "sourceAddress" and "frameBody/frameCheckSequence".
    /// We replicate precisely what was active in the original.
    pub fn init(rawData: []const u8) WifiFrame {
        var f: WifiFrame = undefined;
        // Frame Control: (rawData[1] << 8) | rawData[0] → little-endian read
        f.frameControl = std.mem.readInt(u16, rawData[0..2], .little);
        // Duration/ID: (rawData[3] << 8) | rawData[2]
        f.durationID = std.mem.readInt(u16, rawData[2..4], .little);
        // Receiver Address (6 bytes) from rawData[4..10)
        _ = std.mem.copyForwards(u8, &f.receiverAddress, rawData[4..10]);
        // Transmitter Address (6 bytes) from rawData[10..16)
        _ = std.mem.copyForwards(u8, &f.transmitterAddress, rawData[10..16]);
        // Destination Address (6 bytes) from rawData[16..22)
        _ = std.mem.copyForwards(u8, &f.destinationAddress, rawData[16..22]);
        // Sequence Control: (rawData[22] << 8) | rawData[22] (as in C++: “(rawData[22] << 8) | rawData[22]”)
        f.sequenceControl = std.mem.readInt(u16, rawData[22..24], .little);
        return f;
    }
};
