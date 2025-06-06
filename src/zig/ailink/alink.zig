const std = @import("std");
const net = std.net;
const json = std.json;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const HashMap = std.HashMap;

const DEFAULT_CONFIG =
    \\# adaptive-link VRX settings
    \\
    \\[outgoing]
    \\udp_ip = 10.5.0.10
    \\udp_port = 9999
    \\
    \\[json]
    \\HOST = 127.0.0.1
    \\PORT = 8103
    \\
    \\[weights]
    \\snr_weight = 0.5
    \\rssi_weight = 0.5
    \\
    \\[ranges]
    \\SNR_MIN = 12
    \\SNR_MAX = 38
    \\RSSI_MIN = -80
    \\RSSI_MAX = -30
    \\
    \\[keyframe]
    \\allow_idr = True
    \\idr_max_messages = 20
    \\
    \\[dynamic refinement]
    \\allow_penalty = True
    \\allow_fec_increase = True
    \\
    \\[noise]
    \\min_noise = 0.01
    \\max_noise = 0.1
    \\deduction_exponent = 0.5
    \\min_noise_for_fec_change = 0.01
    \\noise_for_max_fec_change = 0.1
    \\
    \\[error estimation]
    \\kalman_estimate = 0.005
    \\kalman_error_estimate = 0.1
    \\process_variance = 1e-5
    \\measurement_variance = 0.01
;

const Config = struct {
    // Outgoing settings
    udp_ip: []const u8,
    udp_port: u16,

    // JSON settings
    host: []const u8,
    port: u16,

    // Weights
    snr_weight: f32,
    rssi_weight: f32,

    // Ranges
    snr_min: i32,
    snr_max: i32,
    rssi_min: i32,
    rssi_max: i32,

    // Keyframe settings
    allow_idr: bool,
    idr_max_messages: u32,

    // Dynamic refinement
    allow_penalty: bool,
    allow_fec_increase: bool,

    // Noise parameters
    min_noise: f32,
    max_noise: f32,
    deduction_exponent: f32,
    min_noise_for_fec_change: f32,
    noise_for_max_fec_change: f32,

    // Error estimation
    kalman_estimate: f32,
    kalman_error_estimate: f32,
    process_variance: f32,
    measurement_variance: f32,
};

const AppState = struct {
    allocator: Allocator,
    config: Config,
    verbose_mode: bool,

    // UDP socket
    udp_socket: net.Stream,

    // Global state variables
    best_rssi: ?i32 = null,
    best_snr: ?i32 = null,
    all_packets: ?u32 = null,
    fec_rec_packets: ?u32 = null,
    lost_packets: ?u32 = null,
    fec_k: ?u32 = null,
    fec_n: ?u32 = null,
    receiving_video: ?bool = null,
    num_antennas: ?u32 = null,
    penalty: f32 = 0,
    fec_change: i32 = 0,
    final_score: f32 = 1000,
    waiting_for_video_printed: bool = false,
    video_rx_initial_message_printed: bool = false,

    // Keyframe request globals
    keyframe_request_code: ?[]u8 = null,
    keyframe_request_remaining: u32 = 0,

    // Kalman Filter variables
    kalman_estimate: f32,
    kalman_error_estimate: f32,
};

const RxAntStats = struct {
    rssi_avg: ?i32,
    snr_avg: ?i32,
    mcs: ?u32,
};

const PacketStats = struct {
    all: ?u32,
    fec_rec: ?u32,
    lost: ?u32,
};

const SessionInfo = struct {
    fec_k: ?u32,
    fec_n: ?u32,
};

const VideoRxData = struct {
    type: []const u8,
    id: []const u8,
    packets: PacketStats,
    session: ?SessionInfo,
    rx_ant_stats: []RxAntStats,
};

fn createDefaultConfig(config_file: []const u8) !void {
    const file = std.fs.cwd().createFile(config_file, .{}) catch |err| {
        print("Error creating config file: {}\n", .{err});
        return;
    };
    defer file.close();

    _ = try file.writeAll(DEFAULT_CONFIG);
    print("Created default config file at {s}\n", .{config_file});
}

