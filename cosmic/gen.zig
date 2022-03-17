const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const v8 = @import("v8");

const v8x = @import("v8x.zig");
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const SizedJsString = runtime.SizedJsString;
const adapter = @import("adapter.zig");
const This = adapter.This;
const ThisResource = adapter.ThisResource;
const FuncData = adapter.FuncData;
const FuncDataUserPtr = adapter.FuncDataUserPtr;
const CsError = runtime.CsError;
const RuntimeValue = runtime.RuntimeValue;
const PromiseId = runtime.PromiseId;
const tasks = @import("tasks.zig");
const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const log = stdx.log.scoped(.gen);

pub fn genJsFuncSync(comptime native_fn: anytype) v8.FunctionCallback {
    return genJsFunc(native_fn, .{
        .asyncify = false,
        .is_data_rt = true,
    });
}

pub fn genJsFuncAsync(comptime native_fn: anytype) v8.FunctionCallback {
    return genJsFunc(native_fn, .{
        .asyncify = true,
        .is_data_rt = true,
    });
}

fn setErrorAndReturn(rt: *RuntimeContext, info: v8.FunctionCallbackInfo, err: CsError) void {
    rt.last_err = err;
    info.getReturnValue().setValueHandle(rt.js_null.handle);
}

/// Calling v8.throwErrorException inside a native callback function will trigger in v8 when the callback returns.
pub fn genJsFunc(comptime native_fn: anytype, comptime opts: GenJsFuncOptions) v8.FunctionCallback {
    const NativeFn = @TypeOf(native_fn);
    const asyncify = opts.asyncify;
    const is_data_rt = opts.is_data_rt;
    const gen = struct {
        fn cb(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);

            // RT handle is either data or the first field of data.
            const rt = if (is_data_rt) stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue())
                else stdx.mem.ptrCastAlign(*RuntimeContext, info.getData().castTo(v8.Object).getInternalField(0).castTo(v8.External).get());

            const iso = rt.isolate;
            const ctx = rt.getContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(iso);
            defer hscope.deinit();

            const ArgTypesT = std.meta.ArgsTuple(NativeFn);
            const ArgFields = std.meta.fields(ArgTypesT);

            const FuncInfo = comptime getJsFuncInfo(ArgFields);

            const num_js_args = info.length();
            if (num_js_args < FuncInfo.num_req_js_params) {
                v8x.throwErrorExceptionFmt(rt.alloc, iso, "Expected {} args.", .{FuncInfo.num_req_js_params});
                return;
            }

            const StringParams = comptime b: {
                var count: u32 = 0;
                inline for (ArgFields) |field, i| {
                    if (FuncInfo.param_tags[i] == .Param and field.field_type == []const u8) {
                        count += 1;
                    }
                }
                var i: u32 = 0;
                var idxs: [count]u32 = undefined;
                inline for (ArgFields) |field, idx| {
                    if (FuncInfo.param_tags[idx] == .Param and field.field_type == []const u8) {
                        idxs[i] = idx;
                        i += 1;
                    }
                }
                break :b idxs;
            };
            const HasStringParams = StringParams.len > 0;

            const has_f32_slice_param: bool = b: {
                inline for (ArgFields) |field, i| {
                    if (FuncInfo.param_tags[i] == .Param and field.field_type == []const f32) {
                        break :b true;
                    }
                }
                break :b false;
            };
            // This stores the JsValue to JsString conversion to be accessed later to go from JsString to []const u8
            // It should be optimized out for functions without string params.
            var js_strs: [StringParams.len]SizedJsString = undefined;
            if (HasStringParams) {
                // Since we are converting js strings to native []const u8,
                // we need to make sure the buffer capacity is enough before appending the args or a realloc could invalidate the slice.
                // This also means we need to do the JsValue to JsString conversion here and store it in memory.
                var total_size: u32 = 0;
                inline for (StringParams) |ParamIdx, i| {
                    const js_str = info.getArg(FuncInfo.param_js_idxs[ParamIdx].?).toString(ctx) catch unreachable;
                    const len = js_str.lenUtf8(iso);
                    total_size += len;
                    js_strs[i] = .{
                        .str = js_str,
                        .len = len,
                    };
                }
                rt.cb_str_buf.clearRetainingCapacity();
                rt.cb_str_buf.ensureUnusedCapacity(total_size) catch unreachable;
            }
            if (has_f32_slice_param) {
                if (rt.cb_f32_buf.items.len > 1e6) {
                    rt.cb_f32_buf.clearRetainingCapacity();
                }
            }

            var native_args: ArgTypesT = undefined;
            inline for (ArgFields) |Field, i| {
                switch (FuncInfo.param_tags[i]) {
                    .This => @field(native_args, Field.name) = This{ .obj = info.getThis() },
                    .ThisResource => {
                        const Ptr = stdx.meta.FieldType(Field.field_type, .res);
                        const res_id = info.getThis().getInternalField(0).castTo(v8.Integer).getValueU32();
                        const handle = rt.resources.getAssumeExists(res_id);
                        if (!handle.deinited) {
                            @field(native_args, Field.name) = Field.field_type{
                                .res = stdx.mem.ptrCastAlign(Ptr, handle.ptr),
                                .res_id = res_id,
                                .obj = info.getThis(),
                            };
                        } else {
                            v8x.throwErrorException(iso, "Resource handle is already deinitialized.");
                            return;
                        }
                    },
                    .ThisHandle => {
                        const Ptr = comptime stdx.meta.FieldType(Field.field_type, .ptr);
                        const this = info.getThis();
                        const handle_id = @intCast(u32, @ptrToInt(this.getInternalField(0).castTo(v8.External).get()));
                        const handle = rt.weak_handles.getAssumeExists(handle_id);
                        if (handle.tag != .Null) {
                            @field(native_args, Field.name) = Field.field_type{
                                .ptr = stdx.mem.ptrCastAlign(Ptr, handle.ptr),
                                .id = handle_id,
                                .obj = this,
                            };
                        } else {
                            v8x.throwErrorException(iso, "Handle is already deinitialized.");
                            return;
                        }
                    },
                    .FuncData => @field(native_args, Field.name) = .{ .val = info.getData() },
                    .FuncDataUserPtr => {
                        const Ptr = comptime stdx.meta.FieldType(Field.field_type, .ptr);
                        const ptr = info.getData().castTo(v8.Object).getInternalField(1).castTo(v8.External).get();
                        @field(native_args, Field.name) = Field.field_type{
                            .ptr = stdx.mem.ptrCastAlign(Ptr, ptr),
                        };
                    },
                    .ThisPtr => {
                        const Ptr = Field.field_type;
                        const ptr = @ptrToInt(info.getThis().getInternalField(0).castTo(v8.External).get());
                        if (ptr > 0) {
                            @field(native_args, Field.name) = @intToPtr(Ptr, ptr);
                        } else {
                            v8x.throwErrorException(iso, "Native handle expired");
                            return;
                        }
                    },
                    .RuntimePtr => @field(native_args, Field.name) = rt,
                    else => {},
                }
            }

            var has_args = true;
            inline for (ArgFields) |field, i| {
                if (FuncInfo.param_tags[i] == .Param) {
                    if (field.field_type == []const u8) {
                        const StrBufIdx = comptime std.mem.indexOfScalar(u32, &StringParams, @intCast(u32, i)).?;
                        if (rt.getNativeValue(field.field_type, js_strs[StrBufIdx])) |native_val| {
                            if (asyncify) {
                                // getNativeValue only returns temporary allocations. Dupe so it can be persisted.
                                if (@TypeOf(native_val) == []const u8) {
                                    @field(native_args, field.name) = rt.alloc.dupe(u8, native_val) catch unreachable;
                                } else {
                                    @field(native_args, field.name) = native_val;
                                }
                            } else {
                                @field(native_args, field.name) = native_val;
                            }
                        } else |err| {
                            throwConversionError(rt, err, @typeName(field.field_type));
                            has_args = false;
                        }
                    } else {
                        if (@typeInfo(field.field_type) == .Optional) {
                            const JsParamIdx = FuncInfo.param_js_idxs[i].?;
                            if (JsParamIdx >= num_js_args) {
                                @field(native_args, field.name) = null;
                            } else {
                                const FieldType = comptime @typeInfo(field.field_type).Optional.child;
                                const js_arg = info.getArg(FuncInfo.param_js_idxs[i].?);
                                @field(native_args, field.name) = (rt.getNativeValue(FieldType, js_arg) catch null);
                            }
                        } else {
                            const js_arg = info.getArg(FuncInfo.param_js_idxs[i].?);
                            if (rt.getNativeValue2(field.field_type, js_arg)) |native_val| {
                                @field(native_args, field.name) = native_val;
                            } else {
                                throwConversionError(rt, rt.get_native_val_err, @typeName(field.field_type));
                                // TODO: How to use return here without crashing compiler? Using a boolean var as a workaround.
                                has_args = false;
                            }
                        }
                    }
                }
            }
            if (!has_args) {
                return;
            }

            if (asyncify) {
                const ClosureTask = tasks.ClosureTask(native_fn);
                const task = ClosureTask{
                    .alloc = rt.alloc,
                    .args = native_args,
                };
                const resolver = iso.initPersistent(v8.PromiseResolver, v8.PromiseResolver.init(ctx));
                const promise = resolver.inner.getPromise();
                const promise_id = rt.promises.add(resolver) catch unreachable;
                const S = struct {
                    fn onSuccess(_ctx: RuntimeValue(PromiseId), _res: TaskOutput(ClosureTask)) void {
                        const _promise_id = _ctx.inner;
                        runtime.resolvePromise(_ctx.rt, _promise_id, _res);
                    }
                    fn onFailure(_ctx: RuntimeValue(PromiseId), _err: anyerror) void {
                        const _promise_id = _ctx.inner;
                        runtime.rejectPromise(_ctx.rt, _promise_id, _err);
                    }
                };
                const task_ctx = RuntimeValue(PromiseId){
                    .rt = rt,
                    .inner = promise_id,
                };
                _ = rt.work_queue.addTaskWithCb(task, task_ctx, S.onSuccess, S.onFailure);
                const return_value = info.getReturnValue();
                return_value.setValueHandle(rt.getJsValuePtr(promise));
            } else {
                const ReturnType = comptime stdx.meta.FunctionReturnType(NativeFn);
                if (ReturnType == void) {
                    @call(.{}, native_fn, native_args);
                } else if (@typeInfo(ReturnType) == .ErrorUnion) {
                    if (@call(.{}, native_fn, native_args)) |native_val| {
                        const js_val = rt.getJsValuePtr(native_val);
                        const return_value = info.getReturnValue();
                        return_value.setValueHandle(js_val);
                        freeNativeValue(rt.alloc, native_val);
                    } else |err| {
                        if (@typeInfo(ReturnType).ErrorUnion.error_set == CsError) {
                            setErrorAndReturn(rt, info, err);
                            return;
                        } else {
                            v8x.throwErrorExceptionFmt(rt.alloc, iso, "Unexpected error: {s}", .{@errorName(err)});
                            return;
                        }
                    }
                } else {
                    const native_val = @call(.{}, native_fn, native_args);
                    const js_val = rt.getJsValuePtr(native_val);
                    const return_value = info.getReturnValue();
                    return_value.setValueHandle(js_val);
                    freeNativeValue(rt.alloc, native_val);
                }
            }
        }
    };
    return gen.cb;
}

