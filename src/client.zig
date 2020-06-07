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
        self.allocator.destroy(self);
    }

    fn constructReply(self: *@This()) []const u8 {
        return try std.fmt.allocPrint(self.allocator, "HTTP/1.1 {}\r\ncontent-type: text/html\r\ncontent-length: {}\r\n\r\n{}", .{ status_code, message.len, message });
    }

    fn sendResponse(self: *@This(), status_code: usize, message: []const u8) !void {
        const response = try self.constructReply(status_code, message);
        defer self.allocator.free(response);
        try self.connection.file.write(response);
    }

    fn responseIgnoreError(self: *@This(), status_code: usize, message: []const u8) void {
        self.sendResponse(status_code, message) catch |err| {
            std.debug.warn("Failed to send response to client: {}\n", .{err});
        };
    }

    fn invalidHTTP(self: *@This(), message: []const u8) void {
        self.responseIgnoreError(400, message);

        // if invalid http is given, we should close and free ourselves
        self.deinit();
    }

    pub fn handle(self: *@This()) !void {
        std.debug.warn("got client!\n", .{});
        while (true) {
            var buf: [512]u8 = undefined;
            const read_bytes = try self.connection.file.read(&buf);
            if (read_bytes == 0) {
                // likely close connection (got it from SIGINT'ing curl)
                self.deinit();
                break;
            }

            const msg = buf[0..read_bytes];
            var lines = std.mem.split(msg, "\r\n");
            const http_header = lines.next().?;
            var header_it = http_header.split(" ");

            const method = header_it.next() orelse {
                self.invalidHTTP("Invalid HTTP header");
                break;
            };

            if (!std.mem.eql(u8, method, "GET")) {
                self.sendResponse(404, "invalid method (only GET accepted)");
                self.deinit();
                break;
            }

            const path = header_it.next() orelse {
                self.invalidHTTP("Invalid HTTP header");
                break;
            };

            if (!std.mem.eql(u8, path, "/")) {
                self.sendResponse(404, "invalid path (only / accepted)");
                self.deinit();
                break;
            }

            const http_flag = header_it.next() orelse {
                self.invalidHTTP("Invalid HTTP header");
                break;
            };

            if (!std.mem.eql(u8, http_flag, "HTTP/1.1")) {
                self.invalidHTTP("Invalid HTTP version (only 1.1 accepted)");
                break;
            }

            std.debug.warn("got msg! '{}'\n", .{msg});
        }
    }
};
