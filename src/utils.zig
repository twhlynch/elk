const std = @import("std");
const fs = std.fs;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub fn readFile(
    file: fs.File,
    allocator: Allocator,
) !ArrayList(u8) {
    const BUFFER_SIZE = 1024;

    var buffer: [BUFFER_SIZE]u8 = undefined;
    var reader = file.reader(&buffer);

    var string = ArrayList(u8).empty;
    errdefer string.deinit(allocator);

    while (true) {
        const byte = reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => |err2| return err2,
        };
        try string.append(allocator, byte);
    }

    return string;
}
