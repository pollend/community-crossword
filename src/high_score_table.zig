const std = @import("std");
const profile_session = @import("profile_session.zig");
const aws = @import("aws");
const game = @import("game.zig");
const client = @import("client.zig");
pub const HIGHSCORE_MAGIC_NUMBER: u32 = 0x48495343; // "HISC"
pub const HighscoreVersion = enum(u16) {
    unknown = 0,
    v0000 = 1, // Initial version
    v0001 = 2, // Initial version
};

pub const Entry = struct {
    nick: client.NickBoundedArray,
    last_word_solve: std.BoundedArray(game.Value, 64),
    num_words_solved: u32,
};


pub fn FixedHighscoreTable(comptime size: usize) type {
    return struct {
        keys: [size]u64 = undefined, 
        scores: [size]u32 = undefined, 
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
                .allocator = allocator
            };
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
                "{s}.highscore", 
                .{base},
            );

            const highscore_data = try aws.Request(aws.services.s3.get_object).call(.{
                .bucket = bucket,
                .key = key
            }, options); 
            var stream = std.io.fixedBufferStream(highscore_data.response.body orelse "");
            var reader = stream.reader();
            
            const magic = try reader.readInt(u32, .little);
            if( magic != HIGHSCORE_MAGIC_NUMBER) {
                return error.InvalidHighscoreMagicNumber;
            }
            const version: HighscoreVersion = try reader.readEnum(HighscoreVersion, .little);
            switch(version) {
                .v0001 => {
                    _ = try reader.readInt(i64, .little); // skip timestamp
                    const num: usize = @min(try reader.readInt(u16, .little), size);

                    result.num_entries = num;
                    var i: usize = 0;
                    while(i < num): (i+=1) {
                        const nick_len = try reader.readInt(u16, .little);
                        if(try reader.readAll(result.table[i].nick.buffer[0..nick_len]) != nick_len) {
                            return error.EndOfStream;
                        }
                        result.table[i].nick.len = nick_len;
                        const last_word_len = try reader.readInt(u16, .little);
                        if(try reader.readAll(@ptrCast(result.table[i].last_word_solve.buffer[0..last_word_len])) != last_word_len) {
                            return error.EndOfStream;
                        }
                        result.table[i].last_word_solve.len = last_word_len;
                        result.scores[i] = try reader.readInt(u32, .little);
                        result.table[i].num_words_solved = try reader.readInt(u32, .little);
                        result.keys[i] = try reader.readInt(u64, .little);
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
            self.lock.lock();
            defer self.lock.unlock();

            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            var writer = buffer.writer();
            
            var key_buf: [64]u8 = undefined;

            try writer.writeInt(u32, HIGHSCORE_MAGIC_NUMBER, .little);
            try writer.writeInt(u16, @intFromEnum(HighscoreVersion.v0001), .little);
            try writer.writeInt(i64, std.time.timestamp(), .little);
            try writer.writeInt(u16, @intCast(self.num_entries), .little);
            std.log.info("Committing highscore table with {d} entries", .{self.num_entries});
            {
                var i: usize = 0;
                while (i < self.num_entries) : (i += 1) {
                    const entry = &self.table[i];
                    try writer.writeInt(u16, @intCast(entry.nick.len), .little);
                    try writer.writeAll(entry.nick.slice());
                    try writer.writeInt(u16, @intCast(entry.last_word_solve.len), .little);
                    try writer.writeAll(@ptrCast(entry.last_word_solve.slice()));
                    try writer.writeInt(u32, self.scores[i], .little);
                    try writer.writeInt(u32, entry.num_words_solved, .little);
                    try writer.writeInt(u64, self.keys[i], .little);
                }
            }
        
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

        pub fn update_nick(
            self: *Self,
            profile_id: u64,
            nick: []const u8
        ) void {
            std.debug.assert(nick.len <= client.NICK_MAX_LENGTH);
            self.lock.lock();
            defer self.lock.unlock();
            var found_index: usize = 0; // Find the index of the key
            while(found_index < self.num_entries) : (found_index += 1) {
                if(self.keys[found_index] == profile_id) {
                    self.table[found_index].nick.resize(0) catch unreachable;
                    self.table[found_index].nick.appendSlice(nick) catch unreachable;
                    break;
                }
            }
        }

        pub fn process(
            self: *Self,
            key: u64, 
            nick: []const u8,
            last_word_solve: []game.Value,
            score: u32,
            num_clues_solved: u32,
        ) !void {
            std.debug.assert(nick.len <= client.NICK_MAX_LENGTH); 
            if(score == 0) {
                return; 
            }
            std.log.info("Processing highscore for key {d} with score {d}", .{key, score});
            self.lock.lock();
            defer self.lock.unlock();
            var entry: Entry = .{
                .nick = undefined,
                .last_word_solve = undefined,
                .num_words_solved = num_clues_solved,
            };
            entry.last_word_solve.resize(0) catch unreachable;
            entry.nick.resize(0) catch unreachable;
            entry.nick.appendSlice(nick) catch unreachable;
            entry.last_word_solve.appendSlice(last_word_solve) catch {
                std.log.warn("Failed to append last word", .{}); 
            };
            var insert_index: usize = 0; // Find the index to insert the new entry
            while(insert_index < self.num_entries) : (insert_index += 1) {
                if(self.scores[insert_index] < score) {
                    break;
                } 
            }
            var found_index: usize = 0; // Find the index of the key
            while(found_index < self.num_entries) : (found_index += 1) {
                if(self.keys[found_index] == key) {
                    break;
                }
            }
            if(insert_index == found_index) {
                if(found_index >= self.table.len) {
                    return;
                }
                self.num_entries = @max(self.num_entries, insert_index + 1);
                self.table[insert_index] = entry;
                self.keys[insert_index] = key;
                self.scores[insert_index] = score;
            } else if(insert_index > found_index) {
                std.log.warn("Tampering: Inserting entry with a lower score than existing entry for key {d}", .{key});
            } else {
                found_index = @min(found_index, self.table.len - 1);
                self.num_entries = @max(self.num_entries, found_index + 1);
                std.mem.copyBackwards(
                    Entry, 
                    self.table[insert_index + 1..found_index + 1],
                    self.table[insert_index..found_index],
                );
                std.mem.copyBackwards(
                    u64, 
                    self.keys[insert_index + 1..found_index + 1],
                    self.keys[insert_index..found_index],
                );
                std.mem.copyBackwards(
                    u32, 
                    self.scores[insert_index + 1..found_index + 1],
                    self.scores[insert_index..found_index],
                );
                self.table[insert_index] = entry;
                self.keys[insert_index] = key;
                self.scores[insert_index] = score;
            } 
        }
    };
}

test "Test HighScoreTable" {
    const allocator = std.testing.allocator;
    const TestTable = FixedHighscoreTable(5);
    var table = TestTable.init(allocator);

    // Add some entries
    try table.process(10, "Alice", "HELLO", 100, 5);
    try table.process(20, "Bob", "WORLD", 150, 8);
    try table.process(30, "Charlie", "TEST", 75, 3);

    try std.testing.expectEqualSlices(u64,  &[_]u64{20, 10, 30}, table.keys[0..3]);
    try std.testing.expectEqual(3, table.num_entries);
    try std.testing.expectEqualSlices(u32,  &[_]u32{150, 100, 75}, table.scores[0..3]);

    try table.process(40, "Dave", "ZIG", 200, 10);
    try table.process(50, "Eve", "ZAG", 50, 2);
    try table.process(150, "Eve", "ZAG", 500, 2);
    try std.testing.expectEqualSlices(u64,  &[_]u64{150, 40, 20, 10, 30}, table.keys[0..5]);
    try std.testing.expectEqual(5, table.num_entries);
    try std.testing.expectEqualSlices(u32,  &[_]u32{500, 200, 150, 100, 75}, table.scores[0..5]);
    try std.testing.expectEqualSlices(u8, table.table[0].nick.slice(), "Eve");
    try std.testing.expectEqualSlices(u8, table.table[1].nick.slice(), "Dave");
    try std.testing.expectEqualSlices(u8, table.table[2].nick.slice(), "Bob");
    try std.testing.expectEqualSlices(u8, table.table[3].nick.slice(), "Alice");

    try table.process(40, "Dave", "ZIG", 900, 10);
    try std.testing.expectEqualSlices(u32,  &[_]u32{900, 500, 150, 100, 75}, table.scores[0..5]);
    try std.testing.expectEqualSlices(u64,  &[_]u64{40, 150, 20, 10, 30}, table.keys[0..5]);

    try std.testing.expectEqualSlices(u8, table.table[0].nick.slice(), "Dave");
    try std.testing.expectEqualSlices(u8, table.table[1].nick.slice(), "Eve");
    try std.testing.expectEqualSlices(u8, table.table[2].nick.slice(), "Bob");
    try std.testing.expectEqualSlices(u8, table.table[3].nick.slice(), "Alice");

    try table.process(40, "Dave", "zoe", 20, 10);
    try std.testing.expectEqualSlices(u64,  &[_]u64{40, 150, 20, 10, 30}, table.keys[0..5]);

}
