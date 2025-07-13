const std = @import("std");
pub const Direction = enum(u1) {
    Across,
    Down,
};

pub const Board = @This();
allocator: std.mem.Allocator,
width: usize,
height: usize,
cells: []u8,
pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Board {
    const buf = try allocator.alloc(u8, width * height);
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = ' '; // Initialize all cells to empty space
    }
    return .{
        .allocator = allocator,
        .width = width,
        .height = height,
        .cells = buf,
    };
}

pub fn deinit(self: *Board) void {
    self.allocator.free(self.cells);
}

pub fn get(self: *Board, x: usize, y: usize) ?u8 {
    if (x >= self.width or y >= self.height) {
        return null;
    }
    return self.cells[(y * self.width) + x];
}

pub fn set(self: *Board, x: usize, y: usize, value: u8) !void {
    if (x >= self.width or y >= self.height) {
        return error.IndexOutOfBounds;
    }
    self.cells[(y * self.width) + x] = value;
}
