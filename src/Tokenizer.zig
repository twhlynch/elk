const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

text: []const u8,
index: usize,

pub fn new(text: []const u8) Self {
    return Self{
        .text = text,
        .index = 0,
    };
}

pub fn next(self: *Self) ?[]const u8 {
    // Skip whitespace
    while (self.peekChar()) |char| {
        if (!char.isWhitespace()) {
            break;
        }
        _ = self.takeChar();
    }

    const start = self.getIndex();
    const first = self.takeChar() orelse {
        return null;
    };

    assert(!first.isWhitespace());
    if (first.value == ';') {
        return null;
    }
    if (first.isAtomic()) {
        return self.text[start..self.getIndex()];
    }

    if (first.value == '"') {
        // String literal
        var is_escaped = false;
        while (self.takeChar()) |char| {
            if (!is_escaped) {
                is_escaped = false;
                continue;
            }
            switch (char.value) {
                '"' => break,
                '\\' => is_escaped = true,
                else => {},
            }
        }
    } else {
        // Normal token
        while (self.peekChar()) |char| {
            if (char.isWhitespace() or char.isAtomic()) {
                break;
            }
            _ = self.takeChar();
        }
    }

    return self.text[start..self.getIndex()];
}

fn peekChar(self: *Self) ?TokenChar {
    if (self.isEnd()) {
        return null;
    }
    return TokenChar.from(self.text[self.index]);
}

fn takeChar(self: *Self) ?TokenChar {
    const char = self.peekChar() orelse {
        return null;
    };
    self.index += 1;
    return char;
}

fn getIndex(self: *const Self) usize {
    return self.index;
}

fn isEnd(self: *const Self) bool {
    return self.index >= self.text.len;
}

const TokenChar = struct {
    value: u8,

    pub const Kind = enum {
        atomic,
        combining,
        whitespace,
        control,
    };

    pub fn from(value: u8) TokenChar {
        return TokenChar{ .value = value };
    }

    pub fn kind(self: TokenChar) Kind {
        return switch (self.value) {
            ' ', '\t'...'\r' => .whitespace,
            0x00...0x08, 0x0e...0x1f, 0x7f => .control,
            ',' => .atomic,
            else => .combining,
        };
    }

    pub fn isWhitespace(self: TokenChar) bool {
        return self.kind() == .whitespace;
    }

    pub fn isAtomic(self: TokenChar) bool {
        return self.kind() == .atomic;
    }
};
