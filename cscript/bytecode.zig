const std = @import("std");
const stdx = @import("stdx");
const cy = @import("cyber.zig");
const log = stdx.log.scoped(.bytecode);

/// Holds vm instructions.
pub const ByteCodeBuffer = struct {
    alloc: std.mem.Allocator,
    /// The number of local vars in the main block to reserve space for.
    mainLocalSize: u32,
    ops: std.ArrayListUnmanaged(OpData),
    consts: std.ArrayListUnmanaged(Const),
    /// Contiguous constant strings in a buffer.
    strBuf: std.ArrayListUnmanaged(u8),
    /// Tracks the start index of strings that are already in strBuf.
    strMap: std.HashMapUnmanaged(stdx.IndexSlice(u32), u32, StringIndexContext, std.hash_map.default_max_load_percentage),

    pub fn init(alloc: std.mem.Allocator) ByteCodeBuffer {
        return .{
            .alloc = alloc,
            .mainLocalSize = 0,
            .ops = .{},
            .consts = .{},
            .strBuf = .{},
            .strMap = .{},
        };
    }

    pub fn deinit(self: *ByteCodeBuffer) void {
        self.ops.deinit(self.alloc);
        self.consts.deinit(self.alloc);
        self.strBuf.deinit(self.alloc);
        self.strMap.deinit(self.alloc);
    }

    pub fn clear(self: *ByteCodeBuffer) void {
        self.ops.clearRetainingCapacity();
        self.consts.clearRetainingCapacity();
        self.strBuf.clearRetainingCapacity();
        self.strMap.clearRetainingCapacity();
    }

    pub fn pushConst(self: *ByteCodeBuffer, val: Const) !u32 {
        const start = @intCast(u32, self.consts.items.len);
        try self.consts.resize(self.alloc, self.consts.items.len + 1);
        self.consts.items[start] = val;
        return start;
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
    
    pub fn pushOpSlice(self: *ByteCodeBuffer, code: OpCode, args: []const u8) !void {
        const start = self.ops.items.len;
        try self.ops.resize(self.alloc, self.ops.items.len + args.len + 1);
        self.ops.items[start] = .{ .code = code };
        for (args) |arg, i| {
            self.ops.items[start+i+1] = .{ .arg = arg };
        }
    }

    pub fn pushOperands(self: *ByteCodeBuffer, operands: []const OpData) !void {
        try self.ops.appendSlice(self.alloc, operands);
    }

    pub fn setOpArgs1(self: *ByteCodeBuffer, idx: usize, arg: u8) void {
        self.ops.items[idx].arg = arg;
    }

    pub fn pushStringConst(self: *ByteCodeBuffer, str: []const u8) !u32 {
        const slice = try self.getStringConst(str);
        const idx = @intCast(u32, self.consts.items.len);
        const val = cy.Value.initConstStr(slice.start, @intCast(u16, slice.end - slice.start));
        try self.consts.append(self.alloc, .{ .val = val.val });
        return idx;
    }

    pub fn getStringConst(self: *ByteCodeBuffer, str: []const u8) !stdx.IndexSlice(u32) {
        const ctx = StringIndexContext{ .buf = &self.strBuf };
        const insertCtx = StringIndexInsertContext{ .buf = &self.strBuf };
        const res = try self.strMap.getOrPutContextAdapted(self.alloc, str, insertCtx, ctx);
        if (res.found_existing) {
            return res.key_ptr.*;
        } else {
            const start = @intCast(u32, self.strBuf.items.len);
            try self.strBuf.appendSlice(self.alloc, str);
            res.key_ptr.* = stdx.IndexSlice(u32).init(start, @intCast(u32, self.strBuf.items.len));
            return res.key_ptr.*;
        }
    }

    pub fn dump(self: *ByteCodeBuffer, buf: ByteCodeBuffer) void {
        _ = self;
        var pc: usize = 0;
        const ops = buf.ops.items;
        while (pc < ops.len) {
            log.debug("{}", .{pc});
            switch (ops[pc].code) {
                .pushTrue => {
                    log.debug("pushTrue", .{});
                    pc += 1;
                },
                .pushFalse => {
                    log.debug("pushFalse", .{});
                    pc += 1;
                },
                .pushNone => {
                    log.debug("pushNone", .{});
                    pc += 1;
                },
                .pushConst => {
                    const idx = ops[pc+1].arg;
                    log.debug("pushConst {}", .{idx});
                    pc += 2;
                },
                .pushNot => {
                    log.debug("pushNot", .{});
                    pc += 1;
                },
                .pushCompare => {
                    log.debug("pushCompare", .{});
                    pc += 1;
                },
                .pushLess => {
                    log.debug("pushLess", .{});
                    pc += 1;
                },
                .pushGreater => {
                    log.debug("pushGreater", .{});
                    pc += 1;
                },
                .pushLessEqual => {
                    log.debug("pushLessEqual", .{});
                    pc += 1;
                },
                .pushGreaterEqual => {
                    log.debug("pushGreaterEqual", .{});
                    pc += 1;
                },
                .pushOr => {
                    log.debug("pushOr", .{});
                    pc += 1;
                },
                .pushAnd => {
                    log.debug("pushAnd", .{});
                    pc += 1;
                },
                .pushAdd => {
                    log.debug("pushAdd", .{});
                    pc += 1;
                },
                .pushMinus => {
                    log.debug("pushMinus", .{});
                    pc += 1;
                },
                .pushMinus1 => {
                    const left = ops[pc+1].arg;
                    const right = ops[pc+2].arg;
                    log.debug("pushMinus1 {} {}", .{left, right});
                    pc += 3;
                },
                .pushMinus2 => {
                    const left = ops[pc+1].arg;
                    const right = ops[pc+2].arg;
                    log.debug("pushMinus2 {} {}", .{left, right});
                    pc += 3;
                },
                .pushList => {
                    const numElems = ops[pc+1].arg;
                    log.debug("pushList {}", .{numElems});
                    pc += 2;
                },
                .pushMapEmpty => {
                    log.debug("pushMapEmpty", .{});
                    pc += 1;
                },
                .pushMap => {
                    const numEntries = ops[pc+1].arg;
                    const startConst = ops[pc+2].arg;
                    log.debug("pushMap {} {}", .{numEntries, startConst});
                    pc += 3;
                },
                .pushSlice => {
                    log.debug("pushSlice", .{});
                    pc += 1;
                },
                .addSet => {
                    const offset = ops[pc+1].arg;
                    log.debug("addSet {}", .{offset});
                    pc += 2;
                },
                .releaseSet => {
                    const offset = ops[pc+1].arg;
                    log.debug("releaseSet {}", .{offset});
                    pc += 2;
                },
                .set => {
                    const offset = ops[pc+1].arg;
                    log.debug("set {}", .{offset});
                    pc += 2;
                },
                .setNew => {
                    const offset = ops[pc+1].arg;
                    log.debug("setNew {}", .{offset});
                    pc += 2;
                },
                .setIndex => {
                    log.debug("setIndex", .{});
                    pc += 1;
                },
                .load => {
                    const offset = ops[pc+1].arg;
                    log.debug("load {}", .{offset});
                    pc += 2;
                },
                .loadRetain => {
                    const offset = ops[pc+1].arg;
                    log.debug("loadRetain {}", .{offset});
                    pc += 2;
                },
                .pushIndex => {
                    log.debug("pushIndex", .{});
                    pc += 1;
                },
                .jumpBack => {
                    const offset = ops[pc+1].arg;
                    log.debug("jumpBack {}", .{offset});
                    pc += 2;
                },
                .jump => {
                    const offset = ops[pc+1].arg;
                    log.debug("jump {}", .{offset});
                    pc += 2;
                },
                .jumpNotCond => {
                    const offset = ops[pc+1].arg;
                    log.debug("jumpNotCond {}", .{offset});
                    pc += 2;
                },
                .release => {
                    const offset = ops[pc+1].arg;
                    log.debug("release {}", .{offset});
                    pc += 2;
                },
                .pushCall0 => {
                    const numArgs = ops[pc+1].arg;
                    log.debug("pushCall0 {}", .{numArgs});
                    pc += 2;
                },
                .pushCall1 => {
                    const numArgs = ops[pc+1].arg;
                    log.debug("pushCall1 {}", .{numArgs});
                    pc += 2;
                },
                .call => {
                    stdx.unsupported();
                },
                .callObjSym => {
                    const symId = ops[pc+1].arg;
                    const numArgs = ops[pc+2].arg;
                    log.debug("callObjSym {} {}", .{symId, numArgs});
                    pc += 3;
                },
                .pushCallSym0 => {
                    const symId = ops[pc+1].arg;
                    const numArgs = ops[pc+2].arg;
                    log.debug("pushCallSym0 {} {}", .{symId, numArgs});
                    pc += 3;
                },
                .pushCallSym1 => {
                    const symId = ops[pc+1].arg;
                    const numArgs = ops[pc+2].arg;
                    log.debug("pushCallSym1 {} {}", .{symId, numArgs});
                    pc += 3;
                },
                .pushField => {
                    const symId = ops[pc+1].arg;
                    log.debug("pushField {}", .{symId});
                    pc += 2;
                },
                .pushLambda => {
                    const funcOffset = ops[pc+1].arg;
                    const numParams = ops[pc+2].arg;
                    const numLocals = ops[pc+3].arg;
                    log.debug("pushLambda {} {} {}", .{funcOffset, numParams, numLocals});
                    pc += 4;
                },
                .pushClosure => {
                    const funcOffset = ops[pc+1].arg;
                    const numParams = ops[pc+2].arg;
                    const numCaptured = ops[pc+3].arg;
                    const numLocals = ops[pc+4].arg;
                    log.debug("pushClosure {} {} {} {}", .{funcOffset, numParams, numCaptured, numLocals});
                    pc += 5;
                },
                .forIter => {
                    const local = ops[pc+1].arg;
                    const pcOffset = ops[pc+2].arg;
                    log.debug("forIter {} {}", .{local, pcOffset});
                    pc += 3;
                },
                .forRange => {
                    const local = ops[pc+1].arg;
                    const pcOffset = ops[pc+2].arg;
                    log.debug("forRange {} {}", .{local, pcOffset});
                    pc += 3;
                },
                .cont => {
                    log.debug("cont", .{});
                    pc += 1;
                },
                .ret2 => {
                    log.debug("ret2", .{});
                    pc += 1;
                },
                .ret1 => {
                    log.debug("ret1", .{});
                    pc += 1;
                },
                .ret0 => {
                    log.debug("ret0", .{});
                    pc += 1;
                },
                .end => {
                    log.debug("end", .{});
                    pc += 1;
                },
                else => {
                    stdx.panicFmt("unsupported {}", .{ops[pc].code});
                },
            }
        }

        for (buf.consts.items) |extra| {
            log.debug("extra {}", .{extra});
        }
    }
};

pub const StringIndexContext = struct {
    buf: *std.ArrayListUnmanaged(u8),

    pub fn hash(self: StringIndexContext, s: stdx.IndexSlice(u32)) u64 {
        return std.hash.Wyhash.hash(0, self.buf.items[s.start..s.end]);
    }

    pub fn eql(self: StringIndexContext, a: stdx.IndexSlice(u32), b: stdx.IndexSlice(u32)) bool {
        return std.mem.eql(u8, self.buf.items[a.start..a.end], self.buf.items[b.start..b.end]);
    }
};

pub const StringIndexInsertContext = struct {
    buf: *std.ArrayListUnmanaged(u8),

    pub fn hash(self: StringIndexInsertContext, s: []const u8) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, s);
    }

    pub fn eql(self: StringIndexInsertContext, a: []const u8, b: stdx.IndexSlice(u32)) bool {
        return std.mem.eql(u8, a, self.buf.items[b.start..b.end]);
    }
};

