// packet.zig
const std = @import("std");
const c = @cImport({
    @cInclude("sodium.h");
});
// C-compatible struct definitions matching your C++ structs
pub const RxPktAttrib = extern struct {
    pkt_len: u16,
    physt: bool,
    drvinfo_sz: u8,
    shift_sz: u8,
    qos: bool,
    priority: u8,
    mdata: bool,
    seq_num: u16,
    frag_num: u8,
    mfrag: bool,
    bdecrypted: bool,
    encrypt: u8,
    crc_err: bool,
    icv_err: bool,
    data_rate: u8,
    bw: u8,
    stbc: u8,
    ldpc: u8,
    sgi: u8,
    rssi: [2]u8,
    snr: [2]i8,
    pkt_rpt_type: u32, // Assuming RX_PACKET_TYPE is an enum represented as u32
};

pub const Packet = extern struct {
    RxAtrib: RxPktAttrib,
    DataPtr: [*]const u8,
    DataLen: usize,
};

// Export a function that can process the packet
export fn process_packet(packet: *const Packet) void {
    const writer = std.io.getStdOut().writer();
    writer.print("Packet received:\n", .{}) catch unreachable;
    writer.print("  Length: {}\n", .{packet.RxAtrib.pkt_len}) catch unreachable;
    writer.print("  Data Rate: {}\n", .{packet.RxAtrib.data_rate}) catch unreachable;

    // Access the data
    const data = packet.DataPtr[0..packet.DataLen];
    writer.print("  First byte: {x}\n", .{data[0]}) catch unreachable;
}
