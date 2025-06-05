const std = @import("std");

pub fn zig_print(comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdOut().writer();
    writer.print("[zig] -> " ++ format, args) catch unreachable;
}
pub fn zig_err(comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdErr().writer();
    writer.print("[zig] -> " ++ format, args) catch unreachable;
}
