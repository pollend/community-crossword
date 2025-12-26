const std = @import("std");
const zap = @import("zap");
const client = @import("client.zig");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");
const rect = @import("rect.zig");
const net = @import("net.zig");
const WebsocketHandler = WebSockets.Handler(client.Client);
const high_score_table = @import("high_score_table.zig");
const profile_session = @import("profile_session.zig");

const stb_writer = @cImport({
    @cInclude("stb_image_write.h");
});

pub const ClientLookupMap = std.AutoHashMap(u64, *client.Client);
pub const ClientArrayList = std.ArrayList(*client.Client);
pub const ClueList = std.ArrayList(Clue);
pub const HighscoreTable100 = high_score_table.FixedHighscoreTable(100);
pub const assert = std.debug.assert;

pub const GRID_SIZE: u32 = 16;
pub const GRID_LEN: u32 = GRID_SIZE * GRID_SIZE;
pub const BACKUP_TIME_STAMP: i64 = std.time.s_per_min * 120;
pub const UPDATE_HIGH_SCORE_TIME: i64 = std.time.s_per_min * 15;
pub const MAP_GENERATION_TIME: i64 = std.time.s_per_min * 60;
pub const SYNC_GAME_STATE_TIME: i64 = std.time.s_per_min * 1;
pub const INACTIVE_TIMEOUT: i64 = std.time.s_per_min * 5;
pub const CELL_PIXEL_SIZE: u32 = 80;

pub const CROSSWORD_CACHE_FILE: []const u8 = "crossword.cache";
pub const GLOBAL_LEADERBOARD_FILE: []const u8 = "global.cache";

pub const MAP_MAGIC_NUMBER: u32 = 0x1F9F1E9f;
pub const MAP_CACHE_MAGIC_NUMBER: u32 = 0x1F9F1E9c; // Different magic number for cache

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

    pub fn value_to_char(value: Value) u8 {
        return switch (value) {
            .empty => ' ',
            .dash => '-',
            .a => 'a',
            .b => 'b',
            .c => 'c',
            .d => 'd',
            .e => 'e',
            .f => 'f',
            .g => 'g',
            .h => 'h',
            .i => 'i',
            .j => 'j',
            .k => 'k',
            .l => 'l',
            .m => 'm',
            .n => 'n',
            .o => 'o',
            .p => 'p',
            .q => 'q',
            .r => 'r',
            .s => 's',
            .t => 't',
            .u => 'u',
            .v => 'v',
            .w => 'w',
            .x => 'x',
            .y => 'y',
            .z => 'z',
            else => {
                return ' ';
            },
        };
    }

    pub fn char_to_value(c: u8) Value {
        return switch (c) {
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

    pub fn calculate_score_u8(word: []const u8) u32 {
        var score: u32 = 0;
        for (word) |cc| {
            const value = char_to_value(cc) catch {
                continue;
            };
            if (value == Value.empty or value == Value.black) {
                continue;
            }
            score += switch (value) {
                .a, .e, .i, .o, .u, .l, .n, .s, .t, .r => 1,
                .d, .g => 2,
                .b, .c, .m, .p => 3,
                .f, .h, .v, .w, .y => 4,
                .k => 5,
                .j, .x => 8,
                .q, .z => 10,
                else => 0,
            };
        }
        return score;
    }

    pub fn calculate_score(word: []Value) u32 {
        var score: u32 = 0;
        for (word) |value| {
            if (value == Value.empty or value == Value.black) {
                continue;
            }
            score += switch (value) {
                .a, .e, .i, .o, .u, .l, .n, .s, .t, .r => 1,
                .d, .g => 2,
                .b, .c, .m, .p => 3,
                .f, .h, .v, .w, .y => 4,
                .k => 5,
                .j, .x => 8,
                .q, .z => 10,
                else => 0,
            };
        }
        return score;
    }
};

pub fn to_cell_index(global_cell_pos: @Vector(2, u32)) usize {
    const local_cell_pos = global_cell_pos % @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
    return (local_cell_pos[1] * GRID_SIZE) + local_cell_pos[0];
}

pub fn to_quad_index(quad_pos: @Vector(2, u32), quad_size: @Vector(2, u32)) ?usize {
    if (quad_pos[0] >= quad_size[0] or quad_pos[1] >= quad_size[1]) {
        return null;
    }
    return (quad_pos[1] * quad_size[0]) + quad_pos[0];
}

pub fn to_quad_size(board_size: @Vector(2, u32)) @Vector(2, u32) {
    return board_size / @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
}

pub fn map_to_quad_pos(pos: @Vector(2, u32)) @Vector(2, u32) {
    return pos / @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
}

pub fn map_to_quad(rec: rect.Rect) rect.Rect {
    const x: u32 = rec.x / GRID_SIZE;
    const y: u32 = rec.y / GRID_SIZE;
    const width: u32 = (std.math.divCeil(u32, rec.x + rec.width, GRID_SIZE) catch 1) - x;
    const height: u32 = (std.math.divCeil(u32, rec.y + rec.height, GRID_SIZE) catch 1) - y;
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

    pub fn decode(value: u8) Cell {
        return .{
            .value = @enumFromInt(@as(u8, @intCast(value & 0x7F))),
            .lock = @intFromBool((value & (1 << 7)) != 0),
        };
    }

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
    index: u32 = 0, // Unique ID for the clue
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
            .index = 0, // ID will be set later
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
    allocator: std.mem.Allocator,
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
                try clues.append(self.allocator, cl);
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
            .allocator = allocator,
            .x = x,
            .y = y,
            .client_lock = .{},
            .clients = .empty, //std.ArrayList(*client.Client).init(allocator),
            .input = [_]Cell{.{ .value = Value.black, .lock = 0 }} ** GRID_LEN,
            .lock = .{},
            .overlapping_clues = .empty, //std.ArrayList(*Clue).init(allocator),
            .clues = .empty, //std.ArrayList(*Clue).init(allocator),
        };
    }

    pub fn deinit(self: *Quad) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.overlapping_clues.deinit(self.allocator);
    }
};

