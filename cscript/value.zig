const builtin = @import("builtin");
const endian = builtin.target.cpu.arch.endian();
const stdx = @import("stdx");
const debug = builtin.mode == .Debug;
const log = stdx.log.scoped(.value);

/// Most significant bit.
const SignMask: u64 = 1 << 63;

/// Quiet NaN mask.
const QNANmask: u64 = 0x7ffc000000000000;

/// QNAN + Sign bit indicates a pointer value.
const PointerMask: u64 = QNANmask | SignMask;

const TrueMask: u64 = QNANmask | (TagTrue << 32);
const FalseMask: u64 = QNANmask | (TagFalse << 32);
const NoneMask: u64 = QNANmask | (TagNone << 32);
const ErrorMask: u64 = QNANmask | (TagError << 32);

const TagMask: u32 = (1 << 3) - 1;
pub const TagNone = 0;
pub const TagFalse = 1;
pub const TagTrue = 2;
pub const TagError = 3;

pub const ValuePair = struct {
    left: Value,
    right: Value,
};

/// NaN tagging over a f64 value.
/// Represents a f64 value if not a quiet nan.
/// Otherwise, the sign bit represents either a pointer value or a special value (true, false, none, etc).
/// Pointer values can be at most 51 bits since the sign bit and quiet nan take up 13 bits.
pub const Value = packed union {
    val: u64,
    /// Split into two 4-byte words. Must consider endian.
    two: [2]u32,
    /// Call frame return info.
    retInfo: packed struct {
        pc: u32,
        framePtr: u30,
        numRetVals: u2,
    },

    pub inline fn asI32(self: Value) i32 {
        return @floatToInt(i32, self.asF64());
    }

    pub inline fn asU32(self: Value) u32 {
        return @floatToInt(u32, self.asF64());
    }

    pub inline fn asF64(self: Value) f64 {
        return @bitCast(f64, self.val);
    }

    pub inline fn asError(self: Value) u32 {
        if (endian == .Little) {
            return self.two[0];
        } else {
            return self.two[1];
        } 
    }

    pub fn toF64(self: Value) f64 {
        @setRuntimeSafety(debug);
        if (self.isNumber()) {
            return self.asF64();
        } else {
            switch (self.getTag()) {
                TagFalse => return 0,
                TagTrue => return 1,
                TagNone => return 0,
                else => stdx.panic("unexpected tag"),
            }
        }
    }

    pub fn toBool(self: Value) bool {
        @setRuntimeSafety(debug);
        if (self.isNumber()) {
            return self.asF64() != 0;
        } else {
            switch (self.getTag()) {
                TagFalse => return false,
                TagTrue => return true,
                TagNone => return false,
                else => stdx.panic("unexpected tag"),
            }
        }
    }

    pub inline fn isNumber(self: Value) bool {
        // Only a number(f64) if nan bits are not set.
        return self.val & QNANmask != QNANmask;
    }

    pub inline fn isPointer(self: Value) bool {
        // Only a pointer if nan bits and sign bit are set.
        return self.val & PointerMask == PointerMask;
    }

    pub inline fn asPointer(self: Value) ?*anyopaque {
        return @intToPtr(?*anyopaque, self.val & ~PointerMask);
    }

    pub inline fn asBool(self: Value) bool {
        return self.val == TrueMask;
    }

    pub inline fn isNone(self: Value) bool {
        return self.val == NoneMask;
    }

    pub inline fn isFalse(self: Value) bool {
        return self.val == FalseMask;
    }

    pub inline fn isTrue(self: Value) bool {
        return self.val == TrueMask;
    }

    pub inline fn getTag(self: Value) u2 {
        if (endian == .Little) {
            return @intCast(u2, self.two[1] & TagMask);
        } else {
            return @intCast(u2, self.two[0] & TagMask);
        }
    }

    pub inline fn initFalse() Value {
        return .{ .val = FalseMask };
    }

    pub inline fn initTrue() Value {
        return .{ .val = TrueMask };
    }

    pub inline fn initF64(val: f64) Value {
        return .{ .val = @bitCast(u64, val) };
    }

    pub inline fn initNone() Value {
        return .{ .val = NoneMask };
    }

    pub inline fn initBool(b: bool) Value {
        return if (b) .{ .val = TrueMask} else .{ .val = FalseMask };
    }

    pub inline fn initPtr(ptr: ?*anyopaque) Value {
        return .{ .val = PointerMask | @ptrToInt(ptr) };
    }

    pub inline fn initError(id: u32) Value {
        return .{ .val = ErrorMask | id };
    }

    pub fn dump(self: Value) void {
        if (self.isNumber()) {
            log.info("{}", .{self.asF64()});
        } else {
            log.info("{}", .{self.val});
        }
    }
};