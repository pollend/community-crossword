const std = @import("std");
const aws = @import("aws");
const nanoid = @import("./nanoid.zig");
const evict_fifo = @import("evict_fifo.zig"); 
const game = @import("game.zig");
const Aegis256 = std.crypto.aead.aegis.Aegis256;
const zdt = @import("zdt");

pub const SESSION_MAGIC_NUMBER: u32 = 0x1FA1ABCE;

pub const ProfileVersion = enum(u8) {
    unknown = 0,
    v0000 = 1
};
pub const KEY_LENGTH: usize = Aegis256.key_length;
pub const NICK_MAX_LENGTH: usize = 64;
pub const MAX_WORD_QUEUE_LENGTH: usize = 32; // maximum number of words to store in the session

pub const FifoSolved = evict_fifo.EvictingFifo(Solved, MAX_WORD_QUEUE_LENGTH);
pub const Solved = struct {
    utc: i64,
    clue: []const u8,
    word: []const game.Value,

    pub fn deinit(self: *Solved, alloc: std.mem.Allocator) void {
        alloc.free(self.clue);
        alloc.free(self.word);
    }
};

num_clues_solved: u32 = 0,
refresh_offset: u64 = 0,
last_refresh: std.time.Timer = undefined,
max_age: u32 = 0,
score: u32 = 0,
profile_id: u64 = 0,
pub const ProfileSession = @This();

pub fn empty(max_age: u32) ProfileSession {
    return ProfileSession {
        .profile_id =std.crypto.random.int(u64), 
        .last_refresh = std.time.Timer.start() catch unreachable,
        .num_clues_solved = 0,
        .score = 0,
        .max_age = max_age,
    };
}

pub fn update_solved(
    self: *ProfileSession,
    cl: *game.Clue 
) void {
    self.score += game.Value.calculate_score(cl.word);
    self.num_clues_solved += 1;
}

pub fn refresh(self: *ProfileSession) void {
    self.refresh_offset = 0;
    self.last_refresh.reset(); 
}

pub fn is_expired(self: *ProfileSession) bool {
    const age = (self.last_refresh.read() + self.refresh_offset) / std.time.ns_per_s;
    std.debug.print("Profile session age: {d}, max age: {d}\n", .{age, self.max_age});
    if(self.max_age == 0) {
        return false; // no expiration set
    }
    return  age > self.max_age;
}

pub fn parse_cookie(
    allocator: std.mem.Allocator,
    key: [Aegis256.key_length]u8,
    cookie: []const u8
) !ProfileSession {
    var iter = std.mem.splitAny(u8, cookie, ".");
    const data_b64 = iter.next() orelse return error.InvalidCookieFormat;
    const signature_b64 = iter.next() orelse return error.InvalidCookieFormat;

    const b64 = std.base64.url_safe.Decoder;
    var buffer = try allocator.alloc(u8, try b64.calcSizeUpperBound(data_b64.len));
    var deccrypted_buffer = try allocator.alloc(u8, try b64.calcSizeUpperBound(data_b64.len));
    defer allocator.free(buffer);

    var signature: [Aegis256.tag_length + Aegis256.nonce_length]u8 = undefined;
    try b64.decode(&signature, signature_b64);
    try b64.decode(buffer[0..], data_b64);
    
    var tag: [Aegis256.tag_length]u8 = undefined;
    @memcpy(&tag, signature[0..Aegis256.tag_length]);
    var nonce: [Aegis256.nonce_length]u8 = undefined;
    @memcpy(&nonce, signature[Aegis256.tag_length..]);

    var empty_buf: [0]u8 = undefined;
    try Aegis256.decrypt(deccrypted_buffer, buffer[0..], tag, &empty_buf, nonce, key);

    var reader: std.Io.Reader = .fixed(deccrypted_buffer[0..]);
    //var stream = std.Io.fixedBufferStream(deccrypted_buffer[0..]);
    //var reader = stream.reader();
    return try ProfileSession.load_session(&reader);
}


