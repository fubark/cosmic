const std = @import("std");
const stdx = @import("stdx");
const string = stdx.string;
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const Color = graphics.Color;
const ds = stdx.ds;

const v8 = @import("v8.zig");
const runtime = @import("runtime.zig");
const SizedJsString = runtime.SizedJsString;
const RuntimeContext = runtime.RuntimeContext;
const V8Context = runtime.V8Context;
const ContextBuilder = runtime.ContextBuilder;
const PromiseId = runtime.PromiseId;
const RuntimeValue = runtime.RuntimeValue;
const printFmt = runtime.printFmt;
const ManagedSlice = runtime.ManagedSlice;
const ManagedStruct = runtime.ManagedStruct;
const ThisResource = runtime.ThisResource;
const This = runtime.This;
const Data = runtime.Data;
const log = stdx.log.scoped(.js_env);
const tasks = @import("tasks.zig");
const work_queue = @import("work_queue.zig");
const TaskOutput = work_queue.TaskOutput;
const _server = @import("server.zig");
const HttpServer = _server.HttpServer;
const ResponseWriter = _server.ResponseWriter;
const api = @import("api.zig");

const uv = @import("uv");
const h2o = @import("h2o");

// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
// A parent HandleScope should persist the values we create in here until the end of the script execution.
// At this point rt.v8_ctx should be assumed to be undefined since we haven't created a v8.Context yet.
pub fn initContext(rt: *RuntimeContext, iso: v8.Isolate) v8.Context {
    const ctx = ContextBuilder{
        .rt = rt,
        .isolate = iso,
    };

    // We set with the same undef values for each type, it might help the optimizing compiler if it knows the field types ahead of time.
    const undef_u32 = v8.Integer.initU32(iso, 0);

    // GenericHandle
    const handle_class = v8.ObjectTemplate.initDefault(iso);
    handle_class.setInternalFieldCount(1);
    rt.handle_class = handle_class;

    // GenericObject
    rt.default_obj_t = v8.ObjectTemplate.initDefault(iso);

    // JsWindow
    const window_class = v8.FunctionTemplate.initDefault(iso);
    {
        const inst = window_class.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = window_class.getPrototypeTemplate();
        ctx.setFuncT(proto, "onDrawFrame", api.window_OnDrawFrame);
        ctx.setFuncT(proto, "getGraphics", api.window_GetGraphics);
    }
    rt.window_class = window_class;

    // JsGraphics
    const graphics_class = v8.FunctionTemplate.initDefault(iso);
    graphics_class.setClassName(v8.String.initUtf8(iso, "Graphics"));
    {
        const inst = graphics_class.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = graphics_class.getPrototypeTemplate();
        ctx.setAccessor(proto, "fillColor", Graphics.getFillColor, Graphics.setFillColor);
        ctx.setAccessor(proto, "strokeColor", Graphics.getStrokeColor, Graphics.setStrokeColor);
        ctx.setAccessor(proto, "lineWidth", Graphics.getLineWidth, Graphics.setLineWidth);

        ctx.setConstFuncT(proto, "fillRect", Graphics.fillRect);
        ctx.setConstFuncT(proto, "drawRect", Graphics.drawRect);
        ctx.setConstFuncT(proto, "translate", Graphics.translate);
        ctx.setConstFuncT(proto, "rotateDeg", Graphics.rotateDeg);
        ctx.setConstFuncT(proto, "resetTransform", Graphics.resetTransform);
        ctx.setConstFuncT(proto, "newImage", graphics_NewImage);
        ctx.setConstFuncT(proto, "addTtfFont", graphics_AddTtfFont);
        ctx.setConstFuncT(proto, "addFallbackFont", Graphics.addFallbackFont);
        ctx.setConstFuncT(proto, "setFont", Graphics.setFont);
        ctx.setConstFuncT(proto, "fillText", Graphics.fillText);
        ctx.setConstFuncT(proto, "fillCircle", Graphics.fillCircle);
        ctx.setConstFuncT(proto, "fillCircleSectorDeg", Graphics.fillCircleSectorDeg);
        ctx.setConstFuncT(proto, "drawCircle", Graphics.drawCircle);
        ctx.setConstFuncT(proto, "drawCircleArcDeg", Graphics.drawCircleArcDeg);
        ctx.setConstFuncT(proto, "fillEllipse", Graphics.fillEllipse);
        ctx.setConstFuncT(proto, "fillEllipseSectorDeg", Graphics.fillEllipseSectorDeg);
        ctx.setConstFuncT(proto, "drawEllipse", Graphics.drawEllipse);
        ctx.setConstFuncT(proto, "drawEllipseArcDeg", Graphics.drawEllipseArcDeg);
        ctx.setConstFuncT(proto, "fillTriangle", Graphics.fillTriangle);
        ctx.setConstFuncT(proto, "fillConvexPolygon", api.graphics_FillConvexPolygon);
        ctx.setConstFuncT(proto, "fillPolygon", api.graphics_FillPolygon);
        ctx.setConstFuncT(proto, "drawPolygon", api.graphics_DrawPolygon);
        ctx.setConstFuncT(proto, "fillRoundRect", Graphics.fillRoundRect);
        ctx.setConstFuncT(proto, "drawRoundRect", Graphics.drawRoundRect);
        ctx.setConstFuncT(proto, "drawPoint", Graphics.drawPoint);
        ctx.setConstFuncT(proto, "drawLine", Graphics.drawLine);
        ctx.setConstFuncT(proto, "drawSvgContent", api.graphics_DrawSvgContent);
        ctx.setConstFuncT(proto, "compileSvgContent", api.graphics_CompileSvgContent);
        ctx.setConstFuncT(proto, "executeDrawList", api.graphics_ExecuteDrawList);
        ctx.setConstFuncT(proto, "drawQuadraticBezierCurve", Graphics.drawQuadraticBezierCurve);
        ctx.setConstFuncT(proto, "drawCubicBezierCurve", Graphics.drawCubicBezierCurve);
        ctx.setConstFuncT(proto, "drawImageSized", api.graphics_DrawImageSized);
    }
    rt.graphics_class = graphics_class;

    // JsImage
    const image_class = ctx.initFuncT("Image");
    {
        const inst = image_class.getInstanceTemplate();
        ctx.setProp(inst, "width", undef_u32);
        ctx.setProp(inst, "height", undef_u32);
        // For image id.
        inst.setInternalFieldCount(1);
    }
    rt.image_class = image_class;

    // JsColor
    const color_class = v8.FunctionTemplate.initDefault(iso);
    {
        const proto = color_class.getPrototypeTemplate();
        ctx.setFuncT(proto, "darker", api.color_Darker);
        ctx.setFuncT(proto, "lighter", api.color_Lighter);
        ctx.setFuncT(proto, "withAlpha", api.color_WithAlpha);
    }
    var instance = color_class.getInstanceTemplate();
    ctx.setProp(instance, "r", undef_u32);
    ctx.setProp(instance, "g", undef_u32);
    ctx.setProp(instance, "b", undef_u32);
    ctx.setProp(instance, "a", undef_u32);
    ctx.setFuncT(color_class, "new", api.color_New);
    const colors = &[_]std.meta.Tuple(&.{ []const u8, Color }){
        .{ "LightGray", Color.LightGray },
        .{ "Gray", Color.Gray },
        .{ "DarkGray", Color.DarkGray },
        .{ "Yellow", Color.Yellow },
        .{ "Gold", Color.Gold },
        .{ "Orange", Color.Orange },
        .{ "Pink", Color.Pink },
        .{ "Red", Color.Red },
        .{ "Maroon", Color.Maroon },
        .{ "Green", Color.Green },
        .{ "Lime", Color.Lime },
        .{ "DarkGreen", Color.DarkGreen },
        .{ "SkyBlue", Color.SkyBlue },
        .{ "Blue", Color.Blue },
        .{ "DarkBlue", Color.DarkBlue },
        .{ "Purple", Color.Purple },
        .{ "Violet", Color.Violet },
        .{ "DarkPurple", Color.DarkPurple },
        .{ "Beige", Color.Beige },
        .{ "Brown", Color.Brown },
        .{ "DarkBrown", Color.DarkBrown },
        .{ "White", Color.White },
        .{ "Black", Color.Black },
        .{ "Transparent", Color.Transparent },
        .{ "Magenta", Color.Magenta },
    };
    inline for (colors) |it| {
        ctx.setFuncGetter(color_class, it.@"0", it.@"1");
    }
    rt.color_class = color_class;

    const global_constructor = iso.initFunctionTemplateDefault();
    global_constructor.setClassName(iso.initStringUtf8("Global"));
    // Since Context.init only accepts ObjectTemplate, we can still name the global by using a FunctionTemplate as the constructor.
    const global = v8.ObjectTemplate.init(iso, global_constructor);

    // cs
    const cs_constructor = iso.initFunctionTemplateDefault();
    cs_constructor.setClassName(iso.initStringUtf8("cosmic"));
    const cs = v8.ObjectTemplate.init(iso, cs_constructor);

    // cs.window
    const window_constructor = iso.initFunctionTemplateDefault();
    window_constructor.setClassName(iso.initStringUtf8("window"));
    const window = iso.initObjectTemplate(window_constructor);
    ctx.setConstFuncT(window, "new", api.window_New);
    ctx.setConstProp(cs, "window", window);

    // cs.files
    const files_constructor = iso.initFunctionTemplateDefault();
    files_constructor.setClassName(iso.initStringUtf8("files"));
    const files = iso.initObjectTemplate(files_constructor);
    ctx.setConstFuncT(files, "readFile", api.files_readFile);
    ctx.setConstFuncT(files, "writeFile", api.files_writeFile);
    ctx.setConstFuncT(files, "appendFile", api.files_appendFile);
    ctx.setConstFuncT(files, "removeFile", api.files_removeFile);
    ctx.setConstFuncT(files, "ensurePath", api.files_ensurePath);
    ctx.setConstFuncT(files, "pathExists", api.files_pathExists);
    ctx.setConstFuncT(files, "removeDir", api.files_removeDir);
    ctx.setConstFuncT(files, "resolvePath", api.files_resolvePath);
    ctx.setConstFuncT(files, "copyFile", api.files_copyFile);
    ctx.setConstFuncT(files, "moveFile", api.files_moveFile);
    ctx.setConstFuncT(files, "cwd", api.files_cwd);
    ctx.setConstFuncT(files, "getPathInfo", api.files_getPathInfo);
    ctx.setConstFuncT(files, "listDir", api.files_listDir);
    // ctx.setConstFuncT(files, "openFile", files_OpenFile);
    ctx.setConstProp(cs, "files", files);

    ctx.setConstAsyncFuncT(files, "readFileAsync", api.files_readFile);
    ctx.setConstAsyncFuncT(files, "writeFileAsync", api.files_writeFile);
    ctx.setConstAsyncFuncT(files, "appendFileAsync", api.files_appendFile);
    ctx.setConstAsyncFuncT(files, "removeFileAsync", api.files_removeFile);
    ctx.setConstAsyncFuncT(files, "removeDirAsync", api.files_removeDir);
    ctx.setConstAsyncFuncT(files, "ensurePathAsync", api.files_ensurePath);
    ctx.setConstAsyncFuncT(files, "pathExistsAsync", api.files_pathExists);
    ctx.setConstAsyncFuncT(files, "copyFileAsync", api.files_copyFile);
    ctx.setConstAsyncFuncT(files, "moveFileAsync", api.files_moveFile);
    ctx.setConstAsyncFuncT(files, "getPathInfoAsync", api.files_getPathInfo);
    ctx.setConstAsyncFuncT(files, "listDirAsync", api.files_listDir);
    // TODO: chmod op

    // cs.http
    const http_constructor = iso.initFunctionTemplateDefault();
    http_constructor.setClassName(iso.initStringUtf8("http"));
    const http = iso.initObjectTemplate(http_constructor);
    ctx.setConstFuncT(http, "get", api.http_get);
    ctx.setConstFuncT(http, "getAsync", api.http_getAsync);
    ctx.setConstFuncT(http, "_request", api.http_request);
    ctx.setConstAsyncFuncT(http, "_requestAsync", api.http_request);
    ctx.setConstFuncT(http, "serveHttp", api.http_serveHttp);
    ctx.setConstFuncT(http, "serveHttps", api.http_serveHttps);
    // cs.http.Response
    const response_class = v8.FunctionTemplate.initDefault(iso);
    response_class.setClassName(v8.String.initUtf8(iso, "Response"));
    ctx.setConstProp(http, "Response", response_class);
    rt.http_response_class = response_class;
    {
        // cs.http.Server
        const server_class = iso.initFunctionTemplateDefault();
        server_class.setClassName(iso.initStringUtf8("Server"));

        const inst = server_class.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = server_class.getPrototypeTemplate();
        ctx.setConstFuncT(proto, "setHandler", HttpServer.setHandler);
        ctx.setConstFuncT(proto, "requestClose", HttpServer.requestClose);
        ctx.setConstFuncT(proto, "closeAsync", HttpServer.closeAsync);

        ctx.setConstProp(http, "Server", server_class);
        rt.http_server_class = server_class;
    }
    {
        // cs.http.ResponseWriter
        const constructor = iso.initFunctionTemplateDefault();
        constructor.setClassName(iso.initStringUtf8("ResponseWriter"));

        const obj_t = iso.initObjectTemplate(constructor);
        ctx.setConstFuncT(obj_t, "setStatus", ResponseWriter.setStatus);
        ctx.setConstFuncT(obj_t, "setHeader", ResponseWriter.setHeader);
        ctx.setConstFuncT(obj_t, "send", ResponseWriter.send);
        rt.http_response_writer = obj_t;
    }
    ctx.setConstProp(cs, "http", http);

    if (rt.is_test_env) {
        // cs.test
        ctx.setConstFuncT(cs, "test", createTest);

        // cs.testIsolated
        ctx.setConstFuncT(cs, "testIsolated", createIsolatedTest);

        // cs.asserts
        const cs_asserts = iso.initObjectTemplateDefault();

        ctx.setConstProp(cs, "asserts", cs_asserts);
    }

    // cs.graphics
    const cs_graphics = v8.ObjectTemplate.initDefault(iso);

    // cs.graphics.Color
    ctx.setConstProp(cs_graphics, "Color", color_class);
    ctx.setConstProp(cs, "graphics", cs_graphics);

    ctx.setConstProp(global, "cs", cs);
    const rt_data = iso.initExternal(rt);
    ctx.setConstProp(global, "print", iso.initFunctionTemplateCallbackData(api.print, rt_data));

    const res = iso.initContext(global, null);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(iso, "cs")).castToObject();

    return res;
}

