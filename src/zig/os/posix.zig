const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;
const net = std.net;

const BitrateCalculator = @import("../rtp/bitrate.zig").BitrateCalculator;
const rtp = @import("../rtp/rtp.zig");
var depacketizer: ?rtp.RtpDepacketizer = null;
var rtp_bitrate_calc = BitrateCalculator{};
var video_bitrate_calc = BitrateCalculator{};

var conn: ?std.posix.socket_t = null;
var target_addr: ?net.Address = null;
var allocator1: ?std.mem.Allocator = null;
pub fn init(allocator: std.mem.Allocator) void {
    depacketizer = rtp.RtpDepacketizer.init(allocator);
    zig_print("depacketizer initialized!\n", .{});

    zig_print("posix specific initialized!\n", .{});
}
export fn handle_Rtpdata(data: [*]const u8, len: u16) void {
    rtp_bitrate_calc.addBytes(data[0..len].len);
    handleRtp(depacketizer.?.allocator, data[0..len]);
    zig_print("rtp -> {d} mbps   video ->  {d} mbps\n", .{ rtp_bitrate_calc.getBitrateMbps(), video_bitrate_calc.getBitrateMbps() });
}

pub fn deinit(allocator: std.mem.Allocator) void {
    _ = allocator;
    zig_print("posix specific deinitialized!\n", .{});
}

pub fn onIEEFrame(rssi: i32, snr: i32) void {
    _ = rssi;
    _ = snr;
}
pub fn handleRtp1(allocator: std.mem.Allocator, data: []const u8) void {
    zig_print("Processing RTP packet: {} bytes\n", .{data.len});
    if (depacketizer) |*depak| {
        var result = depak.processRtpPacket(data) catch |err| {
            zig_err("Failed to parse rtp frame {any}!!\n", .{err});
            return;
        };

        if (result) |*frame| {
            defer frame.deinit(allocator);
            video_bitrate_calc.addBytes(frame.data.len);
            //displayFrame(frame.data.ptr, @intCast(frame.data.len), @intFromEnum(frame.codec), @intFromEnum(std.meta.activeTag(frame.profile)), frame.is_keyframe);
        }
    } else {
        zig_err("Warning depacketizer not initialized!!\n", .{});
    }
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
pub fn getGsKey(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, "gs.key");
}
