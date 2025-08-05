const std = @import("std");
const aws = @import("aws");
const nanoid = @import("./nanoid.zig");
const evict_fifo = @import("evict_fifo.zig"); 
const game = @import("game.zig");
pub const SESSION_MAGIC_NUMBER: u32 = 0x1FA1ABCE;

pub const SessionVersion = enum(u32) {
    unknown = 0,
    v0000 = 1, // Initial version
};
pub const SESSION_ID_LENGTH: usize = 8;
pub const NICK_MAX_LENGTH: usize = 64;
pub const MAX_WORD_QUEUE_LENGTH: usize = 32; // maximum number of words to store in the session

pub const FifoSolved = evict_fifo.EvictingFifo(Solved, MAX_WORD_QUEUE_LENGTH);
pub const Solved = struct {
    utc: i64,
    clue: []const u8,
    word: []const u8,

    pub fn deinit(self: *Solved, alloc: std.mem.Allocator) void {
        alloc.free(self.clue);
        alloc.free(self.word);
    }
};

num_clues_solved: u32 = 0,
allocator: std.mem.Allocator,
nick_len: u16 = 0,
nick: [NICK_MAX_LENGTH]u8,
score: u32 = 0,
session_id: [SESSION_ID_LENGTH]u8 = undefined,
words_solved: FifoSolved, 
pub const ProfileSession = @This();

pub fn empty(allocator: std.mem.Allocator) !ProfileSession {
    return ProfileSession {
        .words_solved = FifoSolved.init(),
        .session_id = nanoid.generate(SESSION_ID_LENGTH, std.crypto.random, nanoid.URL_SAFE[0..]), // empty session ID
        .allocator = allocator,
        .nick = undefined,
        .nick_len = 0,
    };
}

pub fn get_nick_name(self: *const ProfileSession) ?[]const u8 {
    if (self.nick_len == 0) {
        return null;
    }
    return self.nick[0..self.nick_len];
}

pub fn commit_profile_s3(
    self: *ProfileSession,
    allocator: std.mem.Allocator,
    bucket: []const u8,
    options: aws.Options
) !void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    self.write(writer.any()) catch |err| {
        std.log.err("Failed to write session data: {any}", .{err});
        return err;
    };

    var key_buf: [64]u8 = undefined;
    const key = try std.fmt.bufPrint(
        key_buf[0..],
        "profile/{s}.profile",
        .{self.session_id },
    );
    const result = aws.Request(aws.services.s3.put_object).call(.{
        .acl = "public-read",
        .bucket = bucket,
        .key = key,
        .content_type = "application/octet-stream",
        .body = buffer.items,
        .storage_class = "STANDARD",
    }, options) catch |err| {
        std.log.err("Failed to upload backup to S3: {any}", .{err});
        return err;
    };
    defer result.deinit();
}

pub fn load_profile_s3(
    allocator: std.mem.Allocator,
    session_id: []const u8,
    bucket: []const u8,
    options: aws.Options,
) !ProfileSession {
    if(session_id.len != SESSION_ID_LENGTH ) {
        return error.InvalidSessionID;
    }
    var key_buf: [64]u8 = undefined;
    const key = try std.fmt.bufPrint(
        key_buf[0..],
        "profile/{s}.profile",
        .{ session_id },
    );
    
    const session_resp = try aws.Request(aws.services.s3.get_object).call(.{
        .bucket = bucket,
        .key = key
    }, options); 
    defer session_resp.deinit();
    
    var stream = std.io.fixedBufferStream(session_resp.response.body orelse "");
    var reader = stream.reader();
    return try ProfileSession.load(allocator, session_id, reader.any());
}


pub fn set_nick_name(
    self: *ProfileSession,
    nick: []const u8,
) !void {
    if (nick.len > NICK_MAX_LENGTH) {
        return error.NickTooLong;
    }
    self.nick_len = @intCast(nick.len);
    @memcpy(self.nick[0..self.nick_len], nick[0..self.nick_len]);
}

pub fn deinit(self: *ProfileSession) void {
    while(self.words_solved.remove()) |solved| {
        var sv = solved;
        sv.deinit(self.allocator);
    }
}

