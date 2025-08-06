const std = @import("std");
const profile_session = @import("profile_session.zig");
const aws = @import("aws");
const game = @import("game.zig");
pub const HIGHSCORE_MAGIC_NUMBER: u32 = 0x48495343; // "HISC"
pub const HighscoreVersion = enum(u16) {
    unknown = 0,
    v0000 = 1, // Initial version
};

pub const Entry = struct {
    session_id: [profile_session.SESSION_ID_LENGTH]u8,
    nick: []const u8,
    last_word: ?[]const game.Value,
    score: u32,
    num_words_solved: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        session_id: []const u8,
        nick: []const u8,
        last_word: ?[]const game.Value,
        score: u32,
        num_clues_solved: u32,
    ) !Entry {
        std.debug.assert(session_id.len == profile_session.SESSION_ID_LENGTH);
        const dup_nick = try allocator.dupe(u8, nick);
        errdefer allocator.free(dup_nick);
        var dup_last_word: ?[]const game.Value = null;
        if (last_word) |word| {
            dup_last_word = try allocator.dupe(game.Value, word);
        }
        errdefer if(dup_last_word) |d| allocator.free(d);

        var entry = Entry{
            .session_id = undefined,
            .nick = dup_nick,
            .last_word = dup_last_word,
            .score = score,
            .num_words_solved = num_clues_solved,
        };
        @memcpy(entry.session_id[0..], session_id[0..]);
        return entry;
    }

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        if (self.last_word) |last_word| {
            allocator.free(last_word);
        }
        allocator.free(self.nick);
    }
};


