/// Provides a convenience wrapper to interpolate a value over time.
pub fn Tween(comptime T: type) type {
    return struct {
        val: T,
        start: T,
        end: T,
        duration_ms: f32,
        t: f32,

        const Self = @This();

        pub fn init(start: T, end: T, duration_ms: f32) Self {
            return .{
                .val = start,
                .start = start,
                .end = end,
                .duration_ms = duration_ms,
                .t = 0,
            };
        }

        pub fn step(self: *Self, delta_ms: f32) void {
            self.t += delta_ms / self.duration_ms;
            if (self.t > 1) {
                self.t = 1;
            }
            switch (T) {
                f32 => {
                    self.val = self.t * (self.end - self.start);
                },
                else => @panic("unsupported"),
            }
        }

        pub inline fn getValue(self: Self) T {
            return self.val;
        }

        pub inline fn reset(self: *Self) void {
            self.t = 0;
            self.val = self.start;
        }

        pub inline fn finish(self: *Self) void {
            self.t = 1;
            self.val = self.end;
        }
    };
}

/// Only updates a t value between 0 and 1.
pub const SimpleTween = struct {

    t: f32,
    duration_ms: f32,

    const Self = @This();

    pub fn init(duration_ms: f32) Self {
        return .{
            .duration_ms = duration_ms,
            .t = 0,
        };
    }

    pub fn step(self: *Self, delta_ms: f32) void {
        self.t += delta_ms / self.duration_ms;
        if (self.t > 1) {
            self.t = 1;
        }
    }

    pub inline fn getValue(self: Self) f32 {
        return self.t;
    }

    pub inline fn reset(self: *Self) void {
        self.t = 0;
    }

    pub inline fn finish(self: *Self) void {
        self.t = 1;
    }
};