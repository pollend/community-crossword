const std = @import("std");
const assert = std.debug.assert;

pub const GRID_SIZE: u32 = 32;
pub const GRID_LEN: u32 = GRID_SIZE * GRID_SIZE;
pub const CallValue = enum(u7) {
    empty, // empty cell
    dash, // space/dash 
    black, // black cell
    a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z
};

pub const GridRect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn is_empty(self: *GridRect) bool {
        return self.width == 0 or self.height == 0;
    }
};

pub const Clue = struct {
    clue: []u8,
    answer: []u8
};

pub const Cell = packed struct {
    value: CallValue,
    lock: u1,
    pub fn encode(self: *Cell) u8 {
        var value: u8= @intFromEnum(self.value);
        if (self.lock ==  1)  {
            value |= 1 << 5; // set the lock bit at position 5
        }
        return value;
    }
}; 

pub const Block = struct {
    x: u32, 
    y: u32,
    input: [GRID_LEN]Cell,
    lock: std.Thread.RwLock
};

//pub const BlockList = std.ArrayList(*BoardBlk);
allocator: std.mem.Allocator,
width: u32,
height: u32,
blocks: []Block,

pub const Board = @This();
pub fn deinit(self: *Board) void {
    self.allocator.free(self.blocks);
}
pub fn create_empty_board(width: u32, height: u32, allocator: std.mem.Allocator) !Board{
    assert(width % GRID_SIZE == 0);
    assert(height % GRID_SIZE == 0);
    const width_blocks: u32 = width / GRID_SIZE;
    const height_blocks: u32 = height / GRID_SIZE;
    var blocks: []Block = try allocator.alignedAlloc(
        Block,
        @alignOf(Block),
        @sizeOf(Block) * (width_blocks * height_blocks),
    );
    var i: usize = 0;
    while(i < width_blocks * height_blocks): (i += 1) {
        var grid_i: usize = 0;
        const pos = block_index_to_global_pos(width, height, i) orelse {
            return error.InvalidBlockIndex;
        };
        blocks[i].x = pos.x;
        blocks[i].y = pos.y;
        while(grid_i < GRID_LEN) : (grid_i += 1) {
            blocks[i].input[grid_i] = Cell{ .value = .black, .lock = 0 };
        }
    }
    return .{
        .allocator = allocator,
        .width = width,
        .height = height,
        .blocks = blocks,
    };
}

pub fn block_index_to_global_pos(board_width: u32, board_height: u32, index: usize) ?struct {x: u32, y: u32}{
    if (index >= (board_width * board_height)) {
        return null;
    }
    const idx: u32 = @intCast(index);
    const block_x = @as(u32, (idx % (board_width / GRID_SIZE)) * GRID_SIZE);
    const block_y = @as(u32, (idx / (board_width / GRID_SIZE)) * GRID_SIZE);
    return .{ .x = block_x, .y = block_y };
}

pub fn blockPosToBlockIndex(board_width: u32, board_height: u32, x: u32, y: u32) ?usize {
    if(x >= (board_width/GRID_SIZE) or y >= (board_height/GRID_SIZE)) {
        return null;
    }
    return @as(usize, (y * (board_width / GRID_SIZE)) + x);
}

pub fn posToBlockIndex(board_width: u32, board_height: u32, x: u32, y: u32) ?usize {
    if(x >= board_width or y >= board_height) {
        return null;
    }
    const block_x = x / GRID_SIZE;
    const block_y = y / GRID_SIZE;
    return @as(usize, (block_y * (board_width / GRID_SIZE)) + block_x);
}

