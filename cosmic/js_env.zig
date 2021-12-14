const std = @import("std");
const stdx = @import("stdx");
const string = stdx.string;
const graphics = @import("graphics");
const Color = graphics.Color;

const v8 = @import("v8.zig");
const runtime = @import("runtime.zig");
const RuntimeContext = runtime.RuntimeContext;
const CsWindow = runtime.CsWindow;
const printFmt = runtime.printFmt;
const log = stdx.log.scoped(.js_env);

var rt: *RuntimeContext = undefined;

// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
pub fn init(ctx: *RuntimeContext, isolate: v8.Isolate) v8.Context {
    rt = ctx;

    // We set with the same undef values for each type, it might help the optimizing compiler if it knows the field types ahead of time.
    const undef_u32 = v8.Integer.initU32(isolate, 0);

    // JsWindow
    const window_class = v8.ObjectTemplate.initDefault(isolate);
    window_class.setInternalFieldCount(1);
    ctx.setFuncT(window_class, "onDrawFrame", window_OnDrawFrame);
    ctx.window_class = window_class;

    // JsColor
    const color_class = v8.FunctionTemplate.initDefault(isolate);
    {
        const proto = color_class.getPrototypeTemplate();
        ctx.setFuncT(proto, "darker", color_Darker);
        ctx.setFuncT(proto, "lighter", color_Lighter);
    }
    var instance = color_class.getInstanceTemplate();
    ctx.setProp(instance, "r", undef_u32);
    ctx.setProp(instance, "g", undef_u32);
    ctx.setProp(instance, "b", undef_u32);
    ctx.setProp(instance, "a", undef_u32);
    ctx.setProp(color_class, "new", v8.FunctionTemplate.initCallback(isolate, csColor_New));
    const colors = &[_]std.meta.Tuple(&.{[]const u8, Color}){
        .{"LightGray", Color.LightGray},
        .{"Gray", Color.Gray},
        .{"DarkGray", Color.DarkGray},
        .{"Yellow", Color.Yellow},
        .{"Gold", Color.Gold},
        .{"Orange", Color.Orange},
        .{"Pink", Color.Pink},
        .{"Red", Color.Red},
        .{"Maroon", Color.Maroon},
        .{"Green", Color.Green},
        .{"Lime", Color.Lime},
        .{"DarkGreen", Color.DarkGreen},
        .{"SkyBlue", Color.SkyBlue},
        .{"Blue", Color.Blue},
        .{"DarkBlue", Color.DarkBlue},
        .{"Purple", Color.Purple},
        .{"Violet", Color.Violet},
        .{"DarkPurple", Color.DarkPurple},
        .{"Beige", Color.Beige},
        .{"Brown", Color.Brown},
        .{"DarkBrown", Color.DarkBrown},
        .{"White", Color.White},
        .{"Black", Color.Black},
        .{"Transparent", Color.Transparent},
        .{"Magenta", Color.Magenta},
    };
    inline for (colors) |it| {
        ctx.setFuncGetter(color_class, it.@"0", it.@"1");
    }
    ctx.color_class = color_class;

    const global_constructor = v8.FunctionTemplate.initDefault(isolate);
    global_constructor.setClassName(v8.String.initUtf8(isolate, "Global"));
    // Since Context.init only accepts ObjectTemplate, we can still name the global by using a FunctionTemplate as the constructor.
    const global = v8.ObjectTemplate.init(isolate, global_constructor);

    // cs
    const cs_constructor = v8.FunctionTemplate.initDefault(isolate);
    cs_constructor.setClassName(v8.String.initUtf8(isolate, "cosmic"));
    const cs = v8.ObjectTemplate.init(isolate, cs_constructor);

    // cs.window
    const window_constructor = v8.FunctionTemplate.initDefault(isolate);
    window_constructor.setClassName(v8.String.initUtf8(isolate, "window"));
    const window = v8.ObjectTemplate.init(isolate, window_constructor);
    ctx.setConstFuncT(window, "new", window_New);
    ctx.setConstProp(cs, "window", window);

    // cs.graphics
    const cs_graphics = v8.ObjectTemplate.initDefault(isolate);

    // cs.graphics.Color
    ctx.setConstProp(cs_graphics, "Color", color_class);
    ctx.setConstProp(cs, "graphics", cs_graphics);

    const graphics_class = v8.FunctionTemplate.initDefault(isolate);
    graphics_class.setClassName(v8.String.initUtf8(isolate, "Graphics"));
    {
        const proto = graphics_class.getPrototypeTemplate();
        ctx.setAccessor(proto, "fillColor", graphics_GetFillColor, graphics_SetFillColor);
        ctx.setAccessor(proto, "strokeColor", graphics_GetStrokeColor, graphics_SetStrokeColor);
        ctx.setAccessor(proto, "lineWidth", graphics_GetLineWidth, graphics_SetLineWidth);

        ctx.setConstFuncT(proto, "fillRect", graphics_FillRect);
        ctx.setConstFuncT(proto, "drawRect", graphics_DrawRect);
    }

    ctx.setConstProp(global, "cs", cs);
    ctx.setConstProp(global, "print", v8.FunctionTemplate.initCallback(isolate, print));

    const res = v8.Context.init(isolate, global, null);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(isolate, "cs")).castToObject();
    // For now, just create one JsGraphics instance for everything.
    ctx.js_graphics = graphics_class.getFunction(res).newInstance(res, &.{}).?;

    return res;
}

