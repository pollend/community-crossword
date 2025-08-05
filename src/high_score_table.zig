const std = @import("std");
const session = @import("session.zig");

pub const Entry = struct {
    session_id: [session.SESSION_ID_LENGTH]u8,
    nick: []const u8,
    last_word: []const u8,
    score: u32,
};


pub fn FixedHighscoreTable(comptime size: usize) type {
    return struct {
        table: Entry[size],
        allocator: std.mem.Allocator,
       // pub fn init(allocator: std.mem.Allocator) !FixedHighscoreTable {
       //     return .{
       //         .scores = table.scores,
       //         .allocator = allocator,
       //     };
       // }

    };
}
