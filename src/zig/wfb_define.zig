const std = @import("std");

const c = @cImport({
    @cInclude("sodium.h");
    @cInclude("sodium/crypto_box.h");
});

/// Equivalent of the Windows/endian utility functions in C++.
pub fn htobe32(host_32bits: u32) u32 {
    return std.mem.nativeToBig(u32, host_32bits);
}

pub fn be64toh(big_endian_64bits: u64) u64 {
    return std.mem.bigToNative(u64, big_endian_64bits);
}

pub fn be32toh(big_endian_32bits: u32) u32 {
    return std.mem.bigToNative(u32, big_endian_32bits);
}

pub fn be16toh(big_endian_16bits: u16) u16 {
    return std.mem.bigToNative(u16, big_endian_16bits);
}

/// Static IEEE 802.11 header bytes (identical to the C++ array).
pub const ieee80211_header = [_]u8{
    0x08, 0x01, 0x00, 0x00, // data frame, not protected, from STA to DS via an AP, duration not set
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // receiver is broadcast
    0x57, 0x42, 0xaa, 0xbb, 0xcc, 0xdd, // last four bytes will be replaced by channel_id
    0x57, 0x42, 0xaa, 0xbb, 0xcc, 0xdd, // last four bytes will be replaced by channel_id
    0x00, 0x00, // (seq_num << 4) + fragment_num
};

pub const IEEE80211_RADIOTAP_MCS_HAVE_BW = 0x01;
pub const IEEE80211_RADIOTAP_MCS_HAVE_MCS = 0x02;
pub const IEEE80211_RADIOTAP_MCS_HAVE_GI = 0x04;
pub const IEEE80211_RADIOTAP_MCS_HAVE_FMT = 0x08;
pub const IEEE80211_RADIOTAP_MCS_HAVE_FEC = 0x10;
pub const IEEE80211_RADIOTAP_MCS_HAVE_STBC = 0x20;

pub const IEEE80211_RADIOTAP_MCS_BW_20 = 0;
pub const IEEE80211_RADIOTAP_MCS_BW_40 = 1;
pub const IEEE80211_RADIOTAP_MCS_BW_20L = 2;
pub const IEEE80211_RADIOTAP_MCS_BW_20U = 3;
pub const IEEE80211_RADIOTAP_MCS_SGI = 0x04;
pub const IEEE80211_RADIOTAP_MCS_FMT_GF = 0x08;
pub const IEEE80211_RADIOTAP_MCS_FEC_LDPC = 0x10;
pub const IEEE80211_RADIOTAP_MCS_STBC_MASK = 0x60;
pub const IEEE80211_RADIOTAP_MCS_STBC_1 = 1;
pub const IEEE80211_RADIOTAP_MCS_STBC_2 = 2;
pub const IEEE80211_RADIOTAP_MCS_STBC_3 = 3;
pub const IEEE80211_RADIOTAP_MCS_STBC_SHIFT = 5;

pub const MCS_KNOWN = IEEE80211_RADIOTAP_MCS_HAVE_MCS |
    IEEE80211_RADIOTAP_MCS_HAVE_BW |
    IEEE80211_RADIOTAP_MCS_HAVE_GI |
    IEEE80211_RADIOTAP_MCS_HAVE_STBC |
    IEEE80211_RADIOTAP_MCS_HAVE_FEC;

/// Radiotap header bytes (identical to C++ array).
pub const radiotap_header = [_]u8{
    0x00, 0x00, // radiotap version
    0x0d, 0x00, // radiotap header length
    0x00, 0x80, 0x08, 0x00, // radiotap present flags: RADIOTAP_TX_FLAGS + RADIOTAP_MCS
    0x08, 0x00, // RADIOTAP_F_TX_NOACK
    MCS_KNOWN, 0x00, 0x00, // bitmap, flags, mcs_index
};

pub const RX_RING_SIZE = 40;

/// Equivalent of C's `rx_ring_item_t`
pub const RxRingItem = struct {
    block_idx: u64,
    fragments: ?[*][*c]u8, // uint8_t **fragments
    fragment_map: ?[*]u8, // uint8_t *fragment_map
    fragment_to_send_idx: u8,
    has_fragments: u8,

    pub fn init() RxRingItem {
        return RxRingItem{
            .block_idx = 0,
            .fragments = null,
            .fragment_map = null,
            .fragment_to_send_idx = 0,
            .has_fragments = 0,
        };
    }
};

/// Inline function equivalent to C++ modN
pub fn modN(x: c_int, base: c_int) c_int {
    return @mod(base + @mod(x, base), base);
}

