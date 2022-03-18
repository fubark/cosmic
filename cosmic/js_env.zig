const std = @import("std");
const stdx = @import("stdx");
const builtin = @import("builtin");
const string = stdx.string;
const graphics = @import("graphics");
const Graphics = graphics.Graphics;
const StdColor = graphics.Color;
const ds = stdx.ds;
const v8 = @import("v8");
const uv = @import("uv");
const h2o = @import("h2o");

const runtime = @import("runtime.zig");
const SizedJsString = runtime.SizedJsString;
const RuntimeContext = runtime.RuntimeContext;
const V8Context = runtime.V8Context;
const ContextBuilder = runtime.ContextBuilder;
const RuntimeValue = runtime.RuntimeValue;
const printFmt = runtime.printFmt;
const errorFmt = runtime.errorFmt;
const ManagedSlice = runtime.ManagedSlice;
const ManagedStruct = runtime.ManagedStruct;
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
const cs_graphics = @import("api_graphics.zig").cs_graphics;
const v8x = @import("v8x.zig");

// TODO: Implement fast api calls using CFunction. See include/v8-fast-api-calls.h
/// Initializes the js global context. Sets up modules and binds api functions.
/// A parent HandleScope should capture and clean up any redundant v8 vars created here.
pub fn initContext(rt: *RuntimeContext, iso: v8.Isolate) v8.Context {
    const ctx = ContextBuilder{
        .rt = rt,
        .isolate = iso,
    };

    // We set with the same undef values for each type, it might help the optimizing compiler if it knows the field types ahead of time.
    const undef_u32 = v8.Integer.initU32(iso, 0);

    // GenericHandle
    // First field is for the handle id.
    // Second field is id*2 for setWeakFinalizer.
    const handle_class = v8.Persistent(v8.ObjectTemplate).init(iso, v8.ObjectTemplate.initDefault(iso));
    handle_class.inner.setInternalFieldCount(2);
    rt.handle_class = handle_class;

    // Runtime-context template.
    // First field contains rt pointer.
    // Second field contains a custom pointer or value.
    // Used to create function data when the functions don't accept a user object param. eg. Promise fulfill/reject callbacks.
    rt.rt_ctx_tmpl = iso.initPersistent(v8.ObjectTemplate, iso.initObjectTemplateDefault());
    rt.rt_ctx_tmpl.inner.setInternalFieldCount(2);

    // GenericObject
    rt.default_obj_t = v8.Persistent(v8.ObjectTemplate).init(iso, v8.ObjectTemplate.initDefault(iso));

    // JsWindow
    const window_class = v8.Persistent(v8.FunctionTemplate).init(iso, v8.FunctionTemplate.initDefault(iso));
    {
        const inst = window_class.inner.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = window_class.inner.getPrototypeTemplate();
        ctx.setFuncT(proto, "onUpdate", api.cs_window.Window.onUpdate);
        ctx.setFuncT(proto, "onMouseDown", api.cs_window.Window.onMouseDown);
        ctx.setFuncT(proto, "onMouseUp", api.cs_window.Window.onMouseUp);
        ctx.setFuncT(proto, "onMouseMove", api.cs_window.Window.onMouseMove);
        ctx.setFuncT(proto, "onKeyDown", api.cs_window.Window.onKeyDown);
        ctx.setFuncT(proto, "onKeyUp", api.cs_window.Window.onKeyUp);
        ctx.setFuncT(proto, "onResize", api.cs_window.Window.onResize);
        ctx.setFuncT(proto, "getGraphics", api.cs_window.Window.getGraphics);
        ctx.setFuncT(proto, "getLastFrameDuration", api.cs_window.Window.getLastFrameDuration);
        ctx.setFuncT(proto, "getLastUpdateDuration", api.cs_window.Window.getLastUpdateDuration);
        ctx.setFuncT(proto, "getFps", api.cs_window.Window.getFps);
        ctx.setFuncT(proto, "close", api.cs_window.Window.close);
        ctx.setFuncT(proto, "minimize", api.cs_window.Window.minimize);
        ctx.setFuncT(proto, "maximize", api.cs_window.Window.maximize);
        ctx.setFuncT(proto, "restore", api.cs_window.Window.restore);
        ctx.setFuncT(proto, "setFullscreenMode", api.cs_window.Window.setFullscreenMode);
        ctx.setFuncT(proto, "setPseudoFullscreenMode", api.cs_window.Window.setPseudoFullscreenMode);
        ctx.setFuncT(proto, "setWindowedMode", api.cs_window.Window.setWindowedMode);
        ctx.setFuncT(proto, "createChild", api.cs_window.Window.createChild);
        ctx.setFuncT(proto, "position", api.cs_window.Window.position);
        ctx.setFuncT(proto, "center", api.cs_window.Window.center);
        ctx.setFuncT(proto, "focus", api.cs_window.Window.focus);
        ctx.setFuncT(proto, "getWidth", api.cs_window.Window.getWidth);
        ctx.setFuncT(proto, "getHeight", api.cs_window.Window.getHeight);
        ctx.setFuncT(proto, "setTitle", api.cs_window.Window.setTitle);
        ctx.setFuncT(proto, "getTitle", api.cs_window.Window.getTitle);
        ctx.setFuncT(proto, "resize", api.cs_window.Window.resize);
    }
    rt.window_class = window_class;

    // JsGraphics
    const graphics_class = v8.Persistent(v8.FunctionTemplate).init(iso, v8.FunctionTemplate.initDefault(iso));
    graphics_class.inner.setClassName(v8.String.initUtf8(iso, "Graphics"));
    {
        const inst = graphics_class.inner.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = graphics_class.inner.getPrototypeTemplate();
        
        // NOTE: Accessors are callbacks anyway so it's probably not that much faster than a function call.
        // Although, I have not explored if there exists a native binding to some memory location.
        // For now, eep things consistent and use functions for fillColor/strokeColor/lineWidth. One less thing to gen docs for too.
        // ctx.setAccessor(proto, "fillColor", Graphics.getFillColor, Graphics.setFillColor);
        // ctx.setAccessor(proto, "strokeColor", Graphics.getStrokeColor, Graphics.setStrokeColor);
        // ctx.setAccessor(proto, "lineWidth", Graphics.getLineWidth, Graphics.setLineWidth);

        const Context = cs_graphics.Context;
        ctx.setConstFuncT(proto, "defaultFont", Context.defaultFont);
        ctx.setConstFuncT(proto, "fillColor", Context.fillColor);
        ctx.setConstFuncT(proto, "getFillColor", Context.getFillColor);
        ctx.setConstFuncT(proto, "strokeColor", Context.strokeColor);
        ctx.setConstFuncT(proto, "getStrokeColor", Context.getStrokeColor);
        ctx.setConstFuncT(proto, "lineWidth", Context.lineWidth);
        ctx.setConstFuncT(proto, "getLineWidth", Context.getLineWidth);
        ctx.setConstFuncT(proto, "rect", Context.rect);
        ctx.setConstFuncT(proto, "rectOutline", Context.rectOutline);
        ctx.setConstFuncT(proto, "translate", Context.translate);
        ctx.setConstFuncT(proto, "scale", Context.scale);
        ctx.setConstFuncT(proto, "rotate", Context.rotate);
        ctx.setConstFuncT(proto, "rotateDeg", Context.rotateDeg);
        ctx.setConstFuncT(proto, "resetTransform", Context.resetTransform);
        ctx.setConstFuncT(proto, "newImage", Context.newImage);
        ctx.setConstFuncT(proto, "addTtfFont", Context.addTtfFont);
        ctx.setConstFuncT(proto, "addFallbackFont", Context.addFallbackFont);
        ctx.setConstFuncT(proto, "font", Context.font);
        ctx.setConstFuncT(proto, "fontSize", Context.fontSize);
        ctx.setConstFuncT(proto, "textAlign", Context.textAlign);
        ctx.setConstFuncT(proto, "textBaseline", Context.textBaseline);
        ctx.setConstFuncT(proto, "text", Context.text);
        ctx.setConstFuncT(proto, "circle", Context.circle);
        ctx.setConstFuncT(proto, "circleSector", Context.circleSector);
        ctx.setConstFuncT(proto, "circleSectorDeg", Context.circleSectorDeg);
        ctx.setConstFuncT(proto, "circleOutline", Context.circleOutline);
        ctx.setConstFuncT(proto, "circleArc", Context.circleArc);
        ctx.setConstFuncT(proto, "circleArcDeg", Context.circleArcDeg);
        ctx.setConstFuncT(proto, "ellipse", Context.ellipse);
        ctx.setConstFuncT(proto, "ellipseSector", Context.ellipseSector);
        ctx.setConstFuncT(proto, "ellipseSectorDeg", Context.ellipseSectorDeg);
        ctx.setConstFuncT(proto, "ellipseOutline", Context.ellipseOutline);
        ctx.setConstFuncT(proto, "ellipseArc", Context.ellipseArc);
        ctx.setConstFuncT(proto, "ellipseArcDeg", Context.ellipseArcDeg);
        ctx.setConstFuncT(proto, "triangle", Context.triangle);
        ctx.setConstFuncT(proto, "convexPolygon", Context.convexPolygon);
        ctx.setConstFuncT(proto, "polygon", Context.polygon);
        ctx.setConstFuncT(proto, "polygonOutline", Context.polygonOutline);
        ctx.setConstFuncT(proto, "roundRect", Context.roundRect);
        ctx.setConstFuncT(proto, "roundRectOutline", Context.roundRectOutline);
        ctx.setConstFuncT(proto, "point", Context.point);
        ctx.setConstFuncT(proto, "line", Context.line);
        ctx.setConstFuncT(proto, "svgContent", Context.svgContent);
        ctx.setConstFuncT(proto, "compileSvgContent", Context.compileSvgContent);
        ctx.setConstFuncT(proto, "executeDrawList", Context.executeDrawList);
        ctx.setConstFuncT(proto, "quadraticBezierCurve", Context.quadraticBezierCurve);
        ctx.setConstFuncT(proto, "cubicBezierCurve", Context.cubicBezierCurve);
        ctx.setConstFuncT(proto, "imageSized", Context.imageSized);
    }
    rt.graphics_class = graphics_class;

    // JsImage
    const image_class = v8.Persistent(v8.FunctionTemplate).init(iso, ctx.initFuncT("Image"));
    {
        const inst = image_class.inner.getInstanceTemplate();
        ctx.setProp(inst, "width", undef_u32);
        ctx.setProp(inst, "height", undef_u32);
        // For image id.
        inst.setInternalFieldCount(1);
    }
    rt.image_class = image_class;

    // JsColor
    const color_class = iso.initPersistent(v8.FunctionTemplate, iso.initFunctionTemplateDefault());
    {
        const proto = color_class.inner.getPrototypeTemplate();
        ctx.setFuncT(proto, "darker", cs_graphics.Color.darker);
        ctx.setFuncT(proto, "lighter", cs_graphics.Color.lighter);
        ctx.setFuncT(proto, "withAlpha", cs_graphics.Color.withAlpha);
    }
    var instance = color_class.inner.getInstanceTemplate();
    ctx.setProp(instance, "r", undef_u32);
    ctx.setProp(instance, "g", undef_u32);
    ctx.setProp(instance, "b", undef_u32);
    ctx.setProp(instance, "a", undef_u32);

    const Color = cs_graphics.Color;
    const colors = &[_]std.meta.Tuple(&.{ []const u8, Color }){
        .{ "lightGray", Color.lightGray },
        .{ "gray", Color.gray },
        .{ "darkGray", Color.darkGray },
        .{ "yellow", Color.yellow },
        .{ "gold", Color.gold },
        .{ "orange", Color.orange },
        .{ "pink", Color.pink },
        .{ "red", Color.red },
        .{ "maroon", Color.maroon },
        .{ "green", Color.green },
        .{ "lime", Color.lime },
        .{ "darkGreen", Color.darkGreen },
        .{ "skyBlue", Color.skyBlue },
        .{ "blue", Color.blue },
        .{ "royalBlue", Color.royalBlue },
        .{ "darkBlue", Color.darkBlue },
        .{ "purple", Color.purple },
        .{ "violet", Color.violet },
        .{ "darkPurple", Color.darkPurple },
        .{ "beige", Color.beige },
        .{ "brown", Color.brown },
        .{ "darkBrown", Color.darkBrown },
        .{ "white", Color.white },
        .{ "black", Color.black },
        .{ "transparent", Color.transparent },
        .{ "magenta", Color.magenta },
    };
    inline for (colors) |it| {
        ctx.setFuncGetter(color_class.inner, it.@"0", it.@"1");
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
    ctx.setConstFuncT(window, "create", api.cs_window.create);
    ctx.setConstProp(cs, "window", window);

    // cs.files
    const files_constructor = iso.initFunctionTemplateDefault();
    files_constructor.setClassName(iso.initStringUtf8("files"));
    const files = iso.initObjectTemplate(files_constructor);
    ctx.setConstFuncT(files, "read", api.cs_files.read);
    ctx.setConstFuncT(files, "readText", api.cs_files.readText);
    ctx.setConstFuncT(files, "write", api.cs_files.write);
    ctx.setConstFuncT(files, "writeText", api.cs_files.writeText);
    ctx.setConstFuncT(files, "append", api.cs_files.append);
    ctx.setConstFuncT(files, "appendText", api.cs_files.appendText);
    ctx.setConstFuncT(files, "remove", api.cs_files.remove);
    ctx.setConstFuncT(files, "ensurePath", api.cs_files.ensurePath);
    ctx.setConstFuncT(files, "pathExists", api.cs_files.pathExists);
    ctx.setConstFuncT(files, "removeDir", api.cs_files.removeDir);
    ctx.setConstFuncT(files, "expandPath", api.cs_files.expandPath);
    ctx.setConstFuncT(files, "realPath", api.cs_files.realPath);
    ctx.setConstFuncT(files, "symLink", api.cs_files.symLink);
    ctx.setConstFuncT(files, "copy", api.cs_files.copy);
    ctx.setConstFuncT(files, "move", api.cs_files.move);
    ctx.setConstFuncT(files, "cwd", api.cs_files.cwd);
    ctx.setConstFuncT(files, "getPathInfo", api.cs_files.getPathInfo);
    ctx.setConstFuncT(files, "listDir", api.cs_files.listDir);
    // ctx.setConstFuncT(files, "openFile", files_OpenFile);
    ctx.setConstProp(cs, "files", files);

    ctx.setConstFuncT(files, "_readAsync", api.cs_files.readAsync);
    ctx.setConstFuncT(files, "_readTextAsync", api.cs_files.readTextAsync);
    ctx.setConstFuncT(files, "_writeAsync", api.cs_files.writeAsync);
    ctx.setConstFuncT(files, "_writeTextAsync", api.cs_files.writeTextAsync);
    ctx.setConstFuncT(files, "_appendAsync", api.cs_files.appendAsync);
    ctx.setConstFuncT(files, "_appendTextAsync", api.cs_files.appendTextAsync);
    ctx.setConstFuncT(files, "_removeAsync", api.cs_files.removeAsync);
    ctx.setConstFuncT(files, "_removeDirAsync", api.cs_files.removeDirAsync);
    ctx.setConstFuncT(files, "_ensurePathAsync", api.cs_files.ensurePathAsync);
    ctx.setConstFuncT(files, "_pathExistsAsync", api.cs_files.pathExistsAsync);
    ctx.setConstFuncT(files, "_copyAsync", api.cs_files.copyAsync);
    ctx.setConstFuncT(files, "_moveAsync", api.cs_files.moveAsync);
    ctx.setConstFuncT(files, "_getPathInfoAsync", api.cs_files.getPathInfoAsync);
    ctx.setConstFuncT(files, "_listDirAsync", api.cs_files.listDirAsync);
    // TODO: chmod op

    const filekind = iso.initObjectTemplateDefault();
    ctx.setProp(filekind, "blockDevice", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.blockDevice)));
    ctx.setProp(filekind, "characterDevice", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.characterDevice)));
    ctx.setProp(filekind, "directory", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.directory)));
    ctx.setProp(filekind, "namedPipe", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.namedPipe)));
    ctx.setProp(filekind, "symLink", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.symLink)));
    ctx.setProp(filekind, "file", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.file)));
    ctx.setProp(filekind, "unixDomainSocket", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.unixDomainSocket)));
    ctx.setProp(filekind, "whiteout", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.whiteout)));
    ctx.setProp(filekind, "door", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.door)));
    ctx.setProp(filekind, "eventPort", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.eventPort)));
    ctx.setProp(filekind, "unknown", iso.initIntegerU32(@enumToInt(api.cs_files.FileKind.unknown)));
    ctx.setConstProp(files, "FileKind", filekind);

    // cs.http
    const http_constructor = iso.initFunctionTemplateDefault();
    http_constructor.setClassName(iso.initStringUtf8("http"));
    const http = iso.initObjectTemplate(http_constructor);
    ctx.setConstFuncT(http, "get", api.cs_http.get);
    ctx.setConstFuncT(http, "_getAsync", api.cs_http.getAsync);
    ctx.setConstFuncT(http, "post", api.cs_http.post);
    ctx.setConstFuncT(http, "_postAsync", api.cs_http.postAsync);
    ctx.setConstFuncT(http, "_request", api.cs_http.request);
    ctx.setConstFuncT(http, "_requestAsync", api.cs_http.requestAsync);
    ctx.setConstFuncT(http, "serveHttp", api.cs_http.serveHttp);
    ctx.setConstFuncT(http, "serveHttps", api.cs_http.serveHttps);
    // cs.http.Response
    const response_class = v8.FunctionTemplate.initDefault(iso);
    response_class.setClassName(v8.String.initUtf8(iso, "Response"));
    ctx.setConstProp(http, "Response", response_class);
    rt.http_response_class = v8.Persistent(v8.FunctionTemplate).init(iso, response_class);
    {
        // cs.http.Server
        const server_class = iso.initFunctionTemplateDefault();
        server_class.setClassName(iso.initStringUtf8("Server"));

        const inst = server_class.getInstanceTemplate();
        inst.setInternalFieldCount(1);

        const proto = server_class.getPrototypeTemplate();
        ctx.setConstFuncT(proto, "setHandler", api.cs_http.Server.setHandler);
        ctx.setConstFuncT(proto, "requestClose", api.cs_http.Server.requestClose);
        ctx.setConstFuncT(proto, "closeAsync", api.cs_http.Server.closeAsync);

        ctx.setConstProp(http, "Server", server_class);
        rt.http_server_class = v8.Persistent(v8.FunctionTemplate).init(iso, server_class);
    }
    {
        // cs.http.ResponseWriter
        const constructor = iso.initFunctionTemplateDefault();
        constructor.setClassName(iso.initStringUtf8("ResponseWriter"));

        const obj_t = iso.initObjectTemplate(constructor);
        ctx.setConstFuncT(obj_t, "setStatus", api.cs_http.ResponseWriter.setStatus);
        ctx.setConstFuncT(obj_t, "setHeader", api.cs_http.ResponseWriter.setHeader);
        ctx.setConstFuncT(obj_t, "send", api.cs_http.ResponseWriter.send);
        ctx.setConstFuncT(obj_t, "sendBytes", api.cs_http.ResponseWriter.sendBytes);
        rt.http_response_writer = v8.Persistent(v8.ObjectTemplate).init(iso, obj_t);
    }
    ctx.setConstProp(cs, "http", http);

    if (rt.is_test_env or builtin.is_test) {
        // cs.test
        const cs_test = iso.initObjectTemplateDefault();

        ctx.setConstFuncT(cs_test, "create", api.cs_test.create);
        ctx.setConstFuncT(cs_test, "createIsolated", api.cs_test.createIsolated);

        // ctx.setConstProp(cs, "asserts", cs_asserts);
        ctx.setConstProp(cs, "test", cs_test);
    }

    // cs.graphics
    {
        const mod = v8.ObjectTemplate.initDefault(iso);

        // cs.graphics.Color
        ctx.setConstProp(mod, "Color", color_class.inner);

        // cs.graphics.TextAlign
        const text_align = iso.initObjectTemplateDefault();
        ctx.setProp(text_align, "left", iso.initIntegerU32(@enumToInt(cs_graphics.TextAlign.left)));
        ctx.setProp(text_align, "center", iso.initIntegerU32(@enumToInt(cs_graphics.TextAlign.center)));
        ctx.setProp(text_align, "right", iso.initIntegerU32(@enumToInt(cs_graphics.TextAlign.right)));
        ctx.setConstProp(mod, "TextAlign", text_align);

        // cs.graphics.TextBaseline
        const text_baseline = iso.initObjectTemplateDefault();
        ctx.setProp(text_baseline, "top", iso.initIntegerU32(@enumToInt(cs_graphics.TextBaseline.top)));
        ctx.setProp(text_baseline, "middle", iso.initIntegerU32(@enumToInt(cs_graphics.TextBaseline.middle)));
        ctx.setProp(text_baseline, "alphabetic", iso.initIntegerU32(@enumToInt(cs_graphics.TextBaseline.alphabetic)));
        ctx.setProp(text_baseline, "bottom", iso.initIntegerU32(@enumToInt(cs_graphics.TextBaseline.bottom)));
        ctx.setConstProp(mod, "TextBaseline", text_baseline);

        ctx.setConstFuncT(mod, "hsvToRgb", cs_graphics.hsvToRgb);
        ctx.setConstProp(cs, "graphics", mod);
    }

    const rt_data = iso.initExternal(rt);

    // cs.audio
    const cs_audio = iso.initObjectTemplateDefault();
    ctx.setConstFuncT(cs_audio, "loadWav", api.cs_audio.loadWav);
    ctx.setConstFuncT(cs_audio, "loadWavFile", api.cs_audio.loadWavFile);
    ctx.setConstFuncT(cs_audio, "loadMp3", api.cs_audio.loadMp3);
    ctx.setConstFuncT(cs_audio, "loadMp3File", api.cs_audio.loadMp3File);
    ctx.setConstFuncT(cs_audio, "loadFlac", api.cs_audio.loadFlac);
    ctx.setConstFuncT(cs_audio, "loadFlacFile", api.cs_audio.loadFlacFile);
    ctx.setConstFuncT(cs_audio, "loadOgg", api.cs_audio.loadOgg);
    ctx.setConstFuncT(cs_audio, "loadOggFile", api.cs_audio.loadOggFile);
    ctx.setConstFuncT(cs_audio, "load", api.cs_audio.load);
    ctx.setConstFuncT(cs_audio, "loadFile", api.cs_audio.loadFile);
    ctx.setConstFuncT(cs_audio, "getListenerPos", api.cs_audio.getListenerPos);
    ctx.setConstFuncT(cs_audio, "setListenerPos", api.cs_audio.setListenerPos);
    ctx.setConstFuncT(cs_audio, "getListenerDir", api.cs_audio.getListenerDir);
    ctx.setConstFuncT(cs_audio, "setListenerDir", api.cs_audio.setListenerDir);
    ctx.setConstFuncT(cs_audio, "getListenerUpDir", api.cs_audio.getListenerUpDir);
    ctx.setConstFuncT(cs_audio, "setListenerUpDir", api.cs_audio.setListenerUpDir);
    ctx.setConstFuncT(cs_audio, "getListenerVel", api.cs_audio.getListenerVel);
    ctx.setConstFuncT(cs_audio, "setListenerVel", api.cs_audio.setListenerVel);
    {
        // Sound
        const sound_class = iso.initPersistent(v8.ObjectTemplate, iso.initObjectTemplateDefault());
        sound_class.inner.setInternalFieldCount(2);
        ctx.setConstFuncT(sound_class.inner, "play", api.cs_audio.Sound.play);
        ctx.setConstFuncT(sound_class.inner, "playBg", api.cs_audio.Sound.playBg);
        ctx.setConstFuncT(sound_class.inner, "isPlayingBg", api.cs_audio.Sound.isPlayingBg);
        ctx.setConstFuncT(sound_class.inner, "loopBg", api.cs_audio.Sound.loopBg);
        ctx.setConstFuncT(sound_class.inner, "isLoopingBg", api.cs_audio.Sound.isLoopingBg);
        ctx.setConstFuncT(sound_class.inner, "pauseBg", api.cs_audio.Sound.pauseBg);
        ctx.setConstFuncT(sound_class.inner, "resumeBg", api.cs_audio.Sound.resumeBg);
        ctx.setConstFuncT(sound_class.inner, "stopBg", api.cs_audio.Sound.stopBg);
        ctx.setConstFuncT(sound_class.inner, "setVolume", api.cs_audio.Sound.setVolume);
        ctx.setConstFuncT(sound_class.inner, "getVolume", api.cs_audio.Sound.getVolume);
        ctx.setConstFuncT(sound_class.inner, "setGain", api.cs_audio.Sound.setGain);
        ctx.setConstFuncT(sound_class.inner, "getGain", api.cs_audio.Sound.getGain);
        ctx.setConstFuncT(sound_class.inner, "setPitch", api.cs_audio.Sound.setPitch);
        ctx.setConstFuncT(sound_class.inner, "getPitch", api.cs_audio.Sound.getPitch);
        ctx.setConstFuncT(sound_class.inner, "setPan", api.cs_audio.Sound.setPan);
        ctx.setConstFuncT(sound_class.inner, "getPan", api.cs_audio.Sound.getPan);
        ctx.setConstFuncT(sound_class.inner, "getLengthInPcmFrames", api.cs_audio.Sound.getLengthInPcmFrames);
        ctx.setConstFuncT(sound_class.inner, "getLength", api.cs_audio.Sound.getLength);
        ctx.setConstFuncT(sound_class.inner, "getCursorPcmFrame", api.cs_audio.Sound.getCursorPcmFrame);
        ctx.setConstFuncT(sound_class.inner, "seekToPcmFrame", api.cs_audio.Sound.seekToPcmFrame);
        ctx.setConstFuncT(sound_class.inner, "setPosition", api.cs_audio.Sound.setPosition);
        ctx.setConstFuncT(sound_class.inner, "getPosition", api.cs_audio.Sound.getPosition);
        ctx.setConstFuncT(sound_class.inner, "setDirection", api.cs_audio.Sound.setDirection);
        ctx.setConstFuncT(sound_class.inner, "getDirection", api.cs_audio.Sound.getDirection);
        ctx.setConstFuncT(sound_class.inner, "setVelocity", api.cs_audio.Sound.setVelocity);
        ctx.setConstFuncT(sound_class.inner, "getVelocity", api.cs_audio.Sound.getVelocity);
        ctx.setConstProp(cs_audio, "Sound", sound_class.inner);
        rt.sound_class = sound_class;
    }
    ctx.setConstProp(cs, "audio", cs_audio);

    // cs.core
    const cs_core = iso.initObjectTemplateDefault();
    ctx.setConstFuncT(cs_core, "getCliArgs", api.cs_core.getCliArgs);
    if (!rt.dev_mode) {
        ctx.setConstProp(cs_core, "print", iso.initFunctionTemplateCallbackData(api.cs_core.print, rt_data));
        ctx.setConstProp(cs_core, "puts", iso.initFunctionTemplateCallbackData(api.cs_core.puts, rt_data));
        ctx.setConstProp(cs_core, "dump", iso.initFunctionTemplateCallbackData(api.cs_core.dump, rt_data));
    } else {
        ctx.setConstProp(cs_core, "print", iso.initFunctionTemplateCallbackData(api.cs_core.print_DEV, rt_data));
        ctx.setConstProp(cs_core, "puts", iso.initFunctionTemplateCallbackData(api.cs_core.puts_DEV, rt_data));
        ctx.setConstProp(cs_core, "dump", iso.initFunctionTemplateCallbackData(api.cs_core.dump_DEV, rt_data));
    }
    ctx.setConstFuncT(cs_core, "bufferToUtf8", api.cs_core.bufferToUtf8);
    ctx.setConstFuncT(cs_core, "setTimeout", api.cs_core.setTimeout);
    ctx.setConstFuncT(cs_core, "errCode", api.cs_core.errCode);
    ctx.setConstFuncT(cs_core, "errString", api.cs_core.errString);
    ctx.setConstFuncT(cs_core, "clearError", api.cs_core.clearError);
    ctx.setConstFuncT(cs_core, "getMainScriptPath", api.cs_core.getMainScriptPath);
    ctx.setConstFuncT(cs_core, "getMainScriptDir", api.cs_core.getMainScriptDir);
    ctx.setConstFuncT(cs_core, "getAppDir", api.cs_core.getAppDir);
    ctx.setConstFuncT(cs_core, "panic", api.cs_core.panic);
    ctx.setConstFuncT(cs_core, "exit", api.cs_core.exit);
    ctx.setConstFuncT(cs_core, "getOs", api.cs_core.getOs);
    ctx.setConstFuncT(cs_core, "getOsVersion", api.cs_core.getOsVersion);
    ctx.setConstFuncT(cs_core, "getCpu", api.cs_core.getCpu);
    ctx.setConstFuncT(cs_core, "getResourceUsage", api.cs_core.getResourceUsage);
    ctx.setConstFuncT(cs_core, "gc", api.cs_core.gc);
    {
        const cs_os = iso.initObjectTemplateDefault();
        ctx.setProp(cs_os, "linux", iso.initIntegerU32(@enumToInt(api.cs_core.Os.linux)));
        ctx.setProp(cs_os, "macos", iso.initIntegerU32(@enumToInt(api.cs_core.Os.macos)));
        ctx.setProp(cs_os, "windows", iso.initIntegerU32(@enumToInt(api.cs_core.Os.windows)));
        ctx.setProp(cs_os, "web", iso.initIntegerU32(@enumToInt(api.cs_core.Os.web)));
        ctx.setConstProp(cs_core, "Os", cs_os);
    }
    {
        const cs_err = iso.initObjectTemplateDefault();
        ctx.setProp(cs_err, "NoError", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.NoError)));
        ctx.setProp(cs_err, "FileNotFound", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.FileNotFound)));
        ctx.setProp(cs_err, "PathExists", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.PathExists)));
        ctx.setProp(cs_err, "IsDir", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.IsDir)));
        ctx.setProp(cs_err, "ConnectFailed", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.ConnectFailed)));
        ctx.setProp(cs_err, "InvalidFormat", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.InvalidFormat)));
        ctx.setProp(cs_err, "Unsupported", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.Unsupported)));
        ctx.setProp(cs_err, "Unknown", iso.initIntegerU32(@enumToInt(api.cs_core.CsError.Unknown)));
        ctx.setConstProp(cs_core, "CsError", cs_err);
    }
    ctx.setConstProp(cs, "core", cs_core);

    ctx.setConstProp(global, "cs", cs);

    // cs.input
    const cs_input = iso.initObjectTemplateDefault();

    const mouse_button = iso.initObjectTemplateDefault();
    ctx.setProp(mouse_button, "left", iso.initIntegerU32(@enumToInt(api.cs_input.MouseButton.left)));
    ctx.setProp(mouse_button, "middle", iso.initIntegerU32(@enumToInt(api.cs_input.MouseButton.middle)));
    ctx.setProp(mouse_button, "right", iso.initIntegerU32(@enumToInt(api.cs_input.MouseButton.right)));
    ctx.setProp(mouse_button, "x1", iso.initIntegerU32(@enumToInt(api.cs_input.MouseButton.x1)));
    ctx.setProp(mouse_button, "x2", iso.initIntegerU32(@enumToInt(api.cs_input.MouseButton.x2)));
    ctx.setConstProp(cs_input, "MouseButton", mouse_button);

    const key_obj = iso.initObjectTemplateDefault();
    for (std.enums.values(api.cs_input.Key)) |key| {
        ctx.setProp(key_obj, @tagName(key), iso.initIntegerU32(@enumToInt(key)));
    }
    ctx.setConstProp(cs_input, "Key", key_obj);

    ctx.setConstProp(cs, "input", cs_input);

    const res = iso.initContext(global, null);

    // Attach rt pointer for callbacks that don't have user data. eg. ResolveModuleCallback
    res.setEmbedderData(0, rt_data);

    // const rt_global = res.getGlobal();
    // const rt_cs = rt_global.getValue(res, v8.String.initUtf8(iso, "cs")).castToObject();

    return res;
}