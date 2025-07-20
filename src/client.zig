const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");
const rect = @import("rect.zig");
const net = @import("net.zig");

pub const WebsocketHandler = WebSockets.Handler(Client);

pub const MsgID = enum(u8) { 
    ready = 0, 
    set_view = 1, 
    sync_block = 2, 
    input_or_sync_cell = 3, 
    unknown };

pub const Client = @This();

lock: std.Thread.Mutex,
channel: []const u8,
handle: WebSockets.WsHandle,
settings: WebsocketHandler.WebSocketSettings,
cell_rect: rect.Rect, // The region of the board that the client is currently viewing
quad_rect: rect.Rect, // The quad region that the client is subscribed to
ready: bool,
allocator: std.mem.Allocator,
pub fn upgrade(allocator: std.mem.Allocator, r: zap.Request) !*Client {
    game.state.client_lock.lock();
    defer game.state.client_lock.unlock();
    const client = try game.state.allocator.create(Client);
    errdefer client.deinit();
    const client_channel = try std.fmt.allocPrint(allocator, "c-{any}", .{game.state.client_id});
    game.state.client_id += 1;

    client.* = .{
        .lock = .{},
        .allocator = allocator,
        .channel = client_channel,
        .handle = undefined,
        .cell_rect = rect.empty(),
        .quad_rect = rect.empty(),
        .settings = .{ .on_open = on_open_websocket, .on_close = on_close_websocket, .on_message = on_message_websocket, .context = client },
        .ready = false,
    };
    try WebsocketHandler.upgrade(r.h, &client.settings);
    try game.state.clients.append(client);
    return client;
}

pub fn deinit(self: *Client) void {
    self.lock.lock();
    defer self.lock.unlock();
    game.state.board.unregister_client_board(self, self.quad_rect);
    self.allocator.free(self.channel);
}

fn on_close_websocket(client: ?*Client, _: isize) !void {
    if (client) |c| {
        game.state.client_lock.lock();
        defer game.state.client_lock.unlock();
        var i: usize = 0;
        while (i < game.state.clients.items.len) : (i += 1) {
            if (game.state.clients.items[i] == c) {
                _ = game.state.clients.swapRemove(i);
                break;
            }
        }
        c.deinit();
        game.state.allocator.destroy(c);
    }
}

pub fn msg_parse_view(reader: std.io.AnyReader) !rect.Rect {
    const x = try reader.readInt(u32, .little);
    const y = try reader.readInt(u32, .little);
    const width = try reader.readInt(u32, .little);
    const height = try reader.readInt(u32, .little);
    return rect.create(x, y, width, height);
}

