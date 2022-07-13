const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const build_options = @import("build_options");
const stdx = @import("stdx");
const Vec3 = stdx.math.Vec3;
const Vec4 = stdx.math.Vec4;
const Quaternion = stdx.math.Quaternion;
const Transform = stdx.math.Transform;
const fatal = stdx.fatal;
const platform = @import("platform");
const GraphicsBackend = platform.GraphicsBackend;
const gfx_backend = std.enums.nameCast(GraphicsBackend, build_options.GraphicsBackend);
const graphics = @import("graphics");
const glslang = @import("glslang");
const Color = graphics.Color;
const ui = @import("ui");
const Row = ui.widgets.Row;
const Text = ui.widgets.Text;
const TextButton = ui.widgets.TextButton;
const Padding = ui.widgets.Padding;
const Center = ui.widgets.Center;
const Column = ui.widgets.Column;
const ColorPicker = ui.widgets.ColorPicker;
const Sized = ui.widgets.Sized;
const SliderFloatOption = ui.widgets.SliderFloatOption;
const SliderFloat = ui.widgets.SliderFloat;
const SliderFloatOptions = ui.widgets.SliderFloatOptions;
const SwitchOption = ui.widgets.SwitchOption;

const jolt = @import("jolt");

const helper = @import("../graphics/examples/helper.zig");
const log = stdx.log.scoped(.main);
const World = @import("world.zig").World;

var app: helper.App = undefined;
var main_cam: graphics.Camera = undefined;
var cam_mod: graphics.CameraModule = undefined;

var ui_mod: ui.Module = undefined;
var app_root: *App = undefined;

const box_data = @embedFile("../examples/assets/models/box.gltf");
var box_scene: graphics.GLTFscene = undefined;

const duck_data = @embedFile("../examples/assets/models/duck.gltf");
var duck_scene: graphics.GLTFscene = undefined;

const animated_tri_data = @embedFile("../examples/assets/models/animated_triangle.gltf");
var animated_tri_scene: graphics.GLTFscene = undefined;
var animated_tri_mesh: graphics.AnimatedMesh = undefined;

const simple_skin_data = @embedFile("../examples/assets/models/simple_skin.gltf");
var simple_skin_scene: graphics.GLTFscene = undefined;
var simple_skin_mesh: graphics.AnimatedMesh = undefined;

const fox_data = @embedFile("../examples/assets/models/fox.glb");
var fox_scene: graphics.GLTFscene = undefined;
var fox_mesh: graphics.AnimatedMesh = undefined;

const brainstem_data = @embedFile("../examples/assets/models/brainstem.glb");
var brainstem_scene: graphics.GLTFscene = undefined;
var brainstem_mesh: graphics.AnimatedMesh = undefined;

fn initGlobal() !void {
    const res = glslang.glslang_initialize_process();
    if (res == 0) {
        return error.GlslangInitFailed;
    }
}

fn deinitGlobal() void {
    glslang.glslang_finalize_process();
}

