const std = @import("std");
const builtin = @import("builtin");
const IsWasm = builtin.target.isWasm();
const stdx = @import("stdx");
const platform = @import("platform");
const Window = platform.Window;
const graphics = @import("graphics");
const Color = graphics.Color;
const ui = @import("ui");
const TextEditor = ui.widgets.TextEditor;
const TextButton = ui.widgets.TextButton;
const Column = ui.widgets.Column;
const Row = ui.widgets.Row;
const Text = ui.widgets.Text;
const Flex = ui.widgets.Flex;
const Button = ui.widgets.Button;
const Padding = ui.widgets.Padding;
const Stretch = ui.widgets.Stretch;
const ColorPicker = ui.widgets.ColorPicker;
const SwitchOption = ui.widgets.SwitchOption;
const FileDialog = ui.widgets.FileDialog;
const SliderOption = ui.widgets.SliderOption;
const Slider = ui.widgets.Slider;
const Root = ui.widgets.Root;

const helper = @import("helper.zig");
const log = stdx.log.scoped(.main);

/// Note: This embedded color emoji font only contains two emojis for the demo. Download the full emoji set on the web.
const NotoColorEmoji = @embedFile("../../examples/assets/NotoColorEmoji.ttf");

const tamzen9_otb = @embedFile("../../assets/tamzen5x9r.otb");

pub const App = struct {
    alloc: std.mem.Allocator,
    text_editor: ui.WidgetRef(TextEditor),
    size_slider: ui.WidgetRef(Slider),

    text_color: Color,
    bg_color: Color,
    text_wrap: bool,

    root: *Root,
    file_m: u32,
    cwd: []const u8,
    ctx: *ui.CommonContext,

    font_family: graphics.FontFamily,

    const Self = @This();

    pub fn init(self: *Self, c: *ui.InitContext) void {
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

    pub fn deinit(node: *ui.Node, alloc: std.mem.Allocator) void {
        const self = node.getWidget(Self);
        alloc.free(self.cwd);
    }

    pub fn build(self: *Self, c: *ui.BuildContext) ui.FrameId {
        const S = struct {
            fn onSliderChange(self_: *Self, value: i32) void {
                self_.text_editor.getWidget().setFontSize(@intToFloat(f32, value));
            }

            fn onFgPreviewChange(self_: *Self, color: Color) void {
                self_.text_color = color;
            }

            fn onFgResult(self_: *Self, color: Color, save: bool) void {
                _ = save;
                self_.text_color = color;
            }

            fn onBgPreviewChange(self_: *Self, color: Color) void {
                self_.bg_color = color;
            }

            fn onBgResult(self_: *Self, color: Color, save: bool) void {
                _ = save;
                self_.bg_color = color;
            }

            fn onTextWrapChange(self_: *Self, is_set: bool) void {
                self_.text_wrap = is_set;
            }

            fn onOpenFont(self_: *Self, path: []const u8) void {
                const font_data = std.fs.cwd().readFileAlloc(self_.alloc, path, 1e8) catch @panic("error");
                defer self_.alloc.free(font_data);
                const g = self_.ctx.getGraphics();
                const font_id = g.addFontTTF(font_data);
                self_.font_family = graphics.FontFamily{ .Font = font_id };
            }

            fn buildFileDialog(ptr: ?*anyopaque, c_: *ui.BuildContext) ui.FrameId {
                const self_ = stdx.mem.ptrCastAlign(*Self, ptr);
                return c_.decl(FileDialog, .{
                    .init_cwd = self_.cwd,
                    .onResult = c_.funcExt(self_, onOpenFont),
                });
            }

            fn onLoadFontClick(self_: *Self, _: platform.MouseUpEvent) void {
                self_.file_m = self_.root.showModal(self_, buildFileDialog, .{});
            }
        };

        const size_slider = ui.WidgetProps(Slider){
            .init_val = 20,
            .min_val = 1,
            .max_val = 200,
            .onChange = c.closure(self, S.onSliderChange),
        };

        return c.decl(Row, .{
            .children = c.list(.{
                c.decl(Flex, .{
                    .flex = 3,
                    .child = c.decl(Column, .{
                        .children = c.list(.{
                            c.decl(Stretch, .{
                                .child = c.decl(Padding, .{
                                    .padding = 10,
                                    .child = c.decl(TextEditor, .{
                                        .bind = &self.text_editor,
                                        // .font_family = "Tamzen",
                                        .font_family = self.font_family,
                                        .init_val = "The quick brown fox 🦊 jumps over the lazy dog 🐶.\n\nThe graphics and UI are built from scratch with no dependencies.",
                                        .text_color = self.text_color,
                                        .bg_color = self.bg_color,
                                    }),
                                }),
                            }),
                        }),
                    }),
                }),
                c.decl(Flex, .{
                    .flex = 1,
                    .child = c.decl(Column, .{
                        .spacing = 10,
                        .children = c.list(.{
                            c.decl(SliderOption, .{
                                .label = "Size",
                                .slider = size_slider,
                            }),
                            c.decl(ColorPicker, .{
                                .label = "Text Color",
                                .init_val = self.text_color,
                                .onPreviewChange = c.funcExt(self, S.onFgPreviewChange),
                                .onResult = c.funcExt(self, S.onFgResult),
                            }),
                            c.decl(ColorPicker, .{
                                .label = "Bg Color",
                                .init_val = self.bg_color,
                                .onPreviewChange = c.funcExt(self, S.onBgPreviewChange),
                                .onResult = c.funcExt(self, S.onBgResult),
                            }),
                            c.decl(SwitchOption, .{
                                .label = "Text Wrap (TODO)",
                                .init_val = false,
                                .onChange = c.funcExt(self, S.onTextWrapChange),
                            }),
                            c.decl(TextButton, .{
                                .text = "Load Font",
                                .onClick = c.funcExt(self, S.onLoadFontClick),
                            }),
                        }),
                    }),
                }),
            }),
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
            return c.decl(App, .{});
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