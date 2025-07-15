const std = @import("std");
const crossword_dict = @import("crossword_dict.zig");
const crossword = @import("crossword.zig");
const assert = std.debug.assert;
    
const Tag = enum{
   wildcard,
   fixed
};

pub const Item = union(Tag) {
    wildcard: struct {
        index: usize,
        start_index: usize,
        node: *crossword_dict.Node,
    },
    fixed: struct {
        index: usize,
        node: *crossword_dict.Node,
    },
};

fn init_fixed(
    node: *crossword_dict.Node,
    index: usize,
) ?Item {
    assert(index < crossword_dict.NUM_CHARACTERS);
    if(node.children[index]) |_| {
        return .{
            .fixed = .{
                .index = index,
                .node = node,
            },
        };
    }
    return null; 
}

fn init_wildcard(
    node: *crossword_dict.Node,
    random: *std.Random,
) ?Item {
    var index = random.int(usize) % crossword_dict.NUM_CHARACTERS;
    assert(index < crossword_dict.NUM_CHARACTERS);
    var i: usize = 0;
    while(i < crossword_dict.NUM_CHARACTERS) : (i += 1) {
        if (node.children[index]) |_|{
            return .{ 
                .wildcard = .{
                    .index = index,
                    .start_index = index,
                    .node = node,
                }
            };
        }
        index = (index + 1) % crossword_dict.NUM_CHARACTERS;
    }
    return null;
}

dict: *crossword_dict.Dictionary = undefined,
start: bool,
allocator: std.mem.Allocator = undefined,
collection: std.ArrayList(Item),
pub const WordDFS = @This();

pub fn init(
    allocator: std.mem.Allocator,
    dict: *crossword_dict.Dictionary,
) !WordDFS {
    return .{
        .collection = std.ArrayList(Item).init(allocator),
        .start = true,
        .dict = dict,
        .allocator = allocator,
    };
}

pub fn reset(
    self: *WordDFS,
) void {
    self.collection.clearRetainingCapacity();
    self.start = true;
}

pub fn deinit(
    self: *WordDFS,
) void {
    self.collection.deinit();
}

pub fn is_exausted(
    self: *WordDFS,
) bool {
    return self.collection.items.len == 0 and !self.start;
}

pub fn get_clue(
    self: *WordDFS,
) ?*crossword_dict.Clue {
    if(self.collection.getLastOrNull()) |last| {
        var cidx: ?usize = null; // Initialize clue index as null
        switch(last) {
            .wildcard => |w| {
                cidx= w.node.children[w.index].?.clue_index orelse return null; // Return clue index if it exists
            },
            .fixed => |f| {
                cidx = f.node.children[f.index].?.clue_index orelse return null; // Return clue index if it exists
            },
        }
        if(cidx) |clue_index| {
            return &self.dict.clues.items[clue_index];
        }
    }
    return null; // No valid clue found
}

pub fn len(
    self: *WordDFS,
) usize {
    return self.collection.items.len;
}

pub fn backtrack(
    self: *WordDFS,
) !bool {
    self.start = false; 
    while(self.collection.pop()) |item| {
        switch(item) {
            .wildcard => |w| {
                var i: usize = 0;
                while(i < crossword_dict.NUM_CHARACTERS) : (i = (i + 1) % crossword_dict.NUM_CHARACTERS) {
                    if (w.node.children[w.index]) |node| {
                        try self.collection.append(.{
                            .wildcard = .{
                                .index = i,
                                .start_index = w.start_index,
                                .node = node,
                            },
                        });
                        return true; // Successfully backtracked
                    }
                    if(i + 1 == w.start_index) {
                        break; // We have looped through all characters
                    }
                }
                
            },
            .fixed => |_| {
                _ = self.collection.pop(); 
            },
        }
    }
    return false;
}


pub fn append_wildcard(
    self: *WordDFS,
    random: *std.Random,
) !bool {
    self.start = false; 
    if(self.collection.getLastOrNull()) |last| {
        switch(last) {
            .wildcard => |w| {
                try self.collection.append(init_wildcard(w.node.children[w.index].?, random) orelse return false);
                return true; // Successfully appended a wildcard item
            },
            .fixed => |f| {
                try self.collection.append(init_wildcard(f.node.children[f.index].?, random) orelse return false);
                return false; // No valid character for this node
            },
        }
    } else {
        try self.collection.append(init_wildcard(&self.dict.root, random) orelse return false);
        return true; // Successfully appended a wildcard item
    }
}


pub fn append_fixed(
    self: *WordDFS,
    value: u8
) !bool {
    self.start = false; 
    if(crossword_dict.ascii_to_index(value)) |idx| {
        if(self.collection.getLastOrNull()) |last| {
            switch(last) {
                .wildcard => |w| {
                    try self.collection.append(init_fixed(w.node.children[w.index].?, idx) orelse return false);
                    return true; // Successfully appended a fixed item
                },
                .fixed => |f| {
                    try self.collection.append(init_fixed(f.node.children[f.index].?, idx) orelse return false);
                    return true; // Successfully appended a fixed item
                },
            }
        } else {
            try self.collection.append(init_fixed(&self.dict.root, idx) orelse return false);
            return true; // Successfully appended a fixed item
        }
    }
    return error.InvalidCharacter; // No valid character for this node
}

