const std = @import("std");

const ui = @import("ui.zig");

// Deprecated. No longer used due to move away from comptime Config.

/// Comptime config passed into ui.Module.
/// Contains type information about all the widgets that will be used in the module.
pub const Config = struct {
    const Self = @This();

    Imports: []const Import,

    pub fn Layout(comptime self: Self) type {
        return ui.LayoutContext(self);
    }

    pub fn Build(comptime self: Self) type {
        return ui.BuildContext(self);
    }

    pub fn Init(comptime self: Self) type {
        return ui.InitContext(self);
    }
};

const ImportTag = enum(u2) {
    /// Contains the Widget type.
    /// This is the recommended way to create an import.
    Type = 0,

    /// Creates the type with a comptime template function. Currently not used due to compiler bug.
    Template = 1,

    /// Creates the type with a comptime module.Config, a container type, and the name of the child template function.
    /// Currently crashes compiler when storing a comptime function so we store a type and name of fn decl instead.
    /// This is currently not used.
    ContainerTemplate = 2,
};

pub const Import = struct {
    const Self = @This();

    // Name used to reference the Widget. No longer used.
    name: ?@Type(.EnumLiteral),

    // For ContainerTypeTemplate.
    container_type: ?type,
    container_fn_name: ?[]const u8,

    create_fn: ?fn (Config) type,

    widget_type: ?type,

    tag: ImportTag,

    /// This is the recommended way to set an import.
    pub fn init(comptime T: type) @This() {
        return .{
            .name = null,
            .container_type = null,
            .container_fn_name = null,
            .create_fn = null,
            .widget_type = T,
            .tag = .Type,
        };
    }

    pub fn initTemplate(comptime TemplateFn: fn (Config) type) Self {
        return .{
            .name = null,
            .create_type = null,
            .container_fn_name = null,
            .create_fn = TemplateFn,
            .widget_type = null,
            .tag = .Template,
        };
    }

    pub fn initContainerTemplate(comptime Container: type, TemplateFnName: []const u8) Self {
        return .{
            .name = null,
            .container_type = Container,
            .container_fn_name = TemplateFnName,
            .create_fn = null,
            .widget_type = null,
            .tag = .ContainerTemplate,
        };
    }

    pub fn initTypes(comptime args: anytype) []const Self {
        var res: []const Self = &.{};
        inline for (std.meta.fields(@TypeOf(args))) |f| {
            const T = @field(args, f.name);
            res = res ++ &[_]Self{init(T)};
        }
        return res;
    }

    pub fn initTypeSlice(comptime Types: []const type) []const Self {
        var res: []const @This() = &.{};
        for (Types) |T| {
            res = res ++ &[_]@This(){init(T)};
        }
        return res;
    }
};