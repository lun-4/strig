const std = @import("std");
const Client = @import("client.zig").Client;

pub const Clients = std.StringHashMap(*Client);

pub const Context = struct {
    allocator: *std.mem.Allocator,
    clients: Clients,
    root_file: std.fs.File,

    pub fn init(allocator: *std.mem.Allocator, root_file: std.fs.File) @This() {
        return .{
            .allocator = allocator,
            .root_file = root_file,
            .clients = Clients.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.clients.deinit();
    }

    // Caller owns returned memory
    pub fn genClientId(self: *@This()) ![]const u8 {
        var randBytes: [32]u8 = undefined;

        const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
        var r = std.rand.DefaultPrng.init(seed);
        r.random.bytes(&randBytes);

        var res = try std.fmt.allocPrint(self.allocator, "{x}", .{&randBytes});
        return res;
    }

    pub fn addClient(self: *@This(), client: *Client) !void {
        std.debug.warn("adding client '{}' => {}\n", .{ client.id, client.connection.address });
        _ = try self.clients.put(client.id, client);
    }
};