pub const App = struct {
    box_color: Color,
    duck_color: Color,
    duck_metallic: f32,
    duck_roughness: f32,
    duck_emissivity: f32,
    enable_shadows: bool,

    const Self = @This();

    pub fn init(self: *Self, _: *ui.InitContext) void {
        self.box_color = Color.Blue;
        self.duck_color = Color.Yellow;
        self.enable_shadows = true;
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onBoxColorPreview(self_: *Self, color: Color) void { self_.box_color = color; }
            fn onBoxColor(self_: *Self, color: Color, _: bool) void { self_.box_color = color; }
            fn onDuckColorPreview(self_: *Self, color: Color) void { self_.duck_color = color; }
            fn onDuckColor(self_: *Self, color: Color, _: bool) void { self_.duck_color = color; }
            fn onDuckMetallicChange(self_: *Self, val: f32) void { self_.duck_metallic = val; }
            fn onDuckRoughnessChange(self_: *Self, val: f32) void { self_.duck_roughness = val; }
            fn onDuckEmissivityChange(self_: *Self, val: f32) void { self_.duck_emissivity = val; }
            fn onShadowsChange(self_: *Self, val: bool) void { self_.enable_shadows = val; }
        };

        // Currently zig is unstable with nested structs in anonymous tuples, so declare outside.
        const metallic_slider = ui.WidgetProps(SliderFloat){
            .init_val = 0,
            .min_val = 0,
            .max_val = 1,
            .onChange = c.closure(self, S.onDuckMetallicChange),
        };

        const roughness_slider = ui.WidgetProps(SliderFloat){
            .init_val = 0,
            .min_val = 0,
            .max_val = 1,
            .onChange = c.closure(self, S.onDuckRoughnessChange),
        };

        const emissivity_slider = ui.WidgetProps(SliderFloat){
            .init_val = 0,
            .min_val = 0,
            .max_val = 1,
            .onChange = c.closure(self, S.onDuckEmissivityChange),
        };

        return c.decl(Sized, .{
            .width = 250,
            .child = c.decl(Column, .{
                .expand = false,
                .children = c.list(.{
                    c.decl(ColorPicker, .{
                        .label = "Box Color",
                        .font_size = 14,
                        .init_val = self.box_color,
                        .onPreviewChange = c.funcExt(self, S.onBoxColorPreview),
                        .onResult = c.funcExt(self, S.onBoxColor),
                    }),
                    c.decl(ColorPicker, .{
                        .label = "Duck Color",
                        .font_size = 14,
                        .init_val = self.duck_color,
                        .onPreviewChange = c.funcExt(self, S.onDuckColorPreview),
                        .onResult = c.funcExt(self, S.onDuckColor),
                    }),
                    c.decl(SliderFloatOption, .{
                        .label = "metallic",
                        .slider = metallic_slider,
                    }),
                    c.decl(SliderFloatOption, .{
                        .label = "roughness",
                        .slider = roughness_slider,
                    }),
                    c.decl(SliderFloatOption, .{
                        .label = "emissivity",
                        .slider = emissivity_slider,
                    }),
                    c.decl(SwitchOption, .{
                        .label = "Enable Shadows",
                        .init_val = self.enable_shadows,
                        .onChange = c.funcExt(self, S.onShadowsChange),
                    }),
                }),
            }),
        });
    }
};

/// Preserve the aligned data until it isn't needed anymore. 
const GLTFhandle = struct {
    data: [] align(8) const u8,
    handle: graphics.GLTFhandle,

    fn deinit(self: *GLTFhandle, alloc: std.mem.Allocator) void {
        self.handle.deinit(alloc);
        alloc.free(self.data);
    }
};

fn loadGLTF(alloc: std.mem.Allocator, gctx: *graphics.Graphics, data: []const u8) !GLTFhandle {
    const aligned = try stdx.mem.dupeAlign(alloc, u8, 8, data);
    return GLTFhandle{
        .data = aligned,
        .handle = try gctx.loadGLTFandBuffers(alloc, aligned, .{}),
    };
}

var world: World = undefined;

