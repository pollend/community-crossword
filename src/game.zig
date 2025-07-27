const std = @import("std");
const zap = @import("zap");
const client = @import("client.zig");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");
const rect = @import("rect.zig");
const WebsocketHandler = WebSockets.Handler(client.Client);

pub const ClientArrayList = std.ArrayList(*client.Client);
pub const ClueList = std.ArrayList(Clue);
pub const assert = std.debug.assert;

pub const GRID_SIZE: u32 = 16;
pub const GRID_LEN: u32 = GRID_SIZE * GRID_SIZE;

pub const GRID_SZ: @Vector(2, u32) = @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
pub const Value = enum(u7) {
    empty, // empty cell
    dash, // space/dash
    black, // black cell
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
};


pub fn to_cell_index(global_cell_pos: @Vector(2, u32)) usize {
    const local_cell_pos = global_cell_pos % @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
    return (local_cell_pos[1] * GRID_SIZE) + local_cell_pos[0];
}

pub fn to_quad_index(quad_pos: @Vector(2, u32), quad_size: @Vector(2, u32)) ?usize  {
    if (quad_pos[0] >= quad_size[0] or quad_pos[1] >= quad_size[1]) {
        return null;
    }
    return (quad_pos[1] * quad_size[0]) + quad_pos[0];
}
    
pub fn to_quad_size(board_size: @Vector(2, u32)) @Vector(2, u32) {
    return board_size / @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
}

pub fn map_to_quad_pos(pos: @Vector(2, u32)) @Vector(2, u32) {
    return pos / @Vector(2, u32){GRID_SIZE, GRID_SIZE};
}

pub fn map_to_quad(rec: rect.Rect) rect.Rect {
    const x: u32 = rec.x / GRID_SIZE;
    const y: u32 = rec.y / GRID_SIZE;
    const width: u32 = (std.math.divCeil(u32, rec.x + rec.width, GRID_SIZE) catch 1) - x;
    const height: u32 = (std.math.divCeil(u32, rec.y + rec.height, GRID_SIZE) catch 1) - y ;
    return .{
        .x = x,
        .y = y,
        .width = width, // Round up to the nearest grid size
        .height = height, // Round up to the nearest grid size
    };
}

pub const Cell = packed struct {
    value: Value,
    lock: u1,

    pub fn encode(self: *const Cell) u8 {
        var value: u8 = @intFromEnum(self.value);
        if (self.lock == 1) {
            value |= 1 << 7;
        }
        return value;
    }
};

pub const Direction = enum(u1) {
    Across,
    Down,
};

