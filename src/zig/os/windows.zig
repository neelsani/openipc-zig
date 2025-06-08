const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;

pub const handleRtp = @import("posix.zig").handleRtp;

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    zig_print("windows specific initialized!\n", .{});
}

pub fn deinit(allocator: std.mem.Allocator) void {
    _ = allocator;
    zig_print("windows specific deinitialized!\n", .{});
}
pub fn onIEEFrame(rssi: i32, snr: i32) void {
    _ = rssi;
    _ = snr;
}
pub const getGsKey = @import("posix.zig").getGsKey;
