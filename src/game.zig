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

pub fn map_to_quad(rec: rect.Rect) rect.Rect {
    const x: u32 = rec.x / GRID_SIZE;
    const y: u32 = rec.y / GRID_SIZE;
    const width: u32 = ((rec.x + rec.width) / GRID_SIZE) - x + 1;
    const height: u32 = ((rec.y + rec.height) / GRID_SIZE) - y + 1;
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

    pub fn get_crossing_clues(self: *Quad, pos: @Vector(2, u32), collection: []*Clue, len: *usize) void {
        for (self.overlapping_clues.items) |cl| {
            if (len.* >= collection.len) {
                return;
            }
            if (cl.to_rect().contains_point(pos)) {
                collection[len.*] = cl;
                len.* += 1;
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

pub fn BoardRectIterator(Context: type, comptime enter: fn (*Context, quad: *Quad) void, comptime exit: fn (*Context, quad: *Quad) void) type {
    return struct {
        board: *Board,
        iter: rect.RectIterator,
        quad: ?*Quad = null,
        context: Context,

        const Self = @This();

        pub fn init(c: Context, board: *Board, rc: rect.Rect) Self {
            return .{
                .board = board,
                .iter = rc.iterator(),
                .quad = null,
                .context = c,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.quad) |q| {
                exit(&self.context, q);
            }
        }
        // returns cell position quad and the relative position within the quad
        pub fn next(self: *Self) ?struct { q: *Quad, p: @Vector(2, u32) } {
            while (self.iter.next()) |cell_pos| {
                if (self.quad) |q| {
                    if (q.quad_rect_global().contains_point(cell_pos)) {
                        return .{ .q = q, .p = q.to_local(cell_pos) };
                    } else {
                        exit(&self.context, q);
                        self.quad = null;
                    }
                }
                if (self.board.get_quad_from_cell_pos(cell_pos)) |q| {
                    enter(&self.context, q);
                    self.quad = q;
                    return .{ .q = q, .p = q.to_local(cell_pos) };
                }
            }
            if (self.quad) |q| {
                exit(&self.context, q);
                self.quad = null;
            }
            return null;
        }
    };
}

pub const DefaultQuadDefault = game.BoardRectIterator(void, _default_board_enter, _default_board_exit);
fn _default_board_enter(_: *void, _: *game.Quad) void {

}
fn _default_board_exit(_: *void, _: *game.Quad) void {}

pub const Board = struct {
    size: @Vector(2, u32),
    quads: []Quad,

    pub fn lock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (self.get_quad(pos)) |quad| {
                quad.lock.lock();
            }
        }
    }

    pub fn unlock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (self.get_quad(pos)) |quad| {
                quad.lock.unlock();
            }
        }
    }

    pub fn set_value_from_cell_position(self: *Board, pos: @Vector(2, u32), value: Value) bool {
        if (get_quad_from_cell_pos(self, pos)) |quad| {
            const cell_x = pos[0] % GRID_SIZE;
            const cell_y = pos[1] % GRID_SIZE;

            quad.lock.lock();
            defer quad.lock.unlock();

            const index = (cell_y * GRID_SIZE) + cell_x;
            quad.input[index].value = value;
            return true;
        }
        return false;
    }

    pub fn quad_width(self: *Board) u32 {
        return self.size[0] / GRID_SIZE;
    }

    pub fn quad_height(self: *Board) u32 {
        return self.size[1] / GRID_SIZE;
    }

    pub fn get_quad(self: *Board, pos: @Vector(2, u32)) ?*Quad {
        const quad_x = pos[0];
        const quad_y = pos[1];
        if (quad_x >= self.quad_width() or quad_y >= self.quad_height()) {
            return null;
        }
        const index = (quad_y * self.quad_width()) + quad_x;
        const quad = &self.quads[index];
        assert(quad.x == quad_x and quad.y == quad_y);
        return quad;
    }

    pub fn get_cell_from_cell_pos(self: *Board, pos: @Vector(2, u32)) ?*Cell {
        if (get_quad_from_cell_pos(self, pos)) |quad| {
            const local_pos = quad.to_local(pos);
            return quad.get_cell(local_pos);
        }
        return null;
    }

    pub fn get_quad_from_cell_pos(self: *Board, pos: @Vector(2, u32)) ?*Quad {
        const quad_x = pos[0] / GRID_SIZE;
        const quad_y = pos[1] / GRID_SIZE;
        if (quad_x >= self.quad_width() or quad_y >= self.quad_height()) {
            return null;
        }
        const index = (quad_y * self.quad_width()) + quad_x;
        const quad = &self.quads[index];
        assert(quad.x == quad_x and quad.y == quad_y);
        return quad;
    }

    pub fn register_client_board(
        board: *game.Board,
        c: *client.Client,
        add_rect: rect.Rect,
    ) void {
        var iter = add_rect.iterator();
        while (iter.next()) |pos| {
            if (board.get_quad(pos)) |quad| {
                quad.client_lock.lock();
                defer quad.client_lock.unlock();
                quad.clients.append(c) catch |err| {
                    std.log.err("Failed to append client to quad: {any}", .{err});
                    unregister_client_board(board, c, add_rect);
                };
            }
        }
    }

    pub fn update_client_rect(
        board: *game.Board,
        c: *client.Client,
        old_rect: rect.Rect,
        new_rect: rect.Rect,
    ) void {
        {
            var iter = old_rect.iterator();
            while (iter.next()) |pos| {
                if (new_rect.contains_point(pos)) 
                    continue;
                if (game.state.board.get_quad(pos)) |quad| {
                    quad.client_lock.lock();
                    defer quad.client_lock.unlock();
                    for (quad.clients.items, 0..) |cl, index| {
                        if (cl == c) {
                            _ = quad.clients.swapRemove(index);
                            break;
                        }
                    }
                }
            }
        }
        {
            var iter = new_rect.iterator();
            while (iter.next()) |pos| {
                if (old_rect.contains_point(pos)) 
                    continue;
                if (game.state.board.get_quad(pos)) |quad| {
                    quad.client_lock.lock();
                    defer quad.client_lock.unlock();
                    quad.clients.append(c) catch |err| {
                        std.log.err("Failed to append client to quad: {any}", .{err});
                        unregister_client_board(board, c, new_rect);
                    };
                }
            }
        }
    }

    pub fn unregister_client_board(
        board: *game.Board,
        c: *client.Client,
        remove_rect: rect.Rect,
    ) void {
        var iter = remove_rect.iterator();
        while (iter.next()) |pos| {
            if (board.get_quad(pos)) |quad| {
                quad.client_lock.lock();
                defer quad.client_lock.unlock();
                for (quad.clients.items, 0..) |cl, index| {
                    if (cl == c) {
                        _ = quad.clients.swapRemove(index);
                        break;
                    }
                }
            }
        }
    }
};

