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
        start_time_us: u64,
        timer: Timer,

        // Result.
        fps: u64,

        // Samples.
        frame_time_samples: [NumSamples]u64,
        frame_time_samples_idx: usize,
        frame_time_samples_sum: u64,

        last_update_time_us: u64,
        last_frame_time_us: u64,

        pub fn init(target_fps: u32) Self {
            const timer = Timer.start() catch unreachable;
            return .{
                .target_fps = target_fps,
                .target_us_per_frame = 1000000 / target_fps,
                .timer = timer,
                .start_time_us = timer.read() / 1000,
                .frame_time_samples = std.mem.zeroes([NumSamples]u64),
                .frame_time_samples_idx = 0,
                .frame_time_samples_sum = 0,
                .fps = 0,
                .last_update_time_us = 0,
                .last_frame_time_us = 0,
            };
        }

        /// Measures the frame time: the time it took to update the last frame and any delays.
        /// We do the measure here so user code has a more relevant frame delta to use since user code starts immediately after.
        pub fn beginFrame(self: *Self) void {
            var now_us = self.timer.read() / 1000;
            // Frame time includes any sleeping so it can be used to calculate fps.
            const frame_time_us = now_us - self.start_time_us;
            self.last_frame_time_us = frame_time_us;

            self.start_time_us = now_us;

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

        /// Measures the user update time and returns delay amount in microseconds to achieve target fps.
        pub fn endFrame(self: *Self) u64 {
            var now_us = self.timer.read() / 1000;

            // Frame update time does not include the delay time.
            const update_time_us = now_us - self.start_time_us;
            self.last_update_time_us = update_time_us;
            if (update_time_us < self.target_us_per_frame) {
                return self.target_us_per_frame - update_time_us;
            } else {
                return 0;
            }
        }

        /// Duration in microseconds.
        pub fn getLastFrameDelta(self: *const Self) u64 {
            return self.last_frame_time_us;
        }

        pub fn getLastUpdateDelta(self: *const Self) u64 {
            return self.last_update_time_us;
        }

        pub fn getFps(self: *const Self) u64 {
            return self.fps;
        }
    };
}