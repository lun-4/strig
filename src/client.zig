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
        try self.send("HTTP/1.1 200\r\n" ++
            "content-type: audio/mp3\r\n" ++
            "access-control-allow-origin: *\r\n" ++
            "server: strig\r\n\r\n");

        var file_buffer: [1024 * 1024]u8 = undefined;
        var memfd = try std.os.memfd_create("copy", 0);
        try std.os.dup2(self.ctx.root_file.handle, memfd);

        var file_copy = std.fs.File{ .handle = memfd };
        defer file_copy.close();

        try file_copy.seekTo(0);
        while (true) {
            const file_bytes = try file_copy.read(&file_buffer);
            if (file_bytes == 0) {
                // reached eof?
                std.debug.warn("eof of file? closing {}\n", .{self.id});
                self.deinit();
                break;
            }

            std.debug.warn("sending {} bytes\n", .{file_bytes});

            const written_bytes = try self.connection.file.write(&file_buffer);
            if (written_bytes == 0) {
                std.debug.warn("broke?\n", .{});
                self.deinit();
                break;
            }

            std.time.sleep(1 * std.time.ns_per_s);
        }
    }
};
