const std = @import("std");
const zap = @import("zap");
const client = @import("client.zig");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");

const WebsocketHandler = WebSockets.Handler(client.Client);

pub const ClientArrayList = std.ArrayList(*client.Client);
pub const ClueList = std.ArrayList(Clue);

pub const GRID_SIZE: u32 = 32;
pub const GRID_LEN: u32 = GRID_SIZE * GRID_SIZE;
pub const Value = enum(u7) {
    empty, // empty cell
    dash, // space/dash 
    black, // black cell
    a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,
};

pub const GridRect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn contains(self: *const GridRect, pos: CellPos) bool {
        return pos.x >= self.x and pos.x < (self.x + self.width) and
               pos.y >= self.y and pos.y < (self.y + self.height);
    }
};

pub const Cell = packed struct {
    value: Value,
    lock: u1,

    pub fn encode(self: *Cell) u8 {
        var value: u8= @intFromEnum(self.value);
        if (self.lock ==  1)  {
            value |= 1 << 5; // set the lock bit at position 5
        }
        return value;
    }
}; 


pub const Direction = enum(u1) {
    Across,
    Down,
};

pub const CellPos = struct {
    x: u32,
    y: u32,
};

pub const Clue = struct {
    word: []Value,
    clue: []const u8,
    pos: @Vector(2, u32),
    dir: Direction,
    allocator: std.mem.Allocator,

    pub fn init_from_ascii(allocator: std.mem.Allocator, word: []const u8, clue: []const u8, pos: @Vector(2, u32), dir: Direction) !Clue {
        var value = try allocator.alloc(Value, word.len);
        for(word, 0..) |c, index| {
            value[index] = switch (c) {
                'a' , 'A' => Value.a,
                'b' , 'B' => Value.b,
                'c' , 'C' => Value.c,
                'd' , 'D' => Value.d,
                'e' , 'E' => Value.e,
                'f' , 'F' => Value.f,
                'g' , 'G' => Value.g,
                'h' , 'H' => Value.h,
                'i' , 'I' => Value.i,
                'j' , 'J' => Value.j,
                'k' , 'K' => Value.k,
                'l' , 'L' => Value.l,
                'm' , 'M' => Value.m,
                'n' , 'N' => Value.n,
                'o' , 'O' => Value.o,
                'p' , 'P' => Value.p,
                'q' , 'Q' => Value.q,
                'r' , 'R' => Value.r,
                's' , 'S' => Value.s,
                't' , 'T' => Value.t,
                'u' , 'U' => Value.u,
                'v' , 'V' => Value.v,
                'w' , 'W' => Value.w,
                'x' , 'X' => Value.x,
                'y' , 'Y' => Value.y,
                'z' , 'Z' => Value.z,
                '-' , ' ' => Value.dash, // space or dash
                else => return error.InvalidCharacter, // Invalid character
            } ;
        }
        return .{
            .word = value,
            .clue = try allocator.dupe(u8, clue),
            .pos = pos,
            .dir = dir,
            .allocator = allocator,
        };

    }

    pub fn deinit(self: *Clue) void {
        self.allocator.free(self.word);
        self.allocator.free(self.clue);
    }
};

pub const Quad = struct {
    x: u32, 
    y: u32,
    input: [GRID_LEN]Cell,
    lock: std.Thread.RwLock,
    clues: std.ArrayList(*Clue)
};

pub const State = struct {
    client_id: u32, 
    client_lock: std.Thread.Mutex,
    clients: ClientArrayList,

    allocator: std.mem.Allocator,
    board_size: @Vector(2, u32),
    quads: []Quad,
    clues: ClueList,

    pub fn quad_width(self: *State) u32 {
        return self.board_width / GRID_SIZE;
    }

    pub fn quad_height(self: *State) u32 {
        return self.board_height / GRID_SIZE;
    }

    pub fn deinit(self: *State) void {
        self.clients.deinit();
        //self.clues.deinit();
        //if (self.quads) |q| {
        //    self.allocator.free(q);
        //}
    }

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, clues: ClueList) !State {
        if(width % GRID_SIZE != 0 or height % GRID_SIZE != 0) {
            std.log.err("Width and height must be multiples of {d}", .{GRID_SIZE});
            return error.SizeNotMultipleOfGridSize;
        }
        if (width == 0 or height == 0) {
            std.log.err("Width and height must be greater than 0", .{});
            return error.InvalidSize;
        }
        const quads = try allocator.alignedAlloc(
            Quad,
            @alignOf(Quad),
            @sizeOf(Quad) * ((width / GRID_SIZE) * (height / GRID_SIZE)),
        );

        return .{
            .allocator = allocator,
            .client_id = 0,
            .client_lock = .{},
            .clients = ClientArrayList.init(allocator),

            .clues = clues,
            .board_size = .{ width, height },
            .quads = quads, 
        };
    }

    pub fn get_quad_from_cell_pos(self: *State, pos: CellPos) ?*Quad {
        const quad_x = pos.x / GRID_SIZE;
        const quad_y = pos.y / GRID_SIZE;
        if (quad_x >= self.quad_width() or quad_y >= self.quad_height()) {
            return null;
        }
        const index = (quad_y * self.quad_width()) + quad_x;
        return &self.quads[index];
    }
};
pub var state: State = undefined; 