pub const Const = packed union {
    val: u64,
    two: [2]u32,
};

const ConstStringTag: u2 = 0b00;

pub const OpData = packed union {
    code: OpCode,
    arg: u8,
};

pub const OpCode = enum(u8) {
    /// Push boolean onto register stack.
    pushTrue,
    pushFalse,
    /// Push none value onto register stack.
    pushNone,
    /// Push constant value onto register stack.
    pushConst,
    /// Pops top two registers, performs or, and pushes result onto stack.
    pushOr,
    /// Pops top two registers, performs and, and pushes result onto stack.
    pushAnd,
    /// Pops top register, performs not, and pushes result onto stack.
    pushNot,
    /// Pops top register and copies value to address relative to the local frame.
    set,
    releaseSet,
    /// Same as set except it also does a ensure capacity on the stack.
    setNew,
    /// Pops right, index, left registers, sets right value to address of left[index].
    setIndex,
    /// Loads a value from address relative to the local frame onto the register stack.
    load,
    loadRetain,
    pushIndex,
    /// Pops top two registers, performs addition, and pushes result onto stack.
    pushAdd,
    /// Pops specifc number of registers to allocate a new list on the heap. Pointer to new list is pushed onto the stack.
    pushList,
    pushMap,
    pushMapEmpty,
    pushSlice,
    /// Pops top register, if value evals to false, jumps the pc forward by an offset.
    jumpNotCond,
    /// Jumps the pc forward by an offset.
    jump,
    jumpBack,

    // releaseMany,
    release,
    /// Pops callee and args, performs a function call, and ensures no return values.
    pushCall0,
    /// Pops callee and args, performs a function call, and ensures one return value.
    pushCall1,
    /// Like pushCall but does not push the result onto the stack.
    call,
    /// Num args includes the receiver.
    callStr,
    /// Num args includes the receiver.
    callObjSym,
    pushCallSym0,
    pushCallSym1,
    ret2,
    ret1,
    ret0,
    pushField,
    pushLambda,
    pushClosure,
    addSet,
    pushCompare,
    pushLess,
    pushGreater,
    pushLessEqual,
    pushGreaterEqual,
    pushMinus,
    pushMinus1,
    pushMinus2,
    cont,
    forRange,
    forIter,

    /// Indicates the end of the main script.
    end,
};