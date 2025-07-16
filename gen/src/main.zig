const std = @import("std");
const crossword_dict = @import("crossword_dict.zig");
const sqlite = @import("sqlite");
const crossword = @import("crossword.zig");
const set = @import("ziglangSet");
const assert = std.debug.assert;
const word_dfs = @import("word_dfs.zig");
pub const WIDTH = 128;
pub const HEIGHT = 128;

pub const BLOCK_CHAR = '@'; // Character used to represent a blocked cell

pub const ValidCellsSet = set.HashSetManaged(CellPos);
pub const CluePool = std.heap.MemoryPool(ClueCrossing);

pub const Solver = struct {
    cells: []Cell, 
    valid_start_cells: ValidCellsSet, 
    clue_pool: CluePool,
    next: ?*ClueCrossing,
    pub fn init(allocator: std.mem.Allocator) !Solver {
        const solver = try allocator.alloc(Cell, WIDTH * HEIGHT);
        for (solver) |*cell| cell.reset(); 
        return .{
            .next = null, 
            .cells = solver,
            .valid_start_cells = ValidCellsSet.init(allocator),
            .clue_pool = CluePool.init(allocator),
        };
    }

    pub fn deinit(self: *Solver) void {
        self.valid_start_cells.deinit();
        self.clue_pool.deinit();
        self.cells = undefined; // Free the cells array
    }

    pub fn create_crossing(self: *Solver, pos: CellPos, dir: Direction, clue: *crossword_dict.Clue) !*ClueCrossing {
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

    pub fn free_crossing(self: *Solver, crossing: *ClueCrossing) void {
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

pub fn solver_assert(solver: *Solver, condition: bool) void {
    if (!condition) {
        print_cells(solver);
        unreachable; // This will panic if the condition is false
    }
}

pub fn print_cells(solver: *Solver) void {
    std.debug.print("----------------------------------------\n", .{});
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const cell = get_cell(solver, x, y);
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


const Direction = enum(u1) {
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
    
    pub fn reset(self: *Cell) void {
        self.ch = ' ';
        self.crossing_x = null;
        self.crossing_y = null;
    }
};

pub fn can_terminate_clue_here(
    solver: *Solver, pos: CellPos,
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

pub fn insert_clue_start_cell(
    solver: *Solver,
    x: usize,
    y: usize,
    dir: Direction,
    clue: *crossword_dict.Clue,
) !void {
    assert(x < WIDTH and y < HEIGHT);
    const ins = try solver.create_crossing(.{.x = x, .y = y}, dir, clue);
    errdefer solver.free_crossing(ins);
    if(dir == .Across) {
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            assert(x + i < WIDTH and y < HEIGHT);
            const cell = get_cell(solver, x + i, y);
            assert(cell.crossing_x == null);
            assert(if(cell.crossing_y == null) true else cell.ch == normalize_ascii(clue.word[i]));

            _ = try solver.valid_start_cells.add(.{ .x = x + i, .y = y }); // Add the cell to the valid start cells
            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_x = ins; // Set the crossing clue for each cell in the clue
        }
        if(get_cell_or_null(solver, x + clue.word.len, y)) |cell| {
            //std.debug.print("cell {any}\n", .{cell});
            solver_assert(solver,cell.crossing_x == null);
            solver_assert(solver,cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_x = ins;
            if(x + clue.word.len + 1 < WIDTH) {
                _ = try solver.valid_start_cells.add(.{ .x = x + clue.word.len + 1, .y = y }); // Add the next cell to the valid start cells
            }
            if(y < HEIGHT) {
                _ = try solver.valid_start_cells.add(.{ .x = x + clue.word.len, .y = y + 1}); // Add the next cell to the valid start cells
            }
        }
    } else {
        var i: usize = 0;
        while (i < clue.word.len) : (i += 1) {
            solver_assert(solver,x < WIDTH and y + i < HEIGHT); // Ensure we are within bounds
            const cell = get_cell(solver, x, y + i);
            solver_assert(solver, cell.crossing_y == null);
            solver_assert(solver, if(cell.crossing_x == null) true else cell.ch == normalize_ascii(clue.word[i]));

            _ = try solver.valid_start_cells.add(.{ .x = x , .y = y + i }); // Add the cell to the valid start cells
            cell.ch = normalize_ascii(clue.word[i]); // Set the character in the cell
            cell.crossing_y = ins; // Set the crossing clue for each cell in the clue
        }
        if(get_cell_or_null(solver, x, y + clue.word.len)) |cell| {
            //std.debug.print("cell {any}\n", .{cell});
            solver_assert(solver,cell.crossing_y == null);
        
            solver_assert(solver,cell.ch == ' ' or cell.ch == BLOCK_CHAR);
            cell.ch = BLOCK_CHAR; 
            cell.crossing_y = ins; 
            
            if(y + clue.word.len + 1 < HEIGHT and x < WIDTH) {
                _ = try solver.valid_start_cells.add(.{ .x = x , .y = y + clue.word.len + 1 }); // Add the next cell to the valid start cells
            }
            if(y + clue.word.len < HEIGHT and x + 1 < WIDTH) {
                _ = try solver.valid_start_cells.add(.{ .x = x + 1, .y = y + clue.word.len}); // Add the next cell to the valid start cells
            }
        }
    }
}

fn get_cell(solver: *Solver, x: usize, y: usize) *Cell {
    assert(x < WIDTH and y < HEIGHT);
    return &solver.cells[(y * WIDTH) + x];
}

fn get_cell_or_null(solver: *Solver, x: usize, y: usize) ?*Cell {
    if (x >= WIDTH or y >= HEIGHT) {
        return null; // Out of bounds
    }
    return &solver.cells[(y * WIDTH) + x];
}

fn normalize_ascii(c: u8) u8 {
    var cc = std.ascii.toLower(c);
    if(cc == '-' or cc == ' ') {
        cc = '-'; // Normalize '-' and ' ' to a single space
    }
    return cc; // Return as is if already lowercase or not a letter
}

fn can_start_clue_here(
    solver: *Solver, pos: CellPos,
    dir: Direction,
) bool {
    if (pos.x >= WIDTH or pos.y >= HEIGHT) {
        return false;
    }
    const cell = get_cell(solver, pos.x, pos.y);
    if(dir == .Down and cell.crossing_y == null) {
        if(pos.y == 0) {
            return true; // The first row can always start a vertical clue
        } else if((pos.x > 0 and pos.y > 0) and get_cell(solver, pos.x, pos.y - 1).ch == BLOCK_CHAR) {
            return true; 
        }
    } else if(dir == .Across and cell.crossing_x == null) {
        if(pos.x == 0) {
            return true; // The first row can always start a vertical clue
        } else if((pos.x > 0 and pos.y > 0) and get_cell(solver, pos.x - 1, pos.y).ch == BLOCK_CHAR) {
            return true; 
        }
    }
    return false;
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator(); 
    var dict = try crossword_dict.init(allocator);
    defer dict.deinit();


    var solver = try Solver.init(allocator);
    defer solver.deinit();
    //_ = try solver.valid_start_cells.add(.{ .x = 0, .y = 0 });
    for (0..WIDTH) |x| _ = try solver.valid_start_cells.add(.{ .x = x, .y = 0 }); 
    for (0..HEIGHT) |y| _ = try solver.valid_start_cells.add(.{ .x = 0, .y = y }); 

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./data.sqlite3" },
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
        try stdout.print("fetching clues from database...\n", .{});
        var stmt = try db.prepare("SELECT clue, answer FROM clues");
        defer stmt.deinit();
        var iter = try stmt.iterator(Row, .{});
        var inserted: usize = 0;
        var skipped: usize = 0;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        while(try iter.nextAlloc(arena.allocator(),.{})) |row| {
            if(inserted % 500 == 0) {
                try stdout.print("inserted {d} clues, skipped {d} \n", .{inserted, skipped});
            }
            inserted += 1;
            if(row.answer.len < 3) {
                continue; // Skip short answers
            }
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
    try bw.flush(); // Don't forget to flush!


    var random = std.crypto.random;
    var dfs = try word_dfs.init(allocator, &dict);
    defer dfs.deinit();

    //_ = try it.append_fixed('a');
    //_ = try it.append_wildcard(&random);
    while(solver.valid_start_cells.pop()) |pos| {
        if(can_start_clue_here(&solver, pos, .Down)) {
            dfs.reset();
            var clue: ?*crossword_dict.Clue = null;
            while(!dfs.is_exausted()) {
                if(get_cell_or_null(&solver, pos.x, pos.y + dfs.len())) |cell| {
                    if(cell.ch == ' ') {
                        if(!try dfs.append_wildcard(&random)) {
                            if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                            }
                            _ = try dfs.backtrack();
                        }
                    } else if(cell.ch == crossword.BLOCK_CHAR) {
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
                std.debug.print("Inserted clue down at ({d},{d}): {s}\n", .{pos.x, pos.y, c.word});
                try insert_clue_start_cell(&solver, pos.x, pos.y, .Down, c);
            } else {
                std.debug.print("No valid clue found down at ({d},{d})\n", .{pos.x, pos.y});
            }
        } 
        if(can_start_clue_here(&solver, pos, .Across)) {
            dfs.reset();
            var clue: ?*crossword_dict.Clue = null;
            while(!dfs.is_exausted()) {
                if(get_cell_or_null(&solver, pos.x + dfs.len(), pos.y)) |cell| {
                    if(cell.ch == ' ') {
                        if(!try dfs.append_wildcard(&random)) {
                            if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                            }
                            _ = try dfs.backtrack();
                        }
                    } else if(cell.ch == crossword.BLOCK_CHAR) {
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
                std.debug.print("Inserted clue across at ({d},{d}): {s}\n", .{pos.x, pos.y, c.word});
                try insert_clue_start_cell(&solver, pos.x, pos.y, .Across, c);
            } else {
                std.debug.print("No valid clue found down at ({d},{d})\n", .{pos.x, pos.y});
            }
        } 
    }
    print_cells(&solver);

    var file = try std.fs.cwd().createFile("crossword.map", .{ .truncate = true });
    defer file.close();
    var writer = file.writer();

    try writer.writeInt(u32, WIDTH, .little);
    try writer.writeInt(u32, HEIGHT, .little);
    if(solver.next) |first_crossing| {
        var it = first_crossing.iterator();
        while (it.next()) |crossing| {
            try writer.writeInt(u32, @intCast(crossing.x), .little);
            try writer.writeInt(u32, @intCast(crossing.y), .little);
            try writer.writeInt(u8, @intFromEnum(crossing.dir), .little);
            try writer.writeInt(u32, @intCast(crossing.clue.word.len), .little);
            try writer.writeAll(crossing.clue.word);
            try writer.writeInt(u32, @intCast(crossing.clue.clue.len), .little);
            try writer.writeAll(crossing.clue.clue);
            //try writer.print("{d},{d},{s},{s},{s}\n", .{
            //    crossing.x,
            //    crossing.y,
            //    if (crossing.dir == .Across) "across" else "down",
            //    crossing.clue.word,
            //    crossing.clue.clue
            //});
        }
    } 

    //try writer.print("{d},{d}\n", .{WIDTH, HEIGHT});
    //if(solver.next) |first_crossing| {
    //    var it = first_crossing.iterator();
    //    while (it.next()) |crossing| {
    //        try writer.print("{d},{d},{s},{s},{s}\n", .{
    //            crossing.x,
    //            crossing.y,
    //            if (crossing.dir == .Across) "across" else "down",
    //            crossing.clue.word,
    //            crossing.clue.clue
    //        });
    //    }
    //} 
}



