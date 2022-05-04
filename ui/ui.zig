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

const config = @import("config.zig");
pub const Config = config.Config;
pub const Import = config.Import;

const frame = @import("frame.zig");
pub const Frame = frame.Frame;
pub const FrameId = frame.FrameId;
pub const NullId = @import("std").math.maxInt(NullId);
pub const NullFrameId = frame.NullFrameId;
pub const FrameListPtr = frame.FrameListPtr;
pub const FramePropsPtr = frame.FramePropsPtr;

const widget = @import("widget.zig");
pub const Node = widget.Node;
pub const WidgetTypeId = widget.WidgetTypeId;
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