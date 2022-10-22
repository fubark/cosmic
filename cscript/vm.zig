const std = @import("std");
const builtin = @import("builtin");
const endian = builtin.target.cpu.arch.endian();
const stdx = @import("stdx");
const cs = @import("cscript.zig");
const debug = builtin.mode == .Debug;

const log = stdx.log.scoped(.vm);

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
const TagNone = 0;
const TagFalse = 1;
const TagTrue = 2;
const TagError = 3;

/// NaN tagging over a f64 value.
/// Represents a f64 value if not a quiet nan.
/// Otherwise, the sign bit represents either a pointer value or a special value (true, false, none, etc).
/// Pointer values can be at most 51 bits since the sign bit and quiet nan take up 13 bits.
pub const Value = packed union {
    val: u64,
    /// Split into two 4-byte words. Must consider endian.
    two: [2]u32,

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

const StackFrame = struct {
    /// Points to start of this frame on the stack.
    framePtr: u32,
    keepReturn: bool,

    /// Saved pc value. Used to restore the pc after a function call.
    pc: u32,

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
    ops: []const OpData,
    consts: []const Const,
    strBuf: []const u8,

    /// Value stack.
    stack: stdx.Stack(Value),

    /// Call stack.
    stackFrames: stdx.Stack(StackFrame),
    curFrame: *StackFrame,

    /// Stack based registers.
    registers: stdx.Stack(Value),

    /// Symbol table used to lookup object fields and methods.
    /// First, the SymbolId indexes into the table for a SymbolMap to lookup the final SymbolEntry by StructId.
    symbols: std.ArrayListUnmanaged(SymbolMap),

    /// Used to track which symbols already exist. Only considers the name right now.
    symSignatures: std.StringHashMapUnmanaged(SymbolId),

    /// Regular function symbol table.
    funcSyms: std.ArrayListUnmanaged(FuncSymbolEntry),
    funcSymSignatures: std.StringHashMapUnmanaged(SymbolId),

    /// Structs.
    structs: std.ArrayListUnmanaged(Struct),
    listS: StructId,

    panicMsg: []const u8,

    opCounts: []OpCount,

    pub fn init(self: *VM, alloc: std.mem.Allocator) !void {
        self.* = .{
            .alloc = alloc,
            .parser = cs.Parser.init(alloc),
            .compiler = undefined,
            .ops = undefined,
            .consts = undefined,
            .strBuf = undefined,
            .stack = .{},
            .stackFrames = .{},
            .pc = 0,
            .curFrame = undefined,
            .registers = .{},
            .symbols = .{},
            .symSignatures = .{},
            .funcSyms = .{},
            .funcSymSignatures = .{},
            .structs = .{},
            .listS = undefined,
            .opCounts = undefined,
            .panicMsg = "",
        };
        self.compiler.init(self);
        try self.stack.ensureTotalCapacity(self.alloc, 50);
        try self.stackFrames.ensureTotalCapacity(self.alloc, 50);
        try self.registers.ensureTotalCapacity(self.alloc, 25);

        // Init compile time builtins.
        const resize = try self.ensureStructSym("resize");
        self.listS = try self.addStruct("List");
        try self.addStructSym(self.listS, resize, SymbolEntry.initNativeFunc(nativeListResize));
    }

    pub fn deinit(self: *VM) void {
        self.parser.deinit();
        self.compiler.deinit();
        self.stack.deinit(self.alloc);
        self.stackFrames.deinit(self.alloc);
        self.registers.deinit(self.alloc);

        for (self.symbols.items) |*map| {
            if (map.mapT == .manyStructs) {
                map.inner.manyStructs.deinit(self.alloc);
            }
        }
        self.symbols.deinit(self.alloc);
        self.symSignatures.deinit(self.alloc);

        self.funcSyms.deinit(self.alloc);
        self.funcSymSignatures.deinit(self.alloc);

        self.structs.deinit(self.alloc);
        self.alloc.free(self.panicMsg);
    }

    pub fn eval(self: *VM, src: []const u8, comptime trace: bool) !Value {
        var tt = stdx.debug.trace();
        const astRes = try self.parser.parse(src);
        if (astRes.has_error) {
            log.debug("Parse Error: {s}", .{astRes.err_msg});
            return error.ParseError;
        }
        tt.endPrint("parse");

        tt = stdx.debug.trace();
        const res = try self.compiler.compile(astRes);
        if (res.hasError) {
            log.debug("Compile Error: {s}", .{self.compiler.lastErr});
            return error.CompileError;
        }
        tt.endPrint("compile");

        // self.dumpByteCode(res.buf);

        if (trace) {
            const numOps = @enumToInt(cs.OpCode.end) + 1;
            var opCounts: [numOps]cs.OpCount = undefined;
            self.opCounts = &opCounts;
            var i: u32 = 0;
            while (i < numOps) : (i += 1) {
                self.opCounts[i] = .{
                    .code = i,
                    .count = 0,
                };
            }
        }
        tt = stdx.debug.trace();
        defer {
            tt.endPrint("eval");
            if (trace) {
                self.dumpInfo();
                const S = struct {
                    fn opCountLess(_: void, a: cs.OpCount, b: cs.OpCount) bool {
                        return a.count > b.count;
                    }
                };
                std.sort.sort(cs.OpCount, self.opCounts, {}, S.opCountLess);
                var i: u32 = 0;
                const numOps = @enumToInt(cs.OpCode.end) + 1;
                while (i < numOps) : (i += 1) {
                    if (self.opCounts[i].count > 0) {
                        const op = std.meta.intToEnum(cs.OpCode, self.opCounts[i].code) catch continue;
                        log.info("{} {}", .{op, self.opCounts[i].count});
                    }
                }
            }
        }

        return self.evalByteCode(res.buf, trace) catch |err| {
            if (err == error.Panic) {
                log.debug("panic: {s}", .{self.panicMsg});
            }
            return err;
        };
    }

    pub fn dumpInfo(self: *VM) void {
        log.info("value stack cap: {}", .{self.stack.buf.len});
        log.info("register stack cap: {}", .{self.registers.buf.len});
        log.info("call stack cap: {}", .{self.stackFrames.buf.len});
    }

    pub fn dumpByteCode(self: *VM, buf: ByteCodeBuffer) void {
        _ = self;
        for (buf.consts.items) |extra| {
            log.debug("extra {}", .{extra});
        }
    }

    pub inline fn pushStackFrame(self: *VM) !void {
        try self.stackFrames.push(self.alloc, .{
            .framePtr = @intCast(u32, self.stack.top),
            // Usually return values are needed right after the function call
            .keepReturn = true,
            .pc = self.pc,
        });
        self.curFrame = &self.stackFrames.buf[self.stackFrames.top-1];
    }

    pub inline fn popStackFrame(self: *VM) void {
        var last = self.stackFrames.pop();
        self.stack.top = last.framePtr;
        last.deinit(self.alloc);
        if (self.stackFrames.top > 0) {
            self.curFrame = &self.stackFrames.buf[self.stackFrames.top-1];

            // Restore pc.
            self.pc = self.curFrame.pc;
        }
    }

    pub fn evalByteCode(self: *VM, buf: ByteCodeBuffer, comptime trace: bool) !Value {
        if (buf.ops.items.len == 0) {
            return error.NoEndOp;
        }

        self.stack.clearRetainingCapacity();
        self.stackFrames.clearRetainingCapacity();
        self.registers.clearRetainingCapacity();
        self.ops = buf.ops.items;
        self.consts = buf.consts.items;
        self.strBuf = buf.strBuf.items;
        self.pc = 0;

        try self.pushStackFrame();
        defer self.popStackFrame();
        const res = try self.evalStackFrame(trace);
        return res;
    }

    fn sliceList(self: *VM, listV: Value, startV: Value, endV: Value) !Value {
        if (listV.isPointer()) {
            const obj = stdx.mem.ptrCastAlign(*GenericObject, listV.asPointer());
            if (obj.structId == self.listS) {
                const list = stdx.mem.ptrCastAlign(*Rc(std.ArrayListUnmanaged(Value)), listV.asPointer());
                var start = @floatToInt(i32, startV.toF64());
                if (start < 0) {
                    start = @intCast(i32, list.val.items.len) + start + 1;
                }
                var end = @floatToInt(i32, endV.toF64());
                if (end < 0) {
                    end = @intCast(i32, list.val.items.len) + end + 1;
                }
                if (start < 0 or start > list.val.items.len) {
                    return self.panic("Index out of bounds");
                }
                if (end < start or end > list.val.items.len) {
                    return self.panic("Index out of bounds");
                }
                return self.allocList(list.val.items[@intCast(u32, start)..@intCast(u32, end)]);
            } else {
                try stdx.panic("expected list");
            }
        } else {
            try stdx.panic("expected pointer");
        }
    }

    fn allocList(self: *VM, elems: []const Value) !Value {
        const list = try self.alloc.create(Rc(std.ArrayListUnmanaged(Value)));
        list.* = .{
            .structId = self.listS,
            .rc = 1,
            .val = .{},
        };
        try list.val.appendSlice(self.alloc, elems);
        return Value.initPtr(list);
    }

    inline fn getStackFrameValue(self: *VM, offset: u8) Value {
        @setRuntimeSafety(debug);
        return self.stack.buf[self.curFrame.framePtr + offset];
    }

    inline fn setStackFrameValue(self: *VM, offset: u8, val: Value) void {
        @setRuntimeSafety(debug);
        self.stack.buf[self.curFrame.framePtr + offset] = val;
    }

    inline fn popRegister(self: *VM) Value {
        return self.registers.pop();
    }

    inline fn pushRegister(self: *VM, val: Value) !void {
        if (self.registers.top == self.registers.buf.len) {
            return self.registers.growTotalCapacity(self.alloc, self.registers.top + 1);
        }
        self.registers.buf[self.registers.top] = val;
        self.registers.top += 1;
    }

    fn addStruct(self: *VM, name: []const u8) !StructId {
        _ = name;
        const s = Struct{
            .name = "",
        };
        const id = @intCast(u32, self.structs.items.len);
        try self.structs.append(self.alloc, s);
        return id;
    }
    
    pub fn ensureFuncSym(self: *VM, name: []const u8) !SymbolId {
        const res = try self.funcSymSignatures.getOrPut(self.alloc, name);
        if (!res.found_existing) {
            const id = @intCast(u32, self.funcSyms.items.len);
            try self.funcSyms.append(self.alloc, .{
                .entryT = .none,
                .inner = undefined,
            });
            res.value_ptr.* = id;
            return id;
        } else {
            return res.value_ptr.*;
        }
    }

    pub fn ensureStructSym(self: *VM, name: []const u8) !SymbolId {
        const res = try self.symSignatures.getOrPut(self.alloc, name);
        if (!res.found_existing) {
            const id = @intCast(u32, self.symbols.items.len);
            try self.symbols.append(self.alloc, .{
                .mapT = .empty,
                .inner = undefined,
            });
            res.value_ptr.* = id;
            return id;
        } else {
            return res.value_ptr.*;
        }
    }

    pub inline fn setFuncSym(self: *VM, symId: SymbolId, sym: FuncSymbolEntry) !void {
        self.funcSyms.items[symId] = sym;
    }

    fn addStructSym(self: *VM, id: StructId, symId: SymbolId, sym: SymbolEntry) !void {
        switch (self.symbols.items[symId].mapT) {
            .empty => {
                self.symbols.items[symId] = .{
                    .mapT = .oneStruct,
                    .inner = .{
                        .oneStruct = .{
                            .id = id,
                            .sym = sym,
                        },
                    },
                };
            },
            else => stdx.panicFmt("unsupported {}", .{self.symbols.items[symId].mapT}),
        }
    }

    fn getIndex(self: *VM, left: Value, index: Value) !Value {
        if (left.isPointer()) {
            const obj = stdx.mem.ptrCastAlign(*GenericObject, left.asPointer());
            if (obj.structId == self.listS) {
                const list = stdx.mem.ptrCastAlign(*Rc(std.ArrayListUnmanaged(Value)), left.asPointer());
                const idx = @floatToInt(u32, index.toF64());
                if (idx < list.val.items.len) {
                    return list.val.items[idx];
                } else {
                    return error.OutOfBounds;
                }
            } else {
                return stdx.panic("expected list");
            }
        } else {
            return stdx.panic("expected pointer");
        }
    }

    fn panic(self: *VM, msg: []const u8) error{Panic, OutOfMemory} {
        self.panicMsg = try self.alloc.dupe(u8, msg);
        return error.Panic;
    }

    fn nativeListResize(self: *VM, ptr: *anyopaque, args: []const Value) void {
        if (args.len == 0) {
            stdx.panic("Args mismatch");
        }
        const list = stdx.mem.ptrCastAlign(*Rc(std.ArrayListUnmanaged(Value)), ptr);
        const size = @floatToInt(u32, args[0].toF64());
        list.val.resize(self.alloc, size) catch stdx.fatal();
    }

    fn setIndex(self: *VM, left: Value, index: Value, right: Value) !void {
        if (left.isPointer()) {
            const obj = stdx.mem.ptrCastAlign(*GenericObject, left.asPointer());
            if (obj.structId == self.listS) {
                const list = stdx.mem.ptrCastAlign(*Rc(std.ArrayListUnmanaged(Value)), left.asPointer());
                const idx = @floatToInt(u32, index.toF64());
                if (idx < list.val.items.len) {
                    list.val.items[idx] = right;
                } else {
                    // var i: u32 = @intCast(u32, list.val.items.len);
                    // try list.val.resize(self.alloc, idx + 1);
                    // while (i < idx) : (i += 1) {
                    //     list.val.items[i] = Value.none();
                    // }
                    // list.val.items[idx] = right;
                    return self.panic("Index out of bounds.");
                }
            } else {
                return stdx.panic("expected list");
            }
        } else {
            return stdx.panic("expected pointer");
        }
    }

    pub fn release(self: *VM, val: Value) void {
        @setRuntimeSafety(debug);
        if (val.isPointer()) {
            const obj = stdx.mem.ptrCastAlign(*GenericObject, val.asPointer());
            obj.rc -= 1;
            if (obj.rc == 0) {
                if (obj.structId == self.listS) {
                    const list = stdx.mem.ptrCastAlign(*Rc(std.ArrayListUnmanaged(Value)), val.asPointer());
                    list.val.deinit(self.alloc);
                    self.alloc.destroy(list);
                } else {
                    return stdx.panic("expected list");
                }
            }
        }
    }

    inline fn callSymEntry(self: *VM, entry: SymbolEntry, objPtr: *anyopaque, args: []const Value) void {
        switch (entry.entryT) {
            .nativeFunc => {
                const func = @ptrCast(fn (*VM, *anyopaque, []const Value) void, entry.inner.nativeFunc);
                func(self, objPtr, args);
            },
            else => stdx.panicFmt("unsupported {}", .{entry.entryT}),
        }
    }

    fn callSym(self: *VM, symId: SymbolId, args: []const Value, keepReturn: bool) !void {
        @setRuntimeSafety(debug);
        const sym = self.funcSyms.items[symId];
        switch (sym.entryT) {
            .func => {
                // Save pc.
                self.curFrame.pc = self.pc;

                try self.pushStackFrame();
                if (!keepReturn) {
                    self.curFrame.keepReturn = false;
                }

                self.pc = sym.inner.func.pc;

                // Write args to new frame stack.
                if (self.stack.top + args.len >= self.stack.buf.len) {
                    try self.stack.growTotalCapacity(self.alloc, self.stack.top + args.len);
                }
                self.stack.pushSliceNoCheck(args);
            },
            .none => stdx.panic("Symbol doesn't exist."),
            else => stdx.panic("unsupported callsym"),
        }
    }

    fn callObjSym(self: *VM, recv: Value, symId: SymbolId, args: []const Value) void {
        if (recv.isPointer()) {
            const obj = stdx.mem.ptrCastAlign(*GenericObject, recv.asPointer());
            const map = self.symbols.items[symId];
            switch (map.mapT) {
                .oneStruct => {
                    if (obj.structId == map.inner.oneStruct.id) {
                        self.callSymEntry(map.inner.oneStruct.sym, recv.asPointer().?, args);
                    } else stdx.panic("Symbol does not exist for receiver.");
                },
                else => stdx.panicFmt("unsupported {}", .{map.mapT}),
            } 
        }
    }

    fn evalStackFrame(self: *VM, comptime trace: bool) !cs.Value {
        @setRuntimeSafety(debug);
        while (true) {
            if (trace) {
                const op = self.ops[self.pc].code;
                self.opCounts[@enumToInt(op)].count += 1;
            }
            log.debug("op: {}", .{self.ops[self.pc].code});
            switch (self.ops[self.pc].code) {
                .pushTrue => {
                    try self.pushRegister(Value.initTrue());
                    self.pc += 1;
                    continue;
                },
                .pushFalse => {
                    try self.pushRegister(Value.initFalse());
                    self.pc += 1;
                    continue;
                },
                .pushNone => {
                    try self.pushRegister(Value.initNone());
                    self.pc += 1;
                    continue;
                },
                .pushConst => {
                    const idx = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    try self.pushRegister(Value{ .val = self.consts[idx].val });
                    continue;
                },
                .pushNot => {
                    const val = self.popRegister();
                    try self.pushRegister(evalNot(val));
                    self.pc += 1;
                    continue;
                },
                .pushCompare => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalCompare(left, right));
                    self.pc += 1;
                    continue;
                },
                .pushLess => {
                    self.pc += 1;
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalLess(left, right));
                    continue;
                },
                .pushGreater => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalGreater(left, right));
                    self.pc += 1;
                    continue;
                },
                .pushLessEqual => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalLessOrEqual(left, right));
                    self.pc += 1;
                    continue;
                },
                .pushGreaterEqual => {
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalGreaterOrEqual(left, right));
                    self.pc += 1;
                    continue;
                },
                .pushOr => {
                    self.pc += 1;
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalOr(left, right));
                    continue;
                },
                .pushAnd => {
                    self.pc += 1;
                    const right = self.popRegister();
                    const left = self.popRegister();
                    try self.pushRegister(evalAnd(left, right));
                    continue;
                },
                .pushAdd => {
                    self.pc += 1;
                    self.registers.top -= 1;
                    const left = self.registers.buf[self.registers.top-1];
                    const right = self.registers.buf[self.registers.top];
                    self.registers.buf[self.registers.top-1] = evalAdd(left, right);
                    continue;
                },
                .pushMinus => {
                    self.pc += 1;
                    self.registers.top -= 1;
                    const left = self.registers.buf[self.registers.top-1];
                    const right = self.registers.buf[self.registers.top];
                    self.registers.buf[self.registers.top-1] = evalMinus(left, right);
                    continue;
                },
                .pushMinus1 => {
                    const leftOffset = self.ops[self.pc+1].arg;
                    const rightOffset = self.ops[self.pc+2].arg;
                    self.pc += 3;

                    if (leftOffset == NullStackOffsetU8) {
                        const left = self.registers.buf[self.registers.top-1];
                        const right = self.getStackFrameValue(rightOffset);
                        self.registers.buf[self.registers.top-1] = evalMinus(left, right);
                        continue;
                    } else {
                        const left = self.getStackFrameValue(leftOffset);
                        const right = self.registers.buf[self.registers.top-1];
                        self.registers.buf[self.registers.top-1] = evalMinus(left, right);
                        continue;
                    }
                },
                .pushMinus2 => {
                    const leftOffset = self.ops[self.pc+1].arg;
                    const rightOffset = self.ops[self.pc+2].arg;
                    self.pc += 3;

                    const left = self.getStackFrameValue(leftOffset);
                    const right = self.getStackFrameValue(rightOffset);
                    try self.pushRegister(evalMinus(left, right));
                    continue;
                },
                .pushList => {
                    const numElems = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    const top = self.registers.top;
                    const elems = self.registers.buf[top-numElems..top];
                    const list = try self.allocList(elems);
                    self.registers.top = top-numElems;
                    try self.pushRegister(list);
                    continue;
                },
                .pushSlice => {
                    self.pc += 1;
                    const end = self.popRegister();
                    const start = self.popRegister();
                    const list = self.popRegister();
                    const newList = try self.sliceList(list, start, end);
                    try self.pushRegister(newList);
                    continue;
                },
                .addSet => {
                    const offset = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    const val = self.popRegister();
                    self.setStackFrameValue(offset, evalAdd(self.getStackFrameValue(offset), val));
                    continue;
                },
                .set => {
                    const offset = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    const val = self.popRegister();
                    self.setStackFrameValue(offset, val);
                    continue;
                },
                .setNew => {
                    const offset = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    const val = self.popRegister();
                    const reqSize = self.curFrame.framePtr + offset + 1;
                    if (self.stack.top < reqSize) {
                        try self.stack.ensureTotalCapacity(self.alloc, reqSize);
                        self.stack.top = reqSize;
                    }
                    self.setStackFrameValue(offset, val);
                    continue;
                },
                .setIndex => {
                    self.pc += 1;
                    const right = self.popRegister();
                    const index = self.popRegister();
                    const left = self.popRegister();
                    try self.setIndex(left, index, right);
                    continue;
                },
                .load => {
                    const offset = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    const val = self.getStackFrameValue(offset);
                    try self.pushRegister(val);
                    continue;
                },
                .pushIndex => {
                    self.pc += 1;
                    const index = self.popRegister();
                    const left = self.popRegister();
                    const val = try self.getIndex(left, index);
                    try self.pushRegister(val);
                    continue;
                },
                .jumpBack => {
                    self.pc -= self.ops[self.pc+1].arg;
                    continue;
                },
                .jump => {
                    self.pc += self.ops[self.pc+1].arg;
                    continue;
                },
                .jumpNotCond => {
                    const pcOffset = self.ops[self.pc+1].arg;
                    const cond = self.popRegister();
                    if (!cond.toBool()) {
                        self.pc += pcOffset;
                    } else {
                        self.pc += 2;
                    }
                    continue;
                },
                .release => {
                    const offset = self.ops[self.pc+1].arg;
                    self.pc += 2;
                    self.release(self.getStackFrameValue(offset));
                    continue;
                },
                .pushCall => {
                    stdx.unsupported();
                },
                .call => {
                    stdx.unsupported();
                },
                .callStr => {
                    // const numArgs = self.ops[self.pc+1].arg;
                    // const str = self.extras[self.extraPc].two;
                    self.pc += 3;

                    // const top = self.registers.items.len;
                    // const vals = self.registers.items[top-numArgs..top];
                    // self.registers.items.len = top-numArgs;

                    // self.callStr(vals[0], self.strBuf[str[0]..str[1]], vals[1..]);
                    continue;
                },
                .callObjSym => {
                    const symId = self.ops[self.pc+1].arg;
                    const numArgs = self.ops[self.pc+2].arg;
                    self.pc += 3;

                    const top = self.registers.top;
                    const vals = self.registers.buf[top-numArgs..top];
                    self.registers.top = top-numArgs;

                    self.callObjSym(vals[0], symId, vals[1..]);
                    continue;
                },
                .callSym => {
                    const symId = self.ops[self.pc+1].arg;
                    const numArgs = self.ops[self.pc+2].arg;
                    self.pc += 3;

                    const top = self.registers.top;
                    const vals = self.registers.buf[top-numArgs..top];
                    self.registers.top = top-numArgs;

                    try self.callSym(symId, vals, false);
                    // try @call(.{ .modifier = .always_inline }, self.callSym, .{ symId, vals, false });
                    continue;
                },
                .pushCallSym => {
                    const symId = self.ops[self.pc+1].arg;
                    const numArgs = self.ops[self.pc+2].arg;
                    self.pc += 3;

                    const top = self.registers.top;
                    const vals = self.registers.buf[top-numArgs..top];
                    self.registers.top = top-numArgs;

                    try self.callSym(symId, vals, true);
                    // try @call(.{ .modifier = .always_inline }, self.callSym, .{ symId, vals, true });
                    continue;
                },
                .retTop => {
                    if (!self.curFrame.keepReturn) {
                        _ = self.popRegister();
                    }
                    self.popStackFrame();
                    continue;
                },
                .ret => {
                    if (self.curFrame.keepReturn) {
                        try self.pushRegister(Value.initNone());
                    }
                    self.popStackFrame();
                    continue;
                },
                .end => {
                    if (self.registers.top == 0) {
                        return Value.initNone();
                    } else {
                        return self.popRegister();
                    }
                },
            }
        }
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

