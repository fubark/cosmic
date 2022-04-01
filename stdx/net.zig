const std = @import("std");
const stdx = @import("./stdx.zig");
const t = stdx.testing;

const HostPort = struct {
    host: ?[]const u8,
    port: ?u32,
};

pub fn parseHostPort(str: []const u8) !HostPort {
    var iter = std.mem.split(u8, str, ":");
    const host_str = iter.next() orelse return error.Parse;
    var res = HostPort{
        .host = if (host_str.len == 0) null else host_str,
        .port = null,
    };
    if (iter.next()) |port_str| {
        if (port_str.len == 0) {
            res.port = null;
        } else {
            res.port = try std.fmt.parseInt(u32, port_str, 10);
        }
    }
    if (iter.next()) |_| {
        return error.Parse;
    }
    return res;
}

test "parseHostPort" {
    var res: HostPort = undefined;
    
    res = try parseHostPort("127.0.0.1:8081");
    try t.eqStr(res.host.?, "127.0.0.1");
    try t.eq(res.port.?, 8081);

    try t.expectError(parseHostPort("127.0.0.1:foo"), error.InvalidCharacter);

    res = try parseHostPort("127.0.0.1");
    try t.eqStr(res.host.?, "127.0.0.1");
    try t.eq(res.port, null);

    res = try parseHostPort(":8081");
    try t.eq(res.host, null);
    try t.eq(res.port.?, 8081);

    res = try parseHostPort(":");
    try t.eq(res.host, null);
    try t.eq(res.port, null);
}