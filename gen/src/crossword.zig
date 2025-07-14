const std = @import("std");
const crossword_dict = @import("crossword_dict.zig");
const assert = std.debug.assert;
pub const Direction = enum(u1) {
    Across,
    Down,
};

pub const BLOCK_CHAR = '@'; // Character used to represent a blocked cell

pub const Cell = packed struct {
    ch: u8,
    cx: u1, // clue crossing x-coordinate
    cy: u1, // clue crossing y-coordinate
};

pub const Board = @This();
allocator: std.mem.Allocator,
width: usize,
height: usize,
cells: []Cell,
pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Board {
    const buf = try allocator.alloc(Cell, width * height);
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = .{
            .cx = 0, // Initialize clue crossing x-coordinate to 0
            .cy = 0, // Initialize clue crossing y-coordinate to 0
            .ch = ' ', // Initialize character to empty space (0)
        }; 
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
    


const NodeBackTrack = struct {
    const SelectedIndex = struct {
        selected_idx: usize, // Index of the selected character
        marker_idx: usize, // Index to mark the beginning for backtracking
    };
    const Entry = struct {
        node: *crossword_dict.Node,
        selected: ?SelectedIndex
    };

    collection: std.ArrayList(Entry),
    dict: *crossword_dict.Dictionary,
    pub fn init(allocator: std.mem.Allocator, dict: *crossword_dict.Dictionary) !NodeBackTrack {
        var items = std.ArrayList(Entry).init(allocator);
        errdefer items.deinit(); 
        try items.append(.{
            .node = &dict.root,
            .selected = null, // No selected node at the start
        });
        return .{
            .dict = dict,
            .collection = items,
        };
    }

    pub fn is_exhausted(self: *NodeBackTrack) bool {
        return self.collection.items.len == 0;
    }

    pub fn deinit(self: *NodeBackTrack) void {
        self.collection.deinit();
    }

    pub fn advance_random(top: *Entry, rand: *std.Random) ?SelectedIndex{
        if(top.selected) |sel| {
            var updated = sel;
            while(true) {
                updated.selected_idx = (updated.selected_idx + 1) % crossword_dict.NUM_CHARACTERS; // Move to the next index
                if(updated.marker_idx == updated.selected_idx) {
                    return null; // We have looped back to the start, no valid nodes to advance
                }
                if ((top.node.slots_bits & (@as(u32, 1) << @intCast(updated.selected_idx))) != 0) {
                    // Found a valid character, break the loop
                    break;
                }
            }
            assert(top.node.children[updated.selected_idx] != null);
            top.selected = updated; // Update the selected node
            return updated;
        }
        if (top.node.random_node_idx(rand)) |idx| {
            top.selected = .{
                .selected_idx = idx,
                .marker_idx = idx, // Mark the beginning for backtracking
            };
            assert(top.node.children[idx] != null);
            return top.selected.?;
        } 
        return null;
    }

    pub fn last_node(self: *NodeBackTrack) *Entry {
        return &self.collection.items[self.collection.items.len - 1];
    }

    pub fn num_characters(self: *NodeBackTrack) usize {
        assert(self.collection.items.len >= 1);
        return self.collection.items.len - 1;
    }
};

pub fn find_random_valid_clue(
    self: *Board,
    dict: *crossword_dict.Dictionary,
    rand: *std.Random,
    allocator: std.mem.Allocator,
    x: usize,
    y: usize,
    dir: Direction,
) !?*crossword_dict.Clue {
    var back_track = try NodeBackTrack.init(allocator, dict);
    defer back_track.deinit();
    while (!back_track.is_exhausted()) {
        var c: Cell = undefined; 
        if(dir == .Across) {
            if (x + back_track.num_characters() >= self.width) {
                _ = back_track.collection.pop(); 
            }
            c = self.get(x + back_track.num_characters(), y);
        } else {
            if (y + back_track.num_characters() >= self.height) {
                _ = back_track.collection.pop(); 
            }
            c = self.get(x, y + back_track.num_characters());
        }

        const last_node = back_track.last_node();
        if(crossword_dict.is_empty(c.ch)) {
            if(back_track.num_characters() > 3 and rand.int(u8) > 32) {
                if(last_node.node.clue_index) |clue_idx| {
                    // We have a valid clue, return it
                    return &dict.clues.items[clue_idx];
                } 
            }
            if (NodeBackTrack.advance_random(last_node, rand)) |idx|{
                try back_track.collection.append(.{
                    .node = last_node.node.children[idx.selected_idx].?,
                    .selected = null
                });
            } else {
                if(last_node.node.clue_index) |clue_idx| {
                    // We have a valid clue, return it
                    return &dict.clues.items[clue_idx];
                }
                _ = back_track.collection.pop(); 
            }
        } else if(c.ch == BLOCK_CHAR) {
            _ = back_track.collection.pop(); // Blocked cell, backtrack
        } else {
            if(crossword_dict.ascii_to_index(c.ch))|idx| {
                if((last_node.node.slots_bits & (@as(u32, 1) << @intCast(idx))) != 0) {
                    // We have a valid character, continue with the next node
                    try back_track.collection.append(.{
                        .node = last_node.node.children[idx].?,
                        .selected = null,
                    });
                } else {
                    _ = back_track.collection.pop(); // No valid character, backtrack
                }
            } else {
                return error.InvalidCharacter; // Invalid character in the cell
            }
        }
    }
    return null; // No valid clue found
}

pub fn get(self: *Board, x: usize, y: usize) Cell {
    return self.cells[(y * self.width) + x];
}

pub fn unset_clue_across(self: *Board, x: usize, y: usize) !void {
    if (x >= self.width or y >= self.height) {
        return error.IndexOutOfBounds;
    }
    const old_value = self.cells[(y * self.width) + x];
    if(old_value.cx == 0) {
        return error.CellAlreadyUnset; // Cannot unset a cell that is not part of a clue
    }
    
    self.cells[(y * self.width) + x] = .{ .cx = 0, .cy = old_value.cy, .ch = if(old_value.cy == 0) ' ' else old_value.ch };
}

pub fn unset_clue_vertical(self: *Board, x: usize, y: usize) !void {
    if (x >= self.width or y >= self.height) {
        return error.IndexOutOfBounds;
    }
    const old_value = self.cells[(y * self.width) + x];
    if(old_value.cy == 0) {
        return error.CellAlreadyUnset; // Cannot unset a cell that is not part of a clue
    }
    self.cells[(y * self.width) + x] = .{ .cx = old_value.cx, .cy = 0, .ch = if(old_value.cx == 0) ' ' else old_value.ch };
}

pub fn set_check(self: *Board, x: usize, y: usize, value: Cell) !void {
    if (x >= self.width or y >= self.height) {
        return error.IndexOutOfBounds;
    }
    const old_value = self.cells[(y * self.width) + x];
    if(value.cx == 1 and old_value.cx == 1) {
        return error.CellAlreadySet; // Cannot set a cell that is already part of a clue
    }
    if(value.cy == 1 and old_value.cy == 1) {
        return error.CellAlreadySet; // Cannot set a cell that is already part of a clue
    }
    self.cells[(y * self.width) + x] = value;
}

pub fn set(self: *Board, x: usize, y: usize, value: Cell) void {
    if (x >= self.width or y >= self.height) {
        return;
    }
    self.cells[(y * self.width) + x] = value;
}
