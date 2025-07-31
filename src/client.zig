const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");
const rect = @import("rect.zig");
const net = @import("net.zig");
const resiliance = @import("resiliance.zig");

pub const WebsocketHandler = WebSockets.Handler(Client);

pub const Client = @This();
pub const InputRateLimiter = resiliance.rate_limiter(15, 5 * std.time.ms_per_s, 10 * std.time.ms_per_s);

pub const TrackedCursors = struct {
    client_id: u32,
    pos: @Vector(2, u32),
};
pub fn tracked_cursor_order(client_id: u32, a: TrackedCursors) std.math.Order{
    if (a.client_id == client_id) {
        return .eq;
    } else if (a.client_id < client_id) {
        return .lt;
    } else {
        return .gt;
    }
} 

pub fn less_than_cursor(_: void, a: TrackedCursors, b: TrackedCursors) bool {
    return a.client_id < b.client_id;
}

pub fn is_cursor_within_view(cell_rect: rect.Rect, pos: @Vector(2, u32)) bool {
    return rect.contains_point(cell_rect, pos / @Vector(2, u32){game.CELL_PIXEL_SIZE, game.CELL_PIXEL_SIZE});
}

lock: std.Thread.Mutex,
handle: WebSockets.WsHandle,
settings: WebsocketHandler.WebSocketSettings,
cell_rect: rect.Rect, // The region of the board that the client is currently viewing
quad_rect: rect.Rect, // The quad region that the client is subscribed to
ready: bool,
allocator: std.mem.Allocator,
tracked_cursors_pos: std.ArrayList(TrackedCursors),

client_id: u32 = 0, // Unique identifier for the client
cursor_pos: @Vector(2, u32) = .{0,0},
active_timestamp: i64 = 0, // Timestamp of the last activity from the client

input_rate_limiter: InputRateLimiter = .{},



