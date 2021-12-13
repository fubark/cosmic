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

// TODO: Use comptime to generate zig callback functions.
// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
pub fn init(ctx: *RuntimeContext, isolate: v8.Isolate) v8.Context {
    rt = ctx;

    // We set with the same undef values for each type, it might help the optimizing compiler if it knows the field types ahead of time.
    const undef_u32 = v8.Integer.initU32(isolate, 0);

    // JsWindow
    const window_class = v8.ObjectTemplate.initDefault(isolate);
    window_class.setInternalFieldCount(1);
    ctx.setProp(window_class, "onDrawFrame", v8.FunctionTemplate.initCallback(isolate, csWindow_OnDrawFrame));
    ctx.window_class = window_class;

    // JsColor
    const color_class = v8.FunctionTemplate.initDefault(isolate);
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
        ctx.setFuncGetter(color_class, it.@"0", csColor_Get(it.@"1"));
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
    ctx.setConstProp(window, "new", v8.FunctionTemplate.initCallback(isolate, csWindow_New));
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
        ctx.setAccessor(proto, "fillColor", csGraphics_GetFillColor, csGraphics_SetFillColor);
        ctx.setConstProp(proto, "fillRect", v8.FunctionTemplate.initCallback(isolate, csGraphics_FillRect));
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

fn csWindow_New(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    var title: []const u8 = undefined;
    var width: u32 = 800;
    var height: u32 = 600;

    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len >= 1) {
        title = v8.valueToUtf8Alloc(rt.alloc, isolate, ctx, info.getArg(0));
    } else {
        title = string.dupe(rt.alloc, "Window") catch unreachable;
    }
    defer rt.alloc.free(title);
    if (len >= 2) {
        width = info.getArg(1).toU32(ctx);
    }
    if (len >= 3) {
        height = info.getArg(2).toU32(ctx);
    }

    log.debug("dim {} {}", .{width, height});

    const res = rt.createCsWindowResource();

    const js_window = rt.window_class.initInstance(ctx);
    log.debug("js_window ptr {*}", .{js_window.handle});
    const js_window_id = v8.Integer.initU32(isolate, res.id);
    js_window.setInternalField(0, js_window_id);
    const return_value = info.getReturnValue();
    return_value.set(js_window);

    const window = graphics.Window.init(rt.alloc, .{
        .width = width,
        .height = height,
        .title = title,
    }) catch unreachable;
    res.ptr.init(rt.alloc, window, v8.Persistent.init(isolate, js_window));

    rt.active_window = res.ptr;
    rt.active_graphics = rt.active_window.graphics;
}

fn csWindow_OnDrawFrame(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len == 0) {
        v8.throwErrorException(isolate, "Expected callback arg");
        return;
    }
    const arg = info.getArg(0);
    if (!arg.isFunction()) {
        v8.throwErrorException(isolate, "Expected callback arg");
        return;
    }

    const this = info.getThis();
    const window_id = this.getInternalField(0).toU32(ctx);

    const res = rt.resources.get(window_id);
    if (res.tag == .CsWindow) {
        const window = stdx.mem.ptrCastAlign(*CsWindow, res.ptr);
        
        // Persist callback func.
        const p = v8.Persistent.init(isolate, arg);
        window.onDrawFrameCbs.append(p.castToFunction()) catch unreachable;
    }
}

fn csColor_Get(comptime c: Color) v8.FunctionCallback {
    const S = struct {
        fn get(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
            const isolate = info.getIsolate();
            const ctx = isolate.getCurrentContext();

            var hscope: v8.HandleScope = undefined;
            hscope.init(isolate);
            defer hscope.deinit();

            const new = rt.color_class.getFunction(ctx).newInstance(ctx, &.{}).?;
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "r"), v8.Integer.initU32(isolate, c.channels.r));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "g"), v8.Integer.initU32(isolate, c.channels.g));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "b"), v8.Integer.initU32(isolate, c.channels.b));
            _ = new.setValue(ctx, v8.String.initUtf8(isolate, "a"), v8.Integer.initU32(isolate, c.channels.a));

            const return_value = info.getReturnValue();
            return_value.set(new);
        }
    };
    return S.get;
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

fn csGraphics_GetFillColor(key: ?*const v8.Name, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
    const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    // const return_value = info.getReturnValue();
    // return_value.set();

    _ = key;
}

fn csGraphics_FillRect(raw_info: ?*const v8.RawFunctionCallbackInfo) callconv(.C) void {
    var x: f32 = 0;
    var y: f32 = 0;
    var width: f32 = 0;
    var height: f32 = 0;

    const info = v8.FunctionCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const len = info.length();
    if (len >= 1) {
        x = info.getArg(0).toF32(ctx);
    }
    if (len >= 2) {
        y = info.getArg(1).toF32(ctx);
    }
    if (len >= 3) {
        width = info.getArg(2).toF32(ctx);
    }
    if (len >= 4) {
        height = info.getArg(3).toF32(ctx);
    }

    rt.active_graphics.fillRect(x, y, width, height);
}

fn csGraphics_SetFillColor(key: ?*const v8.Name, value: ?*const c_void, raw_info: ?*const v8.RawPropertyCallbackInfo) callconv(.C) void {
    _ = key;
    const info = v8.PropertyCallbackInfo.initFromV8(raw_info);
    const isolate = info.getIsolate();
    const ctx = isolate.getCurrentContext();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const val = v8.Value{ .handle = value.? };
    if (val.isObject()) {
        const r = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "r")).toU32(ctx);
        const g = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "g")).toU32(ctx);
        const b = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "b")).toU32(ctx);
        const a = val.castToObject().getValue(ctx, v8.String.initUtf8(isolate, "a")).toU32(ctx);
        rt.active_graphics.setFillColor(Color.init(
            @intCast(u8, r),
            @intCast(u8, g),
            @intCast(u8, b),
            @intCast(u8, a),
        ));
    }
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