/// Path can be absolute or relative to the current executing script.
fn resolveEnvPath(rt: *RuntimeContext, path: []const u8) []const u8 {
    return std.fs.path.resolve(rt.alloc, &.{ rt.cur_script_dir_abs, path }) catch unreachable;
}

const Promise = struct {
    task_id: u32,
};

pub fn passIsolatedTest(rt: *RuntimeContext) void {
    rt.num_isolated_tests_finished += 1;
    rt.num_tests_passed += 1;
}

pub fn passAsyncTest(rt: *RuntimeContext) void {
    rt.num_async_tests_passed += 1;
    rt.num_async_tests_finished += 1;
    rt.num_tests_passed += 1;
}

pub fn reportAsyncTestFailure(data: Data, val: v8.Value) void {
    const obj = data.val.castToObject();
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castToExternal().get());

    const test_name = v8.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    // TODO: report stack trace.
    rt.num_async_tests_finished += 1;
    const str = v8.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, val);
    defer rt.alloc.free(str);

    printFmt("Test Failed: \"{s}\"\n{s}\n", .{test_name, str});
}

pub fn reportIsolatedTestFailure(data: Data, val: v8.Value) void {
    const obj = data.val.castToObject();
    const rt = stdx.mem.ptrCastAlign(*RuntimeContext, obj.getInternalField(0).castToExternal().get());

    const test_name = v8.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, obj.getInternalField(1));
    defer rt.alloc.free(test_name);

    rt.num_isolated_tests_finished += 1;
    const str = v8.valueToUtf8Alloc(rt.alloc, rt.isolate, rt.context, val);
    defer rt.alloc.free(str);

    // TODO: Show stack trace.
    printFmt("Test Failed: \"{s}\"\n{s}\n", .{test_name, str});
}

