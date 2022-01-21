const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const Timer = stdx.time.Timer;
const sdl = @import("sdl");

const log = std.log.scoped(.fps);

pub const DefaultFpsLimiter = FpsLimiter(20);

pub fn FpsLimiter(comptime NumSamples: u32) type {
    return struct {
        const Self = @This();

        target_fps: u32,
        target_us_per_frame: u64,
        last_time_us: u64,
        timer: Timer,

        // Result.
        fps: u64,

        // Samples.
        frame_time_samples: [NumSamples]u64,
        frame_time_samples_idx: usize,
        frame_time_samples_sum: u64,

        last_frame_time_us: u64,

        pub fn init(target_fps: u32) Self {
            const timer = Timer.start() catch unreachable;
            return .{
                .target_fps = target_fps,
                .target_us_per_frame = 1000000 / target_fps,
                .timer = timer,
                .last_time_us = timer.read() / 1000,
                .frame_time_samples = std.mem.zeroes([NumSamples]u64),
                .frame_time_samples_idx = 0,
                .frame_time_samples_sum = 0,
                .fps = 0,
                .last_frame_time_us = 0,
            };
        }

        pub fn endFrameAndDelay(self: *Self) void {
            var now_us = self.timer.read() / 1000;

            // Frame update time does not include the delay time.
            const update_time_us = now_us - self.last_time_us;

            if (update_time_us < self.target_us_per_frame) {
                if (builtin.target.cpu.arch != .wasm32) {
                    sdl.SDL_Delay(@intCast(u32, (self.target_us_per_frame - update_time_us)/ 1000));
                } else {
                    // There isn't a good sleep mechanism in js since it's run on event loop.
                    // stdx.time.sleep(self.target_ms_per_frame - render_time_ms);
                }
                // log.debug("sleep {}", .{target_ms_per_frame - diff_ms});
                // Start timer after sleep so we don't include it as our render time.
                now_us = self.timer.read() / 1000;
            }
            // Frame time includes any sleeping so it can be used to calculate fps.
            const frame_time_us = now_us - self.last_time_us;
            self.last_time_us = now_us;
            self.last_frame_time_us = frame_time_us;

            // remove oldest sample from sum first.
            self.frame_time_samples_sum -= self.frame_time_samples[self.frame_time_samples_idx];
            self.frame_time_samples_sum += frame_time_us;
            self.frame_time_samples[self.frame_time_samples_idx] = frame_time_us;
            self.frame_time_samples_idx += 1;
            if (self.frame_time_samples_idx == NumSamples) {
                self.frame_time_samples_idx = 0;
            }

            const frame_time_avg = self.frame_time_samples_sum / NumSamples;
            if (frame_time_avg != 0) {
                // Compute fps even when we don't have all samples yet. It's not much different than waiting since the first
                // few frames will be super fast since vsync hasn't kicked in yet.
                self.fps = 1000000 / frame_time_avg;
                // Round to target_fps if close. The original measurement isn't very accurate anyway since we are using integers for the calculations.
                if (std.math.absInt(@intCast(i32, self.target_fps) - @intCast(i32, self.fps)) catch unreachable < 5) {
                    self.fps = self.target_fps;
                }
            }
        }

        /// Duration in microseconds.
        pub fn getLastFrameDelta(self: *const Self) u64 {
            return self.last_frame_time_us;
        }

        pub fn getFps(self: *const Self) u64 {
            return self.fps;
        }
    };
}