fn window_New(title: []const u8, width: u32, height: u32) v8.Object {
    log.debug("dim {} {}", .{width, height});

    const isolate = rt.cur_isolate;
    const ctx = isolate.getCurrentContext();
    const res = rt.createCsWindowResource();

    const js_window = rt.window_class.initInstance(ctx);
    log.debug("js_window ptr {*}", .{js_window.handle});
    const js_window_id = v8.Integer.initU32(isolate, res.id);
    js_window.setInternalField(0, js_window_id);

    const window = graphics.Window.init(rt.alloc, .{
        .width = width,
        .height = height,
        .title = title,
    }) catch unreachable;
    res.ptr.init(rt.alloc, window, v8.Persistent.init(isolate, js_window));

    rt.active_window = res.ptr;
    rt.active_graphics = rt.active_window.graphics;

    return js_window;
}

fn window_OnDrawFrame(this: v8.Object, arg: v8.Function) void {
    const isolate = rt.cur_isolate;
    const ctx = rt.cur_isolate.getCurrentContext();
    const window_id = this.getInternalField(0).toU32(ctx);

    const res = rt.resources.get(window_id);
    if (res.tag == .CsWindow) {
        const window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
        
        // Persist callback func.
        const p = v8.Persistent.init(isolate, arg);
        window.onDrawFrameCbs.append(p.castToFunction()) catch unreachable;
    }
}

fn color_Lighter(this: v8.Object) Color {
    const ctx = rt.cur_isolate.getCurrentContext();
    return getNativeValue(rt.cur_isolate, ctx, Color, this.toValue()).?.lighter();
}

fn color_Darker(this: v8.Object) Color {
    const ctx = rt.cur_isolate.getCurrentContext();
    return getNativeValue(rt.cur_isolate, ctx, Color, this.toValue()).?.darker();
}

fn csColor_New(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var r: u32 = 0;
    var g: u32 = 0;
    var b: u32 = 0;
    var a: u32 = 255;

    const len = info.length();
    if (len == 3) {
        r = info.getArg(0).toU32(ctx);
        g = info.getArg(1).toU32(ctx);
        b = info.getArg(2).toU32(ctx);
    } else if (len == 4) {
        r = info.getArg(0).toU32(ctx);
        g = info.getArg(1).toU32(ctx);
        b = info.getArg(2).toU32(ctx);
        a = info.getArg(3).toU32(ctx);
    } else {
        v8.throwErrorException(isolate, "Expected (r, g, b) or (r, g, b, a)");
        return;
    }

    const new = rt.color_class.getFunction(ctx).newInstance(ctx, &.{}).?;
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "r"), v8.Integer.initU32(isolate, r));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "g"), v8.Integer.initU32(isolate, g));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "b"), v8.Integer.initU32(isolate, b));
    _ = new.setValue(ctx, v8.String.initUtf8(isolate, "a"), v8.Integer.initU32(isolate, a));

    const return_value = info.getReturnValue();
    return_value.set(new);
}

fn graphics_GetLineWidth() f32 {
    return rt.active_graphics.getLineWidth();
}

fn graphics_GetStrokeColor() Color {
    return rt.active_graphics.getStrokeColor();
}

fn graphics_SetStrokeColor(color: Color) void {
    rt.active_graphics.setStrokeColor(color);
}

fn graphics_DrawRect(x: f32, y: f32, width: f32, height: f32) void {
    rt.active_graphics.drawRect(x, y, width, height);
}

fn graphics_FillRect(x: f32, y: f32, width: f32, height: f32) void {
    rt.active_graphics.fillRect(x, y, width, height);
}

fn graphics_SetLineWidth(width: f32) void {
    rt.active_graphics.setLineWidth(width);
}

fn graphics_SetFillColor(color: Color) void {
    rt.active_graphics.setFillColor(color);
}

fn graphics_GetFillColor() Color {
    return rt.active_graphics.getFillColor();
}

fn print(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const len = info.length();

    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();
    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const str = v8.valueToUtf8Alloc(rt.alloc, isolate, ctx, info.getArg(i));
        defer rt.alloc.free(str);
        printFmt("{s} ", .{str});
    }
    printFmt("\n", .{});
}