pub fn push_solved_clue(
    self: *ProfileSession,
    cl: *game.Clue 
) !Solved {
    const clue = try self.allocator.dupe(u8, cl.clue[0..]);
    errdefer self.allocator.free(clue);
    const word = try self.allocator.alloc(u8, cl.word.len);
    for (cl.word, 0..) |w,idx| {
        word[idx] = game.Value.value_to_char(w);
    }
    errdefer self.allocator.free(word);
    self.score += game.Value.calculate_score(cl.word);
    self.num_clues_solved += 1;
    errdefer self.allocator.free(word);
    const solved = Solved{
        .utc = std.time.timestamp(),
        .clue = clue,
        .word = word,
    };
    if(self.words_solved.push(solved)) |c| {
        var cc = c;
        cc.deinit(self.allocator);
    }
    return solved;
}

pub fn write(
    self: *ProfileSession,
    writer: std.io.AnyWriter,
) !void {
    try writer.writeInt(u32, SESSION_MAGIC_NUMBER, .little);
    try writer.writeInt(u16, @intFromEnum(SessionVersion.v0000), .little);
    try writer.writeInt(i64, std.time.timestamp(), .little);
    try writer.writeInt(u16, self.nick_len, .little);
    try writer.writeAll(self.nick[0..self.nick_len]);
    try writer.writeInt(u32, self.num_clues_solved, .little);
    try writer.writeInt(u32, self.score, .little);
    const solves_len = self.words_solved.length();
    try writer.writeInt(u16, @intCast(solves_len), .little);
    {
        var i: usize = 0;
        var iter = self.words_solved.iterator();
        while (iter.next()) |it| : (i += 1) {
           try writer.writeInt(i64, it.utc, .little);
           try writer.writeInt(u16, @intCast(it.word.len), .little);
           try writer.writeAll(it.word);
           try writer.writeInt(u16, @intCast(it.clue.len), .little);
           try writer.writeAll(it.clue); 
        }
        std.debug.assert(i == solves_len);
    }
}


pub fn load(
    allocator: std.mem.Allocator,
    session_id: []const u8,
    reader: std.io.AnyReader
) !ProfileSession {
    if (session_id.len != SESSION_ID_LENGTH) {
        return error.InvalidSessionID;
    }

    const magic = try reader.readInt(u32, .little);
    if( magic != SESSION_MAGIC_NUMBER) {
        return error.InvalidSessionData;
    }
    const version: SessionVersion = @enumFromInt(try reader.readInt(u16, .little));
    _ = try reader.readInt(i64, .little);
    switch(version) {
        .v0000 => {
            var session = try ProfileSession.empty(allocator);
            errdefer session.deinit();
            @memcpy(session.session_id[0..], session_id[0..]);

            session.nick_len = try reader.readInt(u16, .little);
            if (session.nick_len > NICK_MAX_LENGTH) {
                return error.NickTooLong;
            }
            if(try reader.readAll(session.nick[0..session.nick_len]) != session.nick_len) {
                return error.EndOfStream;
            }
            session.num_clues_solved = try reader.readInt(u32, .little);
            session.score = try reader.readInt(u32, .little);
            const solves_len = try reader.readInt(u16, .little);
            var i: usize = 0;
            while(i < solves_len) : (i += 1) {
                const utc = try reader.readInt(i64, .little);
                const word_len = try reader.readInt(u16, .little);
                const word = try reader.readAllAlloc(allocator, word_len);
                errdefer allocator.free(word);
                const clue_len = try reader.readInt(u16, .little);
                const clue = try reader.readAllAlloc(allocator, clue_len);
                errdefer allocator.free(clue);
                if(session.words_solved.push(.{
                    .utc = utc,
                    .word = word,
                    .clue = clue,
                })) |c| {
                    var cc = c;
                    cc.deinit(allocator);
                }
            }
            return session; 
        },
        else => {},
    }
    return error.UnsupportedSessionVersion;
}

//pub fn load_session_from_s3(
//    allocator: std.mem.Allocator,
//    s3_client: *std.aws.S3.Client,
//    bucket: []const u8,
//    key: []const u8,
//) !Session {
//    var session = try Session.empty(allocator);
//    const data = try s3_client.getObject(bucket, key);
//    defer data.deinit();
//
//    if (data.len < 8) {
//        return error.InvalidSessionData;
//    }
//
//    const magic_number = @as(u32, @bitCast(data[0..4]));
//    if (magic_number != SESSION_MAGIC_NUMBER) {
//        return error.InvalidSessionData;
//    }
//
//    session.session_id = @as(u64, @bitCast(data[4..12]));
//    
//    // Load nick from the remaining data
//    if (data.len > 12) {
//        session.nick = try allocator.dupe(u8, data[12..]);
//    }
//
//    return session;
//}

//pub fn deinit(self: *Session) void {
//    //if (self.nick) |nick| {
//    //    self.allocator.free(nick);
//    //}
//}


