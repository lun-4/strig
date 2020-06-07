const std = @import("std");
const Context = @import("context.zig").Context;
const Client = @import("client.zig").Client;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var addr = try std.net.Address.parseIp("127.0.0.1", 3000);
    var server = std.net.StreamServer.init(.{ .reuse_address = true });
    defer server.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    const loop = std.event.Loop.instance.?;
    loop.beginOneEvent();

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try server.listen(addr);
    std.debug.warn("listening to clients on {}\n", .{addr});
    while (true) {
        var conn = try server.accept();
        var client = try allocator.create(Client);
        client.* = Client{
            .allocator = allocator,
            .connection = conn,
            .ctx = &ctx,
            .handle_frame = async client.handle(),
        };
        // TODO deinit client somehow

        try ctx.addClient(client);
    }
}
