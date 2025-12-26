const std = @import("std");
const crossword_dict = @import("trie.zig");
const sqlite = @import("sqlite");
const set = @import("ziglangSet");
const assert = std.debug.assert;
const word_dfs = @import("word_dfs.zig");
pub const WIDTH = 384;
pub const HEIGHT = 384;

pub const MAGIC_NUMBER: u32 = 0x1F9F1E9f; 
pub const BLOCK_CHAR = '@'; // Character used to represent a blocked cell

pub const RemoveCell = struct {
    pos: CellPos,
    clue: *crossword_dict.Clue,
};

pub const ValidCellsSet = set.HashSetManaged(@Vector(2, i32));
pub const CluePool = std.heap.MemoryPool(ClueCrossing);

pub const Board = struct {
    cells: []Cell, 
    clue_pool: CluePool,
    next: ?*ClueCrossing,
    coverage: usize = 0, 
    pub fn init(allocator: std.mem.Allocator) !Board {
        const solver = try allocator.alloc(Cell, WIDTH * HEIGHT);
        for (solver) |*cell| cell.reset(); 
        return .{
            .next = null, 
            .cells = solver,
            .clue_pool = CluePool.init(allocator),
        };
    }

    pub fn deinit(self: *Board) void {
        self.clue_pool.deinit();
        self.cells = undefined; // Free the cells array
    }
    
    pub fn create_crossing_1(self: *Board, pos: @Vector(2, i32), dir: Direction, clue: *crossword_dict.Clue) !*ClueCrossing {
        const crossing = try self.clue_pool.create();
        errdefer self.clue_pool.destroy(crossing);
        crossing.* = .{
            .x = @intCast(pos[0]),
            .y = @intCast(pos[1]),
            .dir = dir,
            .clue = clue,
            .next = null,
            .prev = null,
        };
        crossing.next = self.next;
        if(self.next) |cross| {
            cross.prev = crossing; // Link the previous crossing to the new one
        }
        self.next = crossing;
        return crossing;
    }

    pub fn create_crossing(self: *Board, pos: CellPos, dir: Direction, clue: *crossword_dict.Clue) !*ClueCrossing {
        const crossing = try self.clue_pool.create();
        errdefer self.clue_pool.destroy(crossing);
        crossing.* = .{
            .x = pos.x,
            .y = pos.y,
            .dir = dir,
            .clue = clue,
            .next = null,
            .prev = null,
        };
        crossing.next = self.next;
        if(self.next) |cross| {
            cross.prev = crossing; // Link the previous crossing to the new one
        }
        self.next = crossing;
        return crossing;
    }

    pub fn free_crossing(self: *Board, crossing: *ClueCrossing) void {
        if (crossing.prev) |prev| {
            prev.next = crossing.next; // Link the previous crossing to the next one
        } else {
            self.next = crossing.next; // Update the head of the list
        }
        if (crossing.next) |next| {
            next.prev = crossing.prev; // Link the next crossing to the previous one
        }
        self.clue_pool.destroy(crossing);
    }
};

pub fn solver_assert(solver: *Board, condition: bool) void {
    if (!condition) {
        print_cells(solver);
        unreachable; // This will panic if the condition is false
    }
}

pub fn print_cells(solver: *Board) void {
    std.debug.print("----------------------------------------\n", .{});
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const cell = get_cell(solver, @Vector(2,i32){@intCast(x), @intCast(y)});
            if (cell.ch == ' ') {
                std.debug.print(" . ", .{});
            } else if (cell.ch == BLOCK_CHAR) {
                std.debug.print(" @ ", .{});
            } else {
                std.debug.print(" {c} ", .{cell.ch});
            }
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("----------------------------------------\n", .{});
}

const Direction = enum(u2) {
    Across,
    Down,
};