/// Currently meant for async tests that need to be run sequentially after all sync tests have ran.
fn createIsolatedTest(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
    if (!cb.toValue().isAsyncFunction()) {
        v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Test \"{s}\": Only async tests can use testIsolated.", .{name});
        return;
    }
    rt.num_tests += 1;
    // Store the function to be run later.
    rt.isolated_tests.append(.{
        .name = rt.alloc.dupe(u8, name) catch unreachable,
        .js_fn = rt.isolate.initPersistent(v8.Function, cb),
    }) catch unreachable;
}

// FUTURE: Save test cases and execute them in parallel.
fn createTest(rt: *RuntimeContext, name: []const u8, cb: v8.Function) void {
    const iso = rt.isolate;
    const ctx = rt.context;

    // Dupe name since we will be invoking functions that could clear the transient string buffer.
    const name_dupe = rt.alloc.dupe(u8, name) catch unreachable;
    defer rt.alloc.free(name_dupe);

    var hscope: v8.HandleScope = undefined;
    hscope.init(iso);
    defer hscope.deinit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(iso);
    defer try_catch.deinit();

    rt.num_tests += 1;
    if (cb.toValue().isAsyncFunction()) {
        // Async test.
        rt.num_async_tests += 1;
        if (cb.call(ctx, rt.js_undefined, &.{})) |val| {
            const promise = val.castToPromise();

            const data = iso.initExternal(rt);
            const on_fulfilled = v8.Function.initWithData(ctx, genJsFuncSync(passAsyncTest), data);

            const tmpl = iso.initObjectTemplateDefault();
            tmpl.setInternalFieldCount(2);
            const extra_data = tmpl.initInstance(ctx);
            extra_data.setInternalField(0, data);
            extra_data.setInternalField(1, iso.initStringUtf8(name_dupe));
            const on_rejected = v8.Function.initWithData(ctx, genJsFunc(reportAsyncTestFailure, false, false), extra_data);

            _ = promise.thenAndCatch(ctx, on_fulfilled, on_rejected);
        } else {
            const err_str = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
            defer rt.alloc.free(err_str);
            printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
        }
    } else {
        // Sync test.
        if (cb.call(ctx, rt.js_undefined, &.{})) |_| {
            rt.num_tests_passed += 1;
        } else {
            const err_str = v8.getTryCatchErrorString(rt.alloc, iso, ctx, try_catch).?;
            defer rt.alloc.free(err_str);
            printFmt("Test: {s}\n{s}", .{ name_dupe, err_str });
        }
    }
}

