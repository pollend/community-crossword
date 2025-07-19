const game = @import("game.zig");
const std = @import("std");

pub const MsgInput = struct {
    pos: @Vector(2, u32),
    input: game.Value, 
};

pub fn msg_parse_input(reader: std.io.AnyReader) !MsgInput{
    const x = try reader.readInt(u32, .little);
    const y = try reader.readInt(u32, .little);
    const input = try reader.readInt(u8, .little);

    return .{ 
        .pos = .{x, y}, 
        .input = switch (input) {
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
            }
        }
    };
}
