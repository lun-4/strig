const std = @import("std");
const Context = @import("context.zig").Context;
const Client = @import("Client.zig").Client;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    std.debug.warn("All your codebase are belong to us.\n", .{});
    var addr = std.net.Address.parseIp("127.0.0.1", 3000);
    var server = std.net.StreamServer.init(.{ .listen_address = addr });
    defer server.close();

    var arena = std.heap.ArenaAllocator(std.heap.direct_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    const loop = std.event.Loop.instance.?;
    loop.beginOneEvent();

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try server.listen();
    while (true) {
        var conn = try server.accept();
        var client = try allocator.create(Client);
        client.* = Client{
            .allocator = allocator,
            .connection = conn,
            .ctx = ctx,
            .handle_frame = async client.handle(),
        };
        // TODO deinit client somehow

        try ctx.addClient(conn);
    }
}
