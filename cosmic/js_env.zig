const std = @import("std");
const stdx = @import("stdx");
const string = stdx.string;
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const Color = graphics.Color;
const ds = stdx.ds;
const v8 = @import("v8");

const runtime = @import("runtime.zig");
const SizedJsString = runtime.SizedJsString;
const RuntimeContext = runtime.RuntimeContext;
const V8Context = runtime.V8Context;
const ContextBuilder = runtime.ContextBuilder;
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
        ctx.setFuncT(proto, "onDrawFrame", api.cs_window.onDrawFrame);
        ctx.setFuncT(proto, "getGraphics", api.cs_window.getGraphics);
    }
    rt.window_class = window_class;

    // JsGraphics
    const graphics_class = v8.FunctionTemplate.initDefault(iso);
    graphics_class.setClassName(v8.String.initUtf8(iso, "Graphics"));
    {
        const inst = graphics_class.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = graphics_class.getPrototypeTemplate();
        
        // NOTE: Accessors are callbacks anyway so it's probably not that much faster than a function call.
        // Although, I have not explored if there exists a native binding to some memory location.
        // For now, eep things consistent and use functions for fillColor/strokeColor/lineWidth. One less thing to gen docs for too.
        // ctx.setAccessor(proto, "fillColor", Graphics.getFillColor, Graphics.setFillColor);
        // ctx.setAccessor(proto, "strokeColor", Graphics.getStrokeColor, Graphics.setStrokeColor);
        // ctx.setAccessor(proto, "lineWidth", Graphics.getLineWidth, Graphics.setLineWidth);

        const Context = api.cs_graphics.Context;
        ctx.setConstFuncT(proto, "setFillColor", Context.setFillColor);
        ctx.setConstFuncT(proto, "fillColor", Context.fillColor);
        ctx.setConstFuncT(proto, "setStrokeColor", Context.setStrokeColor);
        ctx.setConstFuncT(proto, "strokeColor", Context.strokeColor);
        ctx.setConstFuncT(proto, "setLineWidth", Context.setLineWidth);
        ctx.setConstFuncT(proto, "lineWidth", Context.lineWidth);
        ctx.setConstFuncT(proto, "fillRect", Context.fillRect);
        ctx.setConstFuncT(proto, "drawRect", Context.drawRect);
        ctx.setConstFuncT(proto, "translate", Context.translate);
        ctx.setConstFuncT(proto, "scale", Context.scale);
        ctx.setConstFuncT(proto, "rotate", Context.rotate);
        ctx.setConstFuncT(proto, "rotateDeg", Context.rotateDeg);
        ctx.setConstFuncT(proto, "resetTransform", Context.resetTransform);
        ctx.setConstFuncT(proto, "newImage", Context.newImage);
        ctx.setConstFuncT(proto, "addTtfFont", Context.addTtfFont);
        ctx.setConstFuncT(proto, "addFallbackFont", Context.addFallbackFont);
        ctx.setConstFuncT(proto, "setFont", Context.setFont);
        ctx.setConstFuncT(proto, "fillText", Context.fillText);
        ctx.setConstFuncT(proto, "fillCircle", Context.fillCircle);
        ctx.setConstFuncT(proto, "fillCircleSector", Context.fillCircleSector);
        ctx.setConstFuncT(proto, "fillCircleSectorDeg", Context.fillCircleSectorDeg);
        ctx.setConstFuncT(proto, "drawCircle", Context.drawCircle);
        ctx.setConstFuncT(proto, "drawCircleArc", Context.drawCircleArc);
        ctx.setConstFuncT(proto, "drawCircleArcDeg", Context.drawCircleArcDeg);
        ctx.setConstFuncT(proto, "fillEllipse", Context.fillEllipse);
        ctx.setConstFuncT(proto, "fillEllipseSector", Context.fillEllipseSector);
        ctx.setConstFuncT(proto, "fillEllipseSectorDeg", Context.fillEllipseSectorDeg);
        ctx.setConstFuncT(proto, "drawEllipse", Context.drawEllipse);
        ctx.setConstFuncT(proto, "drawEllipseArc", Context.drawEllipseArc);
        ctx.setConstFuncT(proto, "drawEllipseArcDeg", Context.drawEllipseArcDeg);
        ctx.setConstFuncT(proto, "fillTriangle", Context.fillTriangle);
        ctx.setConstFuncT(proto, "fillConvexPolygon", Context.fillConvexPolygon);
        ctx.setConstFuncT(proto, "fillPolygon", Context.fillPolygon);
        ctx.setConstFuncT(proto, "drawPolygon", Context.drawPolygon);
        ctx.setConstFuncT(proto, "fillRoundRect", Context.fillRoundRect);
        ctx.setConstFuncT(proto, "drawRoundRect", Context.drawRoundRect);
        ctx.setConstFuncT(proto, "drawPoint", Context.drawPoint);
        ctx.setConstFuncT(proto, "drawLine", Context.drawLine);
        ctx.setConstFuncT(proto, "drawSvgContent", Context.drawSvgContent);
        ctx.setConstFuncT(proto, "compileSvgContent", Context.compileSvgContent);
        ctx.setConstFuncT(proto, "executeDrawList", Context.executeDrawList);
        ctx.setConstFuncT(proto, "drawQuadraticBezierCurve", Context.drawQuadraticBezierCurve);
        ctx.setConstFuncT(proto, "drawCubicBezierCurve", Context.drawCubicBezierCurve);
        ctx.setConstFuncT(proto, "drawImageSized", Context.drawImageSized);
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
    ctx.setConstFuncT(window, "new", api.cs_window.new);
    ctx.setConstProp(cs, "window", window);

    // cs.files
    const files_constructor = iso.initFunctionTemplateDefault();
    files_constructor.setClassName(iso.initStringUtf8("files"));
    const files = iso.initObjectTemplate(files_constructor);
    ctx.setConstFuncT(files, "readFile", api.cs_files.readFile);
    ctx.setConstFuncT(files, "readTextFile", api.cs_files.readTextFile);
    ctx.setConstFuncT(files, "writeFile", api.cs_files.writeFile);
    ctx.setConstFuncT(files, "writeTextFile", api.cs_files.writeTextFile);
    ctx.setConstFuncT(files, "appendFile", api.cs_files.appendFile);
    ctx.setConstFuncT(files, "appendTextFile", api.cs_files.appendTextFile);
    ctx.setConstFuncT(files, "removeFile", api.cs_files.removeFile);
    ctx.setConstFuncT(files, "ensurePath", api.cs_files.ensurePath);
    ctx.setConstFuncT(files, "pathExists", api.cs_files.pathExists);
    ctx.setConstFuncT(files, "removeDir", api.cs_files.removeDir);
    ctx.setConstFuncT(files, "resolvePath", api.cs_files.resolvePath);
    ctx.setConstFuncT(files, "copyFile", api.cs_files.copyFile);
    ctx.setConstFuncT(files, "moveFile", api.cs_files.moveFile);
    ctx.setConstFuncT(files, "cwd", api.cs_files.cwd);
    ctx.setConstFuncT(files, "getPathInfo", api.cs_files.getPathInfo);
    ctx.setConstFuncT(files, "listDir", api.cs_files.listDir);
    // ctx.setConstFuncT(files, "openFile", files_OpenFile);
    ctx.setConstProp(cs, "files", files);

    ctx.setConstAsyncFuncT(files, "readFileAsync", api.cs_files.readFile);
    ctx.setConstAsyncFuncT(files, "readTextFileAsync", api.cs_files.readTextFile);
    ctx.setConstAsyncFuncT(files, "writeFileAsync", api.cs_files.writeFile);
    ctx.setConstAsyncFuncT(files, "writeTextFileAsync", api.cs_files.writeTextFile);
    ctx.setConstAsyncFuncT(files, "appendFileAsync", api.cs_files.appendFile);
    ctx.setConstAsyncFuncT(files, "appendTextFileAsync", api.cs_files.appendTextFile);
    ctx.setConstAsyncFuncT(files, "removeFileAsync", api.cs_files.removeFile);
    ctx.setConstAsyncFuncT(files, "removeDirAsync", api.cs_files.removeDir);
    ctx.setConstAsyncFuncT(files, "ensurePathAsync", api.cs_files.ensurePath);
    ctx.setConstAsyncFuncT(files, "pathExistsAsync", api.cs_files.pathExists);
    ctx.setConstAsyncFuncT(files, "copyFileAsync", api.cs_files.copyFile);
    ctx.setConstAsyncFuncT(files, "moveFileAsync", api.cs_files.moveFile);
    ctx.setConstAsyncFuncT(files, "getPathInfoAsync", api.cs_files.getPathInfo);
    ctx.setConstAsyncFuncT(files, "listDirAsync", api.cs_files.listDir);
    // TODO: chmod op

    // cs.http
    const http_constructor = iso.initFunctionTemplateDefault();
    http_constructor.setClassName(iso.initStringUtf8("http"));
    const http = iso.initObjectTemplate(http_constructor);
    ctx.setConstFuncT(http, "get", api.cs_http.get);
    ctx.setConstFuncT(http, "getAsync", api.cs_http.getAsync);
    ctx.setConstFuncT(http, "post", api.cs_http.post);
    ctx.setConstFuncT(http, "postAsync", api.cs_http.postAsync);
    ctx.setConstFuncT(http, "_request", api.cs_http.request);
    ctx.setConstFuncT(http, "_requestAsync", api.cs_http.requestAsync);
    ctx.setConstFuncT(http, "serveHttp", api.cs_http.serveHttp);
    ctx.setConstFuncT(http, "serveHttps", api.cs_http.serveHttps);
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
        ctx.setConstFuncT(obj_t, "sendBytes", ResponseWriter.sendBytes);
        rt.http_response_writer = obj_t;
    }
    ctx.setConstProp(cs, "http", http);

    if (rt.is_test_env) {
        // cs.test
        ctx.setConstFuncT(cs, "test", api.createTest);

        // cs.testIsolated
        ctx.setConstFuncT(cs, "testIsolated", api.createIsolatedTest);

        // cs.asserts
        const cs_asserts = iso.initObjectTemplateDefault();

        ctx.setConstProp(cs, "asserts", cs_asserts);
    }

    // cs.graphics
    const cs_graphics = v8.ObjectTemplate.initDefault(iso);

    // cs.graphics.Color
    ctx.setConstProp(cs_graphics, "Color", color_class);
    ctx.setConstProp(cs, "graphics", cs_graphics);

    // cs.util
    const cs_util = v8.ObjectTemplate.initDefault(iso);

    // cs.util.bufferToUtf8
    ctx.setConstFuncT(cs_util, "bufferToUtf8", api.cs_core.bufferToUtf8);
    ctx.setConstProp(cs, "util", cs_util);

    ctx.setConstProp(global, "cs", cs);

    const rt_data = iso.initExternal(rt);
    ctx.setConstProp(global, "print", iso.initFunctionTemplateCallbackData(api.cs_core.print, rt_data));

    const res = iso.initContext(global, null);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(iso, "cs")).castToObject();

    return res;
}