fn throwConversionError(rt: *RuntimeContext, err: anyerror, target_type: []const u8) void {
    switch (err) {
        error.CantConvert => v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Expected {s}", .{target_type}),
        error.HandleExpired => v8x.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Handle {s} expired", .{target_type}),
        else => unreachable,
    }
}

const GenJsFuncOptions = struct {
    // Indicates that the native function is synchronous by nature but we want it async by executing it on a worker thread.
    // User must make sure the native function is thread-safe.
    // Deprecated. Prefer binding to an explicit function and then calling runtime.invokeFuncAsync.
    asyncify: bool,

    is_data_rt: bool,
};

const ParamFieldTag = enum {
    This,
    ThisResource,
    ThisHandle,
    // Pointer is converted from this->getInternalField(0)
    ThisPtr,
    FuncData,
    FuncDataUserPtr,
    RuntimePtr,
    Param,
};

/// Info about a native function callback.
fn JsFuncInfo(comptime NumParams: u32) type {
    return struct {
        // Maps native param idx to it's tag type.
        param_tags: [NumParams]ParamFieldTag,

        // Maps native param idx to the corresponding js param idx.
        // Maps to null if the native param does not map to a js param.
        param_js_idxs: [NumParams]?u32,

        // Number of required js params.
        num_req_js_params: u32,
    };
}

