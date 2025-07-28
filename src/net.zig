const game = @import("game.zig");
const std = @import("std");
const client = @import("client.zig");

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
    try writer.writeByte(@intFromEnum(client.MsgID.input_or_sync_cell));
    try writer.writeInt(u32, pos[0], .little);
    try writer.writeInt(u32, pos[1], .little);
    try writer.writeInt(u8, value.encode(), .little);
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}


pub fn msg_pong(c: *client.Client, board: *game.Board) !void {
    var buffer = std.ArrayList(u8).init(c.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(client.MsgID.ping));
    try writer.writeInt(u32, @bitCast(@as(f32, @floatFromInt(board.clues_completed.load(.unordered))) / @as(f32, @floatFromInt(board.clues.items.len))), .little);
    client.WebsocketHandler.write(c.handle, buffer.items, false) catch |err| {
        std.log.err("Failed to write message: {any}", .{err});
        return err;
    };
}

pub fn msg_sync_block(c: *client.Client, quad: *game.Quad) !void {
    var buffer = std.ArrayList(u8).init(c.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try writer.writeByte(@intFromEnum(client.MsgID.sync_block));
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
