const std = @import("std");

const c = @cImport({
    @cInclude("wrapper.h");
});

pub fn main() !void {
    try std.io.getStdOut().writer().print("hello\n", .{});
    _ = c.zig_cpp_main();
    return;
}