pub fn getJsFuncInfo(comptime param_fields: []const std.builtin.TypeInfo.StructField) JsFuncInfo(param_fields.len) {
    var param_tags: [param_fields.len]ParamFieldTag = undefined;
    var param_js_idxs: [param_fields.len]?u32 = undefined;
    var js_param_idx: u32 = 0;
    var num_req_js_params: u32 = 0; 

    inline for (param_fields) |field, i| {
        if (field.field_type == This) {
            param_tags[i] = .This;
        } else if (@typeInfo(field.field_type) == .Struct and @hasDecl(field.field_type, "ThisResource")) {
            param_tags[i] = .ThisResource;
        } else if (@typeInfo(field.field_type) == .Struct and @hasDecl(field.field_type, "ThisHandle")) {
            param_tags[i] = .ThisHandle;
        } else if (comptime std.meta.trait.isSingleItemPtr(field.field_type) and field.field_type != *RuntimeContext) {
            param_tags[i] = .ThisPtr;
        } else if (field.field_type == FuncData) {
            param_tags[i] = .FuncData;
        } else if (@typeInfo(field.field_type) == .Struct and @hasDecl(field.field_type, "FuncDataUserPtr")) {
            param_tags[i] = .FuncDataUserPtr;
        } else if (field.field_type == *RuntimeContext) {
            param_tags[i] = .RuntimePtr;
        } else {
            param_tags[i] = .Param;
        }
        if (param_tags[i] == .Param) {
            param_js_idxs[i] = js_param_idx;
            js_param_idx += 1;
            if (@typeInfo(field.field_type) != .Optional) {
                num_req_js_params += 1;
            }
        } else {
            param_js_idxs[i] = null;
        }
    }

    return .{
        .param_tags = param_tags,
        .param_js_idxs = param_js_idxs,
        .num_req_js_params = num_req_js_params,
    };
}