pub const Clue = struct {
    id: u32 = 0, // Unique ID for the clue
    word: []Value,
    clue: []const u8,
    pos: @Vector(2, u32),
    dir: Direction,
    allocator: std.mem.Allocator,

    pub fn init_from_ascii(allocator: std.mem.Allocator, word: []const u8, clue: []const u8, pos: @Vector(2, u32), dir: Direction) !Clue {
        var value = try allocator.alloc(Value, word.len);
        for (word, 0..) |c, index| {
            value[index] = switch (c) {
                'a', 'A' => Value.a,
                'b', 'B' => Value.b,
                'c', 'C' => Value.c,
                'd', 'D' => Value.d,
                'e', 'E' => Value.e,
                'f', 'F' => Value.f,
                'g', 'G' => Value.g,
                'h', 'H' => Value.h,
                'i', 'I' => Value.i,
                'j', 'J' => Value.j,
                'k', 'K' => Value.k,
                'l', 'L' => Value.l,
                'm', 'M' => Value.m,
                'n', 'N' => Value.n,
                'o', 'O' => Value.o,
                'p', 'P' => Value.p,
                'q', 'Q' => Value.q,
                'r', 'R' => Value.r,
                's', 'S' => Value.s,
                't', 'T' => Value.t,
                'u', 'U' => Value.u,
                'v', 'V' => Value.v,
                'w', 'W' => Value.w,
                'x', 'X' => Value.x,
                'y', 'Y' => Value.y,
                'z', 'Z' => Value.z,
                '-', ' ' => Value.dash, // space or dash
                else => return error.InvalidCharacter, // Invalid character
            };
        }
        return .{
            .word = value,
            .id = 0, // ID will be set later
            .clue = try allocator.dupe(u8, clue),
            .pos = pos,
            .dir = dir,
            .allocator = allocator,
        };
    }

    pub fn to_rect(self: *Clue) rect.Rect {
        const width = switch (self.dir) {
            .Across => @as(u32, @intCast(self.word.len)),
            .Down => 1,
        };
        const height = switch (self.dir) {
            .Across => 1,
            .Down => @as(u32, @intCast(self.word.len)),
        };
        return rect.create(self.pos[0], self.pos[1], width, height);
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

    client_lock: std.Thread.RwLock,
    clients: std.ArrayList(*client.Client),

    lock: std.Thread.RwLock,
    overlapping_clues: std.ArrayList(*Clue), // clues that overlap with this quad
    clues: std.ArrayList(*Clue), // clues that are starting in this quad

    pub fn get_crossing_clues(self: *Quad, pos: @Vector(2, u32), clues: *std.ArrayList(*game.Clue)) !void {
        for (self.overlapping_clues.items) |cl| {
            if (cl.to_rect().contains_point(pos)) {
                try clues.append(cl);
            }
        }
    }

    pub fn to_global(self: *Quad, pos: @Vector(2, u32)) @Vector(2, u32) {
        assert(pos[0] < GRID_SIZE and pos[1] < GRID_SIZE);
        return @Vector(2, u32){ self.x * GRID_SIZE + pos[0], self.y * GRID_SIZE + pos[1] };
    }

    pub fn to_local(self: *Quad, pos: @Vector(2, u32)) @Vector(2, u32) {
        assert(pos[0] >= self.x * GRID_SIZE and pos[1] >= self.y * GRID_SIZE);
        assert(pos[0] < (self.x + 1) * GRID_SIZE and pos[1] < (self.y + 1) * GRID_SIZE);
        return @Vector(2, u32){ pos[0] % GRID_SIZE, pos[1] % GRID_SIZE };
    }

    pub fn get_cell(self: *Quad, pos: @Vector(2, u32)) *Cell {
        const index = (pos[1] * GRID_SIZE) + pos[0];
        assert(index < GRID_LEN);
        return &self.input[index];
    }

    pub fn init(allocator: std.mem.Allocator, x: u32, y: u32) !Quad {
        return .{
            .x = x,
            .y = y,
            .client_lock = .{},
            .clients = std.ArrayList(*client.Client).init(allocator),
            .input = [_]Cell{.{ .value = Value.black, .lock = 0 }} ** GRID_LEN,
            .lock = .{},
            .overlapping_clues = std.ArrayList(*Clue).init(allocator),
            .clues = std.ArrayList(*Clue).init(allocator),
        };
    }

    pub fn quad_rect_global(self: *Quad) rect.Rect {
        return rect.create(
            self.x * GRID_SIZE,
            self.y * GRID_SIZE,
            GRID_SIZE,
            GRID_SIZE,
        );
    }

    pub fn deinit(self: *Quad) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.overlapping_clues.deinit();
    }
};

