const std = @import("std");
const set = @import("ziglangSet");
const crossword_dict = @import("crossword_dict.zig");
const assert = std.debug.assert;


pub const Direction = enum(u1) {
    Across,
    Down,
};

pub const IncompleteCell = struct {
    x: usize, 
    y: usize,
};

pub const BLOCK_CHAR = '@'; // Character used to represent a blocked cell

pub fn normalize_ascii(c: u8) u8 {
    var cc = std.ascii.toLower(c);
    if(cc == '-' or cc == ' ') {
        cc = '-'; // Normalize '-' and ' ' to a single space
    }
    return cc; // Return as is if already lowercase or not a letter
}

pub const ClueNode = struct {
    x: usize, // x-coordinate of the cell
    y: usize, // y-coordinate of the cell
    dir: Direction, // Direction of the clue (Across or Down)
    clue: *crossword_dict.Clue, // Pointer to the clue
    
    pub fn deinit(self: *Board) void {
        self.pool.destroy(self);
    }
};

pub const Cell = struct {
    ch: u8,
    crossing_x: ?*ClueNode, // Pointer to the clue crossing node in the x-direction
    crossing_y: ?*ClueNode, // Pointer to the clue crossing node in the y-direction
};

pub const CellPos = struct {
    x: usize, // x-coordinate of the cell
    y: usize, // y-coordinate of the cell
};

pub const ValidCellsSet = set.HashSetManaged(CellPos);
pub const Board = @This();
allocator: std.mem.Allocator,
width: usize,
height: usize,
cells: []Cell,
pool: std.heap.MemoryPool(ClueNode),
valid_start_cells: ValidCellsSet, // Set of black nodes (blocked cells)
pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Board {
    const buf = try allocator.alloc(Cell, width * height);
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = .{
            .crossing_x = null, // Initialize crossing x pointer to null
            .crossing_y = null, // Initialize crossing y pointer to null
            .ch = ' ', // Initialize character to empty space (0)
        }; 
    }

    var start_cells = ValidCellsSet.init(allocator);
    _ = try start_cells.add(CellPos{ .x = 0, .y = 0 }); 
    //var xx: usize = 0;
    //while(xx < width) : (xx += 1) {
    //    start_cells.add(.{ .x = xx, .y = 0 }); // Add the first row as valid start cells
    //}
    //var yy: usize = 0;
    //while(yy < height) : (yy += 1) {
    //    start_cells.add(.{ .x = 0, .y = yy }); // Add the first column as valid start cells
    //}

    return .{
        .valid_start_cells = start_cells,
        .pool = std.heap.MemoryPool(ClueNode).init(allocator),
        .allocator = allocator,
        .width = width,
        .height = height,
        .cells = buf,
    };
}

pub fn deinit(self: *Board) void {
    self.allocator.free(self.cells);
}
    
