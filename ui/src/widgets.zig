const ui = @import("ui.zig");
const module = @import("module.zig");

/// Root and overlays.
pub const Root = @import("widgets/root.zig").Root;
pub const PopoverOverlay = @import("widgets/root.zig").PopoverOverlay;
pub const ModalOverlay = @import("widgets/root.zig").ModalOverlay;

/// General widgets.
const slider = @import("widgets/slider.zig");
pub const SliderT = slider.Slider;
pub const Slider = genBuildWithNoChild(SliderT);
pub const SliderFloatT = slider.SliderFloat;
pub const SliderFloat = genBuildWithNoChild(SliderFloatT);
const switch_ = @import("widgets/switch.zig");
pub const SwitchT = switch_.Switch;
pub const Switch = genBuildWithNoChild(SwitchT);
pub const ColorPickerT = @import("widgets/color_picker.zig").ColorPicker;
pub const ColorPicker = genBuildWithNoChild(ColorPickerT);
const progress = @import("widgets/progress.zig");
pub const ProgressBarT = progress.ProgressBar;
pub const ProgressBar = genBuildWithNoChild(ProgressBarT);
pub const FileDialogT = @import("widgets/file_dialog.zig").FileDialog;
pub const FileDialog = genBuildWithNoChild(FileDialogT);

/// Flex containers.
const flex = @import("widgets/flex.zig");
pub const ColumnT = flex.Column;
pub const Column = genBuildWithChildren(ColumnT);
pub const RowT = flex.Row;
pub const Row = genBuildWithChildren(RowT);
pub const FlexT = flex.Flex;
pub const Flex = genBuildWithChild(FlexT);

/// Various containers.
const containers = @import("widgets/containers.zig");
pub const SizedT = containers.Sized;
pub const Sized = genBuildWithChild(SizedT);
pub const PaddingT = containers.Padding;
pub const Padding = genBuildWithChild(PaddingT);
pub const CenterT = containers.Center;
pub const Center = genBuildWithChild(CenterT);
pub const StretchT = containers.Stretch;
pub const Stretch = genBuildWithChild(StretchT);
pub const ZStackT = containers.ZStack;
pub const ZStack = genBuildWithChildren(ZStackT);
pub const ScrollViewT = @import("widgets/scroll_view.zig").ScrollView;
pub const ScrollView = genBuildWithChild(ScrollViewT);
const mouse_area = @import("widgets/mouse_area.zig");
pub const MouseAreaT = mouse_area.MouseArea;
pub const MouseArea = genBuildWithChild(MouseAreaT);
pub const MouseHoverAreaT = mouse_area.MouseHoverArea;
pub const MouseHoverArea = genBuildWithChild(MouseHoverAreaT);
pub const MouseDragAreaT = mouse_area.MouseDragArea;
pub const MouseDragArea = genBuildWithChild(MouseDragAreaT);
const list = @import("widgets/list.zig");
pub const List = list.List;
pub const ScrollListT = list.ScrollList;
pub const ScrollList = genBuildWithChildren(ScrollListT);
pub const ContainerT = containers.Container;
pub const Container = genBuildWithChild(ContainerT);
pub const PositionedT = containers.Positioned;
pub const Positioned = genBuildWithChild(PositionedT);

/// Window.
pub const WindowT = @import("widgets/window.zig").Window;
pub const Window = genBuildWithChild(WindowT);

/// Buttons.
const button = @import("widgets/button.zig");
pub const ButtonT = button.Button;
pub const Button = genBuildWithChild(ButtonT);
pub const TextButtonT = button.TextButton;
pub const TextButton = genBuildWithNoChild(TextButtonT);

/// Text related.
pub const TextT = @import("widgets/text.zig").Text;
pub const Text = genBuildWithNoChild(TextT);
const text_area = @import("widgets/text_area.zig");
pub const TextAreaT = text_area.TextArea;
pub const TextArea = genBuildWithNoChild(TextAreaT);
const text_field = @import("widgets/text_field.zig");
pub const TextFieldT = text_field.TextField;
pub const TextField = genBuildWithNoChild(TextFieldT);

/// Option widgets.
const options = @import("widgets/options.zig");
pub const SwitchOptionT = options.SwitchOption;
pub const SwitchOption = genBuildWithNoChild(SwitchOptionT);
pub const SliderOptionT = options.SliderOption;
pub const SliderOption = genBuildWithNoChild (SliderOptionT);
pub const SliderFloatOptionT = options.SliderFloatOption;
pub const SliderFloatOption = genBuildWithNoChild(SliderFloatOptionT);

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