const std = @import("std");

const client = @import("client.zig");
const game = @import("game.zig");
const rect = @import("rect.zig");

pub const MsgID = enum(u8) { 
    ready = 0, 
    set_view = 1, 
    sync_block = 2, 
    input_or_sync_cell = 3,
    sync_cursors = 4,
    sync_cursors_delete = 5,
    unknown 
};


pub const MsgInput = struct {
    pos: @Vector(2, u32),
    input: game.Value,
};

//pub fn msg_ping(c: *client.Client) !void {
//    var buffer = std.ArrayList(u8).init(c.allocator);
//    defer buffer.deinit();
//    var writer = buffer.writer();
//    try writer.writeByte(@intFromEnum(client.MsgID.ping));
//    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
//        std.log.err("Failed to write message: {any}", .{err});
//        return err;
//    };
//}

pub fn msg_sync_cell(c: *client.Client, pos: @Vector(2, u32), value: game.Cell) !void {
    var buffer = std.ArrayList(u8).init(c.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(MsgID.input_or_sync_cell));
    try writer.writeInt(u32, pos[0], .little);
    try writer.writeInt(u32, pos[1], .little);
    try writer.writeInt(u8, value.encode(), .little);
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_sync_cursors(c: *client.Client, last_cursors: []const client.TrackedCursors, new_cursors: []const client.TrackedCursors) !void {
    var same_cursors = try std.bit_set.DynamicBitSet.initEmpty(c.allocator, last_cursors.len);
    defer same_cursors.deinit();
    var send_cursor = try std.bit_set.DynamicBitSet.initEmpty(c.allocator, new_cursors.len);
    defer send_cursor.deinit();
    next_cursor: for(new_cursors, 0..) |nc, new_idx| {
        for (last_cursors, 0..) |lc, old_idx| {
            if (nc.client_id == lc.client_id) {
                same_cursors.set(old_idx);
                if (std.simd.countTrues(nc.pos == lc.pos) == 2) {
                    continue :next_cursor; 
                }
            }
        }
        send_cursor.set(new_idx);
    }
    const delete_cursor = last_cursors.len - same_cursors.count();
    if(delete_cursor == 0 and send_cursor.count() == 0) {
        return; // No cursors to sync
    }
    var buffer = std.ArrayList(u8).init(c.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    if(delete_cursor > 0) {
        try writer.writeByte(@intFromEnum(MsgID.sync_cursors_delete));
        try writer.writeInt(u16, @truncate(delete_cursor), .little);
        for(last_cursors, 0..) |lc, old_idx| {
            if (!same_cursors.isSet(old_idx)) {
                try writer.writeInt(u32, lc.client_id, .little);
            }
        }
    } else {
        try writer.writeByte(@intFromEnum(MsgID.sync_cursors));
    }

    const quad_pos_px = @Vector(2, i32){ @as(i32, @intCast(c.quad_rect.x * game.GRID_SIZE * game.CELL_PIXEL_SIZE)), @as(i32, @intCast(c.quad_rect.y * game.GRID_SIZE * game.CELL_PIXEL_SIZE)) };
    try writer.writeInt(u16, @intCast(c.quad_rect.x), .little);
    try writer.writeInt(u16, @intCast(c.quad_rect.y), .little);
    
    for(new_cursors, 0..) |new_c, new_idx| {
        if (!send_cursor.isSet(new_idx)) continue;
        try writer.writeInt(u32, new_c.client_id, .little);
        try writer.writeInt(i16, @as(i16, @truncate(@as(i32, @intCast(new_c.pos[0])) - quad_pos_px[0])), .little);
        try writer.writeInt(i16, @as(i16, @truncate(@as(i32, @intCast(new_c.pos[1])) - quad_pos_px[1])), .little);
    }
    
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_parse_view(reader: std.io.AnyReader) !struct {
    cell_rect: rect.Rect,
    cursor_pos: @Vector(2, u32),
}{
    const x = try reader.readInt(u16, .little);
    const y = try reader.readInt(u16, .little);
    const width = try reader.readInt(u16, .little);
    const height = try reader.readInt(u16, .little);
    const cursor_x = try reader.readInt(u32, .little);
    const cursor_y = try reader.readInt(u32, .little);

    return .{
        .cell_rect = rect.create(x, y, width, height),
        .cursor_pos = .{ cursor_x, cursor_y },
    }; 
}

pub fn msg_ready(c: *client.Client) !void {
    var buffer = std.ArrayList(u8).init(c.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(MsgID.ready));
    try writer.writeInt(u32, game.state.board.size[0], .little);
    try writer.writeInt(u32, game.state.board.size[1], .little);
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

//pub fn msg_pong(c: *client.Client, board: *game.Board) !void {
//    var buffer = std.ArrayList(u8).init(c.allocator);
//    defer buffer.deinit();
//    var writer = buffer.writer();
//    try writer.writeByte(@intFromEnum(client.MsgID.ping));
//    try writer.writeInt(u32, @bitCast(@as(f32, @floatFromInt(board.clues_completed.load(.unordered))) / @as(f32, @floatFromInt(board.clues.items.len))), .little);
//    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
//        std.log.err("Failed to write message: {any}", .{err});
//        return err;
//    };
//}

pub fn msg_sync_block(c: *client.Client, quad: *game.Quad) !void {
    var buffer = std.ArrayList(u8).init(c.allocator);
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
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_parse_input(reader: std.io.AnyReader) !MsgInput {
    const x = try reader.readInt(u32, .little);
    const y = try reader.readInt(u32, .little);
    const input = try reader.readInt(u8, .little);

    return .{ .pos = .{ x, y }, .input = switch (input) {
        @intFromEnum(game.Value.empty) => game.Value.empty,
        @intFromEnum(game.Value.dash) => game.Value.dash,
        @intFromEnum(game.Value.a) => game.Value.a,
        @intFromEnum(game.Value.b) => game.Value.b,
        @intFromEnum(game.Value.c) => game.Value.c,
        @intFromEnum(game.Value.d) => game.Value.d,
        @intFromEnum(game.Value.e) => game.Value.e,
        @intFromEnum(game.Value.f) => game.Value.f,
        @intFromEnum(game.Value.g) => game.Value.g,
        @intFromEnum(game.Value.h) => game.Value.h,
        @intFromEnum(game.Value.i) => game.Value.i,
        @intFromEnum(game.Value.j) => game.Value.j,
        @intFromEnum(game.Value.k) => game.Value.k,
        @intFromEnum(game.Value.l) => game.Value.l,
        @intFromEnum(game.Value.m) => game.Value.m,
        @intFromEnum(game.Value.n) => game.Value.n,
        @intFromEnum(game.Value.o) => game.Value.o,
        @intFromEnum(game.Value.p) => game.Value.p,
        @intFromEnum(game.Value.q) => game.Value.q,
        @intFromEnum(game.Value.r) => game.Value.r,
        @intFromEnum(game.Value.s) => game.Value.s,
        @intFromEnum(game.Value.t) => game.Value.t,
        @intFromEnum(game.Value.u) => game.Value.u,
        @intFromEnum(game.Value.v) => game.Value.v,
        @intFromEnum(game.Value.w) => game.Value.w,
        @intFromEnum(game.Value.x) => game.Value.x,
        @intFromEnum(game.Value.y) => game.Value.y,
        @intFromEnum(game.Value.z) => game.Value.z,
        else => |v| {
            std.log.warn("Received unknown input value: {d}", .{v});
            return error.InvalidInput;
        },
    } };
}
