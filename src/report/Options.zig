const Options = @This();

strictness: Strictness = .default,
verbosity: Verbosity = .default,
features: Features = .default,

pub const Strictness = enum {
    strict,
    normal,
    relaxed,
    const default: Strictness = .normal;
};

pub const Verbosity = enum {
    verbose,
    normal,
    quiet,
    const default: Verbosity = .normal;
};

// TODO: Rename. This is more broad than just "features"
pub const Features = struct {
    pub const Policy = enum { permit, forbid };

    const default: Features = .{
        .extension = .forbidAll,
        .smell = .forbidAll,
        .style = .forbidAll,
    };

    extension: struct {
        implicit_origin: Policy,
        implicit_end: Policy,
        multiline_strings: Policy,
        more_integer_radixes: Policy,
        more_integer_forms: Policy,
        label_declaration_colons: Policy,

        pub const forbidAll = fillFields(@This(), .forbid);
        pub const permitAll = fillFields(@This(), .permit);
    },

    smell: struct {
        pc_offset_literals: Policy,

        pub const forbidAll = fillFields(@This(), .forbid);
        pub const permitAll = fillFields(@This(), .permit);
    },

    style: struct {
        undesirable_integer_forms: Policy,
        missing_operand_commas: Policy,
        whitespace_commas: Policy,

        pub const forbidAll = fillFields(@This(), .forbid);
        pub const permitAll = fillFields(@This(), .permit);
    },

    fn fillFields(comptime T: type, comptime value: Policy) T {
        var filled: T = undefined;
        for (@typeInfo(T).@"struct".fields) |field|
            @field(filled, field.name) = value;
        return filled;
    }
};
