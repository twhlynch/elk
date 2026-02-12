const Parser = @This();

const std = @import("std");
const assert = std.debug.assert;

const Air = @import("Air.zig");
const Statement = Air.Line.Statement;
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");
const Span = @import("Span.zig");
const Integer = @import("integers.zig").Integer;
const Reporter = @import("Reporter.zig");

source: []const u8,
reporter: *Reporter,
air: *Air,
tokens: Tokenizer,
current_label: ?Span,

pub fn new(air: *Air, source: []const u8, reporter: *Reporter) Parser {
    return .{
        .source = source,
        .reporter = reporter,
        .air = air,
        .tokens = Tokenizer.new(source),
        .current_label = null,
    };
}

pub fn resolveLabels(parser: *Parser) void {
    // Bruh.
    // TODO: Literally just do this manually.
    for (parser.air.lines.items) |*line| {
        inline for (std.meta.tags(std.meta.Tag(Statement)), 0..) |tag, i| {
            if (tag == line.statement) {
                const variant = @typeInfo(Statement).@"union".fields[i];
                switch (@typeInfo(variant.type)) {
                    .@"struct" => |payload| {
                        assert(line.statement != .raw_word);
                        inline for (payload.fields) |field| {
                            switch (field.type) {
                                Statement.Label => {
                                    parser.resolveFieldLabel(
                                        &@field(
                                            @field(line.statement, variant.name),
                                            field.name,
                                        ),
                                    );
                                },
                                else => {},
                            }
                        }
                    },
                    .int => assert(line.statement == .raw_word),
                    else => unreachable,
                }
                break;
            }
        }
    }
}

fn resolveFieldLabel(parser: *Parser, field: *Statement.Label) void {
    for (parser.air.lines.items, 0..) |*line, index| {
        const label = line.label orelse
            continue;
        // TODO: should it be case insensitive ?
        if (!std.mem.eql(
            u8,
            label.resolve(parser.source),
            field.unresolved.resolve(parser.source),
        ))
            continue;

        field.* = .{ .index = @intCast(index) };
    }
}

pub fn parse(parser: *Parser) !void {
    while (true) {
        const control = parser.parseLine() catch |err| switch (err) {
            error.Reported => {
                parser.discardRestOfLine();
                continue;
            },
            error.Eof => {
                parser.reporter.err(error.ExpectedEnd, .emptyAt(parser.source.len)) catch
                    {}; // Ignore
                break;
            },
            error.OutOfMemory => |other| return other,
        };

        switch (control) {
            .@"continue" => continue,
            .@"break" => break,
        }
    }
}

fn discardRestOfLine(parser: *Parser) void {
    while (true) {
        const token = parser.nextToken(&.{.comma}) catch |err| switch (err) {
            // Ignore any other errors on this line
            error.Reported => continue,
        };
        if (token == null or token.?.kind == .newline)
            break;
    }
}

const Control = enum { @"continue", @"break" };

fn parseLine(parser: *Parser) !Control {
    const token = try parser.nextToken(&.{ .comma, .newline }) orelse
        return error.Eof;

    switch (token.kind) {
        .label => {
            parser.expectNoCurrentLabel();
            parser.current_label = token.span;
        },

        .directive => |directive| {
            return try parser.parseDirective(directive);
        },

        .instruction => |instruction| {
            const statement = try parser.parseInstruction(instruction) orelse
                return error.Reported;
            const span: Span = .fromBounds(
                token.span.offset,
                parser.tokens.index,
            );
            try parser.appendLine(statement, span);
        },

        else => {
            // TODO:
            std.log.warn("unhandled token: {s}", .{token.span.resolve(parser.source)});
        },
    }
    return .@"continue";
}

fn parseDirective(
    parser: *Parser,
    directive: Token.Kind.Directive,
) !Control {
    switch (directive) {
        .end => {
            parser.expectNoCurrentLabel();
            return .@"break";
        },

        .orig => {
            parser.expectNoCurrentLabel();
            if (parser.current_label) |label| {
                try parser.reporter.err(error.UnusedLabel, label);
            }
            const origin = try parser.expectTokenKind(.word);
            if (parser.air.lines.items.len > 0) {
                try parser.reporter.err(error.LateOrigin, origin.span);
            }
            if (parser.air.origin != null) {
                try parser.reporter.err(error.MultipleOrigins, origin.span);
            }
            parser.air.origin = origin.value.asUnsigned() orelse {
                try parser.reporter.err(error.IntegerTooLarge, origin.span);
            };
        },

        .stringz => {
            const string = try parser.expectTokenKind(.string);
            var is_escaped = false;
            for (string.value) |char| {
                if (!is_escaped and char == '\\') {
                    is_escaped = true;
                    continue;
                }
                const char_escaped: u8 =
                    if (!is_escaped) char else switch (char) {
                        '\\' => '\\',
                        '"' => '"',
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        else => {
                            parser.reporter.err(error.InvalidEscapeSequence, string.span) catch
                                {}; // Keep parsing string
                            is_escaped = false;
                            continue;
                        },
                    };
                is_escaped = false;
                try parser.appendLine(
                    .{ .raw_word = char_escaped },
                    string.span,
                );
            }
        },

        else => {
            // TODO:
            std.log.warn("unimplemented directive: {t}", .{directive});
        },
    }

    return .@"continue";
}

