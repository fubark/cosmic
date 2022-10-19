const std = @import("std");
const stdx = @import("stdx");
const cs = @import("cscript.zig");

const log = stdx.log.scoped(.vm);

/// Most significant bit.
const SignMask: u64 = 1 << 63;

/// Quiet NaN mask.
const QNANmask: u64 = 0x7ffc000000000000;

/// QNAN + Sign bit indicates a pointer value.
const PointerMask: u64 = QNANmask | SignMask;

const TrueMask: u64 = QNANmask | TagTrue;
const FalseMask: u64 = QNANmask | TagFalse;
const NoneMask: u64 = QNANmask | TagNone;

const TagMask: u64 = (1 << 3) - 1;
const TagNone = 0;
const TagFalse = 1;
const TagTrue = 2;

/// NaN tagging over a f64 value.
/// Represents a f64 value if not a quiet nan.
/// Otherwise, the sign bit represents either a pointer value or a special value (true, false, none, etc).
/// Pointer values can be at most 51 bits since the sign bit and quiet nan take up 13 bits.
pub const Value = struct {
    val: u64,

    pub fn asI32(self: Value) i32 {
        return @floatToInt(i32, self.asF64());
    }

    pub fn asU32(self: Value) u32 {
        return @floatToInt(u32, self.asF64());
    }

    pub inline fn asF64(self: Value) f64 {
        return @bitCast(f64, self.val);
    }

    pub fn toF64(self: Value) f64 {
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
        return self.val & ~PointerMask;
    }

    pub inline fn asBool(self: Value) bool {
        return self.val == TrueMask;
    }

    pub inline fn isNone(self: Value) bool {
        return self.val == NoneMask;
    }

    pub inline fn getTag(self: Value) u2 {
        return @intCast(u2, self.val & TagMask);
    }

    pub inline fn falseVal() Value {
        return .{ .val = FalseMask };
    }

    pub inline fn trueVal() Value {
        return .{ .val = TrueMask };
    }

    pub inline fn f64Val(val: f64) Value {
        return .{ .val = @bitCast(u64, val) };
    }

    pub inline fn none() Value {
        return .{ .val = NoneMask };
    }
};

const StackFrame = struct {
    /// Points to start of this frame on the stack.
    framePtr: u32,

    fn deinit(self: *StackFrame, alloc: std.mem.Allocator) void {
        _ = self;
        _ = alloc;
    }
};