fn getNativeValue(isolate: v8.Isolate, ctx: v8.Context, comptime T: type, val: v8.Value) ?T {
    switch (T) {
        []const u8 => {
            return v8.appendValueAsUtf8(&rt.cb_str_buf, isolate, ctx, val);
        },
        u32 => return val.toU32(ctx),
        f32 => return val.toF32(ctx),
        Color => {
            if (val.isObject()) {
                const obj = val.castToObject();
                const r = obj.getValue(ctx, v8.String.initUtf8(isolate, "r")).toU32(ctx);
                const g = obj.getValue(ctx, v8.String.initUtf8(isolate, "g")).toU32(ctx);
                const b = obj.getValue(ctx, v8.String.initUtf8(isolate, "b")).toU32(ctx);
                const a = obj.getValue(ctx, v8.String.initUtf8(isolate, "a")).toU32(ctx);
                return Color.init(
                    @intCast(u8, r),
                    @intCast(u8, g),
                    @intCast(u8, b),
                    @intCast(u8, a),
                );
            } else return null;
        },
        v8.Function => {
            if (val.isFunction()) {
                return val.castToFunction();
            } else return null;
        },
        else => comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from v8.Value to {s}", .{@typeName(T)})),
    }
}

// native_cb: fn (Param) void
pub fn genJsSetter(comptime native_fn: anytype) v8.AccessorNameSetterCallback {
    const Param = stdx.meta.FunctionArgs(@TypeOf(native_fn))[0].arg_type.?;
    const gen = struct {
        fn set(_: ?*const v8.Name, value: ?*const c_void, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
            const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const val = v8.Value{ .handle = value.? };

            if (getNativeValue(isolate, ctx, Param, val)) |native_val| {
                native_fn(native_val);
            } else {
                v8.throwErrorExceptionFmt(rt.alloc, isolate, "Could not convert to {s}", .{@typeName(Param)});
                return;
            }
        }
    };
    return gen.set;
}

pub fn genJsFuncGetValue(comptime native_val: anytype) v8.FunctionCallback {
    const gen = struct {
        fn cb(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const return_value = info.getReturnValue();
            return_value.setValueHandle(getJsValue(isolate, ctx, native_val));
        }
    };
    return gen.cb;
}

/// Returns raw value pointer so we don't need to convert back to a v8.Value.
pub fn getJsValue(isolate: v8.Isolate, ctx: v8.Context, native_val: anytype) *const c_void {
    const Type = @TypeOf(native_val);
    switch (Type) {
        f32 => return v8.Number.init(isolate, native_val).handle,
        Color => {
            const new = rt.color_class.getFunction(ctx).newInstance(ctx, &.{}).?;
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "r"), v8.Integer.initU32(isolate, native_val.channels.r));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "g"), v8.Integer.initU32(isolate, native_val.channels.g));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "b"), v8.Integer.initU32(isolate, native_val.channels.b));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "a"), v8.Integer.initU32(isolate, native_val.channels.a));
            return new.handle;
        },
        v8.Object => {
            return native_val.handle;
        },
        else => comptime @compileError(std.fmt.comptimePrint("Unsupported conversion from {s} to js.", .{@typeName(Type)})),
    }
}

/// native_cb: fn () Param
pub fn genJsGetter(comptime native_cb: anytype) v8.AccessorNameGetterCallback {
    const gen = struct {
        fn get(_: ?*const v8.Name, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
            const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const return_value = info.getReturnValue();
            return_value.setValueHandle(getJsValue(isolate, ctx, native_cb()));
        }
    };
    return gen.get;
}

pub fn genJsFunc(comptime native_fn: anytype) v8.FunctionCallback {
    const gen = struct {
        fn cb(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const arg_types_t = std.meta.ArgsTuple(@TypeOf(native_fn));
            const arg_fields = std.meta.fields(arg_types_t);

            // If first param is v8.Object then it refers to "this".
            const has_this_arg = arg_fields.len > 0 and arg_fields[0].field_type == v8.Object;
            const final_arg_fields = if (has_this_arg) arg_fields[1..] else arg_fields;

            if (info.length() < final_arg_fields.len) {
                v8.throwErrorExceptionFmt(rt.alloc, isolate, "Expected {} args.", .{final_arg_fields.len});
                return;
            }

            const has_string_param = b: {
                inline for (final_arg_fields) |field| {
                    if (field.field_type == []const u8) {
                        break :b true;
                    }
                }
                break :b false;
            };
            if (has_string_param) {
                // Clear the converted string buffer if too large.
                if (rt.cb_str_buf.items.len > 1000 * 1000) {
                    rt.cb_str_buf.clearRetainingCapacity();
                }
            }

            var native_args: arg_types_t = undefined;
            if (has_this_arg) {
                @field(native_args, arg_fields[0].name) = info.getThis(); 
            }
            inline for (final_arg_fields) |field, i| {
                if (getNativeValue(isolate, ctx, field.field_type, info.getArg(i))) |native_val| {
                    @field(native_args, field.name) = native_val;
                }
            }
            if (stdx.meta.FunctionReturnType(@TypeOf(native_fn)) == void) {
                @call(.{}, native_fn, native_args);
            } else {
                const new = getJsValue(isolate, ctx, @call(.{}, native_fn, native_args));
                const return_value = info.getReturnValue();
                return_value.setValueHandle(new);
            }
        }
    };
    return gen.cb;
}