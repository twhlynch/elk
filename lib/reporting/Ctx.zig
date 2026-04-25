const Ctx = @This();

const std = @import("std");
const Io = std.Io;

const Span = @import("../compile/Span.zig");
const Parser = @import("../compile/parse/Parser.zig");
const Token = @import("../compile/parse/Token.zig");
const DebuggerCommand = @import("../emulate/debugger/Command.zig");
const reporting = @import("reporting.zig");
const Reporter = reporting.Reporter;
const Verbosity = reporting.Options.Verbosity;
const Level = reporting.Level;
const diagnostic = @import("diagnostic.zig");
const Diagnostic = diagnostic.Diagnostic;
const TokenKinds = diagnostic.TokenKinds;

writer: *Io.Writer,
verbosity: Verbosity,
level: ?Level,
depth: usize,
item_count: ?*usize,
source: ?[]const u8,

const indent_width = 4;

pub fn new(
    writer: *Io.Writer,
    verbosity: Verbosity,
    level: ?Level,
    item_count: ?*usize,
    source: ?[]const u8,
) Ctx {
    return .{
        .writer = writer,
        .verbosity = verbosity,
        .level = level,
        .depth = 0,
        .item_count = item_count,
        .source = source,
    };
}

fn deepen(ctx: Ctx) Ctx {
    var new_ctx = ctx;
    new_ctx.depth += 1;
    return new_ctx;
}

fn withSource(ctx: Ctx, source: []const u8) Ctx {
    var new_ctx = ctx;
    new_ctx.source = source;
    return new_ctx;
}

fn incrementItemCount(ctx: *const Ctx) void {
    if (ctx.item_count) |count|
        count.* += 1;
}

fn printDepth(ctx: Ctx) error{WriteFailed}!void {
    for (0..ctx.depth) |_|
        try ctx.writer.print(" " ** indent_width, .{});
}

fn printTitle(
    ctx: Ctx,
    comptime fmt: []const u8,
    args: anytype,
) error{WriteFailed}!void {
    defer ctx.incrementItemCount();

    const level = ctx.level orelse
        unreachable;
    try ctx.printDepth();
    switch (level) {
        .err => {
            try ctx.writer.print("\x1b[31m", .{});
            try ctx.writer.print("\x1b[1m", .{});
            try ctx.writer.print("Error: ", .{});
            try ctx.writer.print("\x1b[0m", .{});
        },
        .warn => {
            try ctx.writer.print("\x1b[33m", .{});
            try ctx.writer.print("\x1b[1m", .{});
            try ctx.writer.print("Warning: ", .{});
            try ctx.writer.print("\x1b[0m", .{});
        },
        .info => {
            try ctx.writer.print("\x1b[34m", .{});
            try ctx.writer.print("\x1b[1m", .{});
            try ctx.writer.print("Info: ", .{});
            try ctx.writer.print("\x1b[0m", .{});
        },
    }

    try ctx.writer.print(fmt, args);

    switch (ctx.verbosity) {
        .normal => {
            try ctx.writer.print("\n", .{});
        },
        .quiet => {},
    }
}

fn printNote(ctx: Ctx, comptime fmt: []const u8, args: anytype) error{WriteFailed}!void {
    defer ctx.incrementItemCount();

    switch (ctx.verbosity) {
        .normal => {},
        .quiet => return,
    }

    try ctx.printDepth();
    try ctx.writer.print("\x1b[36m", .{});
    try ctx.writer.print("Note: ", .{});
    try ctx.writer.print("\x1b[0m", .{});
    try ctx.writer.print(fmt, args);
    try ctx.writer.print("\n", .{});
}

fn printSourceNote(
    ctx: Ctx,
    comptime fmt: []const u8,
    args: anytype,
    span: Span,
) error{WriteFailed}!void {
    try ctx.printNote(fmt ++ ": ", args);
    try ctx.printSource(span);
}

