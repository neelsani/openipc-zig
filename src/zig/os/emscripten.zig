const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;
// This handles the @cImport with proper Emscripten support
const c = @cImport({
    @cInclude("pthread.h");
});
const rtp = @import("../rtp/rtp.zig");

extern fn displayFrame(data_ptr: [*]const u8, data_len: usize, codec_type: u32, is_key_frame: bool) void;

pub fn handleRtp(allocator: std.mem.Allocator, data: []const u8) void {
    zig_print("Processing RTP packet: {} bytes\n", .{data.len});

    var parsed_payload = rtp.parse(allocator, data) catch |err| {
        zig_err("RTP parsing failed: {any}\n", .{err});
        return;
    };

    switch (parsed_payload) {
        .h264 => |*frame_data| {
            zig_print("Received H.264 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            displayFrame(frame_data.data.ptr, frame_data.data.len, 0, frame_data.is_key_frame);

            // Clean up allocated memory
            frame_data.deinit(allocator);
        },
        .h265 => |*frame_data| {
            zig_print("Received H.265 frame: NAL type {any}, key frame: {}\n", .{ frame_data.nal_type, frame_data.is_key_frame });
            displayFrame(frame_data.data.ptr, frame_data.data.len, 1, frame_data.is_key_frame);

            // Clean up allocated memory

            frame_data.deinit(allocator);
        },
        .unknown => {
            zig_err("Received packet with unknown codec\n", .{});
        },
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
