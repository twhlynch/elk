const Debugger = @This();

const std = @import("std");

const Span = @import("../../compile/Span.zig");
const Lexer = @import("../../compile/parse/Lexer.zig");
const Runtime = @import("../Runtime.zig");
const Command = @import("command.zig").Command;
const tags = @import("tags.zig");

pub fn new() Debugger {
    return .{};
}

fn parseCommand(string: []const u8) !Command {
    var lexer = Lexer.new(string, false);

    const tag = try parseCommandTag(&lexer, string);

    std.debug.print("{t}\n", .{tag});

    return error.Unimplemented;
}

fn parseCommandTag(lexer: *Lexer, source: []const u8) !Command.Tag {
    const first = lexer.next() orelse
        return error.EmptyCommand;
    for (tags.double) |double| {
        if (try findDoubleMatch(double, first, lexer, source)) |tag|
            return tag;
    }
    return findSingleMatch(&tags.single, first.view(source)) orelse
        error.InvalidCommand;
}

fn findDoubleMatch(
    double: tags.DoubleEntry,
    first: Span,
    lexer: *Lexer,
    source: []const u8,
) !?Command.Tag {
    if (!anyCandidateMatches(double.first, first.view(source)))
        return null;
    const second = lexer.next() orelse
        return double.default orelse error.MissingSubcommand;
    return findSingleMatch(&double.second, second.view(source)) orelse
        error.InvalidSubcommand;
}

fn findSingleMatch(singles: *const tags.SingleMap, string: []const u8) ?Command.Tag {
    for (std.meta.tags(Command.Tag)) |tag| {
        if (anyCandidateMatches(singles.get(tag).aliases, string))
            return tag;
    }
    for (std.meta.tags(Command.Tag)) |tag| {
        if (anyCandidateMatches(singles.get(tag).suggestions, string)) {
            // TODO: Report
            std.debug.print("HELP: DID YOU MEAN: {s}\n", .{Command.tagString(tag)});
            return null;
        }
    }
    return null;
}

fn anyCandidateMatches(candidates: []const []const u8, string: []const u8) bool {
    for (candidates) |candidate| {
        if (std.ascii.eqlIgnoreCase(string, candidate))
            return true;
    }
    return false;
}

pub fn invoke(debugger: *Debugger, runtime: *Runtime) !?Runtime.Control {
    std.debug.print("[INVOKE DEBUGGER]\n", .{});

    var command_buffer: [20]u8 = undefined;

    while (true) {
        std.debug.print("\n", .{});

        const command_string = try debugger.readCommand(runtime, &command_buffer);

        const command = parseCommand(command_string) catch |err| {
            std.debug.print("Error: {t}\n", .{err});
            continue;
        };

        std.debug.print("Command: {}\n", .{command});
        return null;
    }
}

fn readCommand(debugger: *Debugger, runtime: *Runtime, buffer: []u8) ![]const u8 {
    _ = debugger;

    var length: usize = 0;

    try runtime.tty.enableRawMode();

    while (true) {
        std.debug.print("\r\x1b[K", .{});
        std.debug.print("> {s}", .{buffer[0..length]});

        const char = try runtime.readByte();

        switch (char) {
            '\n' => break,

            std.ascii.control_code.bs,
            std.ascii.control_code.del,
            => if (length > 0) {
                length -= 1;
            },

            else => if (length < buffer.len) {
                buffer[length] = char;
                length += 1;
            },
        }
    }

    std.debug.print("\n", .{});
    try runtime.tty.disableRawMode();

    return buffer[0..length];
}