pub fn create_cookie( self: *ProfileSession, allocator: std.mem.Allocator, key: [Aegis256.key_length]u8) ![]u8 {
    //var buffer: std.ArrayList(u8) = .empty; //.init(allocator);
    //defer buffer.deinit(allocator);
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try self.write_session(&writer.writer);
    for(0..32) |_| {
        try writer.writer.writeByte(0);
    }
    // need to pad buffer for Aegis256 encryption
    
    var encrpyted_buffer = try allocator.alloc(u8, writer.written().len);
    defer allocator.free(encrpyted_buffer);

    var tag: [Aegis256.tag_length]u8 = undefined;
    var nonce: [Aegis256.nonce_length]u8 = undefined;
    var empty_buf: [0]u8 = undefined;
    std.crypto.random.bytes(nonce[0..]);
    Aegis256.encrypt(encrpyted_buffer[0..], &tag, writer.written(), &empty_buf, nonce, key);

    var signature_buffer: [Aegis256.tag_length + Aegis256.nonce_length]u8 = undefined;
    @memcpy(signature_buffer[0..Aegis256.tag_length], &tag);
    @memcpy(signature_buffer[Aegis256.tag_length..], &nonce);

    const b64 = std.base64.url_safe.Encoder;
    var cookie_buffer = try allocator.alloc(u8, b64.calcSize(writer.written().len) + b64.calcSize(Aegis256.tag_length + Aegis256.nonce_length) + 1); 
    var offset: usize = 0;
    offset += b64.encode(cookie_buffer[offset..], encrpyted_buffer).len;
    cookie_buffer[offset] = '.';
    offset += 1;
    offset += b64.encode(cookie_buffer[offset..], &signature_buffer).len;
    std.log.debug("Cookie buffer length: {d}, offset: {d}", .{cookie_buffer.len, offset});
    std.debug.assert(offset == cookie_buffer.len);
    return cookie_buffer;
}


pub fn write_session(
    self: *ProfileSession,
    writer: *std.Io.Writer,
) !void {
    try writer.writeByte(@intFromEnum(ProfileVersion.v0000));
    try writer.writeInt(u64, self.profile_id, .little);
    try writer.writeInt(u32, self.max_age, .little);
    try writer.writeInt(u64, self.last_refresh.read() + self.refresh_offset, .little); // last modified timestamp
    try writer.writeInt(u32, self.num_clues_solved, .little);
    try writer.writeInt(u32, self.score, .little);
    std.debug.print("Wrote profile session: {d} with {d} clues solved, score: {d}\n", .{
        self.profile_id,
        self.num_clues_solved,
        self.score,
    });
}


pub fn load_session(
    reader: *std.Io.Reader
) !ProfileSession {
    const version: ProfileVersion = try reader.takeEnum(ProfileVersion, .little);
    switch(version) {
        .v0000 => {
            var session: ProfileSession.ProfileSession = .{};
            session.profile_id  = try reader.takeInt(u64, .little);
            session.max_age = try reader.takeInt(u32, .little);
            session.last_refresh = std.time.Timer.start() catch unreachable;
            session.refresh_offset = try reader.takeInt(u64, .little);
            session.num_clues_solved = try reader.takeInt(u32, .little);
            session.score = try reader.takeInt(u32, .little);
            return session; 
        },
        else => {},
    }
    return error.UnsupportedSessionVersion;
}

test "serialize and deserialize" {
    const allocator = std.testing.allocator;
    var session = ProfileSession.empty(10);
   
    var clue = try game.Clue.init_from_ascii(
        allocator,
        "test",
        "A test clue",
        .{0,0},
        .Across
    );
    defer clue.deinit();
    session.update_solved(&clue);
    
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    try session.write_session(writer.any());

    var stream = std.io.fixedBufferStream(buffer.items);
    var reader = stream.reader();
    
    const loaded_session = try ProfileSession.load_session(reader.any());

    try std.testing.expectEqual(session.profile_id, loaded_session.profile_id);
    try std.testing.expectEqual(session.num_clues_solved, loaded_session.num_clues_solved);
    try std.testing.expectEqual(session.score, loaded_session.score);
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
//    session.profile_id = @as(u64, @bitCast(data[4..12]));
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


