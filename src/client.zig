const std = @import("std");
const Context = @import("context.zig").Context;

pub const Client = struct {
    allocator: *std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
    ctx: *Context,
    handle_frame: @Frame(handle),

    pub fn deinit(self: *@This()) void {
        std.debug.warn("closing connection with {}\n", .{self.connection.address});
        self.connection.file.close();
        // TODO free itself
    }

    pub fn handle(self: *@This()) !void {
        std.debug.warn("got client!\n", .{});
        while (true) {
            var buf: [100]u8 = undefined;
            const read_bytes = try self.connection.file.read(&buf);
            if (read_bytes == 0) {
                // likely close connection (got it from SIGINT'ing curl)
                self.deinit();
                break;
            }

            const msg = buf[0..read_bytes];
            std.debug.warn("got msg! '{}'\n", .{msg});
        }
    }
};