pub const ClueCrossingIterator = struct {
    current: ?*ClueCrossing,
    pub fn next(self: *ClueCrossingIterator) ?*ClueCrossing {
        if (self.current) |crossing| {
            self.current = crossing.next;
            return crossing;
        }
        return null; // No more crossings
    }
};

const ClueCrossing = struct {
    x: usize, 
    y: usize, 
    dir: Direction, 
    clue: *crossword_dict.Clue,

    next: ?*ClueCrossing,
    prev: ?*ClueCrossing,


    pub fn iterator(self: *ClueCrossing) ClueCrossingIterator {
        return .{
            .current = self,
        };
    }
};

pub const CellPos = struct {
    x: usize,
    y: usize,
};

const Cell = struct {
    ch: u8,
    crossing_x: ?*ClueCrossing, // Pointer to the clue crossing node in the x-direction
    crossing_y: ?*ClueCrossing, // Pointer to the clue crossing node in the y-direction

    attempts: usize, // Number of attempts to place a clue in this cell
    pub fn reset(self: *Cell) void {
        self.ch = ' ';
        self.attempts = 0;
        self.crossing_x = null;
        self.crossing_y = null;
    }
};

pub fn can_terminate_clue_here(
    solver: *Board, pos: CellPos,
    dir: Direction,
) bool {
    if (pos.x >= WIDTH or pos.y >= HEIGHT) {
        return false;
    }

    const cell = get_cell(solver, pos.x, pos.y);
    if(dir == .Down and cell.crossing_y != null) {
        if(get_cell_or_null(solver, pos.x, pos.y + 1)) |next_cell| {
            if(next_cell.ch == BLOCK_CHAR) {
                return true;
            } 
            if(next_cell.crossing_x == null) {
                return true;
            }
            return false;
        } else {
            return true; // The last row can always terminate a vertical clue
        }  

    } else if(dir == .Across and cell.crossing_x != null) {
        if(get_cell_or_null(solver, pos.x + 1, pos.y)) |next_cell| {
            if(next_cell.ch == BLOCK_CHAR) {
                return true;
            } 
            if(next_cell.crossing_y == null) {
                return true;
            }
            return false;
        } else {
            return true; // The last column can always terminate a horizontal clue
        }
    }
    return false;
}


fn clear_cell_dir(
    board: *Board,
    pos: CellPos,
    dir: Direction,
    valid_start_cells: *ValidCellsSet 
) error{OutOfMemory}!void {
    const cell = get_cell(board, pos.x, pos.y);
    if(dir == .Down) {
        cell.crossing_y = null; 
    } else if(dir == .Across) {
        cell.crossing_x = null;
    }
    if(cell.crossing_x == null and cell.crossing_y == null) {
        if(cell.ch == BLOCK_CHAR) {
            cell.ch = ' ';
            const bottom: CellPos = .{ .x = pos.x, .y = pos.y + 1};
            const right: CellPos = .{ .x = pos.x + 1, .y = pos.y };
            if(!can_start_clue_here(board, bottom, .Down)) {
                try remove_clue_by_cell(board, bottom, .Down, valid_start_cells);    
            }
            if(!can_start_clue_here(board, bottom, .Across)) {
                try remove_clue_by_cell(board, bottom, .Across, valid_start_cells);    
            }
            if(!can_start_clue_here(board, right, .Across))  {
                try remove_clue_by_cell(board, right, .Across, valid_start_cells);
            }
            if(!can_start_clue_here(board, right, .Down))  {
                try remove_clue_by_cell(board, right, .Down, valid_start_cells);
            }
        } 
        cell.ch = ' ';
    }

}