pub const VM = struct {
    alloc: std.mem.Allocator,
    parser: cs.Parser,
    compiler: cs.VMcompiler,

    /// [Eval context]
    /// Program counter. Index to the next instruction op in `ops`.
    pc: u32,
    extraPc: u32,
    ops: []const OpData,
    extras: []const u64,
    stack: std.ArrayListUnmanaged(Value),
    stackFrames: std.ArrayListUnmanaged(StackFrame),
    curFrame: *StackFrame,
    /// Stack based registers.
    registers: std.ArrayListUnmanaged(Value),

    pub fn init(alloc: std.mem.Allocator) VM {
        return .{
            .alloc = alloc,
            .parser = cs.Parser.init(alloc),
            .compiler = cs.VMcompiler.init(alloc),
            .ops = undefined,
            .extras = undefined,
            .stack = .{},
            .stackFrames = .{},
            .pc = 0,
            .extraPc = 0,
            .curFrame = undefined,
            .registers = .{},
        };
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();
        self.compiler.deinit();
        self.stack.deinit(self.alloc);
        self.stackFrames.deinit(self.alloc);
        self.registers.deinit(self.alloc);
    }

    pub fn eval(self: *VM, src: []const u8) !Value {
        const astRes = try self.parser.parse(src);
        if (astRes.has_error) {
            log.debug("Parse Error: {s}", .{astRes.err_msg});
            return error.ParseError;
        }

        const res = try self.compiler.compile(astRes);
        if (res.hasError) {
            log.debug("Compile Error: {s}", .{self.compiler.lastErr});
            return error.CompileError;
        }

        return try self.evalByteCode(res.buf);
    }

    pub fn pushStackFrame(self: *VM) !void {
        try self.stackFrames.append(self.alloc, .{
            .framePtr = @intCast(u32, self.stack.items.len),
        });
        self.curFrame = &self.stackFrames.items[self.stackFrames.items.len-1];
    }

    pub fn popStackFrame(self: *VM) void {
        var last = self.stackFrames.pop();
        self.stack.items.len = last.framePtr;
        last.deinit(self.alloc);
        if (self.stackFrames.items.len > 0) {
            self.curFrame = &self.stackFrames.items[self.stackFrames.items.len-1];
        }
    }

    pub fn evalByteCode(self: *VM, buf: ByteCodeBuffer) !Value {
        if (buf.ops.items.len == 0) {
            return error.NoEndOp;
        }

        self.stack.clearRetainingCapacity();
        self.stackFrames.clearRetainingCapacity();
        self.ops = buf.ops.items;
        self.extras = buf.extras.items;
        self.pc = 0;
        self.extraPc = 0;
        self.registers.clearRetainingCapacity();

        const res = try self.evalStackFrame();
        return res;
    }

    inline fn getStackFrameValue(self: *VM, offset: u8) Value {
        return self.stack.items[self.curFrame.framePtr + offset];
    }

    inline fn setStackFrameValue(self: *VM, offset: u8, val: Value) void {
        self.stack.items[self.curFrame.framePtr + offset] = val;
    }

    inline fn popRegister(self: *VM) Value {
        return self.registers.pop();
    }

    inline fn pushRegister(self: *VM, val: Value) !void {
        return self.registers.append(self.alloc, val);
    }

    fn evalStackFrame(self: *VM) !cs.Value {
        try self.pushStackFrame();
        defer self.popStackFrame();
        while (true) {
            const op = self.ops[self.pc].code;
            // log.debug("op: {}", .{op});
            switch (op) {
                .pushTrue => {
                    try self.pushRegister(Value.trueVal());
                    self.pc += 1;
                },
                .pushFalse => {
                    try self.pushRegister(Value.falseVal());
                    self.pc += 1;
                },
                .pushNone => {
                    try self.pushRegister(Value.none());
                    self.pc += 1;
                },
                .pushF64 => {
                    try self.pushRegister(Value{ .val = self.extras[self.extraPc] });
                    self.pc += 1;
                    self.extraPc += 1;
                },
                .pushNot => {
                    const val = self.popRegister();
                    try self.pushRegister(evalNot(val));
                    self.pc += 1;
                },
                .pushOr => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalOr(left, right));
                    self.pc += 1;
                },
                .pushAnd => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalAnd(left, right));
                    self.pc += 1;
                },
                .pushAdd => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalAdd(left, right));
                    self.pc += 1;
                },
                .set => {
                    const offset = self.ops[self.pc+1].arg;
                    const val = self.popRegister();
                    self.setStackFrameValue(offset, val);
                    self.pc += 2;
                },
                .setNew => {
                    const offset = self.ops[self.pc+1].arg;
                    const val = self.popRegister();
                    if (self.stack.items.len <= self.curFrame.framePtr + offset) {
                        try self.stack.ensureUnusedCapacity(self.alloc, offset+1);
                        self.stack.items.len = self.curFrame.framePtr + offset+1;
                    }
                    self.setStackFrameValue(offset, val);
                    self.pc += 2;
                },
                .load => {
                    const offset = self.ops[self.pc+1].arg;
                    const val = self.getStackFrameValue(offset);
                    try self.pushRegister(val);
                    self.pc += 2;
                },
                .jump => {
                    self.pc += self.ops[self.pc+1].arg;
                    self.extraPc += self.ops[self.pc+2].arg;
                },
                .jumpNotCond => {
                    const pcOffset = self.ops[self.pc+1].arg;
                    const extraPcOffset = self.ops[self.pc+2].arg;
                    const cond = self.popRegister();
                    if (!cond.toBool()) {
                        self.pc += pcOffset;
                        self.extraPc += extraPcOffset;
                    } else {
                        self.pc += 3;
                    }
                },
                .retTop => {
                    return self.popRegister();
                },
                .end => {
                    if (self.registers.items.len == 0) {
                        return Value.none();
                    } else {
                        return self.popRegister();
                    }
                },
            }
        }
        return error.NoEndOp;
    }
};

