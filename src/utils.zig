const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn readFile(
    io: Io,
    file: Io.File,
    allocator: Allocator,
) !ArrayList(u8) {
    const BUFFER_SIZE = 1024;

    var buffer: [BUFFER_SIZE]u8 = undefined;
    var reader = file.reader(io, &buffer);

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
