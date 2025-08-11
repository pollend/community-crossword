const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");
const rect = @import("rect.zig");
const net = @import("net.zig");
const aws = @import("aws");
const resiliance = @import("resiliance.zig");
const profile_session = @import("profile_session.zig");
pub const WebsocketHandler = WebSockets.Handler(Client);
pub const nanoid = @import("nanoid.zig");
pub const SESSION_COOKIE_ID = "_session";

pub const NICK_MAX_LENGTH: usize = 64;

pub const Client = @This();
pub const InputRateLimiter = resiliance.rate_limiter(15, 5 * std.time.ms_per_s, 10 * std.time.ms_per_s);
pub const NickBoundedArray = std.BoundedArray(u8, NICK_MAX_LENGTH);

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

pub fn is_cursor_within_view(cell_rect: rect.Rect, pos: @Vector(2, u32)) bool {
    return rect.contains_point(cell_rect, pos / @Vector(2, u32){game.CELL_PIXEL_SIZE, game.CELL_PIXEL_SIZE});
}

session: profile_session.ProfileSession,
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
nick: NickBoundedArray,
input_rate_limiter: InputRateLimiter = .{},

pub fn upgrade(allocator: std.mem.Allocator, r: zap.Request) !*Client {
    r.parseCookies(true);
    const profile: profile_session.ProfileSession = profile: {
        if(try r.getCookieStr(allocator, SESSION_COOKIE_ID)) |c| {
            std.log.info("Found session cookie: {s}: {any}", .{c, c.len});
            defer allocator.free(c);
            if(profile_session.ProfileSession.parse_cookie(game.state.gpa, game.state.session_key, c) catch  |err| fl: {
                std.log.err("Failed to parse session cookie: {any}", .{err});
                break :fl null;
            } ) |session| {
                if(!session.is_expired()) {
                    break :profile session;
                }
            } 
        }
        return error.InvalidCookie;
    };
    game.state.client_lock.lock();
    defer game.state.client_lock.unlock();

    const res = try game.state.client_lookup.getOrPut(profile.profile_id);
    if(res.found_existing) {
        std.log.warn("Client with profile ID {any} already exists", .{profile.profile_id});
        return error.ClientAlreadyExists;
    }
    
    const client = try game.state.gpa.create(Client);
    res.value_ptr.* = client;
    errdefer game.state.gpa.destroy(client);
    game.state.client_id += 1;
    client.* = .{
        .lock = .{},
        .session = profile,
        .active_timestamp = std.time.timestamp(),
        .allocator = allocator,
        .handle = undefined,
        .client_id = game.state.client_id, 
        .cell_rect = rect.empty(),
        .quad_rect = rect.empty(),
        .tracked_cursors_pos = std.ArrayList(TrackedCursors).init(allocator),
        .nick = std.BoundedArray(u8, NICK_MAX_LENGTH).init(0) catch unreachable,
        .settings = .{ 
            .on_open = on_open_websocket, 
            .on_close = on_close_websocket,
            .on_message = on_message_websocket, 
            .context = client },
        .ready = false,
    };
    errdefer client.deinit();
    try WebsocketHandler.upgrade(r.h, &client.settings);
    return client;
}

pub fn deinit(self: *Client) void {
    self.lock.lock();
    defer self.lock.unlock();
    self.tracked_cursors_pos.deinit();
    game.state.board.unregister_client_board(self, self.quad_rect);
}


