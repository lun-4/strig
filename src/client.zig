const std = @import("std");
const Context = @import("context.zig").Context;

pub const Client = struct {
    id: []const u8,
    allocator: *std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
    ctx: *Context,
    handle_frame: @Frame(handle),

    pub fn deinit(self: *@This()) void {
        std.debug.warn("closing connection with {}\n", .{self.connection.address});
        self.connection.file.close();
        self.allocator.free(self.id);
        self.allocator.destroy(self);
    }

    fn constructReply(self: *@This(), status_code: usize, message: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {}\r\ncontent-type: text/plain\r\ncontent-length: {}\r\n\r\n{}",
            .{
                status_code,
                message.len,
                message,
            },
        );
    }

    fn send(self: *@This(), message: []const u8) !void {
        const sent_bytes = try self.connection.file.write(message);
        if (sent_bytes != message.len) {
            std.debug.warn(
                "Maybe failed to send message! sent {}, expected {}\n",
                .{ sent_bytes, message.len },
            );
        }
    }

    fn sendResponse(self: *@This(), status_code: usize, message: []const u8) !void {
        const response = try self.constructReply(status_code, message);
        defer self.allocator.free(response);
        try self.send(response);
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
        std.debug.warn("got client at {}\n", .{self.connection.address});
        var buf: [512]u8 = undefined;
        const read_bytes = try self.connection.file.read(&buf);
        if (read_bytes == 0) {
            // likely close connection (got it from SIGINT'ing curl)
            self.deinit();
            return;
        }

        const msg = buf[0..read_bytes];
        var lines = std.mem.split(msg, "\r\n");
        const http_header = lines.next().?;
        var header_it = std.mem.split(http_header, " ");

        const method = header_it.next() orelse {
            self.invalidHTTP("Invalid HTTP header");
            return;
        };

        if (!std.mem.eql(u8, method, "GET")) {
            try self.sendResponse(404, "invalid method (only GET accepted)");
            self.deinit();
            return;
        }

        const path = header_it.next() orelse {
            self.invalidHTTP("Invalid HTTP header");
            return;
        };

        if (!std.mem.eql(u8, path, "/")) {
            try self.sendResponse(404, "invalid path (only / accepted)");
            self.deinit();
            return;
        }

        const http_flag = header_it.next() orelse {
            self.invalidHTTP("Invalid HTTP header");
            return;
        };

        if (!std.mem.eql(u8, http_flag, "HTTP/1.1")) {
            self.invalidHTTP("Invalid HTTP version (only 1.1 accepted)");
            return;
        }

        // by now, we have a proper http request we can serve. we don't need
        // the rest of the message to make our reply

        std.debug.warn("got right http request from {}\n", .{self.connection.address});

        // send out initial message, the streaming bit is likely managed by
        // Context? more experiments required
        try self.send("HTTP/1.1 200\r\n");
        try self.send("content-type: application/ogg\r\n");
        try self.send("access-control-allow-origin: *\r\n");
        try self.send("server: strig\r\n\r\n");

        // try to detect when the client closes the connection by reading
        // from the socket in a loop
        var loop_buffer: [512]u8 = undefined;
        while (true) {
            std.debug.warn("keeping {} in readloop\n", .{self.connection.address});

            const loop_bytes = self.connection.file.read(&loop_buffer) catch |err| {
                std.debug.warn("got error in post-exchange loop: {}\n", .{err});
                self.deinit();
                break;
            };

            if (loop_bytes == 0) {
                // likely close connection (got it from SIGINT'ing curl)
                self.deinit();
                return;
            }
        }
    }
};
