pub extern fn displayFrame(data_ptr: [*]const u8, data_len: usize, codec_type: u32, is_key_frame: bool) void;
pub extern fn logToConsole(msg_ptr: [*]const u8, msg_len: usize) void;