fn evalGreaterOrEqual(left: cs.Value, right: cs.Value) cs.Value {
    return Value.initBool(left.toF64() >= right.toF64());
}

fn evalGreater(left: cs.Value, right: cs.Value) cs.Value {
    return Value.initBool(left.toF64() > right.toF64());
}

fn evalLessOrEqual(left: cs.Value, right: cs.Value) cs.Value {
    return Value.initBool(left.toF64() <= right.toF64());
}

fn evalLess(left: cs.Value, right: cs.Value) cs.Value {
    @setRuntimeSafety(debug);
    return Value.initBool(left.toF64() < right.toF64());
}

fn evalCompare(left: cs.Value, right: cs.Value) cs.Value {
    if (left.isNumber()) {
        return Value.initBool(right.isNumber() and left.asF64() == right.asF64());
    } else {
        switch (left.getTag()) {
            TagFalse => return Value.initBool(right.isFalse()),
            TagTrue => return Value.initBool(right.isTrue()),
            TagNone => return Value.initBool(right.isNone()),
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalMinus(left: cs.Value, right: cs.Value) cs.Value {
    @setRuntimeSafety(debug);
    if (left.isNumber()) {
        return Value.initF64(left.asF64() - right.toF64());
    } else {
        switch (left.getTag()) {
            TagFalse => return Value.initF64(-right.toF64()),
            TagTrue => return Value.initF64(1 - right.toF64()),
            TagNone => return Value.initF64(-right.toF64()),
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalAdd(left: cs.Value, right: cs.Value) cs.Value {
    @setRuntimeSafety(debug);
    if (left.isNumber()) {
        return Value.initF64(left.asF64() + right.toF64());
    } else {
        switch (left.getTag()) {
            TagFalse => return Value.initF64(right.toF64()),
            TagTrue => return Value.initF64(1 + right.toF64()),
            TagNone => return Value.initF64(right.toF64()),
            else => stdx.panic("unexpected tag"),
        }
    }
}

fn evalNot(val: cs.Value) cs.Value {
    if (val.isNumber()) {
        return cs.Value.initFalse();
    } else {
        switch (val.getTag()) {
            TagFalse => return cs.Value.initTrue(),
            TagTrue => return cs.Value.initFalse(),
            TagNone => return cs.Value.initTrue(),
            else => stdx.panic("unexpected tag"),
        }
    }
}

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

/// Holds vm instructions.
pub const ByteCodeBuffer = struct {
    alloc: std.mem.Allocator,
    ops: std.ArrayListUnmanaged(OpData),
    consts: std.ArrayListUnmanaged(Const),
    /// Contiguous constant strings in a buffer.
    strBuf: std.ArrayListUnmanaged(u8),
    /// Tracks the start index of strings that are already in strBuf.
    strMap: std.HashMapUnmanaged(stdx.IndexSlice(u32), u32, StringIndexContext, std.hash_map.default_max_load_percentage),

    pub fn init(alloc: std.mem.Allocator) ByteCodeBuffer {
        return .{
            .alloc = alloc,
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

    pub fn setOpArgs1(self: *ByteCodeBuffer, idx: usize, arg: u8) void {
        self.ops.items[idx].arg = arg;
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
};

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
    /// Same as set except it also does a ensure capacity on the stack.
    setNew,
    /// Pops right, index, left registers, sets right value to address of left[index].
    setIndex,
    /// Loads a value from address relative to the local frame onto the register stack.
    load,
    pushIndex,
    /// Pops top two registers, performs addition, and pushes result onto stack.
    pushAdd,
    /// Pops specifc number of registers to allocate a new list on the heap. Pointer to new list is pushed onto the stack.
    pushList,
    pushSlice,
    /// Pops top register, if value evals to false, jumps the pc forward by an offset.
    jumpNotCond,
    /// Jumps the pc forward by an offset.
    jump,
    jumpBack,

    release,
    /// Pops args and callee registers, performs a function call, and pushes result onto stack.
    pushCall,
    /// Like pushCall but does not push the result onto the stack.
    call,
    /// Num args includes the receiver.
    callStr,
    /// Num args includes the receiver.
    callObjSym,
    callSym,
    pushCallSym,
    retTop,
    ret,
    addSet,
    pushCompare,
    pushLess,
    pushGreater,
    pushLessEqual,
    pushGreaterEqual,
    pushMinus,
    pushMinus1,
    pushMinus2,

    /// Returns the top register or None back to eval.
    end,
};

const NullStackOffsetU8 = 255;

pub fn Rc(comptime T: type) type {
    return struct {
        structId: StructId,
        rc: u32,
        val: T,
    };
}

const GenericObject = struct {
    structId: StructId,
    rc: u32,
};

const SymbolMapType = enum {
    oneStruct,
    // twoStructs,
    manyStructs,
    empty,
};

const SymbolMap = struct {
    mapT: SymbolMapType,
    inner: union {
        oneStruct: struct {
            id: StructId,
            sym: SymbolEntry,
        },
        // twoStructs: struct {
        // },
        manyStructs: struct {
            map: std.AutoHashMapUnmanaged(StructId, SymbolEntry),

            fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
                self.map.deinit(alloc);
            }
        },
    },
};

const SymbolEntryType = enum {
    func,
    nativeFunc,
    field,
};

const SymbolEntry = struct {
    entryT: SymbolEntryType,
    inner: packed union {
        nativeFunc: *const anyopaque,
        func: packed struct {
            pc: u32,
        },
    },

    fn initNativeFunc(func: *const anyopaque) SymbolEntry {
        return .{
            .entryT = .nativeFunc,
            .inner = .{
                .nativeFunc = func,
            },
        };
    }
};

const FuncSymbolEntryType = enum {
    func,
    nativeFunc,
    none,
};

pub const FuncSymbolEntry = struct {
    entryT: FuncSymbolEntryType,
    inner: packed union {
        nativeFunc: *const anyopaque,
        func: packed struct {
            pc: u32,
        },
    },

    fn initNativeFunc(func: *const anyopaque) FuncSymbolEntry {
        return .{
            .entryT = .nativeFunc,
            .inner = .{
                .nativeFunc = func,
            },
        };
    }

    pub fn initFunc(pc: u32) FuncSymbolEntry {
        return .{
            .entryT = .func,
            .inner = .{
                .func = .{
                    .pc = pc,
                },
            },
        };
    }
};

const StructId = u32;

const Struct = struct {
    name: []const u8,
};

// const StructSymbol = struct {
//     name: []const u8,
// };

const SymbolId = u32;

pub const OpCount = struct {
    code: u32,
    count: u32,
};