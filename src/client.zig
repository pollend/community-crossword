const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const WebsocketHandler = WebSockets.Handler(Client);
const game = @import("game.zig");
const rect = @import("rect.zig");

const MsgID = enum(u8) {
   ready,
   set_view,
   sync_block,
   unknown 
};

pub const Client = @This(); 

channel: []const u8,
handle: WebSockets.WsHandle,
settings: WebsocketHandler.WebSocketSettings,
view: rect.Rect,
ready: bool,
allocator: std.mem.Allocator,
pub fn upgrade(allocator: std.mem.Allocator,r: zap.Request) !*Client {
    game.state.client_lock.lock();
    defer game.state.client_lock.unlock();
    const client = try game.state.allocator.create(Client);
    errdefer client.deinit();
    const client_channel = try std.fmt.allocPrint(allocator, "c-{any}", .{game.state.client_id});
    game.state.client_id += 1;

    client.* = .{
        .allocator = allocator,
        .channel = client_channel,
        .handle = undefined,
        .settings = .{
            .on_open = on_open_websocket,
            .on_close = on_close_websocket,
            .on_message = on_message_websocket,
            .context = client 
        },
        .ready = false,
        .view = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    };
    try WebsocketHandler.upgrade(r.h, &client.settings);
    try game.state.clients.append(client);
    return client;
}

pub fn deinit(self: *Client) void {
    self.allocator.free(self.channel);
}

fn on_close_websocket(client: ?*Client, _: isize) !void {
    if(client) |c| {
        game.state.client_lock.lock();
        defer game.state.client_lock.unlock();
        var i: usize = 0;
        while(i < game.state.clients.items.len) : (i += 1) {
            if (game.state.clients.items[i] == c) {
                _ = game.state.clients.orderedRemove(i);
                break;
            }
        }
        game.state.allocator.destroy(c); 
    }
}

fn update_view(client: ?*Client, r: rect.Rect) !void {
    if (client) |c| {
        var quad_rect: rect.Rect = game.map_to_quad(r.pad(game.GRID_SIZE));
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if(game.state.board.get_quad(pos)) |quad| {
                try msg_sync_block(c, quad); // Sync the first block of the quad
                std.log.debug("Posted block at quad {any}", .{pos}); 
            } else {
                std.log.warn("Quad not found for position {any}", .{pos});
            }
        }
        c.view = r;
        std.log.debug("Updated client view to: {any}", .{c.view});
    } else {
        std.log.warn("Received update_pos with no client context", .{});
    }
}

pub fn msg_ready(client: *Client) !void {
    const msg: [1]u8 = .{
        @intFromEnum(MsgID.ready),
    };
    WebsocketHandler.write(client.handle, &msg, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_sync_block(client: *Client, quad: *game.Quad) !void{
    var buffer = std.ArrayList(u8).init(client.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(MsgID.sync_block));
    var i: usize = 0;
    try writer.writeInt(u32, quad.x, .little);
    try writer.writeInt(u32, quad.y, .little);
    while (i < game.GRID_LEN) : (i += 1) {
        try writer.writeInt(u8, quad.input[i].encode(), .little);
    }
    WebsocketHandler.write(client.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

fn on_message_websocket(
    client: ?*Client,
    _: WebSockets.WsHandle,
    buffer: []const u8,
    _: bool,
) !void {
    if(client) |c| {
        var stream = std.io.fixedBufferStream(buffer); 
        var reader = stream.reader();
        const msg_id = reader.readEnum(MsgID, .little) catch |err| {
            std.log.err("Failed to read message type: {any}", .{err});
            return;
        };
        std.log.debug("Received message with ID: {any}", .{msg_id});
        switch (msg_id) {
            .set_view => {
                const x = try reader.readInt(u32, .little);
                const y = try reader.readInt(u32, .little);
                const width = try reader.readInt(u32, .little);
                const height = try reader.readInt(u32, .little);
                c.view = rect.create(x, y, width, height);
                std.log.debug("Received set_view message: x={d}, y={d}, width={d}, height={d}", .{x, y, width, height});
                update_view(c, c.view) catch |err| {
                    std.log.err("Failed to update view: {any}", .{err});
                };
            },
            else => {   
                std.log.warn("Received unknown message type", .{});
            }
        }
    }
}

fn on_open_websocket(client: ?*Client, handle: WebSockets.WsHandle) !void {
    if (client) |c| {
        c.handle = handle;
        c.ready = true;
        try msg_ready(c);
        std.log.info("WebSocket connection opened for client: {s}", .{c.channel});
    } else {
        std.log.warn("WebSocket connection opened without a client context", .{});
    }

}