fn parseInstruction(
    parser: *Parser,
    instruction: Token.Kind.Instruction,
) !?Statement {
    const regular_instructions = [_]Token.Kind.Instruction{
        .add,
        .lea,
    };
    const trap_instructions = [_]struct { Token.Kind.Instruction, Statement.TrapVect }{
        .{ .puts, 0x22 },
        .{ .halt, 0x25 },
    };

    inline for (regular_instructions) |regular| {
        if (instruction == regular) {
            const Payload = @FieldType(Statement, @tagName(regular));
            var payload: Payload = undefined;

            inline for (@typeInfo(Payload).@"struct".fields) |field| {
                const kind = switch (field.type) {
                    Statement.Register => .register,
                    Statement.Label => .label,
                    Statement.RegImm5 => .reg_imm5,
                    else => comptime unreachable,
                };

                const token = try parser.expectTokenKind(kind);
                @field(payload, field.name) = token.value;
            }

            return @unionInit(Statement, @tagName(regular), payload);
        }
    }

    inline for (trap_instructions) |pair| {
        const trap, const vect = pair;
        if (instruction == trap) {
            return .{ .trap = .{ .vect = vect } };
        }
    }

    // TODO: Replace with `unreachable` and to remove `?` from return type
    return null;
}

fn expectNoCurrentLabel(parser: *Parser) void {
    if (parser.current_label) |label| {
        parser.reporter.err(error.UnusedLabel, label) catch
            {}; // Ignore; caller can continue parsing line
    }
}

fn appendLine(parser: *Parser, statement: Statement, span: Span) !void {
    try parser.air.lines.append(parser.air.allocator, .{
        .label = parser.current_label,
        .statement = statement,
        .span = span,
    });
    parser.current_label = null;
}

fn nextToken(
    parser: *Parser,
    comptime skip: []const std.meta.Tag(Token.Kind),
) error{Reported}!?Token {
    token: while (true) {
        const span = parser.tokens.next() orelse
            return null;
        const token = Token.from(span, parser.source) catch |err| {
            try parser.reporter.err(err, span);
        };
        for (skip) |skip_kind| {
            if (token.kind == skip_kind)
                continue :token;
        }
        return token;
    }
}

fn expectToken(parser: *Parser) !Token {
    const token = try parser.nextToken(&.{.comma}) orelse {
        try parser.reporter.err(error.UnexpectedEof, .emptyAt(parser.source.len));
    };
    switch (token.kind) {
        .newline => {
            try parser.reporter.err(error.UnexpectedEol, .emptyAt(token.span.offset));
        },
        .comma => unreachable,
        else => return token,
    }
}

fn expectTokenKind(
    parser: *Parser,
    comptime kind: @EnumLiteral(),
) !struct {
    span: Span,
    value: ExpectTokenKind(kind),
} {
    const token = try parser.expectToken();
    assert(token.kind != .comma);
    const value_opt: ?ExpectTokenKind(kind) = switch (kind) {
        .register => switch (token.kind) {
            .register => |register| register,
            else => null,
        },
        .reg_imm5 => switch (token.kind) {
            .register => |register| .{ .register = register },
            .integer => |integer| .{
                .immediate = integer.castTo(u5) orelse {
                    try parser.reporter.err(error.IntegerTooLarge, token.span);
                },
            },
            else => null,
        },
        .imm5 => switch (token.kind) {
            .integer => |integer| integer.castTo(u5) orelse {
                try parser.reporter.err(error.IntegerTooLarge, token.span);
            },
            else => null,
        },
        .word => switch (token.kind) {
            .integer => |integer| integer,
            else => null,
        },
        .label => switch (token.kind) {
            .label => .{ .unresolved = token.span },
            else => null,
        },
        .string => switch (token.kind) {
            .string => |string| string,
            else => null,
        },
        else => comptime unreachable,
    };
    const value = value_opt orelse {
        try parser.reporter.err(error.UnexpectedTokenKind, token.span);
    };
    return .{
        .span = token.span,
        .value = value,
    };
}

fn ExpectTokenKind(comptime kind: @EnumLiteral()) type {
    return switch (kind) {
        .register => Statement.Register,
        .reg_imm5 => Statement.RegImm5,
        .imm5 => u5,
        .word => Integer(16),
        .label => Statement.Label,
        .string => []const u8,
        else => @compileError("unsupported token kind `." ++ @tagName(kind) ++ "`"),
    };
}