pub fn msg_ready(client: *Client) !void {
    var buffer = std.ArrayList(u8).init(client.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(MsgID.ready));
    try writer.writeInt(u32, game.state.board.size[0], .little);
    try writer.writeInt(u32, game.state.board.size[1], .little);
    WebsocketHandler.write(client.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_sync_block(client: *Client, quad: *game.Quad) !void {
    var buffer = std.ArrayList(u8).init(client.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(MsgID.sync_block));
    try writer.writeInt(u32, quad.x, .little);
    try writer.writeInt(u32, quad.y, .little);
    var i: usize = 0;
    while (i < game.GRID_LEN) : (i += 1) {
        try writer.writeInt(u8, quad.input[i].encode(), .little);
    }
    try writer.writeInt(u16, @intCast(quad.clues.items.len), .little);
    for (quad.clues.items) |clue| {
        try writer.writeInt(u8, @intCast(clue.pos[0] - (quad.x * game.GRID_SIZE)), .little);
        try writer.writeInt(u8, @intCast(clue.pos[1] - (quad.y * game.GRID_SIZE)), .little);
        try writer.writeInt(u8, @intFromEnum(clue.dir), .little);
        try writer.writeInt(u16, @intCast(clue.clue.len), .little);
        try writer.writeAll(clue.clue);
    }
    WebsocketHandler.write(client.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

fn contains_simd2(a: []const @Vector(2, u32), b: @Vector(2, u32)) bool {
    for (a) |item| {
        if (std.simd.countTrues(item == b) == 2) {
            return true;
        }
    }
    return false;
}

const BoardIterMsgLocking = game.BoardIter(
    void,
    __client_locking_enter,
    __client_locking_exit,
);

fn __client_locking_enter(
    _: *void,
    quad: *game.Quad,
) void {
    quad.client_lock.lockShared();
    quad.lock.lockShared();
}

fn __client_locking_exit(
    _: *void,
    quad: *game.Quad,
) void {
    quad.lock.unlockShared();
    quad.client_lock.unlockShared();
}

fn on_message_websocket(
    client: ?*Client,
    _: WebSockets.WsHandle,
    buffer: []const u8,
    _: bool,
) !void {
    if (client) |c| {
        c.lock.lock();
        defer c.lock.unlock();

        var stream = std.io.fixedBufferStream(buffer);
        var reader = stream.reader();
        const msg_id = reader.readEnum(MsgID, .little) catch |err| {
            std.log.err("Failed to read message type: {any}", .{err});
            return;
        };
        std.log.debug("on_message: {any} client {s}", .{ msg_id, c.channel });
        switch (msg_id) {
            .set_view => {
                c.cell_rect = try msg_parse_view(reader.any());
                const quad_last_rect = c.quad_rect;
                c.quad_rect = game.map_to_quad(c.cell_rect);
                game.state.board.update_client_rect(c, quad_last_rect, c.quad_rect);
                var iter = c.quad_rect.iterator();
                while (iter.next()) |pos| {
                    if (rect.contains_point(quad_last_rect, pos))
                        continue;
                    if (game.state.board.get_quad(pos)) |quad| {
                        quad.lock.lockShared();
                        defer quad.lock.unlockShared();
                        try msg_sync_block(c, quad); // Sync the first block of the quad
                    }
                }
            },
            .input_or_sync_cell => {
                const input = try net.msg_parse_input(reader.any());

                if (game.state.board.get_quad_from_cell_pos(input.pos)) |quad| {
                    const local_pos = quad.to_local(input.pos);
                    {
                        quad.lock.lock();
                        defer quad.lock.unlock();
                        var cell = quad.get_cell(local_pos);
                        if (cell.lock == 1) {
                            return; // Cell is locked, ignore the input
                        }
                        cell.value = input.input;
                    }
                    //var dirty_region: rect.Rect = rect.empty();
                    var dirty_cells = std.ArrayList(@Vector(2, u32)).init(game.state.allocator);
                    defer dirty_cells.deinit();
                    try dirty_cells.append(input.pos);
                    {
                        var clues: [6]*game.Clue = undefined;
                        var len: usize = 0;
                        quad.get_crossing_clues(local_pos, &clues, &len);
                        next_clue: for (clues[0..len]) |cl| {
                            const clue_rect = cl.to_rect();
                            const clue_quad_rect = game.map_to_quad(clue_rect);
                            game.state.board.lock_quads(clue_quad_rect);
                            defer game.state.board.unlock_quads(clue_quad_rect);
                            {
                                var clue_itr = game.DefaultQuadDefault.init({}, &game.state.board, clue_rect);
                                defer clue_itr.deinit();
                                var idx: usize = 0;
                                while (clue_itr.next()) |qq| {
                                    if (qq.q.get_cell(qq.p).value != cl.word[idx]) {
                                        continue :next_clue;
                                    }
                                    idx += 1;
                                }
                            }
                            {
                                var clue_itr = game.DefaultQuadDefault.init({}, &game.state.board, clue_rect);
                                defer clue_itr.deinit();
                                while (clue_itr.next()) |qq| {
                                    qq.q.get_cell(qq.p).lock = 1;
                                    if (!contains_simd2(dirty_cells.items, qq.p)) {
                                        try dirty_cells.append(qq.p);
                                    }
                                }
                            }
                        }
                    }
                    for (dirty_cells.items) |dirty_pos| {
                        if (game.state.board.get_quad_from_cell_pos(dirty_pos)) |quad2| {
                            quad2.client_lock.lockShared();
                            defer quad2.client_lock.unlockShared();
                            quad2.lock.lockShared();
                            defer quad2.lock.unlockShared();
                            for (quad2.clients.items) |cl| {
                                net.msg_sync_cell(cl, dirty_pos, quad2.get_cell(quad2.to_local(dirty_pos)).*) catch |err| {
                                    std.log.err("Failed to sync cell to client: {any}", .{err});
                                };
                            }
                        }
                    }
                }
            },
            else => {
                std.log.warn("Received unknown message type {any}", .{msg_id});
            },
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
