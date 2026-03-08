const Debugger = @This();

const std = @import("std");
const control_code = std.ascii.control_code;

const Runtime = @import("../Runtime.zig");
const parseCommand = @import("parse.zig").parseCommand;

pub fn new() Debugger {
    return .{};
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

    const prompt = "> ";

    var length: usize = 0;
    var cursor: usize = 0;

    try runtime.tty.enableRawMode();

    while (true) {
        std.debug.assert(cursor <= length);

        std.debug.print("\r\x1b[K", .{});
        std.debug.print(prompt, .{});
        std.debug.print("{s}", .{buffer[0..length]});
        std.debug.print("\x1b[{}G", .{cursor + prompt.len + 1});

        const char = try runtime.readByte();

        switch (char) {
            '\n' => break,

            control_code.bs,
            control_code.del,
            => if (cursor > 0) {
                // Shift characters down
                if (cursor < length) {
                    for (cursor..length) |i| {
                        buffer[i - 1] = buffer[i];
                    }
                }
                cursor -= 1;
                length -= 1;
            },

            control_code.esc => {
                if (try runtime.readByte() == '[') {
                    const command = try runtime.readByte();
                    switch (command) {
                        'C' => if (cursor < length) {
                            cursor += 1;
                        },
                        'D' => if (cursor > 0) {
                            cursor -= 1;
                        },
                        else => {},
                    }
                }
            },

            0x20...0x7e => if (length < buffer.len) {
                buffer[length] = char;
                length += 1;
                cursor += 1;
            },

            else => {},
        }
    }

    std.debug.print("\n", .{});
    try runtime.tty.disableRawMode();

    return buffer[0..length];
}
