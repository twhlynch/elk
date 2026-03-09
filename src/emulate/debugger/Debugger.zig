const Debugger = @This();

const std = @import("std");
const Io = std.Io;

const Reporter = @import("../../report/Reporter.zig");
const Runtime = @import("../Runtime.zig");
const Input = @import("Input.zig");
const parseCommand = @import("parse.zig").parseCommand;

input: Input,
// TODO: Replace with `status`
eof: bool,
reporter: *Reporter,

pub fn init(
    gpa: std.mem.Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
    reporter: *Reporter,
) Debugger {
    return .{
        .input = .init(gpa, reader, writer),
        .eof = false,
        .reporter = reporter,
    };
}

pub fn deinit(debugger: *Debugger) void {
    debugger.input.deinit();
}

pub fn invoke(debugger: *Debugger, runtime: *Runtime) !?Runtime.Control {
    var command_buffer: [20]u8 = undefined;

    while (!debugger.eof) {
        const command_string = debugger.readCommand(runtime, &command_buffer) catch |err| switch (err) {
            else => |err2| return err2,
            error.EndOfStream => {
                debugger.eof = true;
                break;
            },
        };

        debugger.reporter.source = command_string;

        const command = parseCommand(command_string, debugger.reporter) catch |err| switch (err) {
            error.Reported => continue,
            // TODO: Remove once all command parsing is implemented
            error.Unimplemented => continue,
        } orelse
            continue; // No tokens lexed

        switch (command) {
            // TODO: Implement all commands
            else => {
                std.debug.print("Command: {}\n", .{command});
            },

            .exit => return .@"break",
        }
    }

    return .@"continue";
}

fn readCommand(debugger: *Debugger, runtime: *Runtime, buffer: []u8) ![]const u8 {
    try runtime.tty.enableRawMode();
    const line = debugger.input.readLine(buffer);
    try runtime.tty.disableRawMode();
    debugger.input.clear();
    return line;
}
