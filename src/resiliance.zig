const std = @import("std");


pub const RateLimiterState = enum(u8) {
    refresh,
    timeout,
};
pub fn rate_limiter(comptime limit_for_period: u32, comptime limit_for_refresh_period_ms: u32, comptime timeout_duration_ms: i64) type{
    return struct {
        timestamp: i64 = 0,
        value: u32 = 0,
        state: RateLimiterState = .refresh,

        pub fn input(self: *@This(), value: u32) bool {
            const now = std.time.milliTimestamp();
            if (self.state == .refresh) {
                if (self.value + value > limit_for_period) {
                    self.state = .timeout;
                    self.timestamp = now;
                    return false;
                }
                if(now - self.timestamp >= limit_for_refresh_period_ms) {
                    self.value = 0; 
                    self.timestamp = now; 
                }
                self.value += value;
                return true;
            } else if (self.state == .timeout) {
                if (now - self.timestamp >= timeout_duration_ms) {
                    self.state = .refresh; 
                    self.value = value; 
                    return true;
                }
                return false; 
            }
            return false; 
        }
    };
}