/// Equivalent of C++ `antennaItem` class.
pub const AntennaItem = struct {
    count_all: i32,
    rssi_sum: i32,
    rssi_min: i8,
    rssi_max: i8,

    pub fn init() AntennaItem {
        return AntennaItem{
            .count_all = 0,
            .rssi_sum = 0,
            .rssi_min = 0,
            .rssi_max = 0,
        };
    }

    pub fn logRssi(self: *AntennaItem, rssi: i8) void {
        if (self.count_all == 0) {
            self.rssi_min = rssi;
            self.rssi_max = rssi;
        } else {
            self.rssi_min = @min(rssi, self.rssi_min);
            self.rssi_max = @max(rssi, self.rssi_max);
        }
        self.rssi_sum += rssi;
        self.count_all += 1;
    }
};

/// Equivalent of C++ `typedef std::unordered_map<uint64_t, antennaItem> antenna_stat_t;`
pub const AntennaStat = std.AutoHashMap(u64, AntennaItem);

/// C++ packed struct `wsession_hdr_t` - Fixed for packed struct limitations
pub const WSessionHdr = packed struct {
    packet_type: u8,
    // Individual bytes for session_nonce (crypto_box_NONCEBYTES = 24)
    session_nonce_0: u8,
    session_nonce_1: u8,
    session_nonce_2: u8,
    session_nonce_3: u8,
    session_nonce_4: u8,
    session_nonce_5: u8,
    session_nonce_6: u8,
    session_nonce_7: u8,
    session_nonce_8: u8,
    session_nonce_9: u8,
    session_nonce_10: u8,
    session_nonce_11: u8,
    session_nonce_12: u8,
    session_nonce_13: u8,
    session_nonce_14: u8,
    session_nonce_15: u8,
    session_nonce_16: u8,
    session_nonce_17: u8,
    session_nonce_18: u8,
    session_nonce_19: u8,
    session_nonce_20: u8,
    session_nonce_21: u8,
    session_nonce_22: u8,
    session_nonce_23: u8,

    pub fn getSessionNonce(self: *const WSessionHdr) [24]u8 {
        return [24]u8{
            self.session_nonce_0,  self.session_nonce_1,  self.session_nonce_2,  self.session_nonce_3,
            self.session_nonce_4,  self.session_nonce_5,  self.session_nonce_6,  self.session_nonce_7,
            self.session_nonce_8,  self.session_nonce_9,  self.session_nonce_10, self.session_nonce_11,
            self.session_nonce_12, self.session_nonce_13, self.session_nonce_14, self.session_nonce_15,
            self.session_nonce_16, self.session_nonce_17, self.session_nonce_18, self.session_nonce_19,
            self.session_nonce_20, self.session_nonce_21, self.session_nonce_22, self.session_nonce_23,
        };
    }

    pub fn setSessionNonce(self: *WSessionHdr, nonce: [24]u8) void {
        self.session_nonce_0 = nonce[0];
        self.session_nonce_1 = nonce[1];
        self.session_nonce_2 = nonce[2];
        self.session_nonce_3 = nonce[3];
        self.session_nonce_4 = nonce[4];
        self.session_nonce_5 = nonce[5];
        self.session_nonce_6 = nonce[6];
        self.session_nonce_7 = nonce[7];
        self.session_nonce_8 = nonce[8];
        self.session_nonce_9 = nonce[9];
        self.session_nonce_10 = nonce[10];
        self.session_nonce_11 = nonce[11];
        self.session_nonce_12 = nonce[12];
        self.session_nonce_13 = nonce[13];
        self.session_nonce_14 = nonce[14];
        self.session_nonce_15 = nonce[15];
        self.session_nonce_16 = nonce[16];
        self.session_nonce_17 = nonce[17];
        self.session_nonce_18 = nonce[18];
        self.session_nonce_19 = nonce[19];
        self.session_nonce_20 = nonce[20];
        self.session_nonce_21 = nonce[21];
        self.session_nonce_22 = nonce[22];
        self.session_nonce_23 = nonce[23];
    }
};

