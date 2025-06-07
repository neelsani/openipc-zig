const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;
const net = std.net;

var conn: ?std.posix.socket_t = null;
var target_addr: ?net.Address = null;
pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator;
    zig_print("posix specific initialized!\n", .{});
}

pub fn deinit(allocator: std.mem.Allocator) void {
    _ = allocator;
    zig_print("posix specific deinitialized!\n", .{});
}

pub fn onIEEFrame(rssi: i32, snr: i32) void {
    _ = rssi;
    _ = snr;
}

pub fn handleRtp(allocator: std.mem.Allocator, data: []const u8) void {
    _ = allocator; // Not needed for this implementation

    // Check if connection exists, if not create it
    if (conn == null or target_addr == null) {
        // Create UDP socket
        const sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch |err| {
            zig_err("Failed to create UDP socket: {any}\n", .{err});
            return;
        };

        // Resolve target address (localhost:5004)
        const addr = net.Address.resolveIp("127.0.0.1", 5004) catch |err| {
            zig_err("Failed to resolve address: {any}\n", .{err});
            std.posix.close(sock);
            return;
        };

        conn = sock;
        target_addr = addr;
        zig_print("UDP connection created to 127.0.0.1:5004\n", .{});
    }

    // Send RTP packet using existing connection
    const sock = conn.?;
    const addr = target_addr.?;

    const sent = std.posix.sendto(sock, data, 0, &addr.any, addr.getOsSockLen()) catch |err| {
        zig_err("Failed to send RTP packet: {any}\n", .{err});
        return;
    };

    zig_print("Sent RTP packet: {} bytes\n", .{sent});
}
