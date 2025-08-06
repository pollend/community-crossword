const std = @import("std");

pub fn EvictingFifo(
    comptime T: type,
    comptime size: usize,
) type {
    return struct {
        items: [size]T,
        head_index: usize,
        tail_index: usize,

        pub const Self = @This();
        pub fn init() Self {
            return Self {
                .items = undefined,
                .head_index = 0,
                .tail_index = 0,
            };
        }

        pub fn last(self: *Self) ?T {
            if (self.tail_index == self.head_index) {
                return null; // queue is empty
            }
            const last_index = (self.head_index + size - 1) % size;
            return self.items[last_index];
        }

        pub fn length(self: *Self) usize {
            if (self.tail_index == self.head_index) {
                return 0; // queue is empty
            }
            if (self.head_index >= self.tail_index) {
                return self.head_index - self.tail_index;
            } 
            return (size - self.tail_index) + self.head_index;
        }

        pub fn iterator(self: *Self) Iterator(T) {
            return .{
                .items = self.items[0..],
                .head_index = self.head_index,
                .index = self.tail_index,
            };
        }

        pub fn remove(self: *Self) ?T {
            if (self.tail_index == self.head_index) {
                return null; // queue is empty
            }
            const value = self.items[self.tail_index];
            self.tail_index = (self.tail_index + 1) % size;
            return value;
        }

        // apped a value to the lifo and return the oldest value if the queue is full
        pub fn push(self: *Self, value: T) ?T {
            var it: ?T = null;
            if ((self.head_index + 1) % size == self.tail_index) {
                it= self.items[self.tail_index];
                self.tail_index = (self.tail_index + 1) % size;
            } 
            self.items[self.head_index] = value;
            self.head_index = (self.head_index + 1) % size;
            return it;
        }
    };
}

pub fn Iterator(
    comptime T: type,
) type {
    return struct {
        items: []T,
        head_index: usize,
        index: usize,

        pub const Self = @This();
        pub fn next(self: *Self) ?T {
            if (self.index == self.head_index) return null;
            const value = self.items[self.index];
            self.index = (self.index + 1) % self.items.len;
            return value;
        }
    };

}
const expect = std.testing.expect;

test "EvictingFifo" {
    var fifo = EvictingFifo(u32, 4).init();
    try expect(fifo.length() == 0);

    try expect(fifo.push(1) == null);
    try expect(fifo.length() == 1);
    try expect(fifo.push(2) == null);
    try expect(fifo.length() == 2);
    try expect(fifo.push(3) == null);
    try expect(fifo.length() == 3);

    try expect(fifo.push(4) == 1);
    try expect(fifo.length() == 3);

    var iter = fifo.iterator();
    var value = iter.next();
    try expect(value.? == 2);
    value = iter.next();
    try expect(value.? == 3);
    value = iter.next();
    try expect(value.? == 4);
    value = iter.next();
    try expect(value == null);

    value= fifo.remove();
    try expect(value.? == 2);
    try expect(fifo.length() == 2);

    value= fifo.remove();
    try expect(value.? == 3);
    try expect(fifo.length() == 1);

    value= fifo.remove();
    try expect(value.? == 4);
    try expect(fifo.length() == 0);

    value= fifo.remove();
    try expect(value == null);
}
