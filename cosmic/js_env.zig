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
        ctx.setConstFuncT(proto, "newImage", api.graphics_NewImage);
        ctx.setConstFuncT(proto, "addTtfFont", api.graphics_AddTtfFont);
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
    ctx.setConstFuncT(files, "readTextFile", api.files_readTextFile);
    ctx.setConstFuncT(files, "writeFile", api.files_writeFile);
    ctx.setConstFuncT(files, "writeTextFile", api.files_writeTextFile);
    ctx.setConstFuncT(files, "appendFile", api.files_appendFile);
    ctx.setConstFuncT(files, "appendTextFile", api.files_appendTextFile);
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
    ctx.setConstAsyncFuncT(files, "readTextFileAsync", api.files_readTextFile);
    ctx.setConstAsyncFuncT(files, "writeFileAsync", api.files_writeFile);
    ctx.setConstAsyncFuncT(files, "writeTextFileAsync", api.files_writeTextFile);
    ctx.setConstAsyncFuncT(files, "appendFileAsync", api.files_appendFile);
    ctx.setConstAsyncFuncT(files, "appendTextFileAsync", api.files_appendTextFile);
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
    ctx.setConstFuncT(http, "post", api.http_post);
    ctx.setConstFuncT(http, "postAsync", api.http_postAsync);
    ctx.setConstFuncT(http, "_request", api.http_request);
    ctx.setConstFuncT(http, "_requestAsync", api.http_requestAsync);
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
    ctx.setConstFuncT(cs_util, "bufferToUtf8", api.util_bufferToUtf8);
    ctx.setConstProp(cs, "util", cs_util);

    ctx.setConstProp(global, "cs", cs);

    const rt_data = iso.initExternal(rt);
    ctx.setConstProp(global, "print", iso.initFunctionTemplateCallbackData(api.print, rt_data));

    const res = iso.initContext(global, null);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(iso, "cs")).castToObject();

    return res;
}