// Returns milliseconds.
extern fn performanceNow() f64;

pub const Timer = struct {
    const Self = @This();

    start_ns: u64,

    pub fn start() !Self {
        return Self{
            .start_ns = getNanoTime(),
        };
    }

    pub fn read(self: Self) u64 {
        return getNanoTime() - self.start_ns;
    }
};

fn getNanoTime() u64 {
    return @floatToInt(u64, performanceNow() * 1e6);
}