pub const Board = struct {
    size: @Vector(2, u32),
    quads: []Quad,
    clues: ClueList,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Board) void {
        for (self.quads) |*quad| {
            quad.deinit();
        }
        self.clues.deinit();
        self.allocator.free(self.quads);
    }

    pub fn load_from_reader(
        allocator: std.mem.Allocator,
        reader: std.io.AnyReader,
    ) !Board {
        const board_width = reader.readInt(u32, .little) catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };
        const board_height = reader.readInt(u32, .little) catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };

        if (board_width % GRID_SIZE != 0 or board_height % GRID_SIZE != 0) {
            std.log.err("Width and height must be multiples of {d}", .{GRID_SIZE});
            return error.SizeNotMultipleOfGridSize;
        }
        if (board_width == 0 or board_height == 0) {
            std.log.err("Width and height must be greater than 0", .{});
            return error.InvalidSize;
        }
        var clues = ClueList.init(allocator);
        {
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            while (true) {
                buffer.clearRetainingCapacity();
                const x = reader.readInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const y = reader.readInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const dir = reader.readInt(u8, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };

                const word_len = reader.readInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                try buffer.resize(word_len);
                reader.readNoEof(buffer.items) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const clue_len = reader.readInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                try buffer.resize(clue_len + word_len);
                reader.readNoEof(buffer.items[word_len..]) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const word_slice = buffer.items[0..word_len];
                const clue_slice = buffer.items[word_len..];
                try clues.append(game.Clue.init_from_ascii(
                    allocator,
                    word_slice,
                    clue_slice,
                    .{
                        x,
                        y,
                    },
                    @enumFromInt(dir),
                ) catch |e| {
                    std.log.err("Failed to create clue: {any} {s} - {s}", .{ e, word_slice, clue_slice });
                    return e;
                });
            }
        }
        const quads = try allocator.alloc(Quad, (board_width / GRID_SIZE) * (board_height / GRID_SIZE)); // Initial capacity for clients
        for (quads, 0..) |*quad, index| {
            const quad_x = index % (board_width / GRID_SIZE);
            const quad_y = index / (board_width / GRID_SIZE);
            quad.* = try Quad.init(allocator, @intCast(quad_x), @intCast(quad_y));
        }
        const quad_size = to_quad_size(@Vector(2, u32){board_width, board_height});
        var id: u32 = 0;
        for (clues.items) |*clue| {
            id += 1;
            clue.id = id; // Assign a unique ID to the clue
            if (to_quad_index(map_to_quad_pos(clue.pos), quad_size)) |idx| {
                quads[idx].clues.append(clue) catch |err| {
                    std.log.err("Failed to append clue to quad: {any}", .{err});
                    return err;
                };
            } else {
                std.log.warn("clue is incomplete trying to get quad: {any}", .{clue.pos});
            }
            const cell_pos_dir: @Vector(2, u32) = if(clue.dir == .Across) @Vector(2, u32){1, 0} else @Vector(2, u32){0, 1};
            const quad_hit = if(clue.dir == .Across) map_to_quad(rect.create(clue.pos[0], clue.pos[1], @as(u32, @intCast(clue.word.len)), 1))
                else map_to_quad(rect.create(clue.pos[0], clue.pos[1], 1, @as(u32, @intCast(clue.word.len))));
            var iter = quad_hit.iterator();
            while (iter.next()) |quad_pos| {
                if (to_quad_index(quad_pos, quad_size)) |idx| {
                    quads[idx].overlapping_clues.append(clue) catch |err| {
                        std.log.err("Failed to append clue to quad: {any}", .{err});
                        return err;
                    };
                } else {
                    std.log.warn("clue is incomplete trying to get quad: {any} quads: {any}", .{ quad_pos, quad_hit });
                }
            }

            for (clue.word, 0..) |_, index| {
                const pos = clue.pos + (cell_pos_dir * @Vector(2,u32){@intCast(index), @intCast(index)});
                if(to_quad_index(map_to_quad_pos(pos), quad_size)) |quad_idx| {
                    quads[quad_idx].input[to_cell_index(pos)].value = Value.empty;  
                } else {
                    std.log.err("Failed to set value for clue at position {any}", .{pos});
                }
            }
        }
        return .{
            .allocator = allocator,
            .size = @Vector(2, u32){ board_width, board_height },
            .quads = quads,
            .clues = clues,
        };
    }

    pub fn lock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if(game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].lock.lock();
            }
        }
    }

    pub fn unlock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if(game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].lock.unlock();
            }
        }
    }

    pub fn quad_width(self: *Board) u32 {
        return self.size[0] / GRID_SIZE;
    }

    pub fn quad_height(self: *Board) u32 {
        return self.size[1] / GRID_SIZE;
    }

    pub fn update_client_rect(
        self: *game.Board,
        c: *client.Client,
        old_quad_rect: rect.Rect,
        new_quad_rect: rect.Rect,
    ) void {
        {
            var iter = old_quad_rect.iterator();
            while (iter.next()) |quad_pos| {
                if (new_quad_rect.contains_point(quad_pos))
                    continue;
                if(to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
                    self.quads[idx].client_lock.lock();
                    defer self.quads[idx].client_lock.unlock();
                    for (self.quads[idx].clients.items, 0..) |cl, index| {
                        if (cl == c) {
                            _ = self.quads[idx].clients.swapRemove(index);
                            break;
                        }
                    }
                }
            }
        }
        {
            var iter = new_quad_rect.iterator();
            while (iter.next()) |quad_pos| {
                if (old_quad_rect.contains_point(quad_pos))
                    continue;
                if(to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
                    self.quads[idx].client_lock.lock();
                    defer self.quads[idx].client_lock.unlock();
                    self.quads[idx].clients.append(c) catch |err| {
                        std.log.err("Failed to append client to quad: {any}", .{err});
                        unregister_client_board(self, c, new_quad_rect);
                        return;
                    };
                }
            }
        }
    }

    pub fn unregister_client_board(
        self: *game.Board,
        c: *client.Client,
        remove_quad_rect: rect.Rect,
    ) void {
        var iter = remove_quad_rect.iterator();
        while (iter.next()) |quad_pos| {
            if(to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
                self.quads[idx].client_lock.lock();
                defer self.quads[idx].client_lock.unlock();
                for (self.quads[idx].clients.items, 0..) |cl, client_index| {
                    if (cl == c) {
                        _ = self.quads[idx].clients.swapRemove(client_index);
                        break;
                    }
                }
            }
        }
    }
};

pub const State = struct {
    client_id: u32,
    client_lock: std.Thread.Mutex = .{},
    clients: ClientArrayList,

    gpa: std.mem.Allocator,
    board: Board,

    //pub fn deinit(self: *State) void {
    //    //for (self.board.quads) |*quad| quad.deinit();
    //    //for (self.clues.items) |*clue| clue.deinit();
    //    self.clients.deinit();
    //    self.board.deinit();
    //    self.gpa.free(self.board.quads);
    //}

    //pub fn init(allocator: std.mem.Allocator, options: struct {
    //    board: Board
    //}) !State {
    //    return .{
    //        .allocator = allocator,
    //        .client_id = 0,
    //        .client_lock = .{},
    //        .clients = ClientArrayList.init(allocator),
    //        .board = options.board
    //    };
    //}
};
pub var state: State = undefined;
