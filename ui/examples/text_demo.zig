const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const fatal = stdx.fatal;
const platform = @import("platform");
const Window = platform.Window;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const u = ui.widgets;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

/// Note: This embedded color emoji font only contains two emojis for the demo. Download the full emoji set on the web.
const NotoColorEmoji = @embedFile("../../examples/assets/NotoColorEmoji.ttf");

const tamzen9_otb = @embedFile("../../assets/tamzen5x9r.otb");

pub const App = struct {
    alloc: std.mem.Allocator,
    text_editor: ui.WidgetRef(u.TextAreaT),
    size_slider: ui.WidgetRef(u.SliderT),

    text_color: Color,
    bg_color: Color,
    text_wrap: bool,

    root: *u.Root,
    file_m: u32,
    cwd: []const u8,
    ctx: *ui.CommonContext,

    font_family: graphics.FontFamily,

    pub fn init(self: *App, c: *ui.InitContext) void {
        self.* = .{
            .alloc = c.alloc,
            .root = c.getRoot(),
            .text_editor = .{},
            .size_slider = .{},
            .text_color = Color.Black,
            .bg_color = Color.White,
            .text_wrap = false,
            .cwd = undefined,
            .file_m = undefined,
            .font_family = graphics.FontFamily.Default,
            .ctx = c.common,
        };
        var buf: [std.os.PATH_MAX]u8 = undefined;
        const cwd = std.os.getcwd(&buf) catch @panic("error");
        self.cwd = c.alloc.dupe(u8, cwd) catch @panic("error");
    }

    pub fn deinit(self: *App, alloc: std.mem.Allocator) void {
        alloc.free(self.cwd);
    }

    pub fn build(self: *App, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onSliderChange(self_: *App, value: i32) void {
                self_.text_editor.getWidget().setFontSize(@intToFloat(f32, value));
            }

            fn onFgPreviewChange(self_: *App, color: Color) void {
                self_.text_color = color;
            }

            fn onFgResult(self_: *App, color: Color, save: bool) void {
                _ = save;
                self_.text_color = color;
            }

            fn onBgPreviewChange(self_: *App, color: Color) void {
                self_.bg_color = color;
            }

            fn onBgResult(self_: *App, color: Color, save: bool) void {
                _ = save;
                self_.bg_color = color;
            }

            fn onTextWrapChange(self_: *App, is_set: bool) void {
                self_.text_wrap = is_set;
            }

            fn onOpenFont(self_: *App, path: []const u8) void {
                const font_data = std.fs.cwd().readFileAlloc(self_.alloc, path, 1e8) catch @panic("error");
                defer self_.alloc.free(font_data);
                const g = self_.ctx.getGraphics();
                const font_id = g.addFontTTF(font_data);
                self_.font_family = graphics.FontFamily{ .Font = font_id };
            }

            fn buildFileDialog(ptr: ?*anyopaque, c_: *ui.BuildContext) ui.FrameId {
                const self_ = stdx.mem.ptrCastAlign(*App, ptr);
                return u.FileDialog(.{
                    .init_cwd = self_.cwd,
                    .onResult = c_.funcExt(self_, onOpenFont),
                });
            }

            fn onLoadFontClick(self_: *App, _: ui.MouseUpEvent) void {
                self_.file_m = self_.root.showModal(self_, buildFileDialog, .{}) catch fatal();
            }
        };

        const size_slider = ui.WidgetProps(u.SliderT){
            .init_val = 20,
            .min_val = 1,
            .max_val = 200,
            .onChange = c.closure(self, S.onSliderChange),
        };

        return u.Row(.{}, &.{
            u.Flex(.{ .flex = 3 },
                u.Column(.{}, &.{
                    u.Stretch(.{},
                        u.Padding(.{ .padding = 10 }, 
                            u.TextArea(.{
                                .bind = &self.text_editor,
                                // .font_family = "Tamzen",
                                .font_family = self.font_family,
                                .init_val = "The quick brown fox 🦊 jumps over the lazy dog 🐶.\n\nThe graphics and UI are built on top of Freetype and OpenGL/Vulkan.",
                                .text_color = self.text_color,
                                .bg_color = self.bg_color,
                            }),
                        ),
                    ),
                }),
            ),
            u.Flex(.{ .flex = 1 },
                u.Column(.{ .spacing = 10 }, &.{ 
                    u.SliderOption(.{ .label = "Size", .slider = size_slider }),
                    u.ColorPicker(.{
                        .label = "Text Color",
                        .init_val = self.text_color,
                        .onPreviewChange = c.funcExt(self, S.onFgPreviewChange),
                        .onResult = c.funcExt(self, S.onFgResult),
                    }),
                    u.ColorPicker(.{
                        .label = "Bg Color",
                        .init_val = self.bg_color,
                        .onPreviewChange = c.funcExt(self, S.onBgPreviewChange),
                        .onResult = c.funcExt(self, S.onBgResult),
                    }),
                    u.SwitchOption(.{
                        .label = "Text Wrap (TODO)",
                        .init_val = false,
                        .onChange = c.funcExt(self, S.onTextWrapChange),
                    }),
                    u.TextButton(.{ .text = "Load Font", .onClick = c.funcExt(self, S.onLoadFontClick) }),
                }),
            ),
        });
    }
};

var app: helper.App = undefined;

pub fn main() !void {
    // This is the app loop for desktop. For web/wasm see wasm exports below.
    app.init("Text Demo");
    defer app.deinit();

    _ = app.gctx.addFontOTB(&.{
        .{ .data = tamzen9_otb, .size = 9 },
    });
    const emoji_font = app.gctx.addFontTTF(NotoColorEmoji);
    app.gctx.addFallbackFont(emoji_font);

    app.runEventLoop(update);
}

fn update(delta_ms: f32) void {
    const S = struct {
        fn buildRoot(_: void, c: *ui.BuildContext) ui.FrameId {
            return c.build(App, .{});
        }
    };
    const ui_width = @intToFloat(f32, app.win.getWidth());
    const ui_height = @intToFloat(f32, app.win.getHeight());
    app.ui_mod.updateAndRender(delta_ms, {}, S.buildRoot, ui_width, ui_height) catch unreachable;
}

pub usingnamespace if (IsWasm) struct {
    export fn wasmInit() *const u8 {
        return helper.wasmInit(&app, "Text Demo");
    }

    export fn wasmUpdate(cur_time_ms: f64, input_buffer_len: u32) *const u8 {
        return helper.wasmUpdate(cur_time_ms, input_buffer_len, &app, update);
    }

    /// Not that useful since it's a long lived process in the browser.
    export fn wasmDeinit() void {
        app.deinit();
        stdx.wasm.deinit();
    }
} else struct {};