fn evalAnd(left: cs.Value, right: cs.Value) cs.Value {
    if (left.isNumber()) {
        if (left.asF64() == 0) {
            return left;
        } else {
            return right;
        }
    } else {
        switch (left.getTag()) {
            TagFalse => return left,
            TagTrue => return right,
            TagNone => return left,
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalOr(left: cs.Value, right: cs.Value) cs.Value {
    if (left.isNumber()) {
        if (left.asF64() == 0) {
            return right;
        } else {
            return left;
        }
    } else {
        switch (left.getTag()) {
            TagFalse => return right,
            TagTrue => return left,
            TagNone => return right,
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalAdd(left: cs.Value, right: cs.Value) cs.Value {
    if (left.isNumber()) {
        return Value.f64Val(left.asF64() + right.toF64());
    } else {
        switch (left.getTag()) {
            TagFalse => return Value.f64Val(right.toF64()),
            TagTrue => return Value.f64Val(1 + right.toF64()),
            TagNone => return Value.f64Val(right.toF64()),
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalNot(val: cs.Value) cs.Value {
    if (val.isNumber()) {
        return cs.Value.falseVal();
    } else {
        switch (val.getTag()) {
            TagFalse => return cs.Value.trueVal(),
            TagTrue => return cs.Value.falseVal(),
            TagNone => return cs.Value.trueVal(),
            else => stdx.panic("unexpected tag"),
        }
    }
}

/// Holds vm instructions.
pub const ByteCodeBuffer = struct {
    alloc: std.mem.Allocator,
    ops: std.ArrayListUnmanaged(OpData),
    extras: std.ArrayListUnmanaged(u64),

    pub fn init(alloc: std.mem.Allocator) ByteCodeBuffer {
        return .{
            .alloc = alloc,
            .ops = .{},
            .extras = .{},
        };
    }

    pub fn deinit(self: *ByteCodeBuffer) void {
        self.ops.deinit(self.alloc);
        self.extras.deinit(self.alloc);
    }

    pub fn clear(self: *ByteCodeBuffer) void {
        self.ops.clearRetainingCapacity();
        self.extras.clearRetainingCapacity();
    }

    pub fn pushExtra(self: *ByteCodeBuffer, extra: u64) !void {
        const start = self.extras.items.len;
        try self.extras.resize(self.alloc, self.extras.items.len + 1);
        self.extras.items[start] = extra;
    }

    pub fn pushOp(self: *ByteCodeBuffer, code: OpCode) !void {
        const start = self.ops.items.len;
        try self.ops.resize(self.alloc, self.ops.items.len + 1);
        self.ops.items[start] = .{ .code = code };
    }

    pub fn pushOp1(self: *ByteCodeBuffer, code: OpCode, arg: u8) !void {
        const start = self.ops.items.len;
        try self.ops.resize(self.alloc, self.ops.items.len + 2);
        self.ops.items[start] = .{ .code = code };
        self.ops.items[start+1] = .{ .arg = arg };
    }

    pub fn pushOp2(self: *ByteCodeBuffer, code: OpCode, arg: u8, arg2: u8) !void {
        const start = self.ops.items.len;
        try self.ops.resize(self.alloc, self.ops.items.len + 3);
        self.ops.items[start] = .{ .code = code };
        self.ops.items[start+1] = .{ .arg = arg };
        self.ops.items[start+2] = .{ .arg = arg2 };
    }

    pub fn setOpArgs2(self: *ByteCodeBuffer, idx: usize, arg: u8, arg2: u8) void {
        self.ops.items[idx] = .{ .arg = arg };
        self.ops.items[idx+1] = .{ .arg = arg2 };
    }
};

const OpData = packed union {
    code: OpCode,
    arg: u8,
};

const OpCode = enum(u8) {
    /// Push boolean onto register stack.
    pushTrue = 0,
    pushFalse = 1,
    /// Push none value onto register stack.
    pushNone = 2,
    /// Push f64 value onto register stack.
    pushF64 = 3,
    /// Pops top two registers, performs or, and pushes result onto stack.
    pushOr = 4,
    /// Pops top two registers, performs and, and pushes result onto stack.
    pushAnd = 5,
    /// Pops top register, performs not, and pushes result onto stack.
    pushNot = 6,
    /// Pops top register and copies value to address relative to the local frame.
    set = 7,
    /// Same as set except it also does a ensure capacity on the stack.
    setNew = 8,
    /// Loads a value from address relative to the local frame onto the register stack.
    load = 9,
    /// Pops top two registers, performs addition, and pushes result onto stack.
    pushAdd = 10,
    /// Pops top register, if value evals to false, jumps the pc forward by an offset.
    jumpNotCond = 15,
    /// Jumps the pc forward by an offset.
    jump = 16,
    retTop = 17,
    /// Returns the top register or None back to eval.
    end = 20,
};

const NullStackOffsetU8 = 255;