const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Tokenizer = @import("Tokenizer.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
                std.debug.print("\tERROR: {t}\n", .{err});
            }
        }

        std.debug.print("\n", .{});
    }
}

const Token = union(enum) {
    const Self = @This();

    const assert = std.debug.assert;
    const Io = std.Io;

    comma: void,
    register: u3,
    // TODO:
    // integer: u16,
    string: []const u8,
    directive: Directive,
    instruction: Instruction,
    label: []const u8,

    pub fn from(string: []const u8) !Self {
        assert(string.len > 0);
        if (tryComma(string)) |token| {
            return token;
        }
        if (try tryRegister(string)) |token| {
            return token;
        }
        if (try tryString(string)) |token| {
            return token;
        }
        if (try tryDirective(string)) |token| {
            return token;
        }
        if (try tryInstruction(string)) |token| {
            return token;
        }
        if (try tryLabel(string)) |token| {
            return token;
        }
        return error.InvalidToken;
    }

    fn tryComma(string: []const u8) ?Self {
        if (std.mem.eql(u8, string, ",")) {
            return .{ .comma = void{} };
        } else {
            return null;
        }
    }

    fn tryRegister(string: []const u8) !?Self {
        if (string.len != 2) {
            return null;
        }
        switch (string[0]) {
            'r', 'R' => {},
            else => return null,
        }
        const register: u3 = switch (string[1]) {
            '0'...'7' => |char| @intCast(char - '0'),
            else => return null,
        };
        return .{ .register = register };
    }

    fn tryString(string: []const u8) !?Self {
        if (string.len < 2) {
            return null;
        }
        const has_initial_quote = string[0] == '"';
        const has_final_quote = string[string.len - 1] == '"';
        if (!has_initial_quote and !has_final_quote) {
            return null;
        }
        assert(has_initial_quote and has_final_quote);
        return .{ .string = string[1 .. string.len - 1] };
    }

    fn tryDirective(string: []const u8) !?Self {
        if (string.len < 2 or string[0] != '.') {
            return null;
        }
        const rest = string[1..];
        if (!isIdent(rest)) {
            return error.InvalidIdent;
        }
        for (std.meta.tags(Directive)) |directive| {
            const mnemonic = @tagName(directive);
            if (std.ascii.eqlIgnoreCase(rest, mnemonic)) {
                return .{ .directive = directive };
            }
        }
        return error.InvalidDirective;
    }

    fn tryInstruction(string: []const u8) !?Self {
        assert(string.len > 0);
        for (std.meta.tags(Instruction)) |instruction| {
            const mnemonic = @tagName(instruction);
            if (std.ascii.eqlIgnoreCase(string, mnemonic)) {
                return .{ .instruction = instruction };
            }
        }
        return null;
    }

    fn tryLabel(string: []const u8) !?Self {
        assert(string.len > 0);
        if (!isIdent(string[0..0])) {
            return null;
        }
        if (!isIdent(string)) {
            return error.InvalidIdent;
        }
        return .{ .label = string };
    }

    fn isIdent(string: []const u8) bool {
        for (string, 0..) |char, i| {
            switch (char) {
                'a'...'z', 'A'...'Z', '_' => {},
                '0'...'9' => if (i == 0) return false,
                else => return false,
            }
        }
        return true;
    }

    pub fn format(self: *const Self, writer: *Io.Writer) Io.Writer.Error!void {
        switch (self.*) {
            .comma => {
                try writer.print("comma", .{});
            },
            .register => |register| {
                try writer.print("register R{}", .{register});
            },
            .string => |string| {
                try writer.print("string \"{s}\"", .{string});
            },
            .directive => |directive| {
                try writer.print("directive `{t}`", .{directive});
            },
            .instruction => |instruction| {
                try writer.print("instruction `{t}`", .{instruction});
            },
            .label => |string| {
                try writer.print("label `{s}`", .{string});
            },
        }
    }
};

const Directive = enum {
    ORIG,
    END,
    FILL,
    BLKW,
    STRINGZ,
};

const Instruction = enum {
    // Arithmetic
    ADD,
    AND,
    NOT,
    // Branch / jump
    BR,
    BRN,
    BRZ,
    BRP,
    BRNZ,
    BRZP,
    BRNP,
    BRNZP,
    JMP,
    RET,
    JSR,
    JSRR,
    // Load / store
    LD,
    ST,
    LDI,
    STI,
    LDR,
    STR,
    LEA,
    // Traps
    TRAP,
    GETC,
    OUT,
    PUTS,
    IN,
    PUTSP,
    HALT,
    // Extension traps
    REG,
    DEBUG,
    // Only used in 'supervisor' mode
    RTI,
};