pub fn main() !void {
    try initGlobal();
    defer deinitGlobal();

    // This is the app loop for desktop. For web/wasm see wasm exports below.
    app.init("3d");
    defer app.deinit();

    const alloc = app.alloc;
    const gctx = app.gctx;

    world = World.init(alloc);
    defer world.deinit();

    // Floor.
    world.addCuboid(Vec3.init(0, -1.01, 0), Vec3.init(800, 2, 800), Quaternion.initIdent(), true);

    // Boxes.
    world.addCuboid(Vec3.init(0, 50, 0), Vec3.init(5, 5, 5), Quaternion.initIdent(), false);
    world.addCuboid(Vec3.init(0, 20, 5), Vec3.init(5, 5, 5), Quaternion.initRotation(Vec3.UnitZ, 0.25 * std.math.pi), false);
    world.addCuboid(Vec3.init(0, 20, 0), Vec3.init(5, 5, 5), Quaternion.initRotation(Vec3.UnitX, 0.25 * std.math.pi).mul(Quaternion.initRotation(Vec3.UnitZ, 0.25 * std.math.pi)), false);

    world.genTerrain();

    ui_mod.init(alloc, app.gctx);
    ui_mod.addInputHandlers(&app.dispatcher);
    defer ui_mod.deinit();

    // Load models.
    var box = try loadGLTF(alloc, gctx, box_data);
    defer box.deinit(alloc);
    box_scene = try box.handle.loadDefaultScene(alloc, gctx);
    defer box_scene.deinit(alloc);

    var duck = try loadGLTF(alloc, gctx, duck_data);
    defer duck.deinit(alloc);
    duck_scene = try duck.handle.loadDefaultScene(alloc, gctx);
    defer duck_scene.deinit(alloc);

    var animated_tri = try loadGLTF(alloc, gctx, animated_tri_data);
    defer animated_tri.deinit(alloc);
    animated_tri_scene = try animated_tri.handle.loadDefaultScene(alloc, gctx);
    defer animated_tri_scene.deinit(alloc);
    animated_tri_mesh = graphics.AnimatedMesh.init(alloc, animated_tri_scene, 0);
    defer animated_tri_mesh.deinit(alloc);

    var simple_skin = try loadGLTF(alloc, gctx, simple_skin_data);
    defer simple_skin.deinit(alloc);
    simple_skin_scene = try simple_skin.handle.loadDefaultScene(alloc, gctx);
    defer simple_skin_scene.deinit(alloc);
    simple_skin_mesh = graphics.AnimatedMesh.init(alloc, simple_skin_scene, 0);
    defer simple_skin_mesh.deinit(alloc);

    var fox = try loadGLTF(alloc, gctx, fox_data);
    defer fox.deinit(alloc);
    fox_scene = try fox.handle.loadDefaultScene(alloc, gctx);
    defer fox_scene.deinit(alloc);
    fox_mesh = graphics.AnimatedMesh.init(alloc, fox_scene, 2);
    defer fox_mesh.deinit(alloc);

    var brainstem = try loadGLTF(alloc, gctx, brainstem_data);
    defer brainstem.deinit(alloc);
    brainstem_scene = try brainstem.handle.loadDefaultScene(alloc, gctx);
    defer brainstem_scene.deinit(alloc);
    brainstem_mesh = graphics.AnimatedMesh.init(alloc, brainstem_scene, 0);
    defer brainstem_mesh.deinit(alloc);

    const aspect = app.win.getAspectRatio();
    main_cam.initPerspective3D(60, aspect, 0.1, 1000);
    main_cam.moveForward(90);
    main_cam.moveUp(40);
    main_cam.setRotation(0, 0);
    cam_mod.init(&main_cam, &app.dispatcher);

    // Update ui once to bind user root.
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    ui_mod.update(0, {}, buildRoot, ui_width, ui_height) catch unreachable;
    app_root = ui_mod.getUserRoot(App).?;

    app.runEventLoop(update);
}

fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
    return c.decl(App, .{});
}

var duck_spin: f32 = 0;

