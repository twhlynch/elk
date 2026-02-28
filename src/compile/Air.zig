const Air = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Runtime = @import("../emulate/Runtime.zig");
const Span = @import("Span.zig");

origin: u16,
lines: ArrayList(Line),

pub const Line = struct {
    label: ?Span,
    statement: Statement,
    span: Span,
};

/// Note that some instructions (`Statement` variants) share the same 4-bit
/// opcode, eg. `jsr` and `jsrr`, which are distinguished by a flag bit.
pub const Statement = union(enum) {
    raw_word: u16,

    add: struct {
        dest: Operand.Register,
        src_a: Operand.Register,
        src_b: Operand.RegImm5,
    },
    @"and": struct {
        dest: Operand.Register,
        src_a: Operand.Register,
        src_b: Operand.RegImm5,
    },
    not: struct {
        dest: Operand.Register,
        src: Operand.Register,
    },
    br: struct {
        condition: Operand.ConditionMask,
        dest: Operand.PcOffset(9),
    },
    jmp: struct {
        base: Operand.Register,
    },
    ret: struct {},
    jsr: struct {
        dest: Operand.PcOffset(11),
    },
    jsrr: struct {
        base: Operand.Register,
    },
    lea: struct {
        dest: Operand.Register,
        src: Operand.PcOffset(9),
    },
    ld: struct {
        dest: Operand.Register,
        src: Operand.PcOffset(9),
    },
    ldi: struct {
        dest: Operand.Register,
        src: Operand.PcOffset(9),
    },
    ldr: struct {
        dest: Operand.Register,
        src: Operand.Register,
        offset: Operand.Offset6,
    },
    st: struct {
        src: Operand.Register,
        dest: Operand.PcOffset(9),
    },
    sti: struct {
        src: Operand.Register,
        dest: Operand.PcOffset(9),
    },
    str: struct {
        src: Operand.Register,
        dest: Operand.Register,
        offset: Operand.Offset6,
    },
    trap: struct {
        vect: Operand.TrapVect,
    },
    push: struct {
        src: Operand.Register,
    },
    pop: struct {
        dest: Operand.Register,
    },
    call: struct {
        dest: Operand.PcOffset(10),
    },
    rets: struct {},
    rti: struct {},

    fn encode(statement: Statement) u16 {
        switch (statement) {
            .raw_word => |raw| {
                return raw;
            },
            .add => |operands| {
                var raw: u16 = 0x1000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src_a.value.bits() << 6;
                raw |= operands.src_b.value.bits();
                return raw;
            },
            .@"and" => |operands| {
                var raw: u16 = 0x5000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src_a.value.bits() << 6;
                raw |= operands.src_b.value.bits();
                return raw;
            },
            .not => |operands| {
                var raw: u16 = 0x9000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits() << 6;
                raw |= 0b111111;
                return raw;
            },
            .br => |operands| {
                var raw: u16 = 0x0000;
                raw |= operands.condition.value.bits() << 9;
                raw |= operands.dest.value.bits();
                return raw;
            },
            .jmp => |operands| {
                var raw: u16 = 0xc000;
                raw |= operands.base.value.bits() << 6;
                return raw;
            },
            .ret => {
                return 0xc1c0;
            },
            .jsr => |operands| {
                var raw: u16 = 0x4800;
                raw |= operands.dest.value.bits();
                return raw;
            },
            .jsrr => |operands| {
                var raw: u16 = 0x4000;
                raw |= operands.base.value.bits() << 6;
                return raw;
            },
            .lea => |operands| {
                var raw: u16 = 0xe000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits();
                return raw;
            },
            .ld => |operands| {
                var raw: u16 = 0x2000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits();
                return raw;
            },
            .ldi => |operands| {
                var raw: u16 = 0xa000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits();
                return raw;
            },
            .ldr => |operands| {
                var raw: u16 = 0x6000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits() << 6;
                raw |= operands.offset.value.bits();
                return raw;
            },
            .st => |operands| {
                var raw: u16 = 0x3000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits();
                return raw;
            },
            .sti => |operands| {
                var raw: u16 = 0xb000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits();
                return raw;
            },
            .str => |operands| {
                var raw: u16 = 0x7000;
                raw |= operands.dest.value.bits() << 9;
                raw |= operands.src.value.bits() << 6;
                raw |= operands.offset.value.bits();
                return raw;
            },
            .trap => |operands| {
                var raw: u16 = 0xf000;
                raw |= operands.vect.value.bits();
                return raw;
            },
            .push => |operands| {
                var raw: u16 = 0xd400;
                raw |= operands.src.value.bits() << 6;
                return raw;
            },
            .pop => |operands| {
                var raw: u16 = 0xd000;
                raw |= operands.dest.value.bits() << 6;
                return raw;
            },
            .call => |operands| {
                var raw: u16 = 0xdc00;
                raw |= operands.dest.value.bits();
                return raw;
            },
            .rets => {
                return 0xd800;
            },
            .rti => {
                return 0x8000;
            },
        }
    }
};

