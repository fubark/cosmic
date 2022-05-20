const module = @import("module.zig");
pub const Module = module.Module;
pub const Layout = module.Layout;
pub const TextMeasureId = module.TextMeasureId;
pub const BuildContext = module.BuildContext;
pub const RenderContext = module.RenderContext;
pub const LayoutContext = module.LayoutContext;
pub const EventContext = module.EventContext;
pub const InitContext = module.InitContext;
pub const ModuleContext = module.ModuleContext;
pub const CommonContext = module.CommonContext;
pub const IntervalId = module.IntervalId;
pub const Event = module.Event;
pub const IntervalEvent = module.IntervalEvent;
pub const KeyDownEvent = module.KeyDownEvent;
pub const KeyUpEvent = module.KeyUpEvent;
pub const MouseDownEvent = module.MouseDownEvent;
pub const MouseUpEvent = module.MouseUpEvent;
pub const MouseMoveEvent = module.MouseMoveEvent;
pub const MouseScrollEvent = module.MouseScrollEvent;

const config = @import("config.zig");
pub const Config = config.Config;
pub const Import = config.Import;

const frame = @import("frame.zig");
pub const Frame = frame.Frame;
pub const FrameId = frame.FrameId;
pub const NullId = @import("std").math.maxInt(u32);
pub const NullFrameId = frame.NullFrameId;
pub const FrameListPtr = frame.FrameListPtr;
pub const FramePropsPtr = frame.FramePropsPtr;

const widget = @import("widget.zig");
pub const Node = widget.Node;
pub const WidgetTypeId = widget.WidgetTypeId;
pub const WidgetUserId = widget.WidgetUserId;
pub const WidgetKey = widget.WidgetKey;
pub const WidgetRef = widget.WidgetRef;
pub const WidgetVTable = widget.WidgetVTable;
pub const LayoutSize = widget.LayoutSize;

pub const widgets = @import("widgets.zig");

const text = @import("text.zig");
pub const TextMeasure = text.TextMeasure;

pub const VAlign = enum(u2) {
    Top = 0,
    Center = 1,
    Bottom = 2,
};

pub const HAlign = enum(u2) {
    Left = 0,
    Center = 1,
    Right = 2,
};

pub const FlexFit = enum(u2) {
    /// Prefers to fit exactly the available space.
    Exact = 0,
    /// Prefers to wrap the child. If the available space is less than the child's dimension, prefers to fit the available space.
    Shrink = 1,
    /// Like Shrink but in the case that the child size is less than the available space; instead of skipping the missing space to the next flex widget,
    /// that missing space is given to the next flex widget, which can make the next flex widget bigger than it's calculated flex size.
    ShrinkAndGive = 2,
};

pub const FlexInfo = struct {
    val: u32,
    fit: FlexFit,
};