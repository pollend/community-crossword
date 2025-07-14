const std = @import("std");
const crossword = @import("crossword.zig");
const assert = std.debug.assert;
// a = 0, b = 1, c = 2, d = 3, e = 4, f = 5, g = 6, h = 7, i = 8, j = 9, k = 10, l = 11, m = 12, n = 13, o = 14, 
// p = 15, q = 16, r = 17, s = 18, t = 19, u = 20, v = 21 , w = 22, x = 23, y = 24, z = 25
// space_dash = 26
pub const NUM_CHARACTERS = 27; // 26 letters + space/dash

pub fn is_valid_character(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c == ' ' or c == '-');
}

pub fn is_valid_alpahabetic_character(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

pub fn is_empty(c: u8) bool {
    return c == ' ' or c == '-';
}

pub fn ascii_to_index(c: u8) ?usize{
    if (c >= 'a' and c <= 'z') {
        return (c - 'a');
    } 
    if (c >= 'A' and c <= 'Z') {
        return (c - 'A');
    }
    if(c == ' ' or c == '-') {
        return 26; // Assuming 27 is the index for space or dash
    }
    std.debug.print("Invalid character: {c}\n", .{c});
    return null; // Invalid character
}

pub const Clue = struct {
    word: []const u8,
    clue: []const u8,
};

pub const Node = struct {
    children: [NUM_CHARACTERS]?*Node, // 26 letters in the alphabet
    index: ?usize,
    slots_bits: u32, // Bitmask to track which slots are occupied (for optimization)
    clue_index: ?usize, // index in the clues array, if this node is the end of a word
    //
    pub fn to_ascii_char(self: *const Node) ?u8 {
        if ( self.index) |idx| {
            if(idx >= 0 and idx <= 25) {
                return @as(u8, 'a' + idx); // Convert index to ASCII character
            } else if (idx == 26) {
                return ' '; // Space or dash
            }
        }
        return null; // No valid character for this node
    }

    pub fn has_ascii_char(self: *const Node, c: u8) bool {
        const index = ascii_to_index(c); // Convert character to index
        if (index) |idx| {
            return (self.slots_bits & (@as(u32, 1) << @intCast(idx))) != 0; // Check if the bit for this slot is set
        }
        return false; // Invalid character
    }

    pub fn random_node_idx (self: *const Node, rng: *std.Random) ?usize{
        if(self.slots_bits == 0) return null; // No valid slots available
        var collect: [NUM_CHARACTERS]usize = undefined; // Collect valid children nodes
        var i: usize = 0;
        {
            var idx: usize = 0;
            while (idx < NUM_CHARACTERS) : (idx += 1) {
                if ((self.slots_bits & (@as(u32, 1) << @intCast(idx))) != 0) {
                    collect[i] = idx;
                    i += 1; // Increment the index for the next valid child
                } 
            }
        }
        return collect[rng.int(usize) % i]; // Randomly select an index from the collected nodes
    }
};

pub const CluesArrayList = std.ArrayList(Clue);
root: Node,
clues: CluesArrayList, 
allocator: std.mem.Allocator,

pub const Dictionary = @This();
pub fn init(allocator: std.mem.Allocator) !Dictionary{
    return .{
        .root = .{
            .children = [_]?*Node{null} ** NUM_CHARACTERS,
            .slots_bits = 0, // Initialize slots_bits to 0
            .clue_index = null,
            .index = null, // No index for the root node
        },
        .clues = CluesArrayList.init(allocator),  
        .allocator = allocator,
    };
}

fn free_node(node: *Node, allocator: std.mem.Allocator) void {
    for (node.children) |child| {
        if (child) |c| {
            free_node(c, allocator);
            allocator.destroy(c);
        }
    }
}

pub fn deinit(self: *Dictionary) void {
    free_node(&self.root, self.allocator);
}

pub fn insert(self: *Dictionary, clue: Clue) !void {
    for (clue.word) |c| {
        if (!is_valid_character(c)) {
            return error.InvalidCharacter;
        }
    }

    var current: *Node = &self.root;
    const res: Clue = .{
        .word = try self.allocator.dupe(u8, clue.word),
        .clue = try self.allocator.dupe(u8, clue.clue),
    };
    try self.clues.append(res);
    errdefer {
        self.allocator.free(res.word);
        self.allocator.free(res.clue);
    }

    for (clue.word) |c| {
        if(ascii_to_index(c)) | index| {
            assert(index < NUM_CHARACTERS);
            if (current.children[index]) |n| {
                current = n;
            } else {
                const node = try self.allocator.create(Node);
                node.* = .{
                    .children = [_]?*Node{null} ** NUM_CHARACTERS,
                    .clue_index = null, // No clue index for this node
                    .slots_bits = 0, // Initialize slots_bits to 0
                    .index = index, // No index for this node
                };
                current.slots_bits |= @as(u32,1) << @intCast(index); // Set the bit for this slot
                current.children[index] = node;
                current = node;
            }
        } else unreachable; // Invalid character, should not happen due to earlier validation
    }
    current.clue_index = self.clues.items.len - 1; // Set the clue index to the last added clue
}