fn loadConfiguration(config_file: []const u8, allocator: Allocator) !Config {
    // Simplified config loading - in a real implementation, you'd want to use
    // a proper INI parser. For now, using default values.
    _ = config_file;
    _ = allocator;

    return Config{
        .udp_ip = "10.5.0.10",
        .udp_port = 9999,
        .host = "127.0.0.1",
        .port = 8103,
        .snr_weight = 0.5,
        .rssi_weight = 0.5,
        .snr_min = 12,
        .snr_max = 38,
        .rssi_min = -80,
        .rssi_max = -30,
        .allow_idr = true,
        .idr_max_messages = 20,
        .allow_penalty = true,
        .allow_fec_increase = true,
        .min_noise = 0.01,
        .max_noise = 0.1,
        .deduction_exponent = 0.5,
        .min_noise_for_fec_change = 0.01,
        .noise_for_max_fec_change = 0.1,
        .kalman_estimate = 0.005,
        .kalman_error_estimate = 0.1,
        .process_variance = 1e-5,
        .measurement_variance = 0.01,
    };
}

fn generateRandomString(allocator: Allocator, length: usize) ![]u8 {
    const chars = "abcdefghijklmnopqrstuvwxyz";
    const result = try allocator.alloc(u8, length);
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.os.getrandom(std.mem.asBytes(&seed)) catch 0;
        break :blk seed;
    });
    const random = prng.random();

    for (result) |*c| {
        c.* = chars[random.intRangeAtMost(usize, 0, chars.len - 1)];
    }

    return result;
}

fn sendUdp(state: *AppState, message: []const u8) !void {
    const message_size = @as(u32, @intCast(message.len));
    var size_bytes: [4]u8 = undefined;
    std.mem.writeIntBig(u32, &size_bytes, message_size);

    const udp_addr = try net.Address.parseIp(state.config.udp_ip, state.config.udp_port);
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.DGRAM, 0);
    defer std.os.closeSocket(socket);

    var full_message = try state.allocator.alloc(u8, 4 + message.len);
    defer state.allocator.free(full_message);

    std.mem.copy(u8, full_message[0..4], &size_bytes);
    std.mem.copy(u8, full_message[4..], message);

    _ = try std.os.sendto(socket, full_message, 0, &udp_addr.any, udp_addr.getOsSockLen());

    if (state.verbose_mode) {
        print("\nUDP Message Sent: {s} (size: {} bytes)\n\n", .{ message, message.len });
    }
}

fn kalmanFilterUpdate(state: *AppState, measurement: f32) f32 {
    const predicted_estimate = state.kalman_estimate;
    const predicted_error = state.kalman_error_estimate + state.config.process_variance;

    const kalman_gain = predicted_error / (predicted_error + state.config.measurement_variance);

    state.kalman_estimate = predicted_estimate + kalman_gain * (measurement - predicted_estimate);
    state.kalman_error_estimate = (1 - kalman_gain) * predicted_error;

    return state.kalman_estimate;
}

fn adjustFecRecovered(fec_rec: u32, fec_k: ?u32, fec_n: ?u32) f32 {
    if (fec_k == null or fec_n == null or fec_n.? == 0) {
        return @floatFromInt(fec_rec);
    }

    const redundancy = @as(f32, @floatFromInt(fec_n.? - fec_k.?));
    const weight = 6.0 / (1 + redundancy);
    return @as(f32, @floatFromInt(fec_rec)) * weight;
}

fn generateMessage(state: *AppState) !void {
    const timestamp = std.time.timestamp();

    var message_buf: [512]u8 = undefined;
    var message = try std.fmt.bufPrint(&message_buf, "{}:{}:{}:{}:{}:{}:{}:{}:{}:{}", .{
        timestamp,
        @as(i32, @intFromFloat(state.final_score)),
        @as(i32, @intFromFloat(state.final_score)),
        state.fec_rec_packets orelse 0,
        state.lost_packets orelse 0,
        state.best_rssi orelse 0,
        state.best_snr orelse 0,
        state.num_antennas orelse 0,
        @as(i32, @intFromFloat(state.penalty)),
        state.fec_change,
    });

    if (state.keyframe_request_code != null and state.keyframe_request_remaining > 0) {
        const extended_buf: [600]u8 = undefined;
        _ = extended_buf;
        // Extend message with keyframe code
        message = try std.fmt.bufPrint(&message_buf, "{}:{s}", .{ message, state.keyframe_request_code.? });
        state.keyframe_request_remaining -= 1;
        if (state.keyframe_request_remaining == 0) {
            if (state.keyframe_request_code) |code| {
                state.allocator.free(code);
            }
            state.keyframe_request_code = null;
        }
    }

    try sendUdp(state, message);
}