fn on_close_websocket(client: ?*Client, _: isize) !void {
    std.log.info("Disconnection", .{});
    if (client) |c| {
        std.log.info("Client {any} disconnected", .{c.client_id});
        {
            // remove the client from the board
            game.state.client_lock.lock();
            defer game.state.client_lock.unlock();
            if(game.state.client_lookup.remove(c.session.profile_id)) {
                std.log.debug("Removed client {any} from lookup", .{c.session.profile_id});
            } else {
                std.log.err("Client is untracked {any}", .{c.session.profile_id});
            }
           // var i: usize = 0;
           // while (i < game.state.clients.items.len) : (i += 1) {
           //     if (game.state.clients.items[i] == c) {
           //         _ = game.state.clients.swapRemove(i);
           //         std.log.debug("Remove client from index {d}", .{i});
           //         break;
           //     }
           // }
        }
        //c.profile.commit_profile_s3(
        //    c.allocator,
        //    game.state.bucket,
        //    .{
        //        .region = game.state.region,
        //        .client = game.state.aws_client,
        //    },
        //) catch |err| {
        //    std.log.err("Failed to commit session: {any}", .{err});
        //};
        c.deinit();
        game.state.gpa.destroy(c);
    }
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
            .update_nick => {
                c.nick = try reader.readBoundedBytes(NICK_MAX_LENGTH);
                std.debug.print("updating nick: {any} - {s}\n", .{c.client_id, c.nick.slice()});
                game.state.global.update_nick(c.session.profile_id, c.nick.slice());
                try net.msg_send_nick(c, c.nick.slice());
            },
            .set_view => {
                const board = &game.state.board;
                const quad_last_rect = c.quad_rect;
                const msg  = try net.msg_parse_view(reader.any());
                const quad_rect = game.map_to_quad(msg.cell_rect);
                if(quad_rect.width * quad_rect.height > 9) {
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
                        var cell: *game.Cell = &board.quads[update_quad_idx].input[game.to_cell_index(input.pos)];
                        if(cell.lock == 1) {
                            return; // Cell is locked, ignore the input
                        }
                        cell.value = input.input;
                        for(board.quads[update_quad_idx].clients.items) |cl| {
                            net.msg_sync_cell(cl, input.pos, cell.*) catch |err| {
                                std.log.err("Failed to sync cell to client: {any}", .{err});
                            };
                        }
                    }
                    {
                        var tmp: [@sizeOf(*game.Clue) * 6]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&tmp);
                        var clues = try std.ArrayList(*game.Clue).initCapacity(fba.allocator(), 6);
                        try board.quads[update_quad_idx].get_crossing_clues(input.pos, &clues);

                        next_clue: for (clues.items) |current_clue| {
                            const clue_rect = current_clue.to_rect();
                            const clue_quad_rect = game.map_to_quad(clue_rect);
                            game.state.board.lock_quads_client_shared(clue_quad_rect);
                            defer game.state.board.unlock_quads_client_shared(clue_quad_rect);
                            game.state.board.lock_quads(clue_quad_rect);
                            defer game.state.board.unlock_quads(clue_quad_rect);
                            {
                                var clue_pos_iter = clue_rect.iterator();
                                var idx: usize = 0;
                                while (clue_pos_iter.next()) |clue_pos|: (idx += 1) {
                                    if(game.to_quad_index(game.map_to_quad_pos(clue_pos), game.to_quad_size(board.size))) |clue_quad_idx| {
                                        if(board.quads[clue_quad_idx].input[game.to_cell_index(clue_pos)].value != current_clue.word[idx]) {
                                            continue :next_clue; 
                                        }
                                    } else {
                                        std.log.warn("Clue position {any} is out of bounds for the board size {any}", .{clue_pos, board.size});
                                        continue :next_clue; 
                                    }
                                }
                            }
                            {
                                c.session.update_solved(current_clue); 
                                game.state.global.process(c.session.profile_id, c.nick.slice(), current_clue.word[0..], c.session.score, c.session.num_clues_solved) catch |err| {
                                    std.log.err("Failed to process global highscore: {any}", .{err});
                                };
                                _ = board.clues_completed.fetchAdd(1, .seq_cst);
                                if(game.to_quad_index(game.map_to_quad_pos(current_clue.pos), game.to_quad_size(board.size))) |clue_quad_idx| {
                                    for (board.quads[clue_quad_idx].clients.items) |other_clients| {
                                        net.msg_sync_solved_clue(other_clients, current_clue, other_clients == c) catch |err| {
                                            std.log.err("Failed to sync clue to client: {any}", .{err});
                                        };
                                    }
                                } else unreachable;

                                var clue_pos_iter = clue_rect.iterator();
                                while (clue_pos_iter.next()) |clue_pos| {
                                    if(game.to_quad_index(game.map_to_quad_pos(clue_pos), game.to_quad_size(board.size))) |clue_quad_idx| {
                                        var cell = &board.quads[clue_quad_idx].input[game.to_cell_index(clue_pos)];
                                        cell.lock = 1;
                                    } else unreachable;
                                }
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
        try net.msg_ready(c);
        game.state.client_lock.lock();
        defer game.state.client_lock.unlock();
        try net.msg_broadcast_game_state(c, &game.state.board);
    } else {
        std.log.warn("WebSocket connection opened without a client context", .{});
    }
}