pub const Board = struct {
    size: @Vector(2, u32),
    uid: u32 = 0, // Unique ID for the board
    quads: []Quad,
    clues: ClueList,
    allocator: std.mem.Allocator,
    clues_completed: std.atomic.Value(u32),

    pub fn deinit(self: *Board) void {
        for (self.quads) |*quad| {
            quad.deinit();
        }
        self.clues.deinit(self.allocator);
        self.allocator.free(self.quads);
    }

    //pub fn commit_s3(
    //    self: *Board,
    //    allocator: std.mem.Allocator,
    //    bucket: []const u8,
    //    key: []const u8,
    //    options: aws.Options
    //) !void {
    //    const load_cache = try std.fmt.allocPrint(allocator, "{s}.cache", .{key});
    //    defer allocator.free(load_cache);

    //    var buffer = std.ArrayList(u8).initCapacity(allocator, self.size[0] * self.size[1] * GRID_LEN) catch |err| {
    //        std.log.err("Failed to create backup buffer: {any}", .{err});
    //        return err;
    //    };
    //    defer buffer.deinit();
    //    var writer = buffer.writer();
    //    self.write_cache_writer(writer.any()) catch |err| {
    //        std.log.err("Failed to write board cache: {any}", .{err});
    //        return err;
    //    };
    //    const result = aws.Request(aws.services.s3.put_object).call(.{
    //        .bucket = bucket,
    //        .key = load_cache,
    //        .content_type = "application/octet-stream",
    //        .body = buffer.items,
    //        .storage_class = "STANDARD",
    //    }, options) catch |err| {
    //        std.log.err("Failed to upload backup to S3: {any}", .{err});
    //        return err;
    //    };

    //    defer result.deinit();
    //}
    pub fn encode_cache(
        self: *Board,
        writer: *std.Io.Writer,
    ) !void {
        writer.writeInt(u32, MAP_CACHE_MAGIC_NUMBER, .little) catch |e| {
            std.log.err("Failed to write map cache file: {any}", .{e});
            return e;
        };

        writer.writeByte(0) catch |e| {
            std.log.err("Failed to write map file: {any}", .{e});
            return e;
        }; // version byte

        writer.writeInt(u32, self.uid, .little) catch |e| {
            std.log.err("Failed to write map file: {any}", .{e});
            return e;
        };
        writer.writeInt(u32, self.size[0], .little) catch |e| {
            std.log.err("Failed to write board size to backup buffer: {any}", .{e});
            return e;
        };
        writer.writeInt(u32, self.size[1], .little) catch |e| {
            std.log.err("Failed to write board size to backup buffer: {any}", .{e});
            return e;
        };

        const quad_whole_map = game.map_to_quad(rect.create(0, 0, self.size[0], self.size[1]));
        var iter = quad_whole_map.iterator();
        self.lock_quads_shared(quad_whole_map);
        defer self.unlock_quads_shared(quad_whole_map);
        const quad_size = to_quad_size(self.size);
        var tmp: [GRID_LEN]u8 = undefined;
        while (iter.next()) |quad_pos| {
            if (to_quad_index(quad_pos, quad_size)) |idx| {
                var i: usize = 0;
                while (i < game.GRID_LEN) : (i += 1) {
                    tmp[i] = state.board.quads[idx].input[i].encode();
                }
                writer.writeAll(&tmp) catch |err| {
                    std.log.err("Failed to write quad data to backup buffer: {any}", .{err});
                    continue;
                };
            } else {
                unreachable;
            }
        }
    }

    //pub fn load_s3(
    //    allocator: std.mem.Allocator,
    //    bucket: []const u8,
    //    key: []const u8,
    //    options: aws.Options,
    //) !Board {
    //    const load_map = try std.fmt.allocPrint(allocator, "{s}.map", .{key});
    //    defer allocator.free(load_map);
    //    const load_cache = try std.fmt.allocPrint(allocator, "{s}.cache", .{key});
    //    defer allocator.free(load_cache);

    //    const map_resp = try aws.Request(aws.services.s3.get_object).call(.{
    //        .bucket = bucket,
    //        .key = load_map,
    //    }, options);
    //    defer map_resp.deinit();
    //    var stream = std.io.fixedBufferStream(map_resp.response.body orelse "");
    //    var reader = stream.reader();

    //    const cache_resp = try aws.Request(aws.services.s3.get_object).call(.{
    //        .bucket = bucket,
    //        .key = load_cache,
    //    },options);
    //    defer cache_resp.deinit();
    //    var cache_stream = std.io.fixedBufferStream(cache_resp.response.body orelse "");
    //    var cache_reader = cache_stream.reader();
    //    return try game.Board.load(allocator, reader.any(),cache_reader.any());
    //}

    pub fn load(allocator: std.mem.Allocator, map_reader: *std.Io.Reader, cache_reader: ?*std.Io.Reader) !Board {
        const magic = map_reader.takeInt(u32, .little) catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };

        if (magic != MAP_MAGIC_NUMBER) {
            std.log.err("Invalid map file magic number: expected {x}, got {x}", .{ MAP_MAGIC_NUMBER, magic });
            return error.InvalidMagicNumber;
        }

        _ = map_reader.takeByte() catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };
        const uid = map_reader.takeInt(u32, .little) catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };

        const board_width = map_reader.takeInt(u32, .little) catch |e| {
            std.log.err("Failed to read map file: {any}", .{e});
            return e;
        };
        const board_height = map_reader.takeInt(u32, .little) catch |e| {
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
        var clues: ClueList = .empty; // ClueList.init(allocator);
        {
            var buffer: std.ArrayList(u8) = .empty; //.init(allocator);
            defer buffer.deinit(allocator);
            while (true) {
                buffer.clearRetainingCapacity();
                const x = map_reader.takeInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const y = map_reader.takeInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const dir = map_reader.takeInt(u8, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };

                const word_len = map_reader.takeInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                try buffer.resize(allocator, word_len);
                map_reader.readSliceAll(buffer.items) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const clue_len = map_reader.takeInt(u32, .little) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                try buffer.resize(allocator, clue_len + word_len);
                map_reader.readSliceAll(buffer.items[word_len..]) catch |e| switch (e) {
                    error.EndOfStream => break,
                    else => |err| {
                        std.log.err("Failed to read map file: {any}", .{err});
                        return err;
                    },
                };
                const word_slice = buffer.items[0..word_len];
                const clue_slice = buffer.items[word_len..];
                try clues.append(allocator, game.Clue.init_from_ascii(
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
        var completed_clues: u32 = 0;

        const quad_size = to_quad_size(@Vector(2, u32){ board_width, board_height });
        var is_valid_cache = false;
        invalid_cache: {
            if (cache_reader) |reader| {
                const cache_magic = reader.takeInt(u32, .little) catch |e| {
                    std.log.err("Failed to read map cache file: {any}", .{e});
                    break :invalid_cache;
                };
                if (cache_magic != MAP_CACHE_MAGIC_NUMBER) {
                    std.log.err("Invalid map cache file magic number: expected {x}, got {x}", .{ MAP_CACHE_MAGIC_NUMBER, cache_magic });
                    break :invalid_cache;
                }
                _ = reader.takeByte() catch |e| {
                    std.log.err("Failed to read map cache file: {any}", .{e});
                    break :invalid_cache;
                };
                const cache_uid = reader.takeInt(u32, .little) catch |e| {
                    std.log.err("Failed to read map cache file: {any}", .{e});
                    break :invalid_cache;
                };
                if (cache_uid != uid) {
                    std.log.err("UID mismatch: expected {d}, got {d}", .{ uid, cache_uid });
                    break :invalid_cache;
                }
                const cache_width = reader.takeInt(u32, .little) catch |e| {
                    std.log.err("Failed to read map cache file: {any}", .{e});
                    break :invalid_cache;
                };
                const cache_height = reader.takeInt(u32, .little) catch |e| {
                    std.log.err("Failed to read map cache file: {any}", .{e});
                    break :invalid_cache;
                };
                if (cache_width != board_width or cache_height != board_height) {
                    std.log.err("Size mismatch: expected {d}x{d}, got {d}x{d}", .{ board_width, board_height, cache_width, cache_height });
                    break :invalid_cache;
                }
                const quad_whole_map = game.map_to_quad(rect.create(0, 0, board_width, board_height));
                var iter = quad_whole_map.iterator();
                while (iter.next()) |quad_pos| {
                    if (to_quad_index(quad_pos, quad_size)) |idx| {
                        var i: usize = 0;
                        while (i < game.GRID_LEN) : (i += 1) {
                            quads[idx].input[i] = Cell.decode(reader.takeByte() catch |err| {
                                std.log.err("Failed to read quad data from backup buffer: {any}", .{err});
                                return err;
                            });
                        }
                    } else {
                        unreachable;
                    }
                }
                is_valid_cache = true;
            }
        }

        {
            var clue_idx: u32 = 0;
            for (clues.items) |*clue| {
                clue.index = clue_idx; // Assign a unique ID to the clue
                clue_idx += 1;
                if (to_quad_index(map_to_quad_pos(clue.pos), quad_size)) |idx| {
                    quads[idx].clues.append(allocator, clue) catch |err| {
                        std.log.err("Failed to append clue to quad: {any}", .{err});
                        return err;
                    };
                } else {
                    std.log.warn("clue is incomplete trying to get quad: {any}", .{clue.pos});
                }
                const cell_pos_dir: @Vector(2, u32) = if (clue.dir == .Across) @Vector(2, u32){ 1, 0 } else @Vector(2, u32){ 0, 1 };
                const quad_hit = if (clue.dir == .Across) map_to_quad(rect.create(clue.pos[0], clue.pos[1], @as(u32, @intCast(clue.word.len)), 1)) else map_to_quad(rect.create(clue.pos[0], clue.pos[1], 1, @as(u32, @intCast(clue.word.len))));
                var iter = quad_hit.iterator();
                while (iter.next()) |quad_pos| {
                    if (to_quad_index(quad_pos, quad_size)) |idx| {
                        quads[idx].overlapping_clues.append(allocator, clue) catch |err| {
                            std.log.err("Failed to append clue to quad: {any}", .{err});
                            return err;
                        };
                    } else {
                        std.log.warn("clue is incomplete trying to get quad: {any} quads: {any}", .{ quad_pos, quad_hit });
                    }
                }

                if (!is_valid_cache) {
                    for (clue.word, 0..) |_, index| {
                        const pos = clue.pos + (cell_pos_dir * @Vector(2, u32){ @intCast(index), @intCast(index) });
                        if (to_quad_index(map_to_quad_pos(pos), quad_size)) |quad_idx| {
                            quads[quad_idx].input[to_cell_index(pos)].value = Value.empty;
                        } else {
                            std.log.err("Failed to set value for clue at position {any}", .{pos});
                        }
                    }
                } else {
                    var is_complete = true;
                    for (clue.word, 0..) |_, index| {
                        const pos = clue.pos + (cell_pos_dir * @Vector(2, u32){ @intCast(index), @intCast(index) });
                        if (to_quad_index(map_to_quad_pos(pos), quad_size)) |quad_idx| {
                            if (quads[quad_idx].input[to_cell_index(pos)].value != clue.word[index]) {
                                is_complete = false;
                            }
                        }
                    }
                    if (is_complete) {
                        completed_clues += 1;
                    }
                }
            }
        }

        return .{
            .allocator = allocator,
            .uid = uid,
            .size = @Vector(2, u32){ board_width, board_height },
            .clues_completed = std.atomic.Value(u32).init(completed_clues),
            .quads = quads,
            .clues = clues,
        };
    }

    pub fn unlock_quads_shared(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].lock.unlockShared();
            }
        }
    }

    pub fn lock_quads_shared(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].lock.lockShared();
            }
        }
    }

    pub fn lock_quads_client_shared(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].client_lock.lockShared();
            }
        }
    }

    pub fn unlock_quads_client_shared(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].client_lock.unlockShared();
            }
        }
    }

    pub fn lock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
                self.quads[idx].lock.lock();
            }
        }
    }

    pub fn unlock_quads(self: *Board, quad_rect: rect.Rect) void {
        var iter = quad_rect.iterator();
        while (iter.next()) |pos| {
            if (game.to_quad_index(pos, game.to_quad_size(self.size))) |idx| {
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
                if (to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
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
                if (to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
                    self.quads[idx].client_lock.lock();
                    defer self.quads[idx].client_lock.unlock();
                    self.quads[idx].clients.append(self.allocator, c) catch |err| {
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
            if (to_quad_index(quad_pos, to_quad_size(self.size))) |idx| {
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

fn background_write_map() void {
    var img_buf = state.gpa.alloc(u8, state.board.size[0] * state.board.size[1] * 4) catch |err| {
        std.log.err("Failed to allocate image buffer: {any}", .{err});
        return;
    };
    defer state.gpa.free(img_buf);
    for (state.board.quads) |*quad| {
        quad.lock.lockShared();
        defer quad.lock.unlockShared();

        const pos = @Vector(2, u32){ quad.x, quad.y } * @Vector(2, u32){ GRID_SIZE, GRID_SIZE };
        for (quad.input, 0..) |cell, cell_index| {
            const offset_pos = @Vector(2, u32){ @as(u32, @intCast(cell_index)) % GRID_SIZE, @as(u32, @intCast(cell_index)) / GRID_SIZE };
            const cell_pos = pos + offset_pos;
            const pix_start = (cell_pos[1] * state.board.size[0] + cell_pos[0]) * 4;
            var pix_color = img_buf[pix_start .. pix_start + 4];
            if (cell.lock == 1) {
                pix_color[0] = 0;
                pix_color[1] = 155;
                pix_color[2] = 0;
            } else {
                switch (cell.value) {
                    .black => |_| {
                        pix_color[0] = 0;
                        pix_color[1] = 0;
                        pix_color[2] = 0;
                    },
                    else => {
                        pix_color[0] = 255;
                        pix_color[1] = 255;
                        pix_color[2] = 255;
                    },
                }
            }
        }
    }
    if (stb_writer.stbi_write_png("dist/map.png", @intCast(state.board.size[0]), @intCast(state.board.size[1]), 4, img_buf.ptr, @intCast(4 * state.board.size[0])) <= 0) {
        std.log.err("Failed to save map image", .{});
    }
}

pub fn update_clients() !void {
    state.client_lock.lock();
    defer state.client_lock.unlock();
    var disconnect_clients: std.ArrayList(*client.Client) = .empty; //.init(state.gpa);
    defer disconnect_clients.deinit(state.gpa);

    var visible_cursors: std.ArrayList(client.TrackedCursors) = .empty; //.init(state.gpa);
    defer visible_cursors.deinit(state.gpa);

    const quad_size = game.to_quad_size(state.board.size);
    var value_iter = state.client_lookup.valueIterator();
    while (value_iter.next()) |ptr_client| {
        var cur_client = ptr_client.*;
        cur_client.lock.lock();
        defer cur_client.lock.unlock();
        visible_cursors.clearRetainingCapacity();
        if ((cur_client.active_timestamp.read() / std.time.ns_per_s) >= INACTIVE_TIMEOUT) {
            try disconnect_clients.append(state.gpa, cur_client);
            continue;
        }
        {
            var client_quad_iter = cur_client.quad_rect.iterator();
            while (client_quad_iter.next()) |pos| {
                if (game.to_quad_index(pos, quad_size)) |idx| {
                    const quad = &state.board.quads[idx];
                    quad.client_lock.lockShared();
                    defer quad.client_lock.unlockShared();
                    next: for (quad.clients.items) |quad_client| {
                        if (quad_client.client_id == cur_client.client_id) continue;
                        if (client.is_cursor_within_view(cur_client.cell_rect.pad(5), quad_client.cursor_pos)) {
                            for (visible_cursors.items) |existing_cursor| {
                                if (existing_cursor.client_id == quad_client.client_id) {
                                    continue :next;
                                }
                            }
                            try visible_cursors.append(state.gpa, .{
                                .client_id = quad_client.client_id,
                                .pos = quad_client.cursor_pos,
                            });
                        }
                    }
                }
            }
            net.msg_sync_cursors(cur_client, cur_client.tracked_cursors_pos.items, visible_cursors.items) catch |err| {
                std.log.err("Failed to sync cursors for client {d}: {any}", .{ cur_client.client_id, err });
                continue;
            };
            cur_client.tracked_cursors_pos.clearRetainingCapacity();
            cur_client.tracked_cursors_pos.appendSlice(state.gpa, visible_cursors.items) catch |err| {
                std.log.err("Failed to append cursors for client {d}: {any}", .{ cur_client.client_id, err });
                continue;
            };
        }
    }

    for (disconnect_clients.items) |c| {
        client.WebsocketHandler.close(c.handle);
    }
}

pub fn background_worker() void {
    while (state.running.load(.monotonic)) {
        //if (std.time.timestamp() - state.update_highscore_timestamp >= UPDATE_HIGH_SCORE_TIME) {
        //    std.log.info("Updating Highscores...", .{});
        //    state.update_highscore_timestamp = std.time.timestamp();
        //    state.global.commit_s3(
        //        "global",
        //        state.gpa,
        //        state.bucket,
        //        .{
        //            .region = state.region,
        //            .client = state.aws_client,
        //        },
        //    ) catch |err| {
        //        std.log.err("Failed to write global highscores: {any}", .{err});
        //    };
        //}
        //if (std.time.timestamp() - state.backup_timestamp >= BACKUP_TIME_STAMP) {
        //    std.log.info("Creating game backup...", .{});
        //    state.backup_timestamp = std.time.timestamp();
        //    state.board.commit_s3(
        //        state.gpa,
        //        state.bucket,
        //        state.map_key,
        //        .{
        //            .region = state.region,
        //            .client = state.aws_client,
        //        },
        //    ) catch |err| {
        //        std.log.err("Failed to write board cache to S3: {any}", .{err});
        //    };
        //}
        //
        if ((state.generate_map_timer.read() / std.time.ns_per_s) >= SYNC_GAME_STATE_TIME) {
            state.generate_map_timer.reset();
            state.client_lock.lock();
            defer state.client_lock.unlock();
            var value_iter = state.client_lookup.valueIterator();
            while (value_iter.next()) |cur_client| {
                cur_client.*.lock.lock();
                defer cur_client.*.lock.unlock();
                net.msg_broadcast_game_state(cur_client.*, &state.board) catch |err| {
                    std.log.err("Failed to sync game state for client {d}: {any}", .{ cur_client.*.client_id, err });
                };
            }
        }

        update_clients() catch |err| {
            std.log.err("Failed to update clients: {any}", .{err});
        };
        std.Thread.sleep(200 * std.time.ns_per_ms);
    }

    leaderboard: {
        const leaderboard_fs_path = std.fs.path.join(state.gpa, &.{state.data_dir, GLOBAL_LEADERBOARD_FILE}) catch |err| {
            std.log.err("Failed to create leaderboard file path: {any}", .{err});
            break :leaderboard;
        };
        defer state.gpa.free(leaderboard_fs_path);
        var file = std.fs.cwd().createFile(leaderboard_fs_path, .{ .truncate = true }) catch |err| {
            std.log.err("Failed to open leaderboard file for writing: {any}", .{err});
            break :leaderboard;
        };
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        defer writer.end() catch |err| {
            std.log.err("Failed to finalize leaderboard file: {any}", .{err});
        };
        state.global.encode(&writer.interface) catch |err| {
            std.log.err("Failed to write leaderboard file: {any}", .{err});
        };
    }
    map_cache: {
        const mcache_cache_fs_path = std.fs.path.join(state.gpa, &.{state.data_dir, CROSSWORD_CACHE_FILE}) catch |err| {
            std.log.err("Failed to create map cache file path: {any}", .{err});
            break :map_cache;
        };
        defer state.gpa.free(mcache_cache_fs_path);
        var file = std.fs.cwd().createFile(mcache_cache_fs_path, .{ .truncate = true }) catch |err| {
            std.log.err("Failed to open map cache file for writing: {any}", .{err});
            break :map_cache;
        };
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(&buffer);
        defer writer.end() catch |err| {
            std.log.err("Failed to finalize map cache file: {any}", .{err});
        };
        state.board.encode_cache(&writer.interface) catch |err| {
            std.log.err("Failed to write map cache file: {any}", .{err});
        };
    }

    //game.state.board.commit_s3(
    //    state.gpa,
    //    state.bucket,
    //    state.map_key,
    //    .{
    //        .region = state.region,
    //        .client = state.aws_client,
    //    },
    //) catch |err| {
    //    std.log.err("Failed to write board cache to S3: {any}", .{err});
    //};
}

pub const State = struct {
    client_id: u32,
    client_lock: std.Thread.Mutex.Recursive,
    client_lookup: ClientLookupMap,

    generate_map_timer: std.time.Timer,
    sync_game_timer: std.time.Timer,
    running: std.atomic.Value(bool),

    session_key: [profile_session.KEY_LENGTH]u8,
    map_key: []const u8,
    data_dir: []const u8,
    domain: []const u8,

    origins: std.ArrayList([]const u8),

    global: HighscoreTable100,

    gpa: std.mem.Allocator,
    client_pool: std.heap.MemoryPool(client.Client),

    board: Board,
};
pub var state: State = undefined;