fn update(delta_ms: f32) void {
    cam_mod.update(delta_ms);

    // Render 3D scene.
    const gctx = app.gctx;
    gctx.setCamera(main_cam);
    if (app_root.enable_shadows) {
        gctx.prepareShadows(main_cam);
    }

    gctx.setFillColor(Color.Red);
    gctx.fillTriangle3D(0, 0, 0, 20, 0, 0, 0, 20, 0);

    var box_xform = Transform.initIdentity();
    box_xform.translate3D(-1, 1, 0);
    box_xform.scale3D(20, 20, 20);
    gctx.setFillColor(app_root.box_color);
    gctx.fillScene3D(box_xform, box_scene);
    gctx.setStrokeColor(Color.Black);
    gctx.strokeScene3D(box_xform, box_scene);

    var duck_xform = Transform.initIdentity();
    duck_spin = @mod(duck_spin + delta_ms * 0.0001, 2*std.math.pi);
    duck_xform.rotateY(duck_spin);
    duck_xform.translate3D(-150, 0, 0);
    // gctx.drawTintedScene3D(duck_xform, duck_scene, app_root.duck_color);
    gctx.drawScenePbrCustom3D(duck_xform, duck_scene, .{
        .metallic = app_root.duck_metallic,
        .emissivity = app_root.duck_emissivity,
        .roughness = app_root.duck_roughness,
        .albedo_color = Color.White.toFloatArray(),
    });
    gctx.setStrokeColor(Color.Black);
    // gctx.strokeScene3D(duck_xform, duck_scene);
    // gctx.drawSceneNormals3D(duck_xform, duck_scene);

    // Draw a platform to see shadows.
    var xform = Transform.initIdentity();
    // xform.scale3D(800, 1, 800);
    // xform.translate3D(0, -0.6, 0);
    // gctx.drawCuboidPbr3D(xform, graphics.Material.initAlbedoColor(Color.Gray));

    xform = Transform.initIdentity();
    xform.scale3D(20, 20, 20);
    xform.rotateY(std.math.pi);
    xform.translate3D(50, 70, 0);
    gctx.setFillColor(Color.DarkGreen);
    animated_tri_mesh.update(delta_ms);
    gctx.fillAnimatedMesh3D(xform, animated_tri_mesh);

    xform = Transform.initIdentity();
    xform.scale3D(20, 20, 20);
    xform.rotateY(std.math.pi);
    xform.translate3D(50, 0, 0);
    gctx.setFillColor(Color.DarkGreen);
    simple_skin_mesh.update(delta_ms);
    gctx.fillAnimatedMesh3D(xform, simple_skin_mesh);

    xform = Transform.initIdentity();
    xform.translate3D(-200, 0, -200);
    fox_mesh.update(delta_ms);
    gctx.drawAnimatedMeshPbr3D(xform, fox_mesh);

    xform = Transform.initIdentity();
    xform.scale3D(70, 70, 70);
    xform.rotateX(std.math.pi/2.0);
    xform.translate3D(0, 0, -300);
    brainstem_mesh.update(delta_ms*0.5);
    gctx.drawAnimatedMeshPbr3D(xform, brainstem_mesh);

    world.update(delta_ms, gctx);

    gctx.drawPlane();

    // Render ui.
    gctx.setCamera(app.cam);
    gctx.setFillColor(Color.White);
    const font_id = gctx.getDefaultFontId();
    gctx.setFont(font_id, 14);
    gctx.fillTextFmt(10, 710, "cam pos: ({d:.1},{d:.1},{d:.1})", .{main_cam.world_pos.x, main_cam.world_pos.y, main_cam.world_pos.z});
    gctx.fillTextFmt(10, 730, "forward: ({d:.1},{d:.1},{d:.1})", .{main_cam.forward_nvec.x, main_cam.forward_nvec.y, main_cam.forward_nvec.z});
    gctx.fillTextFmt(10, 750, "up: ({d:.1},{d:.1},{d:.1})", .{main_cam.up_nvec.x, main_cam.up_nvec.y, main_cam.up_nvec.z});
    gctx.fillTextFmt(10, 770, "right: ({d:.1},{d:.1},{d:.1})", .{main_cam.right_nvec.x, main_cam.right_nvec.y, main_cam.right_nvec.z});
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    ui_mod.updateAndRender(delta_ms, {}, buildRoot, ui_width, ui_height) catch unreachable;
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() *const u8 {
        _ = wasmInitApp(&app, "Cosmic");
        init() catch fatal();
        return stdx.wasm.js_buffer.writeResult();
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) *const u8 {
        return wasmUpdateApp(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        deinit(app.alloc);
        app.deinit();
        stdx.wasm.deinit();
    }
} else struct {};

fn onWindowResize(_: ?*anyopaque, e: platform.WindowResizeEvent) void {
    // Update cameras.
    app.cam.init2D(e.width, e.height);

    // platform.Window's resize handler should have updated the sizes already so getAspectRatio should be accurate.
    const aspect = app.win.getAspectRatio();
    main_cam.updatePerspective3D(60, aspect, 0.1, 1000, gfx_backend);
}

pub const App = struct {
    gctx: *graphics.Graphics,
    renderer: graphics.Renderer,
    cam: graphics.Camera,
    dispatcher: platform.EventDispatcher,
    win: platform.Window,
    fps_limiter: graphics.DefaultFpsLimiter,
    quit: bool,
    last_frame_time_ms: f64,
    alloc: std.mem.Allocator,

    pub fn init(self: *App, title: []const u8) void {
        const alloc = stdx.heap.getDefaultAllocator();
        self.alloc = alloc;
        self.dispatcher = platform.EventDispatcher.init(alloc);

        self.win = platform.Window.init(alloc, .{
            .title = title,
            .width = 1200,
            .height = 800,
            .high_dpi = true,
            .resizable = true,
            .mode = .Windowed,
            .anti_alias = false,
        }) catch unreachable;
        self.win.addDefaultHandlers(&self.dispatcher);
        self.dispatcher.addOnWindowResize(null, onWindowResize);

        self.renderer.init(alloc, &self.win);
        self.gctx = self.renderer.getGraphics();
        self.gctx.setClearColor(Color.init(20, 20, 20, 255));

        self.cam.init2D(self.win.getWidth(), self.win.getHeight());

        // Create an fps limiter in case vsync is off or not supported.
        self.fps_limiter = graphics.DefaultFpsLimiter.init(60);
        self.quit = false;

        const S = struct {
            fn onQuit(ptr: ?*anyopaque) void {
                const self_ = stdx.mem.ptrCastAlign(*App, ptr.?);
                self_.quit = true;
            }
        };
        self.dispatcher.addOnQuit(self, S.onQuit);

        if (builtin.target.isWasm()) {
            self.last_frame_time_ms = stdx.time.getMillisTime();
        }
    }

    pub fn runEventLoop(self: *App, comptime update_fn: fn (delta_ms: f32) void) void {
        while (!app.quit) {
            self.dispatcher.processEvents();

            self.renderer.beginFrame(self.cam);
            self.fps_limiter.beginFrame();
            const delta_ms = self.fps_limiter.getLastFrameDeltaMs();
            update_fn(delta_ms);
            self.renderer.endFrame();

            const delay = self.fps_limiter.endFrame();
            if (delay > 0) {
                platform.delay(delay);
            }
        }
    }

    pub fn deinit(self: *App) void {
        self.dispatcher.deinit();
        self.renderer.deinit(self.alloc);
        self.win.deinit();
        stdx.heap.deinitDefaultAllocator();
    }
};

pub fn wasmUpdateApp(cur_time_ms: f64, input_buffer_len: u32, app_: *App, comptime update_fn: fn (delta_ms: f32) void) *const u8 {
    // Since C++ init code adds atexits, this should trigger an exit call to invoke them.
    defer stdx.wasm.flushAtExits();

    // Update the input buffer view.
    stdx.wasm.js_buffer.input_buf.items.len = input_buffer_len;

    const delta_ms = cur_time_ms - app_.last_frame_time_ms;
    app_.last_frame_time_ms = cur_time_ms;

    app_.dispatcher.processEvents();
    app_.renderer.beginFrame(app_.cam);

    update_fn(@floatCast(f32, delta_ms));

    app_.renderer.endFrame();
    return stdx.wasm.js_buffer.writeResult();
}

pub fn wasmInitApp(app_: *App, title: []const u8) *const u8 {
    defer stdx.wasm.flushAtExits();
    const alloc = stdx.heap.getDefaultAllocator();
    stdx.wasm.init(alloc);
    app_.init(title);
    return stdx.wasm.js_buffer.writeResult();
}