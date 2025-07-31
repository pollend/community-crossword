const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;
const client = @import("client.zig");
const game = @import("game.zig");
const rect = @import("rect.zig");
const aws = @import("aws");

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
    var crossword_cache: []const u8 = undefined;
    var threads: i16 = 1;
    var bucket: []const u8  = undefined;
    var region: []const u8  = undefined;
    if(try __get_env_var(allocator, "PORT")) | port_str| {
        port = try __parse_env_integer(u16, port_str, "PORT");
        defer allocator.free(port_str);
    } else {
        port = 3010;
    }

    if(try __get_env_var(allocator, "CROSSWORD_MAP")) |str| {
        crossword_map = str;
    } else {
        crossword_map = "crossword.map";
    }
    
    if(try __get_env_var(allocator, "CROSSWORD_CACHE")) |str| {
        crossword_cache = str;
    } else {
        crossword_cache  = "crossword.cache";
    }

    if(try __get_env_var(allocator, "THREADS")) |thread_str| {
        threads = try __parse_env_integer(i16, thread_str, "THREADS");
        defer allocator.free(thread_str);
    } else {
        threads = 1;
    }
    
    if(try __get_env_var(allocator, "AWS_REGION")) |region_str| {
        region = region_str;
    } else {
       region = "us-west-2"; 
    }
    
    if(try __get_env_var(allocator, "AWS_BUCKET")) |bucket_str| {
        bucket = bucket_str;
    } else {
        bucket = "crossword";
    }

    if(try __get_env_var(allocator, "AWS_ENDPOINT_URL")) |str| {
        std.debug.print("AWS_ENDPOINT_URL: {s}\n", .{str});
    }

    var aws_client = aws.Client.init(allocator,.{});
    defer aws_client.deinit();
        
    game.state = .{
        .gpa = allocator,
        .clients = std.ArrayList(*client.Client).init(allocator),
        .client_id = 0,
        .client_lock = std.Thread.Mutex.Recursive.init,
        .backup_timestamp = 0,
        .generate_map_timestamp = 0,
        .sync_game_state_timestamp = 0, 
        .running = std.atomic.Value(bool).init(true),

        .crossword_cache = crossword_cache,
        .crossword_map = crossword_map,

        .bucket = bucket,
        .region = region,
        .aws_client = aws_client,
   
        .board = undefined,
    };

    // load the crossword map 
    {
        const map_resp = try aws.Request(aws.services.s3.get_object).call(.{
            .bucket = bucket,
            .key = crossword_map,
        }, .{
            .region = region,
            .client = aws_client,
        });
        defer map_resp.deinit();
        var stream = std.io.fixedBufferStream(map_resp.response.body orelse "");
        var reader = stream.reader();

        const cache_resp = try aws.Request(aws.services.s3.get_object).call(.{
            .bucket = bucket,
            .key = crossword_cache,
        }, .{
            .region = region,
            .client = aws_client,
        });
        defer cache_resp.deinit();
        var cache_stream = std.io.fixedBufferStream(cache_resp.response.body orelse "");
        var cache_reader = cache_stream.reader();
        game.state.board = try game.Board.load(allocator, reader.any(),cache_reader.any());
    }
  
    var background_worker = try std.Thread.spawn(.{}, game.background_worker, .{});
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
    std.log.info("  Threads: {d}, Workers: {d}", .{ threads, 1 });
    std.log.info("", .{});
    std.log.info("Connect with browser to http://localhost:{d}.", .{port});
    std.log.info("Connect to websocket on ws://localhost:{d}.", .{port});
    std.log.info("Terminate with CTRL+C", .{});

    zap.start(.{
        .threads = threads,
        .workers = 1,
    });
    game.state.running.store(false, .monotonic);
    background_worker.join(); 
}

const expect = std.testing.expect;
test {
    _ = rect;
}
