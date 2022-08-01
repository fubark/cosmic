const std = @import("std");

const module = @import("module.zig");
pub const Module = module.Module;
pub const Layout = module.Layout;
pub const TextMeasureId = module.TextMeasureId;
pub const RenderContext = module.RenderContext;
pub const LayoutContext = module.LayoutContext;
pub const InitContext = module.InitContext;
pub const ModuleContext = module.ModuleContext;
pub const CommonContext = module.CommonContext;
pub const IntervalId = module.IntervalId;
pub const WidgetProps = module.WidgetProps;
pub const SizeConstraints = module.SizeConstraints;

const events = @import("events.zig");
pub const Event = events.Event;
pub const IntervalEvent = events.IntervalEvent;
pub const KeyDownEvent = events.KeyDownEvent;
pub const KeyUpEvent = events.KeyUpEvent;
pub const MouseDownEvent = events.MouseDownEvent;
pub const MouseUpEvent = events.MouseUpEvent;
pub const MouseMoveEvent = events.MouseMoveEvent;
pub const MouseScrollEvent = events.MouseScrollEvent;
pub const HoverChangeEvent = events.HoverChangeEvent;
pub const DragStartEvent = events.DragStartEvent;
pub const DragMoveEvent = events.DragMoveEvent;
pub const EventContext = events.EventContext;
pub const EventResult = events.EventResult;

const build = @import("build.zig");
pub const BuildContext = build.BuildContext;

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
pub const NoChild = NullId;

const widget = @import("widget.zig");
pub const Node = widget.Node;
pub const NodeRef = widget.NodeRef;
pub const NodeStateMasks = widget.NodeStateMasks;
pub const EventHandlerMasks = widget.EventHandlerMasks;
pub const WidgetTypeId = widget.WidgetTypeId;
pub const WidgetUserId = widget.WidgetUserId;
pub const WidgetKey = widget.WidgetKey;
pub const WidgetKeyId = widget.WidgetKeyId;
pub const WidgetRef = widget.WidgetRef;
pub const NodeRefMap = widget.NodeRefMap;
pub const BindNodeFunc = widget.BindNodeFunc;
pub const WidgetVTable = widget.WidgetVTable;
pub const LayoutSize = widget.LayoutSize;

pub const widgets = @import("widgets.zig");

const text = @import("text.zig");
pub const TextMeasure = text.TextMeasure;

const tween = @import("tween.zig");
pub const Tween = tween.Tween;
pub const SimpleTween = tween.SimpleTween;

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

/// Create a declaration function for a Widget.
pub fn createDeclFn(comptime Widget: type) fn (*BuildContext, anytype) callconv(.Inline) FrameId {
    const S = struct {
        inline fn decl(c: *BuildContext, props: anytype) FrameId {
            return c.build(Widget, props);
        }
    };
    return S.decl;
}

pub const ExpandedWidth = std.math.inf_f32;
pub const ExpandedHeight = std.math.inf_f32;

pub const OverlayId = @import("widgets/root.zig").OverlayId;