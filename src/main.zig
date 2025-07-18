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

    _ = client.Client.upgrade(game.state.allocator, r) catch |e| {
        std.log.err("Error upgrading client: {any}", .{e});
        return;
    };

    std.log.info("connection upgrade OK", .{});
}

pub fn on_request(r: zap.Request) !void {
    r.setHeader("Cache-Control", "no-cache") catch unreachable;
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    const allocator = gpa.allocator();
    var clues = game.ClueList.init(allocator);
    var board_width: u32 = 0;
    var board_height: u32 = 0;
    try load_board(allocator, "./crossword.map", &board_width, &board_height, &clues);
    game.state = try game.State.init(allocator, board_width, board_height, clues);
    defer game.state.deinit();

    var listener = zap.HttpListener.init(
        .{
            .port = 3010,
            .on_upgrade = on_upgrade,
            .on_request = on_request,
            .max_clients = 1000,
            .max_body_size = 1 * 1024,
            .public_folder = "dist",
            .log = true,
        },
    );
    try listener.listen();
    std.log.info("", .{});
    std.log.info("Connect with browser to http://localhost:3010.", .{});
    std.log.info("Connect to websocket on ws://localhost:3010.", .{});
    std.log.info("Terminate with CTRL+C", .{});

    zap.start(.{
        .threads = 1,
        .workers = 1,
    });
}

const expect = std.testing.expect;

test {
    _ = rect;
}