pub fn FixedHighscoreTable(comptime size: usize) type {
    return struct {
        table: [size]Entry,
        num_entries: usize = 0,
        allocator: std.mem.Allocator,
        lock: std.Thread.Mutex,
        
        const Self = @This();
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .lock = .{},
                .table = undefined,
                .num_entries = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var i: usize = 0;
            while (i < self.num_entries) : (i += 1) {
               self.table[i].deinit(self.allocator); 
            }
        }

        fn find_entry(
            self: *Self,
            session_id: []const u8
        ) ?*Entry {
            var i: usize = 0;
            while(i < self.num_entries) : (i += 1) {
                if (std.mem.eql(u8, self.table[i].session_id[0..], session_id)) {
                    return &self.table[i];
                }
            }
            return null;
        }

        pub fn restore_s3(
            base: []const u8,
            allocator: std.mem.Allocator,
            bucket: []const u8,
            options: aws.Options
        ) !Self {
            var result = Self.init(allocator);
            var key_buf: [64]u8 = undefined;
            const key = try std.fmt.bufPrint(
                key_buf[0..],
                "{s}.priv.highscore", 
                .{base},
            );

            const highscore_data = try aws.Request(aws.services.s3.get_object).call(.{
                .bucket = bucket,
                .key = key
            }, options); 
            defer highscore_data.deinit();
            var stream = std.io.fixedBufferStream(highscore_data.response.body orelse "");
            var reader = stream.reader();
            
            const magic = try reader.readInt(u32, .little);
            if( magic != HIGHSCORE_MAGIC_NUMBER) {
                return error.InvalidHighscoreMagicNumber;
            }
            const version: HighscoreVersion = try reader.readEnum(HighscoreVersion, .little);
            switch(version) {
                .v0000 => {
                    _ = try reader.readInt(i64, .little); // skip timestamp
                    const num: usize = @min(try reader.readInt(u16, .little), size);
                    result.num_entries = num;
                    var i: usize = 0;
                    while(i < num): (i+=1) {
                        const nick_len = try reader.readInt(u16, .little);
                        const nick = try allocator.alloc(u8, nick_len);
                        errdefer allocator.free(nick);
                        if(try reader.readAll(nick) != nick_len){
                            return error.EndOfStream;
                        }

                        var last_word: ?[]game.Value = null;
                        errdefer if(last_word) |l| allocator.free(l);
                        const last_word_len = try reader.readInt(u16, .little);
                        if (last_word_len > 0) {
                            last_word = try allocator.alloc(game.Value, last_word_len);
                            if(try reader.readAll(@as([]u8,@ptrCast(last_word.?[0..]))) != last_word_len) {
                                return error.EndOfStream;
                            }
                        }
                        const score = try reader.readInt(u32, .little);
                        const num_words_solved = try reader.readInt(u32, .little);
                       
                        result.table[i] = .{
                            .session_id = undefined,
                            .nick = nick,
                            .last_word = last_word,
                            .score = score,
                            .num_words_solved = num_words_solved,
                        };
                    }
                    var k: usize = 0;
                    while(k < num) : (k += 1) {
                       if(try reader.readAll(result.table[k].session_id[0..]) != profile_session.SESSION_ID_LENGTH) {
                            return error.InvalidSessionIdLength;
                       }
                    }
                },
                else => return error.UnsupportedHighscoreVersion,
            }
            return result;
        }

        pub fn commit_s3(
            self: *Self,
            base: []const u8,
            allocator: std.mem.Allocator,
            bucket: []const u8,
            options: aws.Options
        ) !void {
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            var writer = buffer.writer();
            
            var key_buf: [64]u8 = undefined;

            try writer.writeInt(u32, HIGHSCORE_MAGIC_NUMBER, .little);
            try writer.writeInt(u16, @intFromEnum(HighscoreVersion.v0000), .little);
            try writer.writeInt(i64, std.time.timestamp(), .little);
            try writer.writeInt(u16, @intCast(self.num_entries), .little);
            {
                var i: usize = 0;
                while (i < self.num_entries) : (i += 1) {
                    const entry = &self.table[i];
                    try writer.writeInt(u16, @intCast(entry.nick.len), .little);
                    try writer.writeAll(entry.nick);
                    if (entry.last_word) |last_word| {
                        try writer.writeInt(u16, @intCast(last_word.len), .little);
                        try writer.writeAll(@as([]const u8,@ptrCast(last_word[0..])));
                    } else {
                        try writer.writeInt(u16, 0, .little);
                    }
                    try writer.writeInt(u32, entry.score, .little);
                    try writer.writeInt(u32, entry.num_words_solved, .little);
                }
            }
            {
                const key = try std.fmt.bufPrint(
                    key_buf[0..],
                    "{s}.highscore",
                    .{base},
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
            {
                var i: usize = 0;
                while (i < self.num_entries) : (i += 1) {
                    const entry = &self.table[i];
                    try writer.writeAll(entry.session_id[0..]);  
                }
                const key = try std.fmt.bufPrint(
                    key_buf[0..],
                    "{s}.priv.highscore", 
                    .{base},
                );
                const result = aws.Request(aws.services.s3.put_object).call(.{
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
        }
        pub fn process(
            self: *Self,
            profile: *profile_session.ProfileSession
        ) !void {
            if(profile.score == 0) {
                return; 
            }
            self.lock.lock();
            defer self.lock.unlock();
            if (self.find_entry(profile.session_id[0..])) |e| {
                e.*.deinit(self.allocator);
                e.* = try Entry.init(
                    self.allocator,
                    profile.session_id[0..],
                    profile.nick.slice(),
                    if(profile.words_solved.last()) |last_word| last_word.word[0..] else null, 
                    profile.score,
                    profile.num_clues_solved,
                );
            } else {
                var i: usize = 0;
                while(i < self.num_entries) : (i += 1) {
                    if(self.table[i].score > profile.score) {
                        continue;
                    } 
                    if(self.num_entries == self.table.len) {
                        // If the table is full, we need to remove the last entry.
                        self.table[self.num_entries - 1].deinit(self.allocator);
                        self.num_entries -= 1;
                    }
                    std.mem.copyForwards(
                        Entry, 
                        self.table[i + 1..self.num_entries + 1],
                        self.table[i..self.num_entries],
                    );
                    self.table[i] = try Entry.init(
                        self.allocator,
                        profile.session_id[0..],
                        profile.nick.slice(),
                        if(profile.words_solved.last()) |last_word| last_word.word[0..] else null, 
                        profile.score,
                        profile.num_clues_solved,
                    );
                    self.num_entries += 1;
                    return;
                }
                if(i < self.table.len) {
                    self.table[i] = try Entry.init(
                        self.allocator,
                        profile.session_id[0..],
                        profile.nick.slice(),
                        if(profile.words_solved.last()) |last_word| last_word.word[0..] else null, 
                        profile.score,
                        profile.num_clues_solved,
                    );
                    self.num_entries += 1;
                } 
            }
        }
    };

}