pub fn upgrade(allocator: std.mem.Allocator, r: zap.Request) !*Client {
    game.state.client_lock.lock();
    defer game.state.client_lock.unlock();
    const client = try game.state.gpa.create(Client);
    errdefer client.deinit();
    game.state.client_id += 1;

    client.* = .{
        .lock = .{},
        .active_timestamp = std.time.timestamp(),
        .allocator = allocator,
        .handle = undefined,
        .client_id = game.state.client_id, 
        .cell_rect = rect.empty(),
        .quad_rect = rect.empty(),
        .tracked_cursors_pos = std.ArrayList(TrackedCursors).init(allocator),
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
    self.tracked_cursors_pos.deinit();
    game.state.board.unregister_client_board(self, self.quad_rect);
}

fn on_close_websocket(client: ?*Client, _: isize) !void {
    if (client) |c| {
        std.log.info("Client {any} disconnected", .{c.client_id});
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
        game.state.gpa.destroy(c);
    }
}

fn contains_simd2(a: []const @Vector(2, u32), b: @Vector(2, u32)) bool {
    for (a) |item| {
        if (std.simd.countTrues(item == b) == 2) {
            return true;
        }
    }
    return false;
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
        const msg_id = reader.readEnum(net.MsgID, .little) catch |err| {
            std.log.err("Failed to read message type: {any}", .{err});
            return;
        };
        switch (msg_id) {
            .set_view => {
                const board = &game.state.board;
                const quad_last_rect = c.quad_rect;
                const msg  = try net.msg_parse_view(reader.any());
                const quad_rect = game.map_to_quad(msg.cell_rect);
                if(quad_rect.width * quad_rect.height > 4) {
                    std.log.warn("Client view is too large: {any}", .{quad_rect});
                    return;
                }
                c.cursor_pos = msg.cursor_pos;
                c.cell_rect = msg.cell_rect; 
                c.quad_rect = quad_rect;
                c.active_timestamp = std.time.timestamp();
                game.state.board.update_client_rect(c, quad_last_rect, c.quad_rect);
                var iter = c.quad_rect.iterator();
                while (iter.next()) |pos| {
                    if (rect.contains_point(quad_last_rect, pos))
                        continue;
                    if(game.to_quad_index(pos, game.to_quad_size(board.size))) |update_quad_idx| {
                        board.quads[update_quad_idx].lock.lockShared();
                        defer board.quads[update_quad_idx].lock.unlockShared();
                        try net.msg_sync_block(c, &board.quads[update_quad_idx]);
                    }
                }
            },
            .input_or_sync_cell => {
                // rate limiting inputs
                if(!c.input_rate_limiter.input(1)) {
                    std.log.warn("Client {any} is sending inputs too fast, ignoring input", .{c.client_id});
                    return;
                }
                c.active_timestamp = std.time.timestamp();

                const board = &game.state.board;
                const input = try net.msg_parse_input(reader.any());
                if(game.to_quad_index(game.map_to_quad_pos(input.pos), game.to_quad_size(board.size))) |update_quad_idx| {
                    {
                        board.quads[update_quad_idx].client_lock.lock();
                        defer board.quads[update_quad_idx].client_lock.unlock();
                        var cell = &board.quads[update_quad_idx].input[game.to_cell_index(input.pos)];
                        if(cell.lock == 1) {
                            return; // Cell is locked, ignore the input
                        }
                        cell.value = input.input;
                    }
                    var dirty_cells = std.ArrayList(@Vector(2, u32)).init(game.state.gpa);
                    defer dirty_cells.deinit();
                    try dirty_cells.append(input.pos);
                    {
                        var tmp: [@sizeOf(*game.Clue) * 6]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&tmp);
                        var clues = try std.ArrayList(*game.Clue).initCapacity(fba.allocator(), 6);
                        try board.quads[update_quad_idx].get_crossing_clues(input.pos, &clues);
                        next_clue: for (clues.items) |cl| {
                            const clue_rect = cl.to_rect();
                            const clue_quad_rect = game.map_to_quad(clue_rect);
                            game.state.board.lock_quads(clue_quad_rect);
                            defer game.state.board.unlock_quads(clue_quad_rect);
                            {
                                var clue_pos_iter = clue_rect.iterator();
                                var idx: usize = 0;
                                while (clue_pos_iter.next()) |clue_pos|: (idx += 1) {
                                    if(game.to_quad_index(game.map_to_quad_pos(clue_pos), game.to_quad_size(board.size))) |clue_quad_idx| {
                                        if(board.quads[clue_quad_idx].input[game.to_cell_index(clue_pos)].value != cl.word[idx]) {
                                            continue :next_clue; 
                                        }
                                    } else {
                                        std.log.warn("Clue position {any} is out of bounds for the board size {any}", .{clue_pos, board.size});
                                        continue :next_clue; 
                                    }
                                }
                            }
                            {
                                _ = board.clues_completed.fetchAdd(1, .seq_cst); 
                                var clue_pos_iter = clue_rect.iterator();
                                while (clue_pos_iter.next()) |clue_pos| {
                                    if(game.to_quad_index(game.map_to_quad_pos(clue_pos), game.to_quad_size(board.size))) |clue_quad_idx| {
                                        var cell = &board.quads[clue_quad_idx].input[game.to_cell_index(clue_pos)];
                                        cell.lock = 1;
                                        if (!contains_simd2(dirty_cells.items, clue_pos)) {
                                            try dirty_cells.append(clue_pos);
                                        }
                                    } else unreachable;
                                }
                            }
                        }
                        for (dirty_cells.items) |dirty_pos| {
                            if(game.to_quad_index(game.map_to_quad_pos(dirty_pos), game.to_quad_size(board.size))) |dirty_quad_idx| {
                                board.quads[dirty_quad_idx].client_lock.lockShared();
                                defer board.quads[dirty_quad_idx].client_lock.unlockShared();
                                board.quads[dirty_quad_idx].lock.lockShared();
                                defer board.quads[dirty_quad_idx].lock.unlockShared();
                                for (board.quads[dirty_quad_idx].clients.items) |cl| {
                                    net.msg_sync_cell(cl, dirty_pos, board.quads[dirty_quad_idx].input[game.to_cell_index(dirty_pos)]) catch |err| {
                                        std.log.err("Failed to sync cell to client: {any}", .{err});
                                    };
                                }
                            } else unreachable;
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
        try net.msg_ready(c);
    } else {
        std.log.warn("WebSocket connection opened without a client context", .{});
    }
}