/// C++ packed struct `wsession_data_t`
pub const WSessionData = packed struct {
    epoch: u64, // Drop session packets from old epoch
    channel_id: u32, // (link_id << 8) + port_number
    fec_type: u8, // Now only supported type is WFB_FEC_VDM_RS
    k: u8, // FEC k
    n: u8, // FEC n
    // Individual bytes for session_key (crypto_aead_chacha20poly1305_KEYBYTES = 32)
    session_key_0: u8,
    session_key_1: u8,
    session_key_2: u8,
    session_key_3: u8,
    session_key_4: u8,
    session_key_5: u8,
    session_key_6: u8,
    session_key_7: u8,
    session_key_8: u8,
    session_key_9: u8,
    session_key_10: u8,
    session_key_11: u8,
    session_key_12: u8,
    session_key_13: u8,
    session_key_14: u8,
    session_key_15: u8,
    session_key_16: u8,
    session_key_17: u8,
    session_key_18: u8,
    session_key_19: u8,
    session_key_20: u8,
    session_key_21: u8,
    session_key_22: u8,
    session_key_23: u8,
    session_key_24: u8,
    session_key_25: u8,
    session_key_26: u8,
    session_key_27: u8,
    session_key_28: u8,
    session_key_29: u8,
    session_key_30: u8,
    session_key_31: u8,

    pub fn getSessionKey(self: *const WSessionData) [32]u8 {
        return [32]u8{
            self.session_key_0,  self.session_key_1,  self.session_key_2,  self.session_key_3,
            self.session_key_4,  self.session_key_5,  self.session_key_6,  self.session_key_7,
            self.session_key_8,  self.session_key_9,  self.session_key_10, self.session_key_11,
            self.session_key_12, self.session_key_13, self.session_key_14, self.session_key_15,
            self.session_key_16, self.session_key_17, self.session_key_18, self.session_key_19,
            self.session_key_20, self.session_key_21, self.session_key_22, self.session_key_23,
            self.session_key_24, self.session_key_25, self.session_key_26, self.session_key_27,
            self.session_key_28, self.session_key_29, self.session_key_30, self.session_key_31,
        };
    }

    pub fn setSessionKey(self: *WSessionData, key: [32]u8) void {
        self.session_key_0 = key[0];
        self.session_key_1 = key[1];
        self.session_key_2 = key[2];
        self.session_key_3 = key[3];
        self.session_key_4 = key[4];
        self.session_key_5 = key[5];
        self.session_key_6 = key[6];
        self.session_key_7 = key[7];
        self.session_key_8 = key[8];
        self.session_key_9 = key[9];
        self.session_key_10 = key[10];
        self.session_key_11 = key[11];
        self.session_key_12 = key[12];
        self.session_key_13 = key[13];
        self.session_key_14 = key[14];
        self.session_key_15 = key[15];
        self.session_key_16 = key[16];
        self.session_key_17 = key[17];
        self.session_key_18 = key[18];
        self.session_key_19 = key[19];
        self.session_key_20 = key[20];
        self.session_key_21 = key[21];
        self.session_key_22 = key[22];
        self.session_key_23 = key[23];
        self.session_key_24 = key[24];
        self.session_key_25 = key[25];
        self.session_key_26 = key[26];
        self.session_key_27 = key[27];
        self.session_key_28 = key[28];
        self.session_key_29 = key[29];
        self.session_key_30 = key[30];
        self.session_key_31 = key[31];
    }
};

/// C++ packed struct `wblock_hdr_t` - Data packet. Embed FEC-encoded data
pub const WBlockHdr = packed struct {
    packet_type: u8,
    data_nonce: u64, // big endian, data_nonce = (block_idx << 8) + fragment_idx
};

/// C++ packed struct `wpacket_hdr_t` - Plain data packet after FEC decode
pub const WPacketHdr = packed struct {
    flags: u8,
    packet_size: u16, // big endian
};

/// Constants matching C++ defines
pub const MAX_PACKET_SIZE = 1510;
pub const MAX_PAYLOAD_SIZE = MAX_PACKET_SIZE -
    @sizeOf(@TypeOf(radiotap_header)) -
    @sizeOf(@TypeOf(ieee80211_header)) -
    @sizeOf(WBlockHdr) -
    c.crypto_aead_chacha20poly1305_ABYTES -
    @sizeOf(WPacketHdr);

pub const MAX_FEC_PAYLOAD = MAX_PACKET_SIZE -
    @sizeOf(@TypeOf(radiotap_header)) -
    @sizeOf(@TypeOf(ieee80211_header)) -
    @sizeOf(WBlockHdr) -
    c.crypto_aead_chacha20poly1305_ABYTES;

pub const MAX_FORWARDER_PACKET_SIZE = MAX_PACKET_SIZE -
    @sizeOf(@TypeOf(radiotap_header)) -
    @sizeOf(@TypeOf(ieee80211_header));

pub const BLOCK_IDX_MASK = (1 << 56) - 1;
pub const MAX_BLOCK_IDX = (1 << 55) - 1;

// packet types
pub const WFB_PACKET_DATA = 0x1;
pub const WFB_PACKET_KEY = 0x2;

// FEC types
pub const WFB_FEC_VDM_RS = 0x1; // Reed-Solomon on Vandermonde matrix

// packet flags
pub const WFB_PACKET_FEC_ONLY = 0x1;

pub const SESSION_KEY_ANNOUNCE_MSEC = 1000;
pub const RX_ANT_MAX = 4;

/// Helper function to create AntennaStat
pub fn createAntennaStat(allocator: std.mem.Allocator) AntennaStat {
    return AntennaStat.init(allocator);
}
