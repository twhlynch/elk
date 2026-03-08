const Debugger = @This();

const std = @import("std");
const Io = std.Io;
const control_code = std.ascii.control_code;

const Runtime = @import("../Runtime.zig");
const parseCommand = @import("parse.zig").parseCommand;

input: Input,

pub fn new(reader: *Io.Reader, writer: *Io.Writer) Debugger {
    return .{
        .input = .new(reader, writer),
    };
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

const Input = struct {
    // const Io = std.Io;
    const assert = std.debug.assert;

    length: usize,
    cursor: usize,

    reader: *Io.Reader,
    writer: *Io.Writer,

    pub fn new(reader: *Io.Reader, writer: *Io.Writer) Input {
        return .{
            .length = 0,
            .cursor = 0,
            .reader = reader,
            .writer = writer,
        };
    }

    fn clear(input: *Input) void {
        input.length = 0;
        input.cursor = 0;
    }

    pub fn readLine(input: *Input, buffer: []u8) ![]const u8 {
        while (true) {
            try input.writePrompt(buffer);
            try input.writer.flush();

            switch (try input.readLineChar(buffer)) {
                .@"continue" => continue,
                .@"break" => break,
            }
        }

        try input.writer.print("\n", .{});
        try input.writer.flush();

        return buffer[0..input.length];
    }

    fn readLineChar(input: *Input, buffer: []u8) !Runtime.Control {
        assert(input.cursor <= input.length);

        const char = try input.readByte() orelse
            return .@"break";

        switch (char) {
            '\n' => return .@"break",

            control_code.bs,
            control_code.del,
            => if (input.cursor > 0) {
                // Shift characters down
                if (input.cursor < input.length) {
                    for (input.cursor..input.length) |i| {
                        buffer[i - 1] = buffer[i];
                    }
                }
                input.cursor -= 1;
                input.length -= 1;
            },

            control_code.esc => {
                if (try input.readByte() == '[') {
                    const command = try input.readByte() orelse
                        return .@"break";
                    switch (command) {
                        'C' => if (input.cursor < input.length) {
                            input.cursor += 1;
                        },
                        'D' => if (input.cursor > 0) {
                            input.cursor -= 1;
                        },
                        else => {},
                    }
                }
            },

            0x20...0x7e => if (input.length < buffer.len) {
                buffer[input.length] = char;
                input.length += 1;
                input.cursor += 1;
            },

            else => {},
        }

        return .@"continue";
    }

    fn readByte(input: *Input) !?u8 {
        var char: u8 = undefined;
        input.reader.readSliceAll(@ptrCast(&char)) catch |err| switch (err) {
            error.EndOfStream => return null,
            else => return error.ReadFailed,
        };
        return char;
    }

    fn writePrompt(input: *Input, buffer: []u8) !void {
        const prompt = "> ";

        try input.writer.print("\r\x1b[K", .{});
        try input.writer.print(prompt, .{});
        try input.writer.print("{s}", .{buffer[0..input.length]});
        try input.writer.print("\x1b[{}G", .{input.cursor + prompt.len + 1});
    }
};

fn readCommand(debugger: *Debugger, runtime: *Runtime, buffer: []u8) ![]const u8 {
    try runtime.tty.enableRawMode();
    const line = try debugger.input.readLine(buffer);
    try runtime.tty.disableRawMode();
    debugger.input.clear();
    return line;
}
