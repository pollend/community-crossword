// MIT License
//
// Copyright (c) 2017 Nikolay Govorov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// https://github.com/ai/nanoid

const std = @import("std");

pub const URL_SAFE = [_]u8{
    '_', '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'g',
    'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
};

// Convenience function that uses a default random number generator
pub fn generate(comptime N: usize, rand: std.Random, alphabet: []const u8) [N]u8 {
    std.debug.assert(alphabet.len <= std.math.maxInt(u8));
    
    const mask = std.math.pow(usize, 2, std.math.log2_int_ceil(usize, alphabet.len)) - 1;
    std.debug.assert(alphabet.len <= mask + 1);
    
    const step_len = @min(32, 8 * N / 5);
    var bytes: [32]u8 = undefined;
    var res: [N]u8 = undefined;
    var index: usize = 0;
    
    while (true) {
        rand.bytes(bytes[0..step_len]);
        for (bytes[0..step_len]) |b| {
            const byte = @as(usize, b) & mask;
            if (alphabet.len > byte) {
                res[index] = alphabet[byte];
                index += 1;
                if (index == res.len) {
                    return res;
                }
            }
        }
    }
    
}


