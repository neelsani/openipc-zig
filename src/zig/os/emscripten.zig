const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;
// This handles the @cImport with proper Emscripten support
const c = @cImport({
    @cInclude("pthread.h");
});
const rtp = @import("../rtp/rtp.zig");

var depacketizer: ?rtp.RtpDepacketizer = null;

extern fn displayFrame(data_ptr: [*]const u8, data_len: usize, codec_type: u32, profile: u32, is_key_frame: bool) void;

pub extern fn onIEEFrame(rssi: u8, snr: i8) void;

pub fn init(allocator: std.mem.Allocator) void {
    depacketizer = rtp.RtpDepacketizer.init(allocator);
    zig_print("depacketizer initialized!\n", .{});

    zig_print("wasm specific initialized!\n", .{});
}

pub fn handleRtp(allocator: std.mem.Allocator, data: []const u8) void {
    zig_print("Processing RTP packet: {} bytes\n", .{data.len});

    if (depacketizer) |*depak| {
        var result = depak.processRtpPacket(data) catch |err| {
            zig_err("Failed to parse rtp frame {any}!!\n", .{err});
            return;
        };

        if (result) |*frame| {
            defer frame.deinit(allocator);
            displayFrame(frame.data.ptr, @intCast(frame.data.len), @intFromEnum(frame.codec), @intFromEnum(std.meta.activeTag(frame.profile)), frame.is_keyframe);
        }
    } else {
        zig_err("Warning depacketizer not initialized!!\n", .{});
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    _ = allocator;
    if (depacketizer) |dep| {
        dep.deinit();
    }
}
// Re-export pthread types and functions
const pthread_t = c.pthread_t;
const pthread_create = c.pthread_create;
const pthread_join = c.pthread_join;

// Re-export mutex types and functions
const pthread_mutex_t = c.pthread_mutex_t;
const pthread_mutex_init = c.pthread_mutex_init;
const pthread_mutex_destroy = c.pthread_mutex_destroy;
const pthread_mutex_lock = c.pthread_mutex_lock;
const pthread_mutex_unlock = c.pthread_mutex_unlock;
const pthread_mutex_trylock = c.pthread_mutex_trylock;

fn WebWorker(comptime SharedDataType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        shared_data: *SharedDataType,
        worker_entrypoint: ?*const fn (shared_data: *SharedDataType) anyerror!void = null,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            shared_data: *SharedDataType,
            worker_entrypoint: ?*const fn (shared_data: *SharedDataType) anyerror!void,
        ) !*Self {
            const self = try allocator.create(Self);
            self.* = Self{ .allocator = allocator, .shared_data = shared_data, .worker_entrypoint = worker_entrypoint };
            var thread: pthread_t = undefined;
            const rc = pthread_create(&thread, null, workerEntrypoint, self);
            if (rc != 0) {
                std.debug.print("Failed to create thread\n", .{});
                return error.FailedToCreateThread;
            }

            return self;
        }
        fn workerEntrypoint(self_: ?*anyopaque) callconv(.c) ?*anyopaque {
            const self: *Self = @ptrCast(@alignCast(self_));

            if (self.worker_entrypoint) |entrypoint| {
                entrypoint(self.shared_data) catch |err| {
                    std.debug.print("Error in worker_entrypoint: {}\n", .{err});
                    return null;
                };
            }
            return null;
        }
    };
}
