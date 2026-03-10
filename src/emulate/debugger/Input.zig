const Input = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const control_code = std.ascii.control_code;

const Runtime = @import("../Runtime.zig");

editor: Editor,

reader: *Io.Reader,
writer: *Io.Writer,

pub fn init(gpa: Allocator, reader: *Io.Reader, writer: *Io.Writer) Input {
    return .{
        .editor = .{
            .live = .{
                .buffer = &.{},
                .length = 0,
            },
            .history = .{
                .store = .empty,
                .gpa = gpa,
            },
            .cursor = 0,
            .scrollback = null,
        },
        .reader = reader,
        .writer = writer,
    };
}

pub fn deinit(input: *Input) void {
    input.editor.history.store.deinit(input.editor.history.gpa);
}

pub fn readLine(input: *Input) ![]const u8 {
    var eof = false;

    while (true) {
        try input.writePrompt();
        try input.writer.flush();

        const control: Runtime.Control = input.handleNextKey() catch |err| switch (err) {
            else => |err2| return err2,
            error.EndOfStream => {
                eof = true;
                break;
            },
        };

        switch (control) {
            .@"continue" => continue,
            .@"break" => break,
        }
    }

    try input.writer.print("\n", .{});
    try input.writer.flush();

    if (eof)
        return error.EndOfStream;

    input.editor.makeLive();
    const line = input.editor.getString();
    input.editor.history.push(line);
    return line;
}

fn handleNextKey(input: *Input) error{ EndOfStream, ReadFailed }!Runtime.Control {
    assert(input.editor.cursor <= input.editor.getString().len);

    const key = try input.readKey() orelse
        return .@"continue";

    switch (key) {
        .enter => return .@"break",
        .eot => return error.EndOfStream,

        .char => |char| input.editor.insert(char),
        .bs => input.editor.remove(),

        .escape => |escape| switch (escape) {
            .cursor_up => input.editor.seekHistory(.backward),
            .cursor_down => input.editor.seekHistory(.forward),
            .cursor_forward => input.editor.seekLine(.right),
            .cursor_back => input.editor.seekLine(.left),
        },
    }
    return .@"continue";
}

const Key = union(enum) {
    char: u8,
    enter,
    eot,
    bs,
    escape: Escape,

    pub const Escape = enum {
        cursor_up,
        cursor_down,
        cursor_forward,
        cursor_back,
    };
};

fn readKey(input: *Input) error{ EndOfStream, ReadFailed }!?Key {
    return switch (try input.readByte()) {
        0x20...0x7e => |char| .{ .char = char },

        '\n' => .enter,
        control_code.eot => .eot,
        control_code.bs, control_code.del => .bs,

        control_code.esc => if (try input.readByte() == '[') {
            const escape: Key.Escape = switch (try input.readByte()) {
                'A' => .cursor_up,
                'B' => .cursor_down,
                'C' => .cursor_forward,
                'D' => .cursor_back,
                else => return null,
            };
            return .{ .escape = escape };
        } else null,

        else => null,
    };
}

fn readByte(input: *Input) error{ EndOfStream, ReadFailed }!u8 {
    var char: u8 = undefined;
    input.reader.readSliceAll(@ptrCast(&char)) catch |err| switch (err) {
        error.EndOfStream => return error.EndOfStream,
        else => return error.ReadFailed,
    };
    return char;
}

fn writePrompt(input: *const Input) !void {
    const prompt = "> ";

    try input.writer.print("\r\x1b[K", .{});
    try input.writer.print("{?:04}", .{input.editor.scrollback});
    try input.writer.print(prompt, .{});
    try input.writer.print("{s}", .{input.editor.getString()});
    try input.writer.print("\x1b[{}G", .{input.editor.cursor + prompt.len + 1 + 4});
}