/// Path can be absolute or relative to the cwd.
fn graphics_NewImage(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.Image {
    return g.createImageFromPath(path) catch |err| {
        if (err == error.FileNotFound) {
            v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
            return undefined;
        } else {
            unreachable;
        }
    };
}

/// Path can be absolute or relative to the cwd.
fn graphics_AddTtfFont(rt: *RuntimeContext, g: *Graphics, path: []const u8) graphics.font.FontId {
    return g.addTTF_FontFromPath(path) catch |err| {
        if (err == error.FileNotFound) {
            v8.throwErrorExceptionFmt(rt.alloc, rt.isolate, "Could not find file: {s}", .{path});
            return 0;
        } else {
            unreachable;
        }
    };
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
                        v8.throwErrorException(iso, "Handle has expired.");
                        return;
                    }
                } else {
                    native_cb(native_val);
                }
            } else {
                v8.throwErrorExceptionFmt(rt.alloc, iso, "Could not convert to {s}", .{@typeName(Param)});
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
        // TODO: slice should be wrapped by a struct that indicates that it should be freed by the current allocator.
        []const u8 => alloc.free(native_val),
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
                    v8.throwErrorException(iso, "Handle has expired.");
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

const JsFuncInfo = struct {
    this_field: ?std.builtin.TypeInfo.StructField,
    this_res_field: ?std.builtin.TypeInfo.StructField,
    native_ptr_field: ?std.builtin.TypeInfo.StructField,
    data_field: ?std.builtin.TypeInfo.StructField,
    rt_ptr_field: ?std.builtin.TypeInfo.StructField,
    func_arg_fields: []const std.builtin.TypeInfo.StructField,
};

fn getJsFuncInfo(comptime arg_fields: []const std.builtin.TypeInfo.StructField) JsFuncInfo {
    var res: JsFuncInfo = undefined;

    // First This param will receive "this".
    res.this_field = b: {
        inline for (arg_fields) |field| {
            if (field.field_type == This) {
                break :b field;
            }
        }
        break :b null;
    };

    // First pointer param that is not *RuntimeContext will receive this->getInternalField(0)
    res.native_ptr_field = b: {
        inline for (arg_fields) |field| {
            if (comptime std.meta.trait.isSingleItemPtr(field.field_type) and field.field_type != *RuntimeContext) {
                break :b field;
            }
        }
        break :b null;
    };

    // First ThisResource param will have their resource id from this->getInternalField(0) dereferenced.
    res.this_res_field = b: {
        inline for (arg_fields) |field| {
            if (@typeInfo(field.field_type) == .Struct and @hasDecl(field.field_type, "ThisResource")) {
                break :b field;
            }
        }
        break :b null;
    };

    // First Data param will receive the attached function data.
    res.data_field = b: {
        inline for (arg_fields) |field| {
            if (field.field_type == Data) {
                break :b field;
            }
        }
        break :b null;
    };

    // First *RuntimeContext param will receive the current rt pointer.
    res.rt_ptr_field = b: {
        inline for (arg_fields) |field| {
            if (field.field_type == *RuntimeContext) {
                break :b field;
            }
        }
        break :b null;
    };

    // Get required js func args.
    res.func_arg_fields = b: {
        var args: []const std.builtin.TypeInfo.StructField = &.{};
        inline for (arg_fields) |field| {
            var is_func_arg = true;
            if (res.this_field) |this_field| {
                if (std.mem.eql(u8, field.name, this_field.name)) {
                    is_func_arg = false;
                }
            }
            if (res.this_res_field) |this_res_field| {
                if (std.mem.eql(u8, field.name, this_res_field.name)) {
                    is_func_arg = false;
                }
            }
            if (res.data_field) |data_field| {
                if (std.mem.eql(u8, field.name, data_field.name)) {
                    is_func_arg = false;
                }
            }
            if (res.native_ptr_field) |native_ptr_field| {
                if (std.mem.eql(u8, field.name, native_ptr_field.name)) {
                    is_func_arg = false;
                }
            }
            if (res.rt_ptr_field) |rt_ptr_field| {
                if (std.mem.eql(u8, field.name, rt_ptr_field.name)) {
                    is_func_arg = false;
                }
            }
            if (is_func_arg) {
                args = args ++ &[_]std.builtin.TypeInfo.StructField{field};
            }
        }
        break :b args;
    };

    return res;
}

pub fn genJsFuncSync(comptime native_fn: anytype) v8.FunctionCallback {
    return genJsFunc(native_fn, false, true);
}

pub fn genJsFuncAsync(comptime native_fn: anytype) v8.FunctionCallback {
    return genJsFunc(native_fn, true, true);
}

/// Calling v8.throwErrorException inside a native callback function will trigger in v8 when the callback returns.
pub fn genJsFunc(comptime native_fn: anytype, comptime is_async: bool, comptime is_data_rt: bool) v8.FunctionCallback {
    const NativeFn = @TypeOf(native_fn);
    const gen = struct {
        fn cb(raw_info: ?*const v8.C_FunctionCallbackInfo) callconv(.C) void {
            const info = v8.FunctionCallbackInfo.initFromV8(raw_info);

            // RT handle is either data or the first field of data.
            const rt = if (is_data_rt) stdx.mem.ptrCastAlign(*RuntimeContext, info.getExternalValue())
                else stdx.mem.ptrCastAlign(*RuntimeContext, info.getData().castToObject().getInternalField(0).castToExternal().get());

            const iso = rt.isolate;
            const ctx = rt.context;

            var hscope: v8.HandleScope = undefined;
            hscope.init(iso);
            defer hscope.deinit();

            const arg_types_t = std.meta.ArgsTuple(NativeFn);
            const arg_fields = std.meta.fields(arg_types_t);

            const ct_info = comptime getJsFuncInfo(arg_fields);

            if (info.length() < ct_info.func_arg_fields.len) {
                v8.throwErrorExceptionFmt(rt.alloc, iso, "Expected {} args.", .{ct_info.func_arg_fields.len});
                return;
            }

            const has_string_param: bool = b: {
                inline for (ct_info.func_arg_fields) |field| {
                    if (field.field_type == []const u8) {
                        break :b true;
                    }
                }
                break :b false;
            };
            const has_f32_slice_param: bool = b: {
                inline for (ct_info.func_arg_fields) |field| {
                    if (field.field_type == []const f32) {
                        break :b true;
                    }
                }
                break :b false;
            };
            // This stores the JsValue to JsString conversion to be accessed later to go from JsString to []const u8
            // It should be optimized out for functions without string params.
            var js_strs: [ct_info.func_arg_fields.len]SizedJsString = undefined;
            if (has_string_param) {
                // Since we are converting js strings to native []const u8,
                // we need to make sure the buffer capacity is enough before appending the args or a realloc could invalidate the slice.
                // This also means we need to do the JsValue to JsString conversion here and store it in memory.
                var total_size: u32 = 0;
                inline for (ct_info.func_arg_fields) |field, i| {
                    if (field.field_type == []const u8) {
                        const js_str = info.getArg(i).toString(ctx);
                        const len = js_str.lenUtf8(iso);
                        total_size += len;
                        js_strs[i] = .{
                            .str = js_str,
                            .len = len,
                        };
                    }
                }
                rt.cb_str_buf.clearRetainingCapacity();
                rt.cb_str_buf.ensureUnusedCapacity(total_size) catch unreachable;
            }
            if (has_f32_slice_param) {
                if (rt.cb_f32_buf.items.len > 1e6) {
                    rt.cb_f32_buf.clearRetainingCapacity();
                }
            }

            var native_args: arg_types_t = undefined;
            if (ct_info.this_field) |field| {
                @field(native_args, field.name) = This{ .obj = info.getThis() };
            }
            if (ct_info.this_res_field) |field| {
                const PtrType = stdx.meta.FieldType(field.field_type, .ptr);
                const res_id = info.getThis().getInternalField(0).castToInteger().getValueU32();
                if (rt.getResourcePtr(PtrType, res_id)) |ptr| {
                    @field(native_args, field.name) = ThisResource(PtrType){ .ptr = ptr };
                } else {
                    v8.throwErrorException(iso, "Native handle expired");
                    return;
                }
            }
            if (ct_info.data_field) |field| {
                @field(native_args, field.name) = .{ .val = info.getData() };
            }
            if (ct_info.native_ptr_field) |field| {
                const Ptr = field.field_type;
                const ptr = @ptrToInt(info.getThis().getInternalField(0).castToExternal().get());
                if (ptr > 0) {
                    @field(native_args, field.name) = @intToPtr(Ptr, ptr);
                } else {
                    v8.throwErrorException(iso, "Native handle expired");
                    return;
                }
            }
            if (ct_info.rt_ptr_field) |field| {
                @field(native_args, field.name) = rt;
            }
            var has_args = true;
            inline for (ct_info.func_arg_fields) |field, i| {
                if (field.field_type == []const u8) {
                    if (rt.getNativeValue(field.field_type, js_strs[i])) |native_val| {
                        if (is_async) {
                            // getNativeValue only returns temporary allocations. Dupe so it can be persisted.
                            if (@TypeOf(native_val) == []const u8) {
                                @field(native_args, field.name) = rt.alloc.dupe(u8, native_val) catch unreachable;
                            } else {
                                @field(native_args, field.name) = native_val;
                            }
                        } else {
                            @field(native_args, field.name) = native_val;
                        }
                    } else {
                        v8.throwErrorExceptionFmt(rt.alloc, iso, "Expected {s}", .{@typeName(field.field_type)});
                        has_args = false;
                    }
                } else {
                    if (rt.getNativeValue(field.field_type, info.getArg(i))) |native_val| {
                        @field(native_args, field.name) = native_val;
                    } else {
                        v8.throwErrorExceptionFmt(rt.alloc, iso, "Expected {s}", .{@typeName(field.field_type)});
                        // TODO: How to use return here without crashing compiler? Using a boolean var as a workaround.
                        has_args = false;
                    }
                }
            }
            if (!has_args) return;

            if (is_async) {
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
                        runtime.resolvePromise(_ctx.rt, _promise_id, .{
                            .handle = _ctx.rt.getJsValuePtr(_res),
                        });
                    }
                    fn onFailure(_ctx: RuntimeValue(PromiseId), _err: anyerror) void {
                        const _promise_id = _ctx.inner;
                        runtime.rejectPromise(_ctx.rt, _promise_id, .{
                            .handle = _ctx.rt.getJsValuePtr(_err),
                        });
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
                        v8.throwErrorExceptionFmt(rt.alloc, iso, "Error: {s}", .{@errorName(err)});
                        return;
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
