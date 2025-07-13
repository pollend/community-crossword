const std = @import("std");
const crossword_dict = @import("crossword_dict.zig");
const sqlite = @import("sqlite");
const crossword = @import("crossword.zig");
const set = @import("ziglangSet");

// constants to generate the board
pub const WIDTH = 128;
pub const HEIGHT = 128;

pub const DecisionNode = struct {
    x: usize, 
    y: usize,
    clue: *crossword.Clue,
    dir: crossword.Direction,
};

pub const PosNext = struct {
    x: usize,
    y: usize,
    dir: crossword.Direction,
};

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

    var board = try crossword.init(allocator, WIDTH, HEIGHT);
    defer board.deinit();

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
        var stmt = try db.prepare("SELECT clue, answer FROM clues LIMIT 6000");
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
    
    //const ProcessSet = set.Set(PosNext);
    //var process_set = ProcessSet.init(allocator);
    //var node_stack = std.ArrayList(crossword_dict.Node).init(allocator); 
    //_ = try process_set.add(PosNext{ .x = 0, .y = 0, .dir = crossword.Direction.Across });
    //while(true) {
    //    var iter = process_set.iterator();
    //    if(iter.next()) |ins| {
    //        const process: PosNext = ins.*;
    //        if(process.dir == .Across) {
    //            var x: usize = process.x;
    //            var current_node = &dict.root;
    //            if (board.get(x, process.y)) |c| {
    //                if(crossword_dict.is_empty(c)) {
    //                         
    //                }
    //            } else {

    //            }

    //        } else {

    //        }
    //        

    //        _ = process_set.remove(process);
    //    } else {
    //        break;
    //    }
    //}
}



