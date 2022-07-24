const ui = @import("ui.zig");
const module = @import("module.zig");

/// Root and overlays.
pub const Root = @import("widgets/root.zig").Root;
pub const PopoverOverlay = @import("widgets/root.zig").PopoverOverlay;
pub const ModalOverlay = @import("widgets/root.zig").ModalOverlay;

/// General widgets.
const slider = @import("widgets/slider.zig");
pub const SliderUI = slider.Slider;
pub const Slider = genBuildWithNoChild(SliderUI);
pub const SliderFloatUI = slider.SliderFloat;
pub const SliderFloat = genBuildWithNoChild(SliderFloatUI);
const switch_ = @import("widgets/switch.zig");
pub const SwitchUI = switch_.Switch;
pub const Switch = genBuildWithNoChild(SwitchUI);
pub const ColorPickerUI = @import("widgets/color_picker.zig").ColorPicker;
pub const ColorPicker = genBuildWithNoChild(ColorPickerUI);
const progress = @import("widgets/progress.zig");
pub const ProgressBarUI = progress.ProgressBar;
pub const ProgressBar = genBuildWithNoChild(ProgressBarUI);
pub const FileDialogUI = @import("widgets/file_dialog.zig").FileDialog;
pub const FileDialog = genBuildWithNoChild(FileDialogUI);

/// Flex containers.
const flex = @import("widgets/flex.zig");
pub const ColumnUI = flex.Column;
pub const Column = genBuildWithChildren(ColumnUI);
pub const RowUI = flex.Row;
pub const Row = genBuildWithChildren(RowUI);
pub const FlexUI = flex.Flex;
pub const Flex = genBuildWithChild(FlexUI);

/// Various containers.
const containers = @import("widgets/containers.zig");
pub const SizedUI = containers.Sized;
pub const Sized = genBuildWithChild(SizedUI);
pub const PaddingUI = containers.Padding;
pub const Padding = genBuildWithChild(PaddingUI);
pub const CenterUI = containers.Center;
pub const Center = genBuildWithChild(CenterUI);
pub const StretchUI = containers.Stretch;
pub const Stretch = genBuildWithChild(StretchUI);
pub const ZStack = containers.ZStack;
pub const ScrollViewUI = @import("widgets/scroll_view.zig").ScrollView;
pub const ScrollView = genBuildWithChild(ScrollViewUI);
const mouse_area = @import("widgets/mouse_area.zig");
pub const MouseAreaUI = mouse_area.MouseArea;
pub const MouseArea = genBuildWithChild(MouseAreaUI);
const list = @import("widgets/list.zig");
pub const List = list.List;
pub const ScrollListUI = list.ScrollList;
pub const ScrollList = genBuildWithChildren(ScrollListUI);

/// Buttons.
const button = @import("widgets/button.zig");
pub const ButtonUI = button.Button;
pub const Button = genBuildWithChild(ButtonUI);
pub const TextButtonUI = button.TextButton;
pub const TextButton = genBuildWithNoChild(TextButtonUI);

/// Text related.
pub const TextUI = @import("widgets/text.zig").Text;
pub const Text = genBuildWithNoChild(TextUI);
const text_editor = @import("widgets/text_editor.zig");
pub const TextEditorUI = text_editor.TextEditor;
pub const TextEditor = genBuildWithNoChild(TextEditorUI);
const text_field = @import("widgets/text_field.zig");
pub const TextFieldUI = text_field.TextField;
pub const TextField = genBuildWithNoChild(TextFieldUI);

/// Option widgets.
const options = @import("widgets/options.zig");
pub const SwitchOptionUI = options.SwitchOption;
pub const SwitchOption = genBuildWithNoChild(SwitchOptionUI);
pub const SliderOptionUI = options.SliderOption;
pub const SliderOption = genBuildWithNoChild (SliderOptionUI);
pub const SliderFloatOptionUI = options.SliderFloatOption;
pub const SliderFloatOption = genBuildWithNoChild(SliderFloatOptionUI);

fn genBuildWithNoChild(comptime Widget: type) fn (props: anytype) ui.FrameId {
    const S = struct {
        fn build(props: anytype) ui.FrameId {
            return module.gbuild_ctx.build(Widget, props);
        }
    };
    return S.build;
}

fn genBuildWithChild(comptime Widget: type) fn (props: anytype, child: ui.FrameId) ui.FrameId {
    const S = struct {
        fn build(props: anytype, child: ui.FrameId) ui.FrameId {
            var wprops: ui.WidgetProps(Widget) = undefined;
            ui.BuildContext.setWidgetProps(Widget, &wprops, props);
            wprops.child = child;
            return module.gbuild_ctx.createFrame(Widget, &wprops, props);
        }
    };
    return S.build;
}

fn genBuildWithChildren(comptime Widget: type) fn (props: anytype, children: []const ui.FrameId) ui.FrameId {
    const S = struct {
        fn build(props: anytype, children: []const ui.FrameId) ui.FrameId {
            var wprops: ui.WidgetProps(Widget) = undefined;
            ui.BuildContext.setWidgetProps(Widget, &wprops, props);
            wprops.children = module.gbuild_ctx.list(children);
            return module.gbuild_ctx.createFrame(Widget, &wprops, props);
        }
    };
    return S.build;
}