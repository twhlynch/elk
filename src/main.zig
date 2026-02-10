const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Tokenizer = @import("Tokenizer.zig");
const utils = @import("utils.zig");
const Token = @import("tokens.zig").Token;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = Reporter{};

    const path = "hw.asm";

    const flags: fs.File.OpenFlags = .{};
    const file = try fs.cwd().openFile(path, flags);

    var text = try utils.readFile(file, allocator);
    defer text.deinit(allocator);

    var lines = std.mem.tokenizeAny(u8, text.items, "\r\n");
    while (lines.next()) |line| {
        std.debug.print("-" ** 20 ++ "\n", .{});
        std.debug.print("[{s}]\n", .{line});

        var tokens = Tokenizer.new(line);
        while (tokens.next()) |string| {
            std.debug.print("\t[{s}]", .{string});
            if (Token.from(string)) |token| {
                std.debug.print("\t{f}\n", .{token});
            } else |err| {
                std.debug.print("\n", .{});
                reporter.err(err);
            }
        }

        std.debug.print("\n", .{});
    }
}

pub const Diagnostic = struct {
    string: []const u8,
    code: Token.Error,
};

pub const Reporter = struct {
    const Self = @This();

    pub fn err(self: *Self, code: Token.Error) void {
        _ = self;

        // ??
        var stderr = std.fs.File.stderr();
        const BUFFER_SIZE = 1024;
        var buffer: [BUFFER_SIZE]u8 = undefined;
        var writer = stderr.writer(&buffer);

        writer.interface.print("some error: {t}\n", .{code}) catch unreachable;
        writer.interface.flush() catch unreachable;
    }
};
