const std = @import("std");

pub const BitrateCalculator = struct {
    bytes_accumulated: u64 = 0,
    last_calculation_time: i64 = 0,
    current_bitrate_bps: f64 = 0.0,

    pub fn addBytes(self: *BitrateCalculator, byte_count: u64) void {
        self.bytes_accumulated += byte_count;

        const now = std.time.milliTimestamp();

        // Initialize on first call
        if (self.last_calculation_time == 0) {
            self.last_calculation_time = now;
            return;
        }

        // Calculate every 1000ms (1 second)
        const elapsed_ms = now - self.last_calculation_time;
        if (elapsed_ms >= 1000) {
            // Convert bytes to bits and calculate bits per second
            const bits_accumulated = self.bytes_accumulated * 8;
            self.current_bitrate_bps = @as(f64, @floatFromInt(bits_accumulated * 1000)) / @as(f64, @floatFromInt(elapsed_ms));

            // Reset for next calculation
            self.bytes_accumulated = 0;
            self.last_calculation_time = now;
        }
    }

    pub fn getBitrateMbps(self: *const BitrateCalculator) f64 {
        return self.current_bitrate_bps / 1_000_000.0;
    }

    pub fn getBitrateKbps(self: *const BitrateCalculator) f64 {
        return self.current_bitrate_bps / 1_000.0;
    }
};
