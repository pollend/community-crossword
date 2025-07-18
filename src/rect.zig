const std = @import("std");

x: u32,
y: u32,
width: u32,
height: u32,
pub const Rect = @This();

pub fn iterator(self: Rect) RectIterator {
    return .{
        .rect = self,
        .index = .{ 0, 0 },
    };
}

pub fn empty() Rect {
    return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
}

pub fn create(x: u32, y: u32, width: u32, height: u32) Rect {
    return .{ .x = x, .y = y, .width = width, .height = height };
}

pub fn contains_point(self: Rect, point: @Vector(2, u32)) bool {
    return point[0] >= self.x and point[0] < self.x + self.width and
        point[1] >= self.y and point[1] < self.y + self.height;
}

pub fn pad(self: Rect, padding: u32) Rect {
    return .{
        .x = if (self.x < padding) 0 else self.x - padding,
        .y = if (self.y < padding) 0 else self.y - padding,
        .width = self.width + (padding * 2),
        .height = self.height + (padding * 2),
    };
}

pub const RectIterator = struct {
    rect: Rect,
    index: @Vector(2, u32),
    pub fn next(self: *RectIterator) ?@Vector(2, u32) {
        const current = self.index;
        if (current[1] >= self.rect.height) {
            return null; // No more cells to iterate
        }
        self.index[0] += 1;
        if (self.index[0] >= self.rect.width) {
            self.index = .{ 0, self.index[1] + 1 };
        }
        return .{ current[0] + self.rect.x, current[1] + self.rect.y };
    }
};

const expect = std.testing.expect;
test "rectangle iterator" {
    const rect = Rect.create(0, 0, 1, 1);
    var iter = rect.iterator();
    var it = iter.next();
    try expect(it != null and it.?[0] == 0 and it.?[1] == 0);
    it = iter.next();
    try expect(it == null);
}

test "rectangle iterator empty" {
    const rect = Rect.empty();
    var iter = rect.iterator();
    const it = iter.next();
    try expect(it == null);
}

test "rectangle iterator 2x2" {
    const rect = Rect.create(0, 0, 2, 2);
    var iter = rect.iterator();
    var it = iter.next();
    try expect(it != null and it.?[0] == 0 and it.?[1] == 0);
    it = iter.next();
    try expect(it != null and it.?[0] == 1 and it.?[1] == 0);
    it = iter.next();
    try expect(it != null and it.?[0] == 0 and it.?[1] == 1);
    it = iter.next();
    try expect(it != null and it.?[0] == 1 and it.?[1] == 1);
    it = iter.next();
    try expect(it == null);
}