pub const State = struct {
    client_id: u32,
    client_lock: std.Thread.Mutex,
    clients: ClientArrayList,

    allocator: std.mem.Allocator,
    clues: ClueList,
    board: Board,

    pub fn deinit(self: *State) void {
        for (self.board.quads) |*quad| quad.deinit();
        for (self.clues.items) |*clue| clue.deinit();
        self.clients.deinit();
        self.clues.deinit();
        self.allocator.free(self.board.quads);
    }

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, clues: ClueList) !State {
        std.debug.print("Initializing game state with width: {d}, height: {d} clues: {d}\n", .{ width, height, clues.items.len });
        if (width % GRID_SIZE != 0 or height % GRID_SIZE != 0) {
            std.log.err("Width and height must be multiples of {d}", .{GRID_SIZE});
            return error.SizeNotMultipleOfGridSize;
        }

        if (width == 0 or height == 0) {
            std.log.err("Width and height must be greater than 0", .{});
            return error.InvalidSize;
        }

        const quads = try allocator.alloc(Quad, (width / GRID_SIZE) * (height / GRID_SIZE)); // Initial capacity for clients
        for (quads, 0..) |*quad, index| {
            const quad_x = index % (width / GRID_SIZE);
            const quad_y = index / (width / GRID_SIZE);
            quad.* = try Quad.init(allocator, @intCast(quad_x), @intCast(quad_y));
        }

        var board: Board = .{
            .size = .{ width, height },
            .quads = quads,
        };

        var id: u32 = 0;
        for (clues.items) |*clue| {
            id += 1;
            clue.id = id; // Assign a unique ID to the clue
            if (board.get_quad_from_cell_pos(clue.pos)) |quad| {
                quad.lock.lock();
                defer quad.lock.unlock();
                quad.clues.append(clue) catch |err| {
                    std.log.err("Failed to append clue to quad: {any}", .{err});
                    return err;
                };
            } else {
                std.log.warn("clue is incomplete trying to get quad: {any}", .{clue.pos});
            }
            switch (clue.dir) {
                .Across => {
                    const quad_hit = map_to_quad(rect.create(clue.pos[0], clue.pos[1], @as(u32, @intCast(clue.word.len)), 1));
                    var iter = quad_hit.iterator();
                    while (iter.next()) |pos| {
                        if (board.get_quad_from_cell_pos(pos)) |quad| {
                            quad.lock.lock();
                            defer quad.lock.unlock();
                            quad.overlapping_clues.append(clue) catch |err| {
                                std.log.err("Failed to append clue to quad: {any}", .{err});
                                return err;
                            };
                        } else {
                            std.log.warn("clue is incomplete trying to get quad: {any}", .{pos});
                        }
                    }
                    for (clue.word, 0..) |_, index| {
                        const pos = @Vector(2, u32){ clue.pos[0] + @as(u32, @intCast(index)), clue.pos[1] };
                        if (!board.set_value_from_cell_position(pos, Value.empty)) {
                            std.log.err("Failed to set value for clue at position {any}", .{pos});
                        }
                    }
                },
                .Down => {
                    const quad_hit = map_to_quad(rect.create(clue.pos[0], clue.pos[1], 1, @as(u32, @intCast(clue.word.len))));
                    var iter = quad_hit.iterator();
                    while (iter.next()) |pos| {
                        if (board.get_quad_from_cell_pos(pos)) |quad| {
                            quad.lock.lock();
                            defer quad.lock.unlock();
                            quad.overlapping_clues.append(clue) catch |err| {
                                std.log.err("Failed to append clue to quad: {any}", .{err});
                                return err;
                            };
                        } else {
                            std.log.warn("clue is incomplete trying to get quad: {any}", .{pos});
                        }
                    }
                    for (clue.word, 0..) |_, index| {
                        const pos = @Vector(2, u32){ clue.pos[0], clue.pos[1] + @as(u32, @intCast(index)) };
                        if (!board.set_value_from_cell_position(pos, Value.empty)) {
                            std.log.err("Failed to set value for clue at position {any}", .{pos});
                        }
                    }
                },
            }
        }

        return .{
            .allocator = allocator,
            .client_id = 0,
            .client_lock = .{},
            .clients = ClientArrayList.init(allocator),
            .board = board,
            .clues = clues,
        };
    }
};
pub var state: State = undefined;