const Editor = struct {
    live: Live,
    history: History,
    cursor: usize,
    scrollback: ?usize,

    pub fn getString(editor: *const Editor) []const u8 {
        return if (editor.scrollback) |scrollback|
            editor.history.getLast(scrollback)
        else
            editor.live.getString();
    }

    pub fn makeLive(editor: *Editor) void {
        const scrollback = editor.scrollback orelse
            return;

        const historic = editor.history.getLast(scrollback);
        editor.live.copyFrom(historic);
        editor.scrollback = null;
    }

    pub fn resetCursor(editor: *Editor) void {
        editor.cursor = editor.getString().len;
    }

    pub fn clear(editor: *Editor) void {
        editor.live.clear();
        editor.cursor = 0;
    }

    pub fn insert(editor: *Editor, char: u8) void {
        if (editor.live.length >= editor.live.buffer.len)
            return;

        editor.makeLive();
        editor.live.insert(editor.cursor, char);
        editor.cursor += 1;
    }

    pub fn remove(editor: *Editor) void {
        if (editor.cursor == 0)
            return;

        editor.makeLive();
        editor.live.remove(editor.cursor);
        editor.cursor -= 1;
    }

    pub fn seekLine(editor: *Editor, direction: enum { left, right }) void {
        switch (direction) {
            .left => if (editor.cursor > 0) {
                editor.cursor -= 1;
            },
            .right => if (editor.cursor < editor.live.length) {
                editor.cursor += 1;
            },
        }
    }

    pub fn seekHistory(editor: *Editor, direction: enum { backward, forward }) void {
        switch (direction) {
            .backward => {
                if (editor.history.length() == 0)
                    return;
                if (editor.scrollback) |*scrollback| {
                    if (scrollback.* + 1 < editor.history.length())
                        scrollback.* += 1;
                } else {
                    editor.scrollback = 0;
                }
            },
            .forward => {
                const scrollback = editor.scrollback orelse
                    return;
                editor.scrollback = if (scrollback == 0) null else scrollback - 1;
            },
        }
        editor.resetCursor();
    }
};

const Live = struct {
    buffer: []u8,
    length: usize,

    pub fn getString(live: *const Live) []const u8 {
        return live.buffer[0..live.length];
    }

    pub fn copyFrom(live: *Live, string: []const u8) void {
        const length = @min(string.len, live.buffer.len);
        @memcpy(live.buffer[0..length], string[0..length]);
        live.length = length;
    }

    pub fn clear(live: *Live) void {
        live.length = 0;
    }

    pub fn insert(live: *Live, index: usize, char: u8) void {
        assert(live.length < live.buffer.len);
        assert(index <= live.length);

        // Shift characters up
        if (index < live.length) {
            var i = live.length;
            while (i > index) : (i -= 1)
                live.buffer[i] = live.buffer[i - 1];
        }

        live.buffer[index] = char;
        live.length += 1;
    }

    pub fn remove(live: *Live, index: usize) void {
        assert(live.length > 0);
        assert(index <= live.length);

        // Shift characters down
        if (index < live.length) {
            for (index..live.length) |i|
                live.buffer[i - 1] = live.buffer[i];
        }

        live.length -= 1;
    }
};

const History = struct {
    store: std.ArrayList(u8),
    gpa: Allocator,

    fn push(history: *History, line: []const u8) void {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0)
            return;

        // Don't push sequential duplicates
        if (history.store.items.len > 0) {
            if (std.mem.eql(u8, trimmed, history.getLast(0)))
                return;
        }

        history.store.ensureUnusedCapacity(history.gpa, line.len + 1) catch {
            // TODO: Shift items down until enough room is available
            return;
        };

        history.store.appendSliceAssumeCapacity(line);
        history.store.appendAssumeCapacity('\n');
    }

    fn length(history: *const History) usize {
        return std.mem.countScalar(u8, history.store.items, '\n');
    }

    fn getLast(history: *const History, recent_index: usize) []const u8 {
        assert(history.store.items.len > 0);

        var end: usize = history.store.items.len - 1;
        {
            var count: usize = recent_index;
            while (end > 0) : (end -= 1) {
                if (history.store.items[end] == '\n') {
                    if (count == 0)
                        break;
                    count -= 1;
                }
            }
        }

        const slice = history.store.items[0..end];

        return if (std.mem.findScalarLast(u8, slice, '\n')) |start|
            slice[start + 1 ..]
        else
            slice;
    }
};
