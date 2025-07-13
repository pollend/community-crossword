const std = @import("std");
const zap = @import("zap");
const client = @import("client.zig");
const WebSockets = zap.WebSockets;
const game = @import("game.zig");

const WebsocketHandler = WebSockets.Handler(client.Client);

pub const ClientArrayList = std.ArrayList(*client.Client);

pub var client_id: u32 = 0;
pub var clients: ClientArrayList = undefined;
pub var client_lock: std.Thread.Mutex = .{};
pub var allocator: std.mem.Allocator = undefined;
pub var board: game.Board = undefined;
