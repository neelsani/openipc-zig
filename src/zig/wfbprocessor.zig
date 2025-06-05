const std = @import("std");
const c = @cImport({
    @cInclude("fec.h");
    @cInclude("sodium.h");
});
const WfbDefine = @import("wfb_define.zig");
const builtin = @import("builtin");
const zig_print = @import("utils.zig").zig_print;
const zig_err = @import("utils.zig").zig_err;
pub const Aggregator = struct {
    allocator: std.mem.Allocator,

    fec_p: ?[*c]c.fec_t,
    fec_k: c_int,
    fec_n: c_int,
    seq: u32,
    rx_ring: [WfbDefine.RX_RING_SIZE]WfbDefine.RxRingItem,
    rx_ring_front: c_int,
    rx_ring_alloc: c_int,
    last_known_block: u64,
    epoch: u64,
    channel_id: u32,

    rx_secretkey: [c.crypto_box_SECRETKEYBYTES]u8,
    tx_publickey: [c.crypto_box_PUBLICKEYBYTES]u8,
    session_key: [c.crypto_aead_chacha20poly1305_KEYBYTES]u8,

    antenna_stat: WfbDefine.AntennaStat,
    count_p_all: u32,
    count_p_dec_err: u32,
    count_p_dec_ok: u32,
    count_p_fec_recovered: u32,
    count_p_lost: u32,
    count_p_bad: u32,
    count_p_override: u32,

    dcb: ?*const fn (payload: []const u8) void,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, keypair: []const u8, epoch: u64, channel_id: u32, cb: ?*const fn (payload: []const u8) void) !*Self {
        var self = try allocator.create(Self);

        self.allocator = allocator;
        self.fec_p = null;
        self.fec_k = std.math.maxInt(c_int);
        self.fec_n = std.math.maxInt(c_int);
        self.seq = 0;
        self.rx_ring_front = 0;
        self.rx_ring_alloc = 0;
        self.last_known_block = std.math.maxInt(u64);

        self.epoch = epoch;
        self.channel_id = channel_id;
        self.count_p_all = 0;
        self.count_p_dec_err = 0;
        self.count_p_dec_ok = 0;
        self.count_p_fec_recovered = 0;
        self.count_p_lost = 0;
        self.count_p_bad = 0;
        self.count_p_override = 0;
        self.dcb = cb;

        self.session_key = @splat(0);
        self.antenna_stat = WfbDefine.createAntennaStat(allocator);

        // Initialize rx_ring
        for (&self.rx_ring) |*item| {
            item.* = WfbDefine.RxRingItem.init();
        }

        switch (builtin.target.os.tag) {
            .emscripten => {
                const hardcoded_keypair: []const u8 = &.{ 0xbb, 0xb7, 0xed, 0x6e, 0x83, 0xa4, 0x6a, 0x8a, 0x9b, 0x8a, 0x12, 0xa0, 0xf9, 0x8e, 0xce, 0x2b, 0xdc, 0x97, 0x87, 0x05, 0xb8, 0x20, 0x47, 0x01, 0xb2, 0x08, 0x5f, 0xa2, 0x8c, 0xac, 0x7b, 0x46, 0x0e, 0x05, 0xc4, 0x8a, 0x61, 0x95, 0xfb, 0x70, 0x92, 0x1c, 0x74, 0x7a, 0x66, 0xe8, 0x3c, 0x02, 0xe6, 0x40, 0xbd, 0x6b, 0xbe, 0xb5, 0xb2, 0x51, 0x53, 0x7a, 0x98, 0xa2, 0x74, 0x16, 0xa2, 0x63 };
                @memcpy(self.rx_secretkey[0..], hardcoded_keypair[0..c.crypto_box_SECRETKEYBYTES]);
                @memcpy(self.tx_publickey[0..], hardcoded_keypair[c.crypto_box_SECRETKEYBYTES .. c.crypto_box_SECRETKEYBYTES + c.crypto_box_PUBLICKEYBYTES]);
            },
            else => {
                const cwd = std.fs.cwd();
                var file = try cwd.openFile(keypair, .{});

                defer file.close();
                if (try file.read(&self.rx_secretkey) != c.crypto_box_SECRETKEYBYTES) {
                    return error.BadFile;
                }
                if (try file.read(&self.tx_publickey) != c.crypto_box_PUBLICKEYBYTES) {
                    return error.BadFile;
                }
            },
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.fec_p != null) {
            self.deinit_fec();
        }
        self.antenna_stat.deinit();
        self.allocator.destroy(self);
    }

    fn init_fec(self: *Self, k: c_int, n: c_int) void {
        self.fec_k = k;
        self.fec_n = n;
        self.fec_p = c.fec_new(@intCast(self.fec_k), @intCast(self.fec_n));

        self.rx_ring_front = 0;
        self.rx_ring_alloc = 0;
        self.last_known_block = std.math.maxInt(u64);
        self.seq = 0;

        var ring_idx: usize = 0;
        while (ring_idx < WfbDefine.RX_RING_SIZE) : (ring_idx += 1) {
            self.rx_ring[ring_idx].block_idx = 0;
            self.rx_ring[ring_idx].fragment_to_send_idx = 0;
            self.rx_ring[ring_idx].has_fragments = 0;

            // Allocate array of pointers to fragments
            self.rx_ring[ring_idx].fragments = @ptrCast(self.allocator.alloc([*c]u8, @intCast(self.fec_n)) catch unreachable);

            // Allocate each fragment buffer
            var i: usize = 0;
            while (i < @as(usize, @intCast(self.fec_n))) : (i += 1) {
                self.rx_ring[ring_idx].fragments.?[i] = @ptrCast(self.allocator.alloc(u8, WfbDefine.MAX_FEC_PAYLOAD) catch unreachable);
            }

            // Allocate and initialize fragment map
            self.rx_ring[ring_idx].fragment_map = @ptrCast(self.allocator.alloc(u8, @intCast(self.fec_n)) catch unreachable);
            @memset(self.rx_ring[ring_idx].fragment_map.?[0..@intCast(self.fec_n)], 0);
        }
    }

    fn deinit_fec(self: *Self) void {
        var ring_idx: usize = 0;
        while (ring_idx < WfbDefine.RX_RING_SIZE) : (ring_idx += 1) {
            if (self.rx_ring[ring_idx].fragment_map) |fragment_map| {
                self.allocator.free(@as([*]u8, @ptrCast(fragment_map))[0..@intCast(self.fec_n)]);
                self.rx_ring[ring_idx].fragment_map = null;
            }

            if (self.rx_ring[ring_idx].fragments) |fragments| {
                var i: usize = 0;
                while (i < @as(usize, @intCast(self.fec_n))) : (i += 1) {
                    self.allocator.free(@as([*]u8, @ptrCast(fragments[i]))[0..WfbDefine.MAX_FEC_PAYLOAD]);
                }
                self.allocator.free(@as([*][*c]u8, @ptrCast(fragments))[0..@intCast(self.fec_n)]);
                self.rx_ring[ring_idx].fragments = null;
            }
        }

        if (self.fec_p) |fec| {
            c.fec_free(fec);
            self.fec_p = null;
        }
        self.fec_k = -1;
        self.fec_n = -1;
    }

    fn rx_ring_push(self: *Self) c_int {
        if (self.rx_ring_alloc < WfbDefine.RX_RING_SIZE) {
            const idx = WfbDefine.modN(self.rx_ring_front + self.rx_ring_alloc, WfbDefine.RX_RING_SIZE);
            self.rx_ring_alloc += 1;
            return idx;
        }

        // Ring overflow - override oldest block
        self.count_p_override += 1;

        var f_idx = self.rx_ring[@intCast(self.rx_ring_front)].fragment_to_send_idx;
        while (f_idx < self.fec_k) : (f_idx += 1) {
            if (self.rx_ring[@intCast(self.rx_ring_front)].fragment_map.?[@intCast(f_idx)] != 0) {
                self.send_packet(self.rx_ring_front, f_idx);
            }
        }

        const ring_idx = self.rx_ring_front;
        self.rx_ring_front = WfbDefine.modN(self.rx_ring_front + 1, WfbDefine.RX_RING_SIZE);
        return ring_idx;
    }

    fn get_block_ring_idx(self: *Self, block_idx: u64) c_int {
        // Check if block is already in the ring
        var i = self.rx_ring_front;
        var c1 = self.rx_ring_alloc;
        while (c1 > 0) : ({
            i = WfbDefine.modN(i + 1, WfbDefine.RX_RING_SIZE);
            c1 -= 1;
        }) {
            if (self.rx_ring[@intCast(i)].block_idx == block_idx) return i;
        }

        // Check if block is already known and not in the ring
        if (self.last_known_block != std.math.maxInt(u64) and block_idx <= self.last_known_block) {
            return -1;
        }

        const new_blocks: c_int = @intCast(@min(if (self.last_known_block != std.math.maxInt(u64)) block_idx - self.last_known_block else 1, WfbDefine.RX_RING_SIZE));
        std.debug.assert(new_blocks > 0);

        self.last_known_block = block_idx;
        var ring_idx: c_int = -1;

        var idx: c_int = 0;
        while (idx < new_blocks) : (idx += 1) {
            ring_idx = self.rx_ring_push();
            self.rx_ring[@intCast(ring_idx)].block_idx = block_idx + @as(u64, @intCast(idx)) + 1 - @as(u64, @intCast(new_blocks));
            self.rx_ring[@intCast(ring_idx)].fragment_to_send_idx = 0;
            self.rx_ring[@intCast(ring_idx)].has_fragments = 0;
            @memset(self.rx_ring[@intCast(ring_idx)].fragment_map.?[0..@intCast(self.fec_n)], 0);
        }
        return ring_idx;
    }

    // Updated signature to match C++ interface: process_packet(data, size, wlan_idx, antenna, rssi)
    pub fn process_packet(self: *Self, buf: []const u8, wlan_idx: u8, antenna: [*c]const u8, rssi: [*c]const i8) void {
        _ = antenna; // Suppress unused parameter warning
        _ = rssi; // Suppress unused parameter warning
        _ = wlan_idx; // Suppress unused parameter warning

        var new_session_data: WfbDefine.WSessionData = undefined;
        self.count_p_all += 1;

        if (buf.len == 0) return;

        if (buf.len > WfbDefine.MAX_FORWARDER_PACKET_SIZE) {
            zig_print("Long packet (fec payload)\n", .{});
            self.count_p_bad += 1;
            return;
        }

        switch (buf[0]) {
            WfbDefine.WFB_PACKET_DATA => {
                if (buf.len < @sizeOf(WfbDefine.WBlockHdr) + @sizeOf(WfbDefine.WPacketHdr)) {
                    zig_print("Short packet (fec header)\n", .{});
                    self.count_p_bad += 1;
                    return;
                }
            },
            WfbDefine.WFB_PACKET_KEY => {
                if (buf.len != @sizeOf(WfbDefine.WSessionHdr) + @sizeOf(WfbDefine.WSessionData) + c.crypto_box_MACBYTES) {
                    zig_print("Invalid session key packet\n", .{});
                    self.count_p_bad += 1;
                    return;
                }

                const session_hdr: *const WfbDefine.WSessionHdr = @ptrCast(@alignCast(buf.ptr));

                if (c.crypto_box_open_easy(@ptrCast(&new_session_data), buf.ptr + @sizeOf(WfbDefine.WSessionHdr), @sizeOf(WfbDefine.WSessionData) + c.crypto_box_MACBYTES, &session_hdr.getSessionNonce(), &self.tx_publickey, &self.rx_secretkey) != 0) {
                    zig_print("Unable to decrypt session key\n", .{});
                    self.count_p_dec_err += 1;
                    return;
                }

                const session_epoch = std.mem.bigToNative(u64, new_session_data.epoch);
                if (session_epoch < self.epoch) {
                    zig_print("Session epoch doesn't match: {} < {}\n", .{ session_epoch, self.epoch });
                    self.count_p_dec_err += 1;
                    return;
                }

                const session_channel_id = std.mem.bigToNative(u32, new_session_data.channel_id);
                if (session_channel_id != self.channel_id) {
                    zig_print("Session channel_id doesn't match: {} != {}\n", .{ session_channel_id, self.channel_id });
                    self.count_p_dec_err += 1;
                    return;
                }

                if (new_session_data.fec_type != WfbDefine.WFB_FEC_VDM_RS) {
                    zig_print("Unsupported FEC codec type: {}\n", .{new_session_data.fec_type});
                    self.count_p_dec_err += 1;
                    return;
                }

                if (new_session_data.n < 1) {
                    zig_print("Invalid FEC N: {}\n", .{new_session_data.n});
                    self.count_p_dec_err += 1;
                    return;
                }

                if (new_session_data.k < 1 or new_session_data.k > new_session_data.n) {
                    zig_print("Invalid FEC K: {}\n", .{new_session_data.k});
                    self.count_p_dec_err += 1;
                    return;
                }

                self.count_p_dec_ok += 1;

                const new_session_key = new_session_data.getSessionKey();
                if (!std.mem.eql(u8, &self.session_key, &new_session_key)) {
                    self.epoch = session_epoch;
                    @memcpy(&self.session_key, &new_session_key);

                    if (self.fec_p != null) {
                        self.deinit_fec();
                    }

                    self.init_fec(new_session_data.k, new_session_data.n);
                    zig_print("New session: epoch={}, k={}, n={}\n", .{ self.epoch, self.fec_k, self.fec_n });
                }
                return;
            },
            else => {
                zig_print("Unknown packet type 0x{x}\n", .{buf[0]});
                self.count_p_bad += 1;
                return;
            },
        }

        // Process data packet
        var decrypted: [WfbDefine.MAX_FEC_PAYLOAD]u8 = undefined;
        var decrypted_len: c_ulonglong = undefined;
        const block_hdr: *const WfbDefine.WBlockHdr = @ptrCast(@alignCast(buf.ptr));

        if (c.crypto_aead_chacha20poly1305_decrypt(&decrypted, &decrypted_len, null, buf.ptr + @sizeOf(WfbDefine.WBlockHdr), buf.len - @sizeOf(WfbDefine.WBlockHdr), buf.ptr, @sizeOf(WfbDefine.WBlockHdr), @ptrCast(&block_hdr.data_nonce), &self.session_key) != 0) {
            zig_print("Unable to decrypt packet #{x}\n", .{std.mem.bigToNative(u64, block_hdr.data_nonce)});
            self.count_p_dec_err += 1;
            return;
        }

        self.count_p_dec_ok += 1;
        std.debug.assert(decrypted_len <= WfbDefine.MAX_FEC_PAYLOAD);

        const data_nonce = std.mem.bigToNative(u64, block_hdr.data_nonce);
        const block_idx = data_nonce >> 8;
        const fragment_idx: u8 = @truncate(data_nonce & 0xff);

        if (block_idx > WfbDefine.MAX_BLOCK_IDX) {
            zig_print("block_idx overflow\n", .{});
            self.count_p_bad += 1;
            return;
        }

        if (fragment_idx >= self.fec_n) {
            zig_print("Invalid fragment_idx: {}\n", .{fragment_idx});
            self.count_p_bad += 1;
            return;
        }

        const ring_idx = self.get_block_ring_idx(block_idx);
        if (ring_idx < 0) return; // Already processed

        const p = &self.rx_ring[@intCast(ring_idx)];
        if (p.fragment_map.?[fragment_idx] != 0) return; // Already processed

        @memset(p.fragments.?[fragment_idx][0..WfbDefine.MAX_FEC_PAYLOAD], 0);
        @memcpy(p.fragments.?[fragment_idx][0..@intCast(decrypted_len)], decrypted[0..@intCast(decrypted_len)]);
        p.fragment_map.?[fragment_idx] = 1;
        p.has_fragments += 1;

        // Optimize for current (oldest) block
        if (ring_idx == self.rx_ring_front) {
            while (p.fragment_to_send_idx < self.fec_k and p.fragment_map.?[@intCast(p.fragment_to_send_idx)] != 0) {
                self.send_packet(ring_idx, p.fragment_to_send_idx);
                p.fragment_to_send_idx += 1;
            }

            if (p.fragment_to_send_idx == self.fec_k) {
                self.rx_ring_front = WfbDefine.modN(self.rx_ring_front + 1, WfbDefine.RX_RING_SIZE);
                self.rx_ring_alloc -= 1;
                std.debug.assert(self.rx_ring_alloc >= 0);
                return;
            }
        }

        // FEC recovery if we have K fragments
        if (p.fragment_to_send_idx < self.fec_k and p.has_fragments == self.fec_k) {
            // Send all queued packets in blocks before current
            const nrm = WfbDefine.modN(ring_idx - self.rx_ring_front, WfbDefine.RX_RING_SIZE);
            var remaining = nrm;
            while (remaining > 0) : (remaining -= 1) {
                var f_idx = self.rx_ring[@intCast(self.rx_ring_front)].fragment_to_send_idx;
                while (f_idx < self.fec_k) : (f_idx += 1) {
                    if (self.rx_ring[@intCast(self.rx_ring_front)].fragment_map.?[@intCast(f_idx)] != 0) {
                        self.send_packet(self.rx_ring_front, f_idx);
                    }
                }
                self.rx_ring_front = WfbDefine.modN(self.rx_ring_front + 1, WfbDefine.RX_RING_SIZE);
                self.rx_ring_alloc -= 1;
            }

            std.debug.assert(self.rx_ring_alloc > 0);
            std.debug.assert(ring_idx == self.rx_ring_front);

            // Apply FEC if needed
            var f_idx = p.fragment_to_send_idx;
            while (f_idx < self.fec_k) : (f_idx += 1) {
                if (p.fragment_map.?[@intCast(f_idx)] == 0) {
                    self.apply_fec(ring_idx);

                    // Count recovered fragments
                    var count_idx = f_idx;
                    while (count_idx < self.fec_k) : (count_idx += 1) {
                        if (p.fragment_map.?[@intCast(count_idx)] == 0) {
                            self.count_p_fec_recovered += 1;
                        }
                    }
                    break;
                }
            }

            while (p.fragment_to_send_idx < self.fec_k) : (p.fragment_to_send_idx += 1) {
                self.send_packet(ring_idx, p.fragment_to_send_idx);
            }

            self.rx_ring_front = WfbDefine.modN(self.rx_ring_front + 1, WfbDefine.RX_RING_SIZE);
            self.rx_ring_alloc -= 1;
            std.debug.assert(self.rx_ring_alloc >= 0);
        }
    }

    fn send_packet(self: *Self, ring_idx: c_int, fragment_idx: c_int) void {
        const packet_hdr: *const WfbDefine.WPacketHdr = @ptrCast(@alignCast(self.rx_ring[@intCast(ring_idx)].fragments.?[@intCast(fragment_idx)]));
        const payload = self.rx_ring[@intCast(ring_idx)].fragments.?[@intCast(fragment_idx)] + @sizeOf(WfbDefine.WPacketHdr);
        const flags = packet_hdr.flags;
        const packet_size = std.mem.bigToNative(u16, packet_hdr.packet_size);
        const packet_seq: u32 = @intCast(self.rx_ring[@intCast(ring_idx)].block_idx * @as(u64, @intCast(self.fec_k)) + @as(u64, @intCast(fragment_idx)));

        if (packet_seq > self.seq + 1 and self.seq > 0) {
            self.count_p_lost += (packet_seq - self.seq - 1);
        }

        self.seq = packet_seq;

        if (packet_size > WfbDefine.MAX_PAYLOAD_SIZE) {
            std.debug.print("Corrupted packet {}\n", .{self.seq});
            self.count_p_bad += 1;
        } else if ((flags & WfbDefine.WFB_PACKET_FEC_ONLY) == 0) {
            if (self.dcb) |callback| {
                callback(payload[0..packet_size]);
            }
        }
    }

    fn apply_fec(self: *Self, ring_idx: c_int) void {
        std.debug.assert(self.fec_k >= 1);
        std.debug.assert(self.fec_n >= 1);
        std.debug.assert(self.fec_k <= self.fec_n);
        std.debug.assert(self.fec_p != null);

        const index = self.allocator.alloc(c_uint, @intCast(self.fec_k)) catch unreachable;
        defer self.allocator.free(index);

        const in_blocks = self.allocator.alloc([*c]u8, @intCast(self.fec_k)) catch unreachable;
        defer self.allocator.free(in_blocks);

        const out_blocks = self.allocator.alloc([*c]u8, @intCast(self.fec_n - self.fec_k)) catch unreachable;
        defer self.allocator.free(out_blocks);

        var j: c_int = self.fec_k;
        var ob_idx: usize = 0;

        var i: c_int = 0;
        while (i < self.fec_k) : (i += 1) {
            if (self.rx_ring[@intCast(ring_idx)].fragment_map.?[@intCast(i)] != 0) {
                in_blocks[@intCast(i)] = self.rx_ring[@intCast(ring_idx)].fragments.?[@intCast(i)];
                index[@intCast(i)] = @intCast(i);
            } else {
                while (j < self.fec_n) : (j += 1) {
                    if (self.rx_ring[@intCast(ring_idx)].fragment_map.?[@intCast(j)] != 0) {
                        in_blocks[@intCast(i)] = self.rx_ring[@intCast(ring_idx)].fragments.?[@intCast(j)];
                        out_blocks[ob_idx] = self.rx_ring[@intCast(ring_idx)].fragments.?[@intCast(i)];
                        ob_idx += 1;
                        index[@intCast(i)] = @intCast(j);
                        j += 1;
                        break;
                    }
                }
            }
        }

        _ = c.fec_decode(self.fec_p.?, @ptrCast(in_blocks.ptr), out_blocks.ptr, index.ptr, WfbDefine.MAX_FEC_PAYLOAD);
    }
};
