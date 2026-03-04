// TODO: Rename
const Impl = @This();

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const Reporter = @import("Reporter.zig");
const Ctx = @import("Ctx.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;

source: ?[]const u8,
writer: *Io.Writer,

pub fn new(writer: *Io.Writer) Impl {
    return .{
        .source = null,
        .writer = writer,
    };
}

pub fn interface(impl: *Impl) Reporter {
    return .fromImplementation(impl, &.{
        .showReport = showReport,
        .showSummary = showSummary,
    });
}

pub fn setSource(impl: *Impl, source: []const u8) void {
    assert(impl.source == null);
    impl.source = source;
}

pub fn showReport(
    ptr: *anyopaque,
    diag: Diagnostic,
    options: Reporter.Options,
    level: Reporter.Level,
) void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));

    var ctx_items: usize = 0;
    const ctx: Ctx = .new(impl, options, level, &ctx_items);
    const source = impl.source orelse
        unreachable;

    diag.print(ctx, source);
    ctx.flush();
}

pub fn showSummary(
    ptr: *anyopaque,
    count: *const std.EnumArray(Reporter.Level, usize),
    options: Reporter.Options,
) void {
    const impl: *Impl = @ptrCast(@alignCast(ptr));

    const count_err = count.get(.err);
    const count_warn = count.get(.warn);

    const ctx: Ctx = .new(impl, options, .warn, null);

    if (count_err > 0) {
        ctx.print("\x1b[31m", .{});
        ctx.print("{} errors", .{count_err});
        ctx.print("\x1b[0m", .{});
        ctx.print("\n", .{});
    }

    if (count_warn > 0) {
        ctx.print("\x1b[33m", .{});
        ctx.print("{} warnings", .{count_warn});
        ctx.print("\x1b[0m", .{});
        ctx.print("\n", .{});
    }

    ctx.flush();
}
