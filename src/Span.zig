const Span = @This();

const std = @import("std");
const assert = std.debug.assert;

offset: usize,
len: usize,

pub const dummy: Span = .{ .offset = 0, .len = 0 };

pub fn fromBounds(start: usize, end_: usize) Span {
    return .{ .offset = start, .len = end_ - start };
}

pub fn emptyAt(offset: usize) Span {
    return .{ .offset = offset, .len = 0 };
}

pub fn end(span: Span) usize {
    return span.offset + span.len;
}

pub fn in(inner: Span, containing: Span) Span {
    assert(inner.end() < containing.end());
    return .{
        .offset = containing.offset + inner.offset,
        .len = inner.len,
    };
}

pub fn view(span: Span, source: []const u8) []const u8 {
    return source[span.offset..][0..span.len];
}

pub fn getWholeLine(span: Span, source: []const u8) Span {
    assert(span.end() <= source.len);
    { // Newlines may only be present for newline token "\n"
        const newlines = std.mem.countScalar(u8, span.view(source), '\n');
        switch (newlines) {
            0 => {},
            1 => assert(span.len == 1),
            else => unreachable,
        }
    }

    var start = span.offset;
    while (start > 0) : (start -= 1) {
        if (source[start - 1] == '\n')
            break;
    }

    var end_ = span.offset;
    while (end_ < source.len) : (end_ += 1) {
        if (source[end_] == '\n')
            break;
    }

    return .fromBounds(start, end_);
}