//const WordSearchGraph = struct {
//    const SelectedIndex = struct {
//        selected_idx: usize, // Index of the selected character
//        marker_idx: usize, // Index to mark the beginning for backtracking
//    };
//    const Entry = struct {
//        node: *crossword_dict.Node,
//        selected: ?SelectedIndex,
//    };
//    collection: std.ArrayList(Entry),
//    dict: *crossword_dict.Dictionary,
//    pub fn init(allocator: std.mem.Allocator, dict: *crossword_dict.Dictionary) !WordSearchGraph {
//        var items = std.ArrayList(Entry).init(allocator);
//        errdefer items.deinit(); 
//        try items.append(.{
//            .node = &dict.root,
//            .selected = null, // No selected node at the start
//        });
//        return .{
//            .dict = dict,
//            .collection = items,
//        };
//    }
//    
//
//    pub fn is_exhausted(self: *WordSearchGraph) bool {
//        return self.collection.items.len == 0;
//    }
//
//    pub fn deinit(self: *WordSearchGraph) void {
//        self.collection.deinit();
//    }
//    
//    pub fn backtrack(self: *WordSearchGraph) void {
//        _ = self.collection.pop(); // Pop the last node
//        while(self.collection.items.len > 0) {
//            const n = self.last_node();
//            if (n.selected == null) {
//                // No selected index, just pop the last node
//                _ = self.collection.pop();
//                continue;
//            }
//            break; // We have a selected index, break the loop
//        }
//    }
//
//    pub fn advance_random(top: *Entry, rand: *std.Random) ?SelectedIndex{
//        if(top.selected) |sel| {
//            var updated = sel;
//            while(true) {
//                updated.selected_idx = (updated.selected_idx + 1) % crossword_dict.NUM_CHARACTERS; // Move to the next index
//                if(updated.marker_idx == updated.selected_idx) {
//                    return null; // We have looped back to the start, no valid nodes to advance
//                }
//                if ((top.node.slots_bits & (@as(u32, 1) << @intCast(updated.selected_idx))) != 0) {
//                    // Found a valid character, break the loop
//                    break;
//                }
//            }
//            assert(top.node.children[updated.selected_idx] != null);
//            top.selected = updated; // Update the selected node
//            return updated;
//        }
//        if (top.node.random_node_idx(rand)) |idx| {
//            top.selected = .{
//                .selected_idx = idx,
//                .marker_idx = idx, // Mark the beginning for backtracking
//            };
//            assert(top.node.children[idx] != null);
//            return top.selected.?;
//        } 
//        return null;
//    }
//
//    pub fn last_node(self: *WordSearchGraph) *Entry {
//        return &self.collection.items[self.collection.items.len - 1];
//    }
//
//    pub fn num_characters(self: *WordSearchGraph) usize {
//        assert(self.collection.items.len >= 1);
//        return self.collection.items.len - 1;
//    }
//};
//
//pub fn find_random_valid_clue(
//    self: *Board,
//    dict: *crossword_dict.Dictionary,
//    rand: *std.Random,
//    allocator: std.mem.Allocator,
//    x: usize,
//    y: usize,
//    dir: Direction,
//) !?*crossword_dict.Clue {
//    var back_track = try WordSearchGraph.init(allocator, dict);
//    defer back_track.deinit();
//    while (!back_track.is_exhausted()) {
//        var c: Cell = undefined;
//        if(dir == .Across) {
//            if (x + back_track.num_characters() >= self.width) {
//                back_track.backtrack();
//            }
//            c = self.get_cell(x + back_track.num_characters(), y);
//        } else {
//            if (y + back_track.num_characters() >= self.height) {
//                back_track.backtrack();
//            }
//            c = self.get_cell(x, y + back_track.num_characters());
//        }
//
//        const last_node = back_track.last_node();
//        if(crossword_dict.is_empty(c.ch)) {
//            if(rand.int(u8) > 32) {
//                if(last_node.node.clue_index) |clue_idx| {
//                    // We have a valid clue, return it
//                    return &dict.clues.items[clue_idx];
//                } 
//            }
//            if (WordSearchGraph.advance_random(last_node, rand)) |idx|{
//                try back_track.collection.append(.{
//                    .node = last_node.node.children[idx.selected_idx].?,
//                    .selected = null
//                });
//            } else {
//                if(last_node.node.clue_index) |clue_idx| {
//                    // We have a valid clue, return it
//                    return &dict.clues.items[clue_idx];
//                }
//                back_track.backtrack();
//            }
//        } else if(c.ch == BLOCK_CHAR) {
//            back_track.backtrack();
//        } else {
//            if(crossword_dict.ascii_to_index(c.ch))|idx| {
//                if(dir == .Across and x + back_track.num_characters() == self.width - 1) {
//                    // If we are at the end of the row, we cannot continue
//                    if(last_node.node.clue_index) |clue_idx| {
//                        return &dict.clues.items[clue_idx];
//                    } else {
//                        back_track.backtrack();
//                    }
//                    continue;
//                } else if(dir == .Down and y + back_track.num_characters() == self.height - 1) {
//                    // If we are at the end of the column, we cannot continue
//                    if(last_node.node.clue_index) |clue_idx| {
//                        return &dict.clues.items[clue_idx];
//                    } else {
//                        back_track.backtrack();
//                    }
//                    continue;
//                } 
//
//                if((last_node.node.slots_bits & (@as(u32, 1) << @intCast(idx))) != 0) {
//                    // We have a valid character, continue with the next node
//                    try back_track.collection.append(.{
//                        .node = last_node.node.children[idx].?,
//                        .selected = null,
//                    });
//                } else {
//                    back_track.backtrack();
//                }
//            } else {
//                return error.InvalidCharacter; // Invalid character in the cell
//            }
//        }
//    }
//    return null; // No valid clue found
//}