/// native_cb: fn () Param | fn (Ptr) Param
pub fn genJsGetter(comptime native_cb: anytype) v8.AccessorNameGetterCallback {
    const Args = stdx.meta.FunctionArgs(@TypeOf(native_cb));
    const HasSelf = Args.len > 0;
    const HasSelfPtr = Args.len > 0 and comptime std.meta.trait.isSingleItemPtr(Args[0].arg_type.?);
    const gen = struct {
        fn get(_: ?*const v8.Name, raw_info: ?*const v8.C_PropertyCallbackInfo) callconv(.C) void {
            const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
            const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
            const iso = rt.isolate;
            const ctx = rt.context;

            var hscope: v8.HandleScope = undefined;
            hscope.init(iso);
            defer hscope.deinit();

            const return_value = info.getReturnValue();
            if (HasSelf) {
                const Self = Args[0].arg_type.?;
                const ptr = info.getThis().getInternalField(0).bitCastToU64(ctx);
                if (ptr > 0) {
                    if (HasSelfPtr) {
                        const native_val = native_cb(@intToPtr(Self, ptr));
                        return_value.setValueHandle(rt.getJsValuePtr(native_val));
                        freeNativeValue(native_val);
                    } else {
                        const native_val = native_cb(@intToPtr(*Self, ptr).*);
                        return_value.setValueHandle(rt.getJsValuePtr(native_val));
                        freeNativeValue(rt.alloc, native_val);
                    }
                } else {
                    v8x.throwErrorException(iso, "Handle has expired.");
                    return;
                }
            } else {
                const native_val = native_cb();
                return_value.setValueHandle(rt.getJsValuePtr(native_val));
                freeNativeValue(rt.alloc, native_val);
            }
        }
    };
    return gen.get;
}

// native_cb: fn (Param) void | fn (Ptr, Param) void
pub fn genJsSetter(comptime native_cb: anytype) v8.AccessorNameSetterCallback {
    const Args = stdx.meta.FunctionArgs(@TypeOf(native_cb));
    const HasPtr = Args.len > 0 and comptime std.meta.trait.isSingleItemPtr(Args[0].arg_type.?);
    const Param = if (HasPtr) Args[1].arg_type.? else Args[0].arg_type.?;
    const gen = struct {
        fn set(_: ?*const v8.Name, value: ?*const anyopaque, raw_info: ?*const v8.C_PropertyCallbackInfo) callconv(.C) void {
            const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
            const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
            const iso = rt.isolate;
            const ctx = rt.context;

            var hscope: v8.HandleScope = undefined;
            hscope.init(iso);
            defer hscope.deinit();

            const val = v8.Value{ .handle = value.? };

            if (rt.getNativeValue(Param, val)) |native_val| {
                if (HasPtr) {
                    const Ptr = Args[0].arg_type.?;
                    const ptr = info.getThis().getInternalField(0).bitCastToU64(ctx);
                    if (ptr > 0) {
                        native_cb(@intToPtr(Ptr, ptr), native_val);
                    } else {
                        v8x.throwErrorException(iso, "Handle has expired.");
                        return;
                    }
                } else {
                    native_cb(native_val);
                }
            } else {
                v8x.throwErrorExceptionFmt(rt.alloc, iso, "Could not convert to {s}", .{@typeName(Param)});
                return;
            }
        }
    };
    return gen.set;
}

pub fn genJsFuncGetValue(comptime native_val: anytype) v8.FunctionCallback {
    const gen = struct {
        fn cb(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
            const rt = stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue());
            const iso = rt.isolate;

            var hscope: v8.HandleScope = undefined;
            hscope.init(iso);
            defer hscope.deinit();

            const return_value = info.getReturnValue();
            return_value.setValueHandle(rt.getJsValuePtr(native_val));
        }
    };
    return gen.cb;
}

fn freeNativeValue(alloc: std.mem.Allocator, native_val: anytype) void {
    const Type = @TypeOf(native_val);
    switch (Type) {
        ds.Box([]const u8) => native_val.deinit(),
        else => {
            if (@typeInfo(Type) == .Optional) {
                if (native_val) |child_val| {
                    freeNativeValue(alloc, child_val);
                }
            } else if (comptime std.meta.trait.isContainer(Type)) {
                if (@hasDecl(Type, "ManagedSlice")) {
                    native_val.deinit();
                } else if (@hasDecl(Type, "ManagedStruct")) {
                    native_val.deinit();
                }
            }
        }
    }
}