pub const Operand = struct {
    // Shorthand
    pub const Register = Spanned(Value.Register);
    pub const RegImm5 = Spanned(Value.RegImm5);
    pub const TrapVect = Spanned(Value.TrapVect);
    pub const Offset6 = Spanned(Value.Offset6);
    pub const ConditionMask = Spanned(Value.ConditionMask);
    pub fn PcOffset(comptime size: u4) type {
        return Spanned(Value.PcOffset(size));
    }

    pub fn Spanned(comptime K: type) type {
        return struct {
            span: Span,
            value: K,
        };
    }

    pub const Value = struct {
        pub const Register = struct {
            code: u3,
            pub fn bits(self: @This()) u16 {
                return self.code;
            }
        };

        pub const RegImm5 = union(enum) {
            register: Value.Register,
            immediate: i5,
            pub fn bits(self: @This()) u16 {
                return switch (self) {
                    .register => |register| register.bits(),
                    .immediate => |immediate| 0b100000 +
                        @as(u16, @as(u5, @bitCast(immediate))),
                };
            }
        };

        pub const TrapVect = struct {
            immediate: u8,
            pub fn bits(self: @This()) u16 {
                return self.immediate;
            }
        };

        pub const Offset6 = struct {
            immediate: i6,
            pub fn bits(self: @This()) u16 {
                return @as(u6, @bitCast(self.immediate));
            }
        };

        pub fn PcOffset(comptime size: u4) type {
            switch (size) {
                9, 10, 11 => {},
                else => comptime unreachable,
            }
            return union(enum) {
                unresolved,
                resolved: @Int(.signed, size),
                pub fn bits(self: @This()) u16 {
                    assert(self == .resolved);
                    return @as(@Int(.unsigned, size), @bitCast(self.resolved));
                }
            };
        }

        pub const ConditionMask = enum(u3) {
            n = 0b100,
            z = 0b010,
            p = 0b001,
            nz = 0b110,
            zp = 0b011,
            np = 0b101,
            nzp = 0b111,
            pub fn bits(self: @This()) u16 {
                return @intFromEnum(self);
            }
        };
    };
};

pub fn init() Air {
    return .{
        .origin = 0x3000,
        .lines = .empty,
    };
}

pub fn deinit(air: *Air, allocator: Allocator) void {
    air.lines.deinit(allocator);
}

pub fn getFirstSpan(air: *const Air) ?Span {
    if (air.lines.items.len == 0)
        return null;
    return air.lines.items[0].label orelse
        air.lines.items[0].span;
}

pub fn emitWriter(air: *const Air, writer: *Io.Writer) !void {
    try writer.writeInt(u16, air.origin, .big);
    for (air.lines.items) |line| {
        const raw = line.statement.encode();
        try writer.writeInt(u16, raw, .big);
    }
}

pub fn emitRuntime(air: *const Air, runtime: *Runtime) !void {
    runtime.pc = air.origin;
    for (air.lines.items, 0..) |line, i| {
        const raw = line.statement.encode();
        runtime.memory[air.origin + i] = raw;
    }
}
