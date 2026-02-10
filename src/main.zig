const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tokenizer = @import("Tokenizer.zig");
const utils = @import("utils.zig");
const Token = @import("tokens.zig").Token;

pub fn main(init: std.process.Init) !void {
    const io, const gpa = .{ init.io, init.gpa };

    var reporter = Reporter{ .io = io };

    const path = "hw.asm";

    const flags: Io.File.OpenFlags = .{};
    const file = try Io.Dir.cwd().openFile(io, path, flags);

    var text = try utils.readFile(io, file, gpa);
    defer text.deinit(gpa);

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

    io: Io,

    pub fn err(self: *Self, code: Token.Error) void {

        // ??
        var stderr = std.Io.File.stderr();
        const BUFFER_SIZE = 1024;
        var buffer: [BUFFER_SIZE]u8 = undefined;
        var writer = stderr.writer(self.io, &buffer);

        writer.interface.print("some error: {t}\n", .{code}) catch unreachable;
        writer.interface.flush() catch unreachable;
    }
};
