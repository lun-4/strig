const std = @import("std");
const Context = @import("context.zig").Context;

pub const Client = struct {
    connection: std.net.Connection,
    ctx: *Context,
    handle_frame: @Frame(handle),

    pub fn handle(self: *@This()) !void {
        std.debug.warn("got client!\n");
        while (true) {
            var buf: [100]u8 = undefined;
            const read_bytes = try self.connection.file.read(&buf);
            const msg = buf[0..read_bytes];
            std.debug.warn("got msg! '{}'\n", msg);
        }
    }
};