fn calculateLink(state: *AppState) !void {
    // Start or override a keyframe request if necessary
    if ((state.lost_packets orelse 0) > 0 and state.config.allow_idr) {
        if (state.keyframe_request_code) |old_code| {
            state.allocator.free(old_code);
        }
        state.keyframe_request_code = try generateRandomString(state.allocator, 4);
        state.keyframe_request_remaining = state.config.idr_max_messages;
        if (state.verbose_mode) {
            print("Generated new keyframe request code: {s}\n", .{state.keyframe_request_code.?});
        }
    }

    var filtered_noise: f32 = 0;
    var error_ratio: f32 = 0;

    if ((state.all_packets orelse 0) == 0 or (state.num_antennas orelse 0) == 0) {
        filtered_noise = 0;
        error_ratio = 0;
    } else {
        const adjusted_fec_rec = adjustFecRecovered(state.fec_rec_packets orelse 0, state.fec_k, state.fec_n);
        const packets_per_antenna = @as(f32, @floatFromInt(state.all_packets.?)) / @as(f32, @floatFromInt(state.num_antennas.?));
        error_ratio = (5.0 * @as(f32, @floatFromInt(state.lost_packets orelse 0)) + adjusted_fec_rec) / packets_per_antenna;
        filtered_noise = kalmanFilterUpdate(state, error_ratio);
    }

    if (state.verbose_mode) {
        print("\nRaw noise ratio: {d:.3}\nFiltered noise ratio: {d:.3}\n", .{ error_ratio, filtered_noise });
    }

    // Normalize SNR and RSSI to a 0-1 scale
    const snr_normalized = std.math.clamp((@as(f32, @floatFromInt(state.best_snr orelse 0)) - @as(f32, @floatFromInt(state.config.snr_min))) /
        @as(f32, @floatFromInt(state.config.snr_max - state.config.snr_min)), 0, 1);
    const rssi_normalized = std.math.clamp((@as(f32, @floatFromInt(state.best_rssi orelse 0)) - @as(f32, @floatFromInt(state.config.rssi_min))) /
        @as(f32, @floatFromInt(state.config.rssi_max - state.config.rssi_min)), 0, 1);

    const score_normalized = (state.config.snr_weight * snr_normalized) + (state.config.rssi_weight * rssi_normalized);
    const raw_score = 1000 + score_normalized * 1000;

    // Penalty logic based on noise estimation
    var deduction_ratio: f32 = 0;
    if (filtered_noise >= state.config.min_noise) {
        deduction_ratio = std.math.clamp(std.math.pow(f32, (filtered_noise - state.config.min_noise) / (state.config.max_noise - state.config.min_noise), state.config.deduction_exponent), 0, 1);
    }

    state.final_score = if (state.config.allow_penalty)
        1000 + (raw_score - 1000) * (1 - deduction_ratio)
    else
        raw_score;

    state.penalty = if (state.config.allow_penalty) state.final_score - raw_score else 0;

    // FEC change logic
    state.fec_change = if (!state.config.allow_fec_increase or filtered_noise <= state.config.min_noise_for_fec_change)
        0
    else if (filtered_noise >= state.config.noise_for_max_fec_change)
        5
    else
        @as(i32, @intFromFloat(@round(((filtered_noise - state.config.min_noise_for_fec_change) / (state.config.noise_for_max_fec_change - state.config.min_noise_for_fec_change)) * 5)));

    if (state.verbose_mode) {
        print("Noise triggered fec_change: {}, penalty: {d:.3}\n", .{ state.fec_change, state.penalty });
    }

    try generateMessage(state);
}