pub fn remove_clue_by_cell(
    board: *Board,
    pos: CellPos,
    dir: Direction,
    valid_start_cells: *ValidCellsSet 
  ) error{OutOfMemory}!void {
    if(get_cell_or_null(board,pos.x, pos.y)) |cell| {
        if(dir == .Across and cell.crossing_x != null) {
            const node = cell.crossing_x.?;
            var i: usize = 0; 
            while(i < node.clue.word.len) : (i += 1) {
                assert(node.x + i < WIDTH and node.y < HEIGHT); // Ensure we are within bounds
                assert(get_cell(board, node.x + i, node.y).crossing_x == node);
                try clear_cell_dir(board, .{ .x = node.x + i, .y = node.y }, .Across, valid_start_cells);
            }
            if(get_cell_or_null(board, node.x + node.clue.word.len, node.y)) |c| {
                assert(c.crossing_x == node);
                try clear_cell_dir(board, .{ .x = node.x + node.clue.word.len, .y = node.y }, .Across, valid_start_cells);
            }

            if(can_start_clue_here(board, .{.x = node.x, .y = node.y}, .Across) or 
                can_start_clue_here(board, .{.x = node.x, .y = node.y}, .Down))
                _ = try valid_start_cells.add(.{.x = node.x , .y = node.y });
            board.free_crossing(node);
        } else if(dir == .Down and cell.crossing_y != null) {
            const node = cell.crossing_y.?;
            var i: usize = 0; 
            while(i < node.clue.word.len) : (i += 1) {
                assert(node.x < WIDTH and node.y + i < HEIGHT); // Ensure we are within bounds
                assert(get_cell(board, node.x, node.y + i).crossing_y == node);
                try clear_cell_dir(board, .{ .x = node.x, .y = node.y + i }, .Down, valid_start_cells);
            }
            if(get_cell_or_null(board, node.x, node.y + node.clue.word.len)) |c| {
                assert(c.crossing_y == node);
                try clear_cell_dir(board, .{ .x = node.x, .y = node.y + node.clue.word.len }, .Down, valid_start_cells);
            }
            if(can_start_clue_here(board, .{.x = node.x, .y = node.y}, .Across) or 
                can_start_clue_here(board, .{.x = node.x, .y = node.y}, .Down))
                _ = try valid_start_cells.add(.{.x = node.x , .y = node.y });
            board.free_crossing(node);
        }
    }
}

