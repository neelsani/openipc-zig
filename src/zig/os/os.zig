const builtin = @import("builtin");
pub usingnamespace switch (builtin.os.tag) {
    .emscripten => @import("emscripten.zig"),
    .windows => @import("windows.zig"),
    else => @import("posix.zig"),
};
