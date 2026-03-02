const Mask = @This();

const std = @import("std");
const Signedness = std.builtin.Signedness;
const assert = std.debug.assert;

signedness: Signedness,
lowest: u4,
highest: u4,

pub fn new(
    comptime signedness: Signedness,
    comptime lowest: u4,
    comptime highest: u4,
    comptime assert_size: u16,
) Mask {
    comptime {
        const mask: Mask = .{
            .signedness = signedness,
            .lowest = lowest,
            .highest = highest,
        };
        assert(mask.size() == assert_size);
        return mask;
    }
}

fn size(comptime mask: Mask) u16 {
    return @as(u16, mask.highest) - mask.lowest + 1;
}

pub fn apply(comptime mask: Mask, word: u16) @Int(mask.signedness, mask.size()) {
    comptime assert(mask.lowest <= mask.highest);
    const unsigned: @Int(.unsigned, mask.size()) = @truncate(word >> mask.lowest);
    return @bitCast(unsigned);
}

// TODO:
// test applyUnsigned {
//     const expect = std.testing.expect;
//
//     try expect(applyUnsigned(.new(0, 15), 0b1010_1010_0101_0101) == 0b1010_1010_0101_0101);
//
//     try expect(applyUnsigned(.new(0, 0), 0b1010_1010_0101_0101) == 0b1);
//     try expect(applyUnsigned(.new(0, 1), 0b1010_1010_0101_0101) == 0b01);
//     try expect(applyUnsigned(.new(0, 2), 0b1010_1010_0101_0101) == 0b101);
//     try expect(applyUnsigned(.new(0, 3), 0b1010_1010_0101_0101) == 0b0101);
//     try expect(applyUnsigned(.new(0, 4), 0b1010_1010_0101_0101) == 0b10101);
//
//     try expect(applyUnsigned(.new(15, 15), 0b1010_1010_0101_0101) == 0b1);
//     try expect(applyUnsigned(.new(13, 15), 0b1010_1010_0101_0101) == 0b101);
//     try expect(applyUnsigned(.new(12, 15), 0b1010_1010_0101_0101) == 0b1010);
//
//     try expect(applyUnsigned(.new(1, 4), 0b1010_1010_0101_0101) == 0b1010);
//     try expect(applyUnsigned(.new(2, 4), 0b1010_1010_0101_0101) == 0b101);
//     try expect(applyUnsigned(.new(11, 14), 0b1010_1010_0101_0101) == 0b0101);
//     try expect(applyUnsigned(.new(11, 13), 0b1010_1010_0101_0101) == 0b101);
// }
