const std = @import("std");
const Client = @import("client.zig").Client;

pub const ClientList = ArrayList(Client);

pub const Context = struct {
    allocator: *std.mem.Allocator,
    clients: ClientList,

    pub fn init(allocator: *std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .clients = ClientList.init(allocator),
        };
    }

    pub fn addClient(self: *@This(), client: Client) !void {
        try self.clients.append(client);
    }
};
