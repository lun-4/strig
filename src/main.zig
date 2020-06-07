const std = @import("std");
const Context = @import("context.zig").Context;
const Client = @import("client.zig").Client;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    var args_it = std.process.args();
    _ = args_it.skip();
    const audio_file_path = try (args_it.next(allocator) orelse @panic("expected audio file path"));

    // keep a root fd to the file, from there we spawn other fds via dup2
    var root_file = try std.fs.cwd().openFile(audio_file_path, .{ .read = true, .write = false });
    defer root_file.close();
    std.debug.warn("opened file '{}'\n", .{audio_file_path});

    var addr = try std.net.Address.parseIp("127.0.0.1", 3000);
    var server = std.net.StreamServer.init(.{ .reuse_address = true });
    defer server.close();

    const loop = std.event.Loop.instance.?;
    loop.beginOneEvent();

    var ctx = Context.init(allocator, root_file);
    defer ctx.deinit();

    try server.listen(addr);
    std.debug.warn("listening to clients on {}\n", .{addr});
    while (true) {
        var conn = try server.accept();
        var client = try allocator.create(Client);
        const client_id = try ctx.genClientId();
        client.* = Client{
            .id = client_id,
            .allocator = allocator,
            .connection = conn,
            .ctx = &ctx,
            .handle_frame = async client.handle(),
        };
        try ctx.addClient(client);
    }
}
