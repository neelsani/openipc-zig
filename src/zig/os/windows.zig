const std = @import("std");
const zig_print = @import("../utils.zig").zig_print;
const zig_err = @import("../utils.zig").zig_err;

const posix = @import("posix.zig");

pub const handleRtp = posix.handleRtp;

pub const init = posix.init;

pub const deinit = posix.init;

pub const onIEEFrame = posix.onIEEFrame;

pub const getGsKey = posix.getGsKey;
