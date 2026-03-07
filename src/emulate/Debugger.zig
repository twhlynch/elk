const Debugger = @This();

const std = @import("std");

const Span = @import("../compile/Span.zig");
const Lexer = @import("../compile/parse/Lexer.zig");
const Runtime = @import("Runtime.zig");

pub fn new() Debugger {
    return .{};
}

pub const Command = union(enum) {
    help,
    step_over,
    step_into: struct { count: u16 },
    step_out,
    @"continue",
    registers,
    print: struct { location: Location },
    move: struct { location: Location, value: u16 },
    goto: struct { location: Location.Memory },
    assembly: struct { location: Location.Memory },
    eval: struct { instruction: Span },
    echo: struct { string: Span },
    reset,
    quit,
    exit,
    break_list,
    break_add: struct { location: Location.Memory },
    break_remove: struct { location: Location.Memory },

    pub const Location = union(enum) {
        register: u3,
        memory: Memory,

        pub const Memory = union(enum) {
            pc_offset: i16,
            address: u16,
            label: Label,
        };
    };

    pub const Label = struct {
        name: Span,
        offset: i16,
    };
};

fn parseCommand(string: []const u8) !Command {
    var lexer = Lexer.new(string, false);

    const tag_span = lexer.next() orelse
        return error.EmptyCommand;

    const tag = parseCommandTag(tag_span.view(string)) orelse
        return error.InvalidCommandTag;

    std.debug.print("{t}\n", .{tag});

    return error.Unimplemented;
}

const TAGS: std.EnumArray(
    std.meta.Tag(Command),
    struct { []const []const u8, []const []const u8 },
) = .init(.{
    .help = .{
        &.{ "h", "help", "--help", "-h", ":h", "man", "info", "wtf" },
        &.{},
    },
    .@"continue" = .{
        &.{ "c", "continue", "cont" },
        &.{ "con", "proceed" },
    },
    .print = .{
        &.{ "p", "print" },
        &.{ "get", "show", "display", "put", "puts", "out" },
    },
    .move = .{
        &.{ "m", "move" },
        &.{ "set", "mov", "mv", "assign" },
    },
    .registers = .{
        &.{ "r", "registers", "reg" },
        &.{ "dump", "register", "regs" },
    },
    .goto = .{
        &.{ "g", "goto" },
        &.{ "jump", "call", "go", "go-to", "jsr", "jsrr", "br", "brn", "brz", "brp", "brnz", "brnp", "brzp", "brnzp" },
    },
    .assembly = .{
        &.{ "a", "assembly", "asm" },
        &.{ "source", "src", "ass", "inspect" },
    },
    .eval = .{
        &.{ "e", "eval", "evil", "evaluate" },
        &.{ "run", "exec", "execute", "sim", "simulate", "instruction", "instr" },
    },
    .reset = .{
        &.{ "z", "reset" },
        &.{ "restart", "refresh", "reboot" },
    },
    .echo = .{
        &.{"echo"},
        &.{},
    },
    .quit = .{
        &.{ "q", "quit" },
        &.{},
    },
    .exit = .{
        &.{ "x", "exit", ":q", ":wq", "^C" },
        &.{ "halt", "end", "stop" },
    },
    .step_over = .{
        &.{},
        &.{ "next", "step-over", "stepover" },
    },
    .step_into = .{
        &.{ "si", "stepinto" },
        &.{ "into", "in", "stepin", "step-into", "step-in", "stepi", "step-i", "sin" },
    },
    .step_out = .{
        &.{ "so", "stepout" },
        &.{ "finish", "fin", "out", "step-out", "stepo", "step-o", "sout" },
    },
    .break_list = .{
        &.{ "bl", "breaklist" },
        &.{ "break-list", "break-ls", "blist", "bls", "bp", "breakpoint", "breakpointlist", "breakpoint-list" },
    },
    .break_add = .{
        &.{ "ba", "breakadd" },
        &.{ "break-add", "badd", "breakpointadd", "breakpoint-add" },
    },
    .break_remove = .{
        &.{ "br", "breakremove" },
        &.{ "break-remove", "break-rm", "bremove", "brm", "breakpointremove", "breakpoint-remove" },
    },
});

fn parseCommandTag(string: []const u8) ?std.meta.Tag(Command) {
    for (std.meta.tags(std.meta.Tag(Command))) |tag| {
        const aliases, const misspellings = TAGS.get(tag);
        for (aliases) |alias| {
            if (std.ascii.eqlIgnoreCase(string, alias))
                return tag;
        }
        for (misspellings) |misspelling| {
            if (std.ascii.eqlIgnoreCase(string, misspelling)) {
                std.debug.print("DID YOU MEAN: {s}\n", .{misspelling});
                return null;
            }
        }
    }

    return null;
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
