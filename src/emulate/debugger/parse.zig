const std = @import("std");

const Reporter = @import("../../report/Reporter.zig");
const Span = @import("../../compile/Span.zig");
const Lexer = @import("../../compile/parse/Lexer.zig");
const Command = @import("command.zig").Command;
const tags = @import("tags.zig");

pub fn parseCommand(string: []const u8, reporter: *Reporter) !Command {
    var lexer = Lexer.new(string, false);

    const tag = try parseCommandTag(&lexer, string, reporter);

    std.debug.print("{t}\n", .{tag});

    return error.Unimplemented;
}

fn parseCommandTag(lexer: *Lexer, source: []const u8, reporter: *Reporter) !Command.Tag {
    const first = lexer.next() orelse
        // TODO: Return `null`
        return error.EmptyCommand;

    for (tags.double) |double| {
        if (try findDoubleMatch(double, first, lexer, source, reporter)) |tag|
            return tag;
    }

    return findSingleMatch(&tags.single, first.view(source)) orelse {
        try reporter.report(.debugger_any, .{
            .code = error.InvalidCommand,
            .span = first,
        }).abort();
    };
}

fn findDoubleMatch(
    double: tags.DoubleEntry,
    first: Span,
    lexer: *Lexer,
    source: []const u8,
    reporter: *Reporter,
) !?Command.Tag {
    if (!anyCandidateMatches(double.first, first.view(source)))
        return null;

    const second = lexer.next() orelse
        return double.default orelse {
            try reporter.report(.debugger_any, .{
                .code = error.MissingSubcommand,
                .span = .emptyAt(source.len),
            }).abort();
        };

    return findSingleMatch(&double.second, second.view(source)) orelse {
        try reporter.report(.debugger_any, .{
            .code = error.InvalidSubcommand,
            .span = second,
        }).abort();
    };
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
