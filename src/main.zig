const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Tokenizer = @import("Tokenizer.zig");
const Token = @import("tokens.zig").Token;

pub fn main(init: std.process.Init) !void {
    const io, const gpa = .{ init.io, init.gpa };

    var reporter = Reporter.new(io);
    try reporter.init();

    const path = "hw.asm";

    const text = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(text);

    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
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

    const BUFFER_SIZE = 1024;

    file: Io.File,
    buffer: [BUFFER_SIZE]u8,
    writer: Io.File.Writer,
    io: Io,

    pub fn new(io: Io) Self {
        return .{
            .io = io,
            .file = undefined,
            .buffer = undefined,
            .writer = undefined,
        };
    }

    pub fn init(self: *Self) !void {
        self.file = std.Io.File.stderr();
        self.writer = self.file.writer(self.io, &self.buffer);
    }

    pub fn err(self: *Self, code: Token.Error) void {
        self.writer.interface.print("some error: {t}\n", .{code}) catch
            unreachable;
        self.writer.interface.flush() catch
            unreachable;
    }
};