fn handleVideoRxStats(state: *AppState, data: VideoRxData) !void {
    state.all_packets = data.packets.all;
    state.receiving_video = (state.all_packets orelse 0) != 0;
    state.fec_rec_packets = data.packets.fec_rec;
    state.lost_packets = data.packets.lost;

    if (data.session) |session| {
        state.fec_k = session.fec_k;
        state.fec_n = session.fec_n;
    }

    state.num_antennas = @intCast(data.rx_ant_stats.len);

    state.best_rssi = -101;
    state.best_snr = 0;
    var rx_mcs: u32 = 0;

    for (data.rx_ant_stats) |ant| {
        if (ant.rssi_avg) |rssi| {
            if (rssi > (state.best_rssi orelse -101)) {
                state.best_rssi = rssi;
            }
        }
        if (ant.snr_avg) |snr| {
            if (snr > (state.best_snr orelse 0)) {
                state.best_snr = snr;
            }
        }
        if (ant.mcs) |mcs| {
            if (mcs > rx_mcs) {
                rx_mcs = mcs;
            }
        }
    }

    if (state.receiving_video.?) {
        if (!state.video_rx_initial_message_printed) {
            print("\nReceiving video_rx stats\nWorking...\n");
            state.video_rx_initial_message_printed = true;

            // Always request a keyframe when video starts
            if (state.keyframe_request_code) |old_code| {
                state.allocator.free(old_code);
            }
            state.keyframe_request_code = try generateRandomString(state.allocator, 4);
            state.keyframe_request_remaining = state.config.idr_max_messages;
            if (state.verbose_mode) {
                print("Generated new keyframe request code on video start: {s}\n", .{state.keyframe_request_code.?});
            }
        }

        state.waiting_for_video_printed = false;
        try calculateLink(state);

        if (state.verbose_mode) {
            print("\nReceiving_video: {}\n", .{state.receiving_video.?});
            print("MCS: {} | fec_k: {} | fec_n: {}\n\n", .{ rx_mcs, state.fec_k orelse 0, state.fec_n orelse 0 });
            print("Num_antennas: {} | Best_rssi: {} | Best_snr: {}\n", .{ state.num_antennas.?, state.best_rssi.?, state.best_snr.? });
            print("\nall_packets: {}\n", .{state.all_packets.?});
            const avg_packets = if (state.num_antennas.? > 0) @as(f32, @floatFromInt(state.all_packets.?)) / @as(f32, @floatFromInt(state.num_antennas.?)) else 0;
            print("avg packets per antenna: {d:.1}\n", .{avg_packets});
            print("Fec_rec: {}\n", .{state.fec_rec_packets.?});
            print("Lost: {}\n", .{state.lost_packets.?});
        }
    } else {
        state.video_rx_initial_message_printed = false;
        if (!state.waiting_for_video_printed) {
            print("\nWaiting for video_rx stats...\n");
            state.waiting_for_video_printed = true;
        }
    }
}

fn connectToWfbStats(state: *AppState) !void {
    while (true) {
        const addr = net.Address.parseIp(state.config.host, state.config.port) catch |err| {
            print("Error parsing address: {}\n", .{err});
            std.time.sleep(3 * std.time.ns_per_s);
            continue;
        };

        const stream = net.tcpConnectToAddress(addr) catch |err| {
            print("\n! Check VRX adapter(s)...\nNo connection to wfb-ng stats\n{}\nRetrying in 3 seconds...\n", .{err});
            std.time.sleep(3 * std.time.ns_per_s);
            continue;
        };
        defer stream.close();

        print("\nReceiving wfb-ng stats from {s}:{}\n", .{ state.config.host, state.config.port });

        var buf: [4096]u8 = undefined;
        var reader = stream.reader();

        while (true) {
            if (reader.readUntilDelimiterOrEof(&buf, '\n') catch null) |line| {
                if (line.len == 0) break;

                var parsed = json.parseFromSlice(json.Value, state.allocator, line, .{}) catch continue;
                defer parsed.deinit();

                const root = parsed.value;
                if (root.object.get("type")) |type_val| {
                    if (root.object.get("id")) |id_val| {
                        if (std.mem.eql(u8, type_val.string, "rx") and std.mem.eql(u8, id_val.string, "video rx")) {
                            // Parse the video rx data - this would need more detailed JSON parsing
                            // For brevity, this is simplified
                            const data = VideoRxData{
                                .type = "rx",
                                .id = "video rx",
                                .packets = PacketStats{ .all = null, .fec_rec = null, .lost = null },
                                .session = null,
                                .rx_ant_stats = &[_]RxAntStats{},
                            };
                            try handleVideoRxStats(state, data);
                        }
                    }
                }
            } else {
                break;
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var verbose_mode = false;
    var config_file = "/etc/alink_gs.conf";

    // Simple argument parsing
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--verbose")) {
            verbose_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--config=")) {
            config_file = arg[9..];
        }
    }

    const config = try loadConfiguration(config_file, allocator);

    var state = AppState{
        .allocator = allocator,
        .config = config,
        .verbose_mode = verbose_mode,
        .udp_socket = undefined, // Will be created per send
        .kalman_estimate = config.kalman_estimate,
        .kalman_error_estimate = config.kalman_error_estimate,
    };

    try connectToWfbStats(&state);
}