//pub fn remove_clue(self: *Board,node: *ClueNode) void {
//    const x = node.x;
//    const y = node.y;
//    if (node.dir == .Down) {
//        var i: usize = 0;
//        while(i < node.clue.word.len) : (i += 1) {
//            assert(x < self.width and y + i < self.height); // Ensure we are within bounds
//            const cell = self.get_cell(x, y + i);
//            assert(if(cell.crossing_y) |c| c == node else false);
//            cell.ch = ' '; // Clear the character in the cell
//            cell.crossing_y = null; // Clear the crossing clue for each cell in the clue
//        }
//    } else {
//        var i: usize = 0;
//        while(i < node.clue.word.len) : (i += 1) {
//            assert(x + i < self.width and y < self.height); // Ensure we are within bounds
//            const cell = self.get_cell(x + i, y);
//            assert(if(cell.crossing_x) |c| c == node else false);
//            cell.ch = ' '; // Clear the character in the cell
//            cell.crossing_x = null; // Clear the crossing clue for each cell in the clue
//        }
//    }
//    if(node.parent) |p| {
//        if (p.next == node) {
//            p.next = node.next; // Update the next pointer of the parent
//        }
//        if (p.prev == node) {
//            p.prev = node.prev; // Update the previous pointer of the parent
//        }
//    }
//    const tmp = node.prev;
//    if(tmp) |t| {
//        t.next = node.next; // Update the next pointer of the previous node
//    }
//
//}

pub const SupportDirection = struct {
    down: bool, // Indicates if the cell can be the start of a vertical clue
    across: bool, // Indicates if the cell can be the start of a horizontal clue
};
// tell if this cell can be the start of a clue
pub fn can_start_clue_here(
    self: *Board,
    pos: CellPos,
    dir: Direction,
) bool {
    if (pos.x >= self.width or pos.y >= self.height) {
        return false;
    }
    if(dir == .Down) {
        if(pos.y == 0) {
            return true; // The first row can always start a vertical clue
        } else if((pos.x > 0 and pos.y > 0) and self.get_cell(pos.x, pos.y - 1).ch == BLOCK_CHAR) {
            return true; 
        }
    } else if(dir == .Across) {
        if(pos.x == 0) {
            return true; // The first row can always start a vertical clue
        } else if((pos.x > 0 and pos.y > 0) and self.get_cell(pos.x - 1, pos.y).ch == BLOCK_CHAR) {
            return true; 
        }
    }
    return false;
}

fn clear_cell_dir(
    self: *Board,
    pos: CellPos,
    dir: Direction,
) void {
    const cell = self.get_cell(pos.x, pos.y);
    if(dir == .Down) {
        cell.crossing_y = null; 
    } else if(dir == .Across) {
        cell.crossing_x = null;
    }
    if(cell.crossing_x == null and cell.crossing_y == null) {
        self.valid_start_cells.remove(pos);
        if(cell.ch == BLOCK_CHAR) {
            const bottom: CellPos = .{ .x = pos.x, .y = pos.y + 1};
            const right: CellPos = .{ .x = pos.x + 1, .y = pos.y };
            if(can_start_clue_here(self, bottom, .Down)) |v|{
                if(v == false) {
                    self.valid_start_cells.remove(bottom);
                    remove_clue_by_cell(self, bottom, .Down);    
                }
            }
            if(can_start_clue_here(self, right, .Across)) |v| {
                if(v == false) {
                    self.valid_start_cells.remove(right);
                    remove_clue_by_cell(self, right, .Across);
                }
            }
        } 
        cell.ch = ' '; // Clear the character in the cell
        if(pos.x == 0 or pos.y == 0) {
            self.valid_start_cells.add(pos);
        }
    }
}

pub fn cell_is_start_clue(
    self: *Board,
    pos: CellPos,
    dir: Direction,
) ?*ClueNode {
    if(self.get_cell_or_null(pos.x, pos.y)) |cell| {
        if(dir == .Across) {
            if(cell.crossing_x) |cross| {
                if(cross.x == pos.x and cross.y == pos.y) {
                    return true;
                }
            }
        } else {
            if(cell.crossing_y) |cross| {
                if(cross.x == pos.x and cross.y == pos.y) {
                    return true;
                }
            }
        }
    }
}

pub fn remove_clue_by_cell(
    self: *Board,
    x: usize,
    y: usize,
    dir: Direction,
  )  void {
    if (x >= self.width or y >= self.height) {
        return null; // Out of bounds
    }
    const cell = self.get_cell(x, y);
    if(dir == .Across and cell.crossing_x) {
        const node = cell.crossing_x.?;
        var i = 0; 
        while(i < node.clue.word.len) : (i += 1) {
            assert(node.x + i < self.width and node.y < self.height); // Ensure we are within bounds
            assert(self.get_cell(node.x + i, node.y).crossing_x == node);
            clear_cell_dir(self, .{ .x = node.x + i, .y = node.y }, .Across);
        }
        if(self.get_cell_or_null(x + node.clue.word.len, y)) |c| {
            assert(c.crossing_y == node);
            clear_cell_dir(self, .{ .x = node.x + node.clue.word.len, .y = node.y }, .Across);
        }
        self.pool.destroy(node);
    } else if(dir == .Down and cell.crossing_y) {
        const node = cell.crossing_y.?;
        var i = 0; 
        while(i < node.clue.word.len) : (i += 1) {
            assert(node.x < self.width and node.y + i < self.height); // Ensure we are within bounds
            assert(self.get_cell(node.x, node.y + i).crossing_y == node);
            clear_cell_dir(self, .{ .x = node.x, .y = node.y + i }, .Down);
        }
        if(self.get_cell_or_null(x, y + node.clue.word.len)) |c| {
            assert(c.crossing_y == node);
            clear_cell_dir(self, .{ .x = node.x + node.clue.word.len, .y = node.y }, .Down);
        }
        self.pool.destroy(node);
    }
    return null; 
}

pub fn insert_clue_start_cell(
    self: *Board,
    x: usize,
    y: usize,
    dir: Direction,
    clue: *crossword_dict.Clue,
) ?*ClueNode {
    if (x >= self.width or y >= self.height) {
        return false;
    }
    if(dir == .Across) {
        const ins = try self.pool.create();
        errdefer self.pool.destroy(ins);
        ins.* = .{
            .x = x,
            .y = y,
            .dir = .Across,
            .clue = clue,
        };
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            assert(x + i < self.width and y < self.height);
            const cell = self.get_cell(x + 1, y);
            assert(cell.crossing_x == null);
            assert(if(cell.crossing_y == null) true else cell.ch == normalize_ascii(clue.word[i]));

            self.valid_start_cells.add(.{ .x = x + i, .y = y }); // Add the cell to the valid start cells
            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_x = ins; // Set the crossing clue for each cell in the clue
        }
        if(self.get_cell_or_null(x + clue.word.len, y)) |cell| {
            assert(cell.crossing_x == null);
            assert(cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_x = ins;
            if(x + clue.word.len + 1 < self.width) {
                self.valid_start_cells.add(.{ .x = x + clue.word.len + 1, .y = y }); // Add the next cell to the valid start cells
            }
            if(y < self.height) {
                self.valid_start_cells.add(.{ .x = x + clue.word.len, .y = y + 1}); // Add the next cell to the valid start cells
            }
        }
    } else {
        const ins = try self.pool.create();
        errdefer self.pool.destroy(ins);
        ins.* = .{
            .x = x,
            .y = y,
            .dir = .Down,
            .clue = clue,
        };
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            assert(x < self.width and y + i < self.height); // Ensure we are within bounds
            const cell = self.get_cell(x, y + 1);
            assert(cell.crossing_y == null);
            assert(if(cell.crossing_x == null) true else cell.ch == normalize_ascii(clue.word[i]));

            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_y = ins; // Set the crossing clue for each cell in the clue
        }
        if(self.get_cell_or_null(x, y + clue.word.len)) |cell| {
            assert(cell.crossing_y == null);
            assert(cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_y = ins; 
            
            if(y + clue.word.len + 1 < self.height and x < self.width) {
                self.valid_start_cells.add(.{ .x = x , .y = y + clue.word.len + 1 }); // Add the next cell to the valid start cells
            }
            if(y + clue.word.len < self.height and x + 1 < self.width) {
                self.valid_start_cells.add(.{ .x = x + 1, .y = y + clue.word.len}); // Add the next cell to the valid start cells
            }
        }
    }
}

pub fn get_cell_or_null(self: *Board, x: usize, y: usize) ?*Cell {
    if (x >= self.width or y >= self.height) {
        return null; // Out of bounds
    }
    return &self.cells[(y * self.width) + x];
}

pub fn get_cell(self: *Board, x: usize, y: usize) *Cell {
    return &self.cells[(y * self.width) + x];
}

//pub fn unset_clue_across(self: *Board, x: usize, y: usize) !void {
//    if (x >= self.width or y >= self.height) {
//        return error.IndexOutOfBounds;
//    }
//    const old_value = self.cells[(y * self.width) + x];
//    if(old_value.cx == 0) {
//        return error.CellAlreadyUnset; // Cannot unset a cell that is not part of a clue
//    }
//    
//    self.cells[(y * self.width) + x] = .{ .cx = 0, .cy = old_value.cy, .ch = if(old_value.cy == 0) ' ' else old_value.ch };
//}
//
//pub fn unset_clue_vertical(self: *Board, x: usize, y: usize) !void {
//    if (x >= self.width or y >= self.height) {
//        return error.IndexOutOfBounds;
//    }
//    const old_value = self.cells[(y * self.width) + x];
//    if(old_value.cy == 0) {
//        return error.CellAlreadyUnset; // Cannot unset a cell that is not part of a clue
//    }
//    self.cells[(y * self.width) + x] = .{ .cx = old_value.cx, .cy = 0, .ch = if(old_value.cx == 0) ' ' else old_value.ch };
//}

//pub fn set_check(self: *Board, x: usize, y: usize, value: Cell) !void {
//    if (x >= self.width or y >= self.height) {
//        return error.IndexOutOfBounds;
//    }
//    const old_value = self.cells[(y * self.width) + x];
//    if(value.cx == 1 and old_value.cx == 1) {
//        return error.CellAlreadySet; // Cannot set a cell that is already part of a clue
//    }
//    if(value.cy == 1 and old_value.cy == 1) {
//        return error.CellAlreadySet; // Cannot set a cell that is already part of a clue
//    }
//    self.cells[(y * self.width) + x] = value;
//}
//
//pub fn set_cell(self: *Board, x: usize, y: usize, value: Cell) void {
//    if (x >= self.width or y >= self.height) {
//        return;
//    }
//    self.cells[(y * self.width) + x] = value;
//}
