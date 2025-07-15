const std = @import("std");
const crossword_dict = @import("crossword_dict.zig");
const sqlite = @import("sqlite");
const crossword = @import("crossword.zig");
const set = @import("ziglangSet");
const assert = std.debug.assert;
const word_dfs = @import("word_dfs.zig");
// constants to generate the board
pub const WIDTH = 64;
pub const HEIGHT = 64;

pub const DecisionNodeArrayList = std.ArrayList(*DecisionNode);
pub const DecisionNode = struct {
    x: usize, 
    y: usize,
    clue: ?*crossword_dict.Clue,
    dir: crossword.Direction,
    parent: ?*DecisionNode, // Pointer to the next node in the linked list

    pub fn init(x: usize, y: usize, dir: crossword.Direction, c: ?*crossword_dict.Clue) DecisionNode {
        return .{
            .parent = null,
            .x = x,
            .y = y,
            .clue = c,
            .dir = dir,
        };
    }

    //pub fn detach(self: *DecisionNode) void {
    //    if (self.prev) |prev| {
    //        prev.next = self.next;
    //    }
    //    if (self.next) |next| {
    //        next.prev = self.prev;
    //    }
    //    self.prev = null;
    //    self.next = null;
    //}

    //pub fn append(self: *DecisionNode, pool: *std.heap.MemoryPool(DecisionNode), x: usize, y: usize, dir: crossword.Direction) !*DecisionNode{
    //    const child_ptr = try pool.create();
    //    child_ptr.* = DecisionNode.init( x, y, dir, null);

    //    const tmp = self.next;
    //    child_ptr.prev = self;
    //    self.next = child_ptr;
    //    child_ptr.next = tmp;
    //    return child_ptr;
    //}

    pub fn deinit(self: *DecisionNode) void {
        self.children.deinit();
    }
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
    while(true) {
       
        var iter = board.valid_start_cells.iterator();
        if(iter.next()) |pos| {
            const p: crossword.CellPos = pos.*;
            if(board.can_start_clue_here(p, .Down)) {
                dfs.reset();
                var clue: ?*crossword_dict.Clue = null;
                while(!dfs.is_exausted()) {
                    if(board.get_cell_or_null(p.x, p.y + dfs.len())) |cell| {
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
                            if(dfs.get_clue()) |c| {
                                clue = c;
                                break;
                            }
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
                    std.debug.print("Inserted clue down at ({d},{d}): {s}\n", .{pos.x, pos.y, c.word});
                    iter = board.valid_start_cells.iterator(); // Reset the iterator
                } else {
                    std.debug.print("No valid clue found down at ({d},{d})\n", .{pos.x, pos.y});
                }
            } 
            if(board.can_start_clue_here(p, .Across)) {
                dfs.reset();

            } 
        }
    }
  //  var node_alloc = std.heap.MemoryPool(DecisionNode).init(allocator);
  //  const root = try node_alloc.create();
  //  root.* = DecisionNode.init(0, 0, crossword.Direction.Across, null);
  // 

  //  var process_list = std.ArrayList(struct {
  //      x: usize,
  //      y: usize,
  //      dir: crossword.Direction,
  //  }).init(allocator);
  //  defer process_list.deinit();
  //  try process_list.append(root);
  //  
  //  var random = std.crypto.random;
  //  while(process_list.pop()) |it| {
  //      //if(board.get(visit.x, visit.y).ch == crossword.BLOCK_CHAR) {
  //      //    it.detach(); // Detach the current node from the list
  //      //    node_alloc.destroy(it); // Free the memory for the node
  //      //    continue; // Skip to the next iteration
  //      //}

  //      std.debug.print("processing node ({d},{d})\n", .{it.x, it.y});
  //      if(try board.find_random_valid_clue(
  //          &dict,
  //          &random,
  //          allocator,
  //          it.x,
  //          it.y,
  //          it.dir,
  //      )) |c| {
  //          var index: usize = 0;
  //          if(it.dir == crossword.Direction.Across) {
  //              std.debug.print("inserting word across ({d},{d}) {s}\n", .{it.x, it.y, c.word});
  //              while(index < c.word.len) : (index += 1) {
  //                  assert(it.x + index < board.width);
  //                  try board.set_check(it.x + index, it.y, .{ .ch = c.word[index], .cx = 1, .cy = 0 });
  //                  if(it.y == 0 or board.get(it.x + index, it.y - 1).ch == crossword.BLOCK_CHAR) {
  //                      try process_list.append(try it.append(&node_alloc, it.x + index, it.y, crossword.Direction.Down));
  //                  }
  //              }
  //              try board.set_check(it.x + c.word.len, it.y, .{ .ch = crossword.BLOCK_CHAR, .cx = 1, .cy = 0 });
  //              if(it.x + c.word.len + 1 < board.width) {
  //                  try process_list.append(.{.x = it.x + c.word.len + 1, .y = it.y, .dir = crossword.Direction.Across});
  //                  try process_list.append(.{.x = it.x + c.word.len + 1, .y = it.y, .dir = crossword.Direction.Down});
  //              }
  //              if(it.x + c.word.len < board.width and it.y + 1 < board.height) {
  //                  try process_list.append(try it.append(&node_alloc,it.x + c.word.len, it.y, crossword.Direction.Across));
  //                  try process_list.append(try it.append(&node_alloc,it.x + c.word.len, it.y, crossword.Direction.Down));
  //              }
  //          } else {
  //              std.debug.print("inserting word down ({d},{d}) {s}\n", .{it.x, it.y, c.word});
  //              while(index < c.word.len) : (index += 1) {
  //                  assert(it.y + index < board.width);
  //                  try board.set_check(it.x, it.y + index, .{ .ch = c.word[index], .cy = 1, .cx = 0 });
  //                  if(it.x == 0 or board.get(it.x - 1, it.y + index).ch == crossword.BLOCK_CHAR) {
  //                      try process_list.append(try it.append(&node_alloc, it.x, it.y + index, crossword.Direction.Across));
  //                  }
  //              }
  //              try board.set_check(it.x, it.y + c.word.len, .{ .ch = crossword.BLOCK_CHAR, .cy = 1, .cx = 0 });
  //              if(it.y + c.word.len + 1 < board.height) {
  //                  try process_list.append(try it.append(&node_alloc,it.x, it.y + c.word.len + 1, crossword.Direction.Across));
  //                  try process_list.append(try it.append(&node_alloc,it.x, it.y + c.word.len + 1, crossword.Direction.Down));
  //              }
  //              if(it.x + 1 < board.width and it.y + c.word.len < board.height) {
  //                  try process_list.append(try it.append(&node_alloc,it.x, it.y + c.word.len, crossword.Direction.Across));
  //                  try process_list.append(try it.append(&node_alloc,it.x, it.y + c.word.len, crossword.Direction.Down));
  //              }
  //          }
  //      } else {
  //          process_list.append(it); // Re-append the current node to the list
  //          std.debug.print("no valid clue found for node ({d},{d})\n", .{it.x, it.y});
  //      }
  //  }

}