fn remove_cell_dir(
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

pub fn is_black_cell_required(
    board: *Board,
    pos: @Vector(2, i32),
) bool {
    if(is_valid_pos(pos - @Vector(2, i32){-1, 0})) {
        return get_cell(board, pos - @Vector(2, i32){-1, 0}).crossing_x != null; 
    }
    if(is_valid_pos(pos - @Vector(2, i32){1, 0})) {
        return get_cell(board, pos - @Vector(2, i32){1, 0}).crossing_x != null; 
    }
    if(is_valid_pos(pos - @Vector(2, i32){0, -1})) {
        return get_cell(board, pos - @Vector(2, i32){0, -1}).crossing_y != null; 
    }
    if(is_valid_pos(pos - @Vector(2, i32){0, 1})) {
        return get_cell(board, pos - @Vector(2, i32){0, 1}).crossing_y != null; 
    }
    return false;
}

pub fn update_valid_start_cells(
    board: *Board,
    pos: @Vector(2, i32),
    dir: Direction,
    valid_start_cells: *ValidCellsSet,
) !void {
    if(dir == .Across) {
        var px: @Vector(2, i32) = pos;
        while(px[0] > 0) : (px[0] -= 1) {
            const ch = get_cell(board, px);
            if(ch.ch == BLOCK_CHAR or ch.ch == ' ' or px[0] == 0) {
                if(is_valid_pos(px + @Vector(2,i32){1,0}) and get_cell(board, px + @Vector(2,i32){1,0}).crossing_x == null) {
                    assert(is_valid_pos(px + @Vector(2,i32){1,0}));
                    _ = try valid_start_cells.add(px + @Vector(2,i32){1,0});
                }
                break; // Stop if we hit a blocked cell
            }
            _ = valid_start_cells.remove(px);
        }
        px = pos;
        while(px[0] < WIDTH - 1) : (px[0] += 1) {
            const ch = get_cell(board, px);
            if(ch.ch == BLOCK_CHAR or ch.ch == ' ') {
                break; // Stop if we hit a blocked cell
            }
            _ = valid_start_cells.remove(px);
        }
    } else {
        var py: @Vector(2, i32) = pos;
        while(py[1] > 0) : (py[1] -= 1) {
            const ch = get_cell(board, py);
            if(ch.ch == BLOCK_CHAR or ch.ch == ' ' or py[1] == 0) {
                if(is_valid_pos(py + @Vector(2,i32){0,1}) and get_cell(board, py + @Vector(2,i32){0,1}).crossing_y == null) {
                    assert(is_valid_pos(py + @Vector(2,i32){0,1}));
                    _ = try valid_start_cells.add(py + @Vector(2,i32){0,1});
                }
                break; // Stop if we hit a blocked cell
            }
            _ = valid_start_cells.remove(py);
        }
        py = pos;
        while(py[1] < HEIGHT - 1) : (py[1] += 1) {
            const ch = get_cell(board, py);
            if(ch.ch == BLOCK_CHAR or ch.ch == ' ') {
                break; // Stop if we hit a blocked cell
            }
            _ = valid_start_cells.remove(py);
        }
    }

}

pub fn insert_clue_start_cell_2(
    board: *Board,
    pos: @Vector(2, i32),
    dir: Direction,
    clue: *crossword_dict.Clue,
    valid_start_cells: *ValidCellsSet,
) !void {
    const ins = try board.create_crossing_1(pos, dir, clue);
    errdefer board.free_crossing(ins);
    const iter: @Vector(2, i32) = if(dir == .Across) @Vector(2, i32){1, 0} else @Vector(2, i32){0, 1};
    if(is_valid_pos(pos - iter)) {
        var back_cell = get_cell(board, pos - iter);
        _ = valid_start_cells.remove(pos - iter); 
        if(back_cell.ch == ' ' or back_cell.ch == BLOCK_CHAR) {
            back_cell.ch = BLOCK_CHAR; // Set the left cell to a blocked cell
        } else {
            return;
        }
    }
    var i: usize = 0;
    var p: @Vector(2, i32) = pos;
    while(i < clue.word.len) : ({p += iter; i += 1;}) {
        solver_assert(board,is_valid_pos(p));
        const cell = get_cell(board, p);
        if(dir == .Across) {
            solver_assert(board, cell.crossing_x == null);
            solver_assert(board, if(cell.crossing_y == null) true else cell.ch == normalize_ascii(clue.word[i]));
            cell.crossing_x = ins; 
            cell.ch = normalize_ascii(clue.word[i]);
            try update_valid_start_cells(board, p,  .Down , valid_start_cells); 
        } else {
            solver_assert(board, cell.crossing_y == null);
            solver_assert(board, if(cell.crossing_x == null) true else cell.ch == normalize_ascii(clue.word[i]));
            cell.crossing_y = ins; 
            cell.ch = normalize_ascii(clue.word[i]);
            try update_valid_start_cells(board, p,  .Across, valid_start_cells); 
        }
    }
    const cap_pos = pos + (iter * @Vector(2, i32){@intCast(clue.word.len), @intCast(clue.word.len) });
    if(is_valid_pos(cap_pos)) {
        const cell = get_cell(board, cap_pos);
        //solver_assert(board,cell.crossing_x == null);
        solver_assert(board, cell.ch == ' ' or cell.ch == BLOCK_CHAR);
        cell.ch = BLOCK_CHAR;
        _ = valid_start_cells.remove(cap_pos); 
        const right_pos = cap_pos + @Vector(2, i32){1, 0};
        const down_pos = cap_pos + @Vector(2, i32){0, 1};
        if(is_valid_pos(right_pos) and get_cell(board, right_pos).ch == ' ') {
            _ = try valid_start_cells.add(right_pos); // Add the next cell to the valid start cells
        }
        if(is_valid_pos(down_pos) and get_cell(board, down_pos).ch == ' ') {
            _ = try valid_start_cells.add(down_pos); // Add the next cell to the valid start cells
        }
    }
}


pub fn insert_clue_start_cell(
    board: *Board,
    x: usize,
    y: usize,
    dir: Direction,
    clue: *crossword_dict.Clue,
    valid_start_cells: *ValidCellsSet,
) !void {
    assert(x < WIDTH and y < HEIGHT);
    const ins = try board.create_crossing(.{.x = x, .y = y}, dir, clue);
    errdefer board.free_crossing(ins);
    if(dir == .Across) {
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            solver_assert(board, x + i < WIDTH and y < HEIGHT);
            const cell = get_cell(board, x + i, y);
            solver_assert(board,cell.crossing_x == null);
            solver_assert(board,if(cell.crossing_y == null) true else cell.ch == normalize_ascii(clue.word[i]));
            if(can_start_clue_here(board, .{ .x = x + i, .y = y }, .Down)) 
                _ = try valid_start_cells.add(.{ .x = x + i, .y = y });
            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_x = ins; // Set the crossing clue for each cell in the clue
        }
        if(get_cell_or_null(board, x + clue.word.len, y)) |cell| {
            solver_assert(board,cell.crossing_x == null);
            solver_assert(board,cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_x = ins;
            if(can_start_clue_here(board, .{ .x = x + clue.word.len + 1, .y = y }, .Down) or 
               can_start_clue_here(board, .{ .x = x + clue.word.len + 1, .y = y }, .Across)) 
                _ = try valid_start_cells.add(.{ .x = x + clue.word.len + 1, .y = y }); // Add the next cell to the valid start cells
            if(can_start_clue_here(board, .{ .x = x + clue.word.len, .y = y + 1}, .Down) or 
               can_start_clue_here(board, .{ .x = x + clue.word.len, .y = y + 1}, .Across)) 
                _ = try valid_start_cells.add(.{ .x = x + clue.word.len, .y = y + 1}); // Add the next cell to the valid start cells
        }
    } else {
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            solver_assert(board,x < WIDTH and y + i < HEIGHT); // Ensure we are within bounds
            const cell = get_cell(board, x, y + i);
            solver_assert(board, cell.crossing_y == null);
            solver_assert(board, if(cell.crossing_x == null) true else cell.ch == normalize_ascii(clue.word[i]));
            if(can_start_clue_here(board, .{ .x = x, .y = y + i }, .Across))
                _ = try valid_start_cells.add(.{  .x = x, .y = y + i }); // Add the next cell to the valid start cells

            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_y = ins; // Set the crossing clue for each cell in the clue
        }
        if(get_cell_or_null(board, x, y + clue.word.len)) |cell| {
            solver_assert(board,cell.crossing_y == null);
            solver_assert(board,cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_y = ins; 
            
            if(can_start_clue_here(board, .{ .x = x , .y = y + clue.word.len + 1}, .Down) or 
               can_start_clue_here(board, .{ .x = x , .y = y + clue.word.len + 1}, .Across)) 
                _ = try valid_start_cells.add(.{ .x = x , .y = y + clue.word.len + 1 }); // Add the next cell to the valid start cells
            
            if(can_start_clue_here(board, .{ .x = x + 1, .y = y + clue.word.len}, .Down) or 
               can_start_clue_here(board, .{ .x = x + 1, .y = y + clue.word.len}, .Across)) 
                _ = try valid_start_cells.add(.{ .x = x + 1, .y = y + clue.word.len}); // Add the next cell to the valid start cells
        }
    }
}

//fn get_cell(solver: *Board, x: usize, y: usize) *Cell {
//    assert(x < WIDTH and y < HEIGHT);
//    return &solver.cells[(y * WIDTH) + x];
//}

fn is_valid_pos(pos: @Vector(2, i32)) bool {
    return pos[0] >= 0 and pos[0] < WIDTH and 
           pos[1] >= 0 and pos[1] < HEIGHT;
}

fn get_cell(board: *Board, p: @Vector(2, i32)) *Cell {
    assert(p[0] >= 0 and p[0] < WIDTH and p[1] >= 0 and p[1] < HEIGHT);
    return &board.cells[(@as(usize,@intCast(p[1])) * WIDTH) + @as(usize,@intCast(p[0]))];
}

fn get_cell_or_null(board: *Board, pos: @Vector(2, i32)) ?*Cell {
    if(is_valid_pos(pos)) {
        return get_cell(board, pos);
    }
    return null;
}

//fn get_cell_or_null(solver: *Board, x: usize, y: usize) ?*Cell {
//    if (x >= WIDTH or y >= HEIGHT) {
//        return null; // Out of bounds
//    }
//    return &solver.cells[(y * WIDTH) + x];
//}

fn normalize_ascii(c: u8) u8 {
    var cc = std.ascii.toLower(c);
    if(cc == '-' or cc == ' ') {
        cc = '-'; // Normalize '-' and ' ' to a single space
    }
    return cc; // Return as is if already lowercase or not a letter
}

fn number_cell_accross(board: *Board, pos: CellPos, dir: Direction) usize {
    var index: usize= 0;
    if(dir == .Down) {
        while(pos.y + index < HEIGHT) {
            const cell = get_cell(board, pos.x, pos.y + index);
            if(cell.ch == BLOCK_CHAR) {
                if(index == 0) 
                    return 0; 
                index -= 1;
                return index;
            }
            index += 1;
        }
    } else if(dir == .Across) {
        while(pos.x + index < WIDTH) {
            const cell = get_cell(board, pos.x + index, pos.y);
            if(cell.ch == BLOCK_CHAR) {
                if(index == 0) 
                    return 0; 
                index-= 1;
                return index;
            }
            index += 1;
        }
    }
    return index;
}

fn can_start_clue_here(
    board: *Board, pos: @Vector(2, i32),
    dir: Direction,
) bool {
    if (pos[0] >= WIDTH or pos[1] >= HEIGHT) {
        return false;
    }

    const cell = get_cell(board, pos);
    if(dir == .Down and cell.crossing_y == null) {
        if(pos[1] == 0) {
            return true;
        } else if((pos[0] > 0 and pos[1] > 0) and get_cell(board, pos  - @Vector(2,i32){0,1}).ch == BLOCK_CHAR) {
            return true; 
        }
    } else if(dir == .Across and cell.crossing_x == null) {
        if(pos[0] == 0) {
            return true;
        } else if((pos[0] > 0 and pos[1] > 0) and get_cell(board, pos - @Vector(2,i32){1,0}).ch == BLOCK_CHAR) {
            return true; 
        }
    }
    return false;
}


pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    //const stdout_file = std.io.getStdOut().writer();
    //var bw = std.io.bufferedWriter(stdout_file);
    //const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator(); 
    var dict = try crossword_dict.init(allocator);
    defer dict.deinit();

    var board = try Board.init(allocator);
    defer board.deinit();


    //{
    //    const input = try std.fs.cwd().openFile("train.csv", .{});
    //    defer input.close();
    //    const buffer = try allocator.alloc(u8, 1024);
    //    defer allocator.free(buffer);
    //    var csv_tokenizer = try csv.CsvTokenizer(std.fs.File.Reader).init(input.reader(), buffer, .{});
    //    
    //    var row_index: usize = 0;
    //    var column_index: usize = 0;
    //    var clue_text: std.ArrayList(u8) = std.ArrayList(u8).init(allocator);
    //    var answer_text: std.ArrayList(u8) = std.ArrayList(u8).init(allocator);
    //    defer clue_text.deinit();
    //    defer answer_text.deinit();

    //    while (true)  {
    //        const tk = csv_tokenizer.next() catch |err| {
    //            std.debug.print("failed on row {any} [{s} -- {s}] \n", .{ row_index, clue_text.items, answer_text.items });
    //            return err; 
    //        };
    //        if(tk) |token| {
    //            switch (token) {
    //                .field => |val| {
    //                    switch(column_index) {
    //                        1 =>  {
    //                            clue_text.clearRetainingCapacity();
    //                            try clue_text.appendSlice(val);
    //                        },
    //                        2 =>  {
    //                            answer_text.clearRetainingCapacity();
    //                            try answer_text.appendSlice(val);
    //                        },
    //                        else => {
    //                        }
    //                    }
    //                    column_index += 1;
    //                },
    //                .row_end => {
    //                    if(row_index >= 1) {
    //                        dict.insert(.{
    //                            .word = answer_text.items,
    //                            .clue = clue_text.items,
    //                        }) catch |err|{
    //                            if(err == error.InvalidCharacter) {
    //                                continue;
    //                            }
    //                            return err;
    //                        };
    //                    }
    //                    row_index += 1;
    //                    column_index = 0;
    //                },
    //            }
    //        } else {
    //            break;
    //        }
    //    } 
    //}
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./crossword.db" },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();
    {
        const Row = struct {
            clue: []const u8,
            answer: []const u8,
        };
        std.debug.print("fetching clues from database...\n", .{});
        var stmt = try db.prepare("SELECT clue, answer FROM crossword WHERE LENGTH(answer) >= 3 AND LENGTH(answer) >= 3 AND NOT (UPPER(answer) LIKE UPPER('%Across%') OR UPPER(answer) LIKE UPPER('%down%'));");
        defer stmt.deinit();
        var iter = try stmt.iterator(Row, .{});
        var inserted: usize = 0;
        var skipped: usize = 0;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        while(try iter.nextAlloc(arena.allocator(),.{})) |row| {
            if(inserted % 500 == 0) {
                std.debug.print("inserted {d} clues, skipped {d} \n", .{inserted, skipped});
            }
            inserted += 1;
            dict.insert(.{
                .word = row.answer,
                .clue = row.clue,
            }) catch |err|{
                if(err == error.InvalidCharacter) {
                    skipped += 1;
                    continue;
                }
                return err;
            };
            _ = arena.reset(.retain_capacity);
        }
    }

    var random = std.crypto.random;
    var dfs = try word_dfs.init(allocator, &dict);
    defer dfs.deinit();

    var valid_start_cells = ValidCellsSet.init(allocator);
    defer valid_start_cells.deinit();

    try update_valid_start_cells(&board, .{ 0, 0 }, .Down, &valid_start_cells); 

    for (0..WIDTH) |x| {
        assert(x < WIDTH);
        _ = try valid_start_cells.add(.{ @intCast(x),  0 });
    } 
    for (0..HEIGHT) |y| {
        assert(y < HEIGHT);
        _ = try valid_start_cells.add(.{ 0, @intCast( y) });  
    } 

    while(valid_start_cells.pop()) |pos| {
       // var remove_pos: CellPos = .{ .x = pos.x, .y = pos.y};  
        if(can_start_clue_here(&board, pos, .Down)) {
            dfs.reset();
            var clue: ?*crossword_dict.Clue = null;
            while(!dfs.is_exausted()) {
                if(get_cell_or_null(&board, pos + @Vector(2, i32){0, @intCast(dfs.len())})) |cell| {
                    if(cell.ch == ' ') {
                        if(!try dfs.append_wildcard(&random)) {
                            if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                            }
                            _ = try dfs.backtrack();
                        }
                    } else if(cell.ch == BLOCK_CHAR) {
                        if(dfs.get_clue()) |c| {
                            clue = c;
                            break;
                        }
                        _ = try dfs.backtrack();
                    } else if(!try dfs.append_fixed(cell.ch)) {
                        _ = try dfs.backtrack();
                    }
                } else {
                    // If the cell we want to append is out of bounds, we can still try to get a clue 
                    if(dfs.get_clue()) |c| {
                        clue = c;
                        break;
                    }
                    _ = try dfs.backtrack();
                }
            }
            if(clue) |c| {
                std.debug.print("Inserted clue down at ({d},{d}): {s}\n", .{pos[0], pos[1], c.word});
                try insert_clue_start_cell_2(&board, pos, .Down, c, &valid_start_cells);
            } else {
                //std.debug.print("No valid clue found down at ({d},{d})\n", .{pos[0], pos[1]});
                //if(remove_pos.y >= HEIGHT) {
                //    std.debug.print("Reached the end of the board skipping.\n", .{});
                //    break; // Stop if we reach the end of the board
                //}
                //assert(remove_pos.y < HEIGHT);
                //get_cell(&board,pos.x,pos.y).attempts += 1;
                //try remove_clue_by_cell(&board, .{.x = remove_pos.x, .y = remove_pos.y + random.intRangeAtMost(usize, 0, remove_pos.y + dfs.len())}, .Across, &valid_start_cells);
            }
        } 
        if(can_start_clue_here(&board, pos, .Across)) {
            dfs.reset();
            var clue: ?*crossword_dict.Clue = null;
            while(!dfs.is_exausted()) {
                if(get_cell_or_null(&board, pos + @Vector(2, i32){@intCast(dfs.len()), 0})) |cell| {
                    if(cell.ch == ' ') {
                        if(!try dfs.append_wildcard(&random)) {
                            if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                            }
                            _ = try dfs.backtrack();
                        }
                    } else if(cell.ch == BLOCK_CHAR) {
                        if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                        }
                        _ = try dfs.backtrack();
                    } else if(!try dfs.append_fixed(cell.ch)) {
                        _ = try dfs.backtrack();
                    }
                } else {
                    if(dfs.get_clue()) |c| {
                        clue = c;
                        break;
                    }
                    _ = try dfs.backtrack();
                }
            }
            if(clue) |c| {
                std.debug.print("Inserted clue across at ({d},{d}): {s}\n", .{pos[0], pos[1], c.word});
                try insert_clue_start_cell_2( &board, pos, .Across, c, &valid_start_cells);
            } else {
                //std.debug.print("No valid clue found across at ({d},{d})\n", .{pos[0], pos[1]});
                //if(remove_pos.x >= WIDTH) {
                //    //std.debug.print("Reached the end of the board skipping.\n", .{});
                //    break; // Stop if we reach the end of the board
                //}
                //get_cell(&board,pos.x,pos.y).attempts += 1;
                //assert(remove_pos.x < WIDTH);
                //try remove_clue_by_cell(&board,  .{.x = remove_pos.x + random.intRangeAtMost(usize, 0, remove_pos.y + dfs.len()), .y = remove_pos.y}, .Down, &valid_start_cells);
            }
        } 
    }
    print_cells(&board);

    var file = try std.fs.cwd().createFile("crossword.map", .{ .truncate = true });
    defer file.close();
    var writer = file.writer();
    try writer.writeInt(u32, MAGIC_NUMBER, .little);
    try writer.writeByte(0);
    try writer.writeInt(u32, random.int(u32), .little);
    try writer.writeInt(u32, WIDTH, .little);
    try writer.writeInt(u32, HEIGHT, .little);
    if(board.next) |first_crossing| {
        var it = first_crossing.iterator();
        while (it.next()) |crossing| {
            try writer.writeInt(u32, @intCast(crossing.x), .little);
            try writer.writeInt(u32, @intCast(crossing.y), .little);
            try writer.writeInt(u8, @intFromEnum(crossing.dir), .little);
            try writer.writeInt(u32, @intCast(crossing.clue.word.len), .little);
            try writer.writeAll(crossing.clue.word);
            try writer.writeInt(u32, @intCast(crossing.clue.clue.len), .little);
            try writer.writeAll(crossing.clue.clue);
        }
    } 
}