fn printSource(ctx: Ctx, span: Span) error{WriteFailed}!void {
    const source = ctx.source orelse
        unreachable;

    switch (ctx.verbosity) {
        .normal => {},
        .quiet => {
            // Scuffed!
            if (if (ctx.item_count) |count| count.* > 2 else true)
                return;

            const start_line = span.getLineNumber(source);
            const end_line = span.getEndLineNumber(source);
            const start_column = span.getColumnNumber(source);
            const end_column = span.getEndColumnNumber(source);

            try ctx.writer.print(" (Line {}:{}-{}:{})", .{
                start_line, start_column, end_line, end_column,
            });
            try ctx.writer.print("\n", .{});
            return;
        },
    }

    try reporting.writeSpanContext(ctx.writer, span, .{
        .indent = ctx.depth * indent_width,
        .max_line_width = 90,
    }, source);
}

pub fn printDiagnostic(ctx: Ctx, diag: Diagnostic) error{WriteFailed}!void {
    const source = ctx.source orelse
        unreachable;

    switch (diag) {
        .invalid_source_byte => |info| {
            try ctx.printTitle("Assembly file contains invalid bytes", .{});
            try ctx.deepen().printSourceNote("Byte", .{}, .{ .offset = info.byte, .len = 1 });
            try ctx.deepen().printNote("Assembly file must only contain printable ASCII characters", .{});
            try ctx.deepen().printNote("The assembler cannot read object files", .{});
        },
        .output_too_long => |info| {
            try ctx.printTitle("Assembly file would emit too many words", .{});
            try ctx.deepen().printSourceNote("Line", .{}, info.statement);
            try ctx.deepen().printNote("Object files cannot contain more than 0xffff words", .{});
        },
        .line_too_long => |info| {
            try ctx.printTitle("Line is longer than {} characters", .{Parser.max_line_width});
            try ctx.deepen().printSourceNote("Characters past column limit", .{}, info.overflow);
        },

        .invalid_token => |info| {
            try ctx.printTitle("Invalid token", .{});
            try ctx.deepen().printSourceNote("Token", .{}, info.token);
            if (info.guess) |kind|
                try ctx.deepen().printNote("Cannot parse as {s}", .{TokenKinds.name(kind)})
            else
                try ctx.deepen().printNote("Cannot parse as any valid token", .{});
        },
        .unexpected_token_kind => |info| {
            try ctx.printTitle("Unexpected {s}", .{TokenKinds.name(info.found.value)});
            try ctx.deepen().printSourceNote("Token", .{}, info.found.span);
            try ctx.deepen().printNote("Expected {f}", .{TokenKinds{ .kinds = info.expected }});
        },
        .unexpected_eol => |info| {
            try ctx.printTitle("Unexpected end of line", .{});
            try ctx.deepen().printSourceNote("Line ends too early", .{}, info.eol);
            try ctx.deepen().printNote("Expected {f}", .{TokenKinds{ .kinds = info.expected }});
            try ctx.deepen().printNote("Instructions cannot span multiple lines", .{});
        },
        .expected_eol => |info| {
            try ctx.printTitle("Unexpected {s}", .{TokenKinds.name(info.found.value)});
            try ctx.deepen().printSourceNote("Token", .{}, info.found.span);
            try ctx.deepen().printNote("Expected end of line", .{});
        },
        .missing_operand_comma => |info| {
            try ctx.printTitle("Missing comma `,` after operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.operand);
            try ctx.deepen().printNote("Operands should be separated with commas", .{});
        },
        .whitespace_comma => |info| {
            try ctx.printTitle("Unexpected comma `,`", .{});
            try ctx.deepen().printSourceNote("Comma", .{}, info.comma);
            try ctx.deepen().printNote("Commas should only appear between instruction operands", .{});
        },
        .unconventional_case => |info| switch (info.kind) {
            .mnemonic => {
                try ctx.printTitle("Instruction mnemonic is not lowercase", .{});
                try ctx.deepen().printSourceNote("Mnemonic", .{}, info.token);
            },
            .trap_alias => {
                try ctx.printTitle("Trap instruction alias is not lowercase", .{});
                try ctx.deepen().printSourceNote("Trap alias", .{}, info.token);
            },
            .directive => {
                try ctx.printTitle("Directive name is not uppercase", .{});
                try ctx.deepen().printSourceNote("Directive", .{}, info.token);
            },
            .label => {
                try ctx.printTitle("Label name is not PascalCase", .{});
                try ctx.deepen().printSourceNote("Label declared here", .{}, info.token);
            },
            .register => {
                try ctx.printTitle("Register name is not lowercase", .{});
                try ctx.deepen().printSourceNote("Register", .{}, info.token);
            },
            .integer_prefix => {
                try ctx.printTitle("Integer prefix is not lowercase", .{});
                try ctx.deepen().printSourceNote("Integer", .{}, info.token);
            },
            .integer_digits => {
                try ctx.printTitle("Integer does not use uppercase letters", .{});
                try ctx.deepen().printSourceNote("Integer", .{}, info.token);
            },
        },

        .unsupported_directive => |info| {
            try ctx.printTitle("Directive is not supported", .{});
            try ctx.deepen().printSourceNote("Tried to use directive here", .{}, info.directive);
        },
        .multiple_origins => |info| {
            try ctx.printTitle("Multiple .ORIG directives", .{});
            try ctx.deepen().printSourceNote("First declared here", .{}, info.existing);
            try ctx.deepen().printSourceNote("Tried to redeclare here", .{}, info.new);
        },
        .late_origin => |info| {
            try ctx.printTitle("Origin declared after statements", .{});
            try ctx.deepen().printSourceNote("Origin declared here", .{}, info.origin);
            try ctx.deepen().printSourceNote(
                "Origin must be declared at start of file",
                .{},
                info.first_token orelse .firstCharOf(source),
            );
        },
        .missing_origin => |info| {
            try ctx.printTitle("Missing .ORIG directive", .{});
            try ctx.deepen().printSourceNote(
                "Origin should be declared before any instructions",
                .{},
                info.first_token orelse .firstCharOf(source),
            );
        },
        .missing_end => |info| {
            try ctx.printTitle("Missing .END directive", .{});
            try ctx.deepen().printSourceNote(
                "End should be declared after included all instructions",
                .{},
                info.last_token orelse .lastCharOf(source),
            );
        },

        .existing_label_left => |info| {
            try ctx.printTitle("Multiple labels cannot be declared on the same line", .{});
            try ctx.deepen().printSourceNote("First label declared here", .{}, info.existing);
            try ctx.deepen().printSourceNote("Another label declared on the same line", .{}, info.new);
        },
        .existing_label_above => |info| {
            try ctx.printTitle("Line is annotated with multiple labels", .{});
            try ctx.deepen().printSourceNote("First label declared here", .{}, info.existing);
            try ctx.deepen().printSourceNote("Another label declared in the same position", .{}, info.new);
        },
        .invalid_label_target => |info| {
            try ctx.printTitle("Label is useless in this position", .{});
            try ctx.deepen().printSourceNote("Label declared here", .{}, info.label);
            if (info.target) |target|
                try ctx.deepen().printSourceNote("Token cannot be annotated with label", .{}, target)
            else
                try ctx.deepen().printSourceNote("Label is not followed by any token", .{}, .lastCharOf(source));
        },
        .label_colon => |info| {
            try ctx.printTitle("Label followed by colon `:`", .{});
            try ctx.deepen().printSourceNote("Colon", .{}, info.colon);
            try ctx.deepen().printNote("A post-label colon is non-standard syntax", .{});
        },

        .redefined_label => |info| {
            try ctx.printTitle("Label already declared", .{});
            try ctx.deepen().printSourceNote("Label is first declared here", .{}, info.existing);
            try ctx.deepen().printSourceNote("Tried to redeclare here", .{}, info.new);
        },
        .undefined_label => |info| {
            try ctx.printTitle("Label is not declared", .{});
            try ctx.deepen().printSourceNote("Label used here", .{}, info.reference);
            if (info.nearest) |close_match| {
                try ctx.deepen().withSource(info.definition_source)
                    .printSourceNote("This label declaration is similar", .{}, close_match);
                try ctx.deepen().printNote("Label names are case-sensitive", .{});
            }
        },
        .unused_label => |info| {
            try ctx.printTitle("Label declaration is not used", .{});
            try ctx.deepen().printSourceNote("Label declared here", .{}, info.label);
        },

        // TODO: Change "operand" to "argument", and elsewhere
        .malformed_integer => |info| {
            try ctx.printTitle("Malformed integer operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Integer token is not in an valid form", .{});
        },
        .malformed_character => |info| {
            try ctx.printTitle("Malformed character literal operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Character literal token is invalid", .{});
        },
        .expected_digit => |info| {
            try ctx.printTitle("Expected digit in integer operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Integer token ended unexpectedly", .{});
        },
        .invalid_digit => |info| {
            try ctx.printTitle("Invalid digit in integer operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Integer token contains a character which is not valid in the base", .{});
        },
        .unexpected_delimiter => |info| {
            try ctx.printTitle("Unexpected digit delimiter in integer operand", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Delimiter character `_` must appear between digits", .{});
        },
        .nonstandard_integer_radix => |info| {
            try ctx.printTitle("Integer uses non-standard base specifier '{t}'", .{info.radix});
            try ctx.deepen().printSourceNote("Integer", .{}, info.integer);
        },
        .nonstandard_integer_form => |info| {
            try ctx.printTitle("Integer uses non-standard syntax", .{});
            try ctx.deepen().printSourceNote("Integer", .{}, info.integer);
            try ctx.deepen().printNote("{s}", .{switch (info.reason) {
                .delimiter => "Delimiter character `_` is non-standard",
            }});
        },
        .undesirable_integer_form => |info| {
            try ctx.printTitle("Integer uses undesirable syntax", .{});
            try ctx.deepen().printSourceNote("Integer", .{}, info.integer);
            try ctx.deepen().printNote("{s}", .{switch (info.reason) {
                .missing_zero => "Leading zero should appear before base specifier",
                .pre_radix_sign => "Sign character should appear after decimal base specifier",
                .post_radix_sign => "Sign character should appear before non-decimal base specifier",
                .implicit_radix => "Decimal integer literal should begin with `#`",
            }});
        },
        .character_integer => |info| {
            try ctx.printTitle("Use of non-standard character literal token", .{});
            try ctx.deepen().printSourceNote("Character", .{}, info.integer);
        },

        .integer_too_large => |info| {
            try ctx.printTitle("Integer operand is too large", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
            try ctx.deepen().printNote("Value cannot be represented in {} bits", .{info.type_info.bits});
            if (info.type_info.signedness == .signed) {
                try ctx.deepen().printNote("Since the operand is a signed integer, the highest bit is reserved as the sign bit", .{});
            }
        },
        .offset_too_large => |info| {
            try ctx.printTitle("Calculated label offset is too large", .{});
            try ctx.deepen().printSourceNote("Label declared here", .{}, info.definition);
            try ctx.deepen().withSource(info.definition_source)
                .printSourceNote("Label used here", .{}, info.reference);
            try ctx.deepen().printNote("Address offset of {} words cannot be represented in {} bits", .{ info.offset, info.bits });
        },
        .unexpected_negative_integer => |info| {
            try ctx.printTitle("Integer operand cannot be negative", .{});
            try ctx.deepen().printSourceNote("Operand", .{}, info.integer);
        },

        .unmatched_quote => |info| {
            try ctx.printTitle("String literal does not end with quote `\"`", .{});
            try ctx.deepen().printSourceNote("String is used here", .{}, info.string);
            try ctx.deepen().printNote("Strings do not automatically stop at end of line", .{});
        },
        .invalid_string_escape => |info| {
            try ctx.printTitle("Invalid escape sequence", .{});
            try ctx.deepen().printSourceNote("String", .{}, info.string);
            try ctx.deepen().printSourceNote("Erroneous escape sequence", .{}, info.sequence);
        },
        .multiline_string => |info| {
            try ctx.printTitle("String covers multiple lines", .{});
            try ctx.deepen().printSourceNote("String", .{}, info.string);
        },

        .stack_instruction => |info| {
            try ctx.printTitle("Use of non-standard stack instruction `{t}`", .{info.kind});
            try ctx.deepen().printSourceNote("Instruction is an ISA extension", .{}, info.mnemonic);
        },
        .literal_pc_offset => |info| {
            try ctx.printTitle("Address operand is a literal offset", .{});
            try ctx.deepen().printSourceNote("Integer", .{}, info.integer);
            try ctx.deepen().printNote("PC-offset operand should be a label reference, instead of hardcoded offset value", .{});
        },
        .explicit_trap_vect => |info| {
            try ctx.printTitle("Use of trap instruction with explicit vector operand", .{});
            try ctx.deepen().printSourceNote("Trap vector", .{}, info.vect);
            try ctx.deepen().printNote("Consider using trap alias `{s}`", .{info.alias});
        },
        .undeclared_trap_vect => |info| {
            try ctx.printTitle("Use of unknown trap vector 0x{x:02}", .{info.value});
            try ctx.deepen().printSourceNote("Trap vector", .{}, info.vect);
            try ctx.deepen().printNote("Traps vector 0x{x:02} is not recognized", .{info.value});
        },

        .emulate_exception => |info| {
            try ctx.printTitle("Runtime exception: {t}", .{info.code});
            // TODO: Add additional information
        },

        .debugger_requires_assembly => |info| {
            try ctx.printTitle("Command requires access to assembly", .{});
            try ctx.deepen().printSourceNote("Command", .{}, info.command);
            try ctx.deepen().printNote("Debugger does not have access to original assembly", .{});
        },
        .debugger_requires_state => |info| {
            try ctx.printTitle("Command requires initial state to be set", .{});
            try ctx.deepen().printSourceNote("Command", .{}, info.command);
            try ctx.deepen().printNote("Debugger does not have access to initial emulator state", .{});
        },
        .debugger_address_not_in_assembly => |info| {
            try ctx.printTitle("Address 0x{x:04} is not contained in assembly source", .{info.value});
            try ctx.deepen().printNote("Largest address in assembly is 0x{x:04}", .{info.max});
        },
        .debugger_address_not_user_memory => |info| {
            try ctx.printTitle("Address 0x{x:04} is not in user memory", .{info.value});
            try ctx.deepen().printSourceNote("Address", .{}, info.address);
            try ctx.deepen().printNote("Largest address in user memory is 0x{x:04}", .{info.max});
        },
        .debugger_label_partial_match => |info| {
            try ctx.printTitle("Label reference does not use correct case", .{});
            try ctx.deepen().printSourceNote("Label", .{}, info.reference);
            try ctx.deepen().withSource(info.definition_source)
                .printSourceNote("This label declaration is similar", .{}, info.nearest);
            try ctx.deepen().printNote("Label names are case-sensitive", .{});
        },
        .debugger_no_space => {
            try ctx.deepen().printTitle("No space left", .{});
        },
        .debugger_invalid_argument_kind => |info| {
            try ctx.printTitle("Invalid argument kind", .{});
            try ctx.deepen().printSourceNote("Argument", .{}, info.found);
        },
        .debugger_invalid_command => |info| {
            try ctx.printTitle("Invalid command name", .{});
            try ctx.deepen().printSourceNote("Command", .{}, info.command);
            if (info.nearest) |nearest|
                try ctx.deepen().printNote("Did you mean `{s}`?", .{DebuggerCommand.tagString(nearest)});
        },
        .debugger_missing_subcommand => |info| {
            try ctx.printTitle("Missing subcommand for `{s}`", .{info.first.view(source)});
            try ctx.deepen().printSourceNote("Command requires subcommand", .{}, info.eol);
        },
        .debugger_unexpected_eol => |info| {
            try ctx.printTitle("Missing argument", .{});
            try ctx.deepen().printSourceNote("Command ends too early", .{}, info.eol);
        },
        .debugger_expected_eol => |info| {
            try ctx.printTitle("Unexpected argument", .{});
            try ctx.deepen().printSourceNote("Argument", .{}, info.found);
            try ctx.deepen().printNote("Expected end of command", .{});
        },
        .debugger_integer_too_small => |info| {
            try ctx.printTitle("Integer argument is too small", .{});
            try ctx.deepen().printSourceNote("Argument", .{}, info.integer);
            try ctx.deepen().printNote("Minimum value is {}", .{info.minimum});
        },
    }

    const count = if (ctx.item_count) |count| count.* else 0;
    if (count > 1 and ctx.verbosity == .normal) {
        try ctx.writer.print("\n", .{});
    }
}
