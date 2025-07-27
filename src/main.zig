const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const client = @import("client.zig");
const game = @import("game.zig");
const rect = @import("rect.zig");

fn on_upgrade(r: zap.Request, target_protocol: []const u8) !void {
    // make sure we're talking the right protocol
    if (!std.mem.eql(u8, target_protocol, "websocket")) {
        std.log.warn("received illegal protocol: {s}", .{target_protocol});
        r.setStatus(.bad_request);
        r.sendBody("400 - BAD REQUEST") catch unreachable;
        return;
    }

    _ = client.Client.upgrade(game.state.gpa, r) catch |e| {
        std.log.err("Error upgrading client: {any}", .{e});
        return;
    };

    std.log.info("connection upgrade OK", .{});
}

pub fn on_request(r: zap.Request) !void {
    if(r.path) |path| {
        if(std.mem.eql(u8, path, "/health")) {
            r.setStatus(.ok);
            try r.setHeader("Content-Type", "text/plain");
            if (r.sendBody("OK")) {} else |err| {
                std.log.err("Unable to send body: {any}", .{err});
            }
            return;
        }
    }

    try r.setHeader("Cache-Control", "no-cache");
    if (r.sendFile("dist/index.html")) {} else |err| {
        std.log.err("Unable to send file: {any}", .{err});
    }
}

fn load_board(allocator: std.mem.Allocator, path: []const u8, board_width: *u32, board_height: *u32, clues: *game.ClueList) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var reader = file.reader();
    board_width.* = reader.readInt(u32, .little) catch |e| {
        std.log.err("Failed to read map file: {any}", .{e});
        return e;
    };
    board_height.* = reader.readInt(u32, .little) catch |e| {
        std.log.err("Failed to read map file: {any}", .{e});
        return e;
    };
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

//const Config = struct {
//    allocator: std.mem.Allocator,
//    port: u16,
//    crossword_map: []const u8,
//    threads: i16,
//    workers: i16,
//
//    fn __parse_env_integer(comptime T: type, value: []const u8, env_name: []const u8) !T {
//        return std.fmt.parseInt(T, value, 10) catch |err| {
//            std.log.err("Error: Invalid {s} value '{s}': {any}", .{ env_name, value, err });
//            return err;
//        };
//    }
//
//    fn __get_env_var(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
//        return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
//            error.EnvironmentVariableNotFound => return null,
//            else => return err,
//        };
//    }
//
//
//    fn deinit(self: *Config) void {
//        self.allocator.free(self.crossword_map);
//    }
//    fn load_config_from_env(allocator: std.mem.Allocator) !Config {
//        var port: u16 = 3010; 
//        var crossword_map: []const u8 = undefined;
//        var threads: i16 = 1;
//        var workers: i16 = 1;
//
//        if(try __get_env_var(allocator, "PORT")) | port_str| {
//            port = try __parse_env_integer(u16, port_str, "PORT");
//            defer allocator.free(port_str);
//        } else {
//            port = 3010;
//        }
//
//        if(try __get_env_var(allocator, "CROSSWORD_MAP")) |str| {
//            crossword_map = str;
//        } else {
//            crossword_map = try allocator.dupe(u8,"./crossword.map");
//        }
//
//        if(try __get_env_var(allocator, "THREADS")) |thread_str| {
//            threads = try __parse_env_integer(i16, thread_str, "THREADS");
//            defer allocator.free(thread_str);
//        } else {
//            threads = 1;
//        }
//
//        if(try __get_env_var(allocator, "WORKERS")) |thread_str| {
//            workers = try __parse_env_integer(i16, thread_str, "WORKERS");
//            defer allocator.free(thread_str);
//        } else {
//            workers = 1;
//        }
//
//        return .{
//            .allocator = allocator,
//            .port = port,
//            .crossword_map = crossword_map,
//            .threads = threads,
//            .workers = workers,
//        };
//    }
//};

fn __parse_env_integer(comptime T: type, value: []const u8, env_name: []const u8) !T {
    return std.fmt.parseInt(T, value, 10) catch |err| {
        std.log.err("Error: Invalid {s} value '{s}': {any}", .{ env_name, value, err });
        return err;
    };
}

fn __get_env_var(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();

    var port: u16 = 3010; 
    var crossword_map: []const u8 = undefined;
    var threads: i16 = 1;
    var workers: i16 = 1;
    if(try __get_env_var(allocator, "PORT")) | port_str| {
        port = try __parse_env_integer(u16, port_str, "PORT");
        defer allocator.free(port_str);
    } else {
        port = 3010;
    }

    if(try __get_env_var(allocator, "CROSSWORD_MAP")) |str| {
        crossword_map = str;
    } else {
        crossword_map = "./crossword.map";
    }

    if(try __get_env_var(allocator, "THREADS")) |thread_str| {
        threads = try __parse_env_integer(i16, thread_str, "THREADS");
        defer allocator.free(thread_str);
    } else {
        threads = 1;
    }

    if(try __get_env_var(allocator, "WORKERS")) |thread_str| {
        workers = try __parse_env_integer(i16, thread_str, "WORKERS");
        defer allocator.free(thread_str);
    } else {
        workers = 1;
    }

    // configure game state
    {
        var file = try std.fs.cwd().openFile(crossword_map, .{});
        defer file.close();
        var reader = file.reader();
        game.state = .{
            .gpa = allocator,
            .clients = std.ArrayList(*client.Client).init(allocator),
            .client_id = 0,
            .board = try game.Board.load_from_reader(allocator, reader.any())
        };
    }

    var listener = zap.HttpListener.init(
        .{
            .port = port,
            .on_upgrade = on_upgrade,
            .on_request = on_request,
            .max_clients = null,
            .max_body_size = 1 * 1024,
            .public_folder = "dist",
            .log = true,
        },
    );
    try listener.listen();
    std.log.info("", .{});
    std.log.info("Server configuration:", .{});
    std.log.info("  Port: {d}", .{port});
    std.log.info("  Crossword map: {s}", .{crossword_map});
    std.log.info("  Threads: {d}, Workers: {d}", .{ threads, workers });
    std.log.info("", .{});
    std.log.info("Connect with browser to http://localhost:{d}.", .{port});
    std.log.info("Connect to websocket on ws://localhost:{d}.", .{port});
    std.log.info("Terminate with CTRL+C", .{});

    zap.start(.{
        .threads = threads,
        .workers = workers,
    });
}

const expect = std.testing.expect;
test {
    _ = rect;
}
