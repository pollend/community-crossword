const std = @import("std");
const zap = @import("zap");
const WebSockets = zap.WebSockets;

const Context = struct {
    userName: []const u8,
    channel: []const u8,
    // we need to hold on to them and just re-use them for every incoming
    // connection
    subscribeArgs: WebsocketHandler.SubscribeArgs,
    settings: WebsocketHandler.WebSocketSettings,
};
//
//
const WebsocketHandler = WebSockets.Handler(Context);

fn on_upgrade(r: zap.Request, target_protocol: []const u8) !void {
    // make sure we're talking the right protocol
    if (!std.mem.eql(u8, target_protocol, "websocket")) {
        std.log.warn("received illegal protocol: {s}", .{target_protocol});
        r.setStatus(.bad_request);
        r.sendBody("400 - BAD REQUEST") catch unreachable;
        return;
    }
    //var context = GlobalContextManager.newContext() catch |err| {
    //    std.log.err("Error creating context: {any}", .{err});
    //    return;
    //};

    //try WebsocketHandler.upgrade(r.h, &context.settings);
    std.log.info("connection upgrade OK", .{});
}


pub fn on_request(r: zap.Request) !void {
    r.setHeader("Cache-Control", "no-cache") catch unreachable;
    if (r.sendFile("dist/index.html")) {} else |err| {
        std.log.err("Unable to send file: {any}", .{err});
    }
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    //var gpa = std.heap.GeneralPurposeAllocator(.{
    //    .thread_safe = true,
    //}){};
    //const allocator = gpa.allocator(); 

    // setup listener
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

