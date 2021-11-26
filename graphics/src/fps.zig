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
        target_ms_per_frame: u64,
        last_time_ms: u64,
        timer: Timer,

        // Result.
        fps: u64,

        // Samples.
        frame_time_samples: [NumSamples]u64,
        frame_time_samples_idx: usize,
        frame_time_samples_sum: u64,

        pub fn init(target_fps: u32) Self {
            const timer = Timer.start() catch unreachable;
            return .{
                .target_fps = target_fps,
                .target_ms_per_frame = 1000 / target_fps,
                .timer = timer,
                .last_time_ms = timer.read() / 1000000,
                .frame_time_samples = std.mem.zeroes([NumSamples]u64),
                .frame_time_samples_idx = 0,
                .frame_time_samples_sum = 0,
                .fps = 0,
            };
        }

        pub fn endFrameAndDelay(self: *Self) void {
            var now_ms = self.timer.read() / 1000000;
            const render_time_ms = now_ms - self.last_time_ms;

            // log.debug("render time {}", .{diff_ms});
            if (render_time_ms < self.target_ms_per_frame) {
                if (builtin.target.cpu.arch != .wasm32) {
                    sdl.SDL_Delay(@intCast(u32, self.target_ms_per_frame - render_time_ms));
                } else {
                    // There isn't a good sleep mechanism in js since it's run on event loop.
                    // stdx.time.sleep(self.target_ms_per_frame - render_time_ms);
                }
                // log.debug("sleep {}", .{target_ms_per_frame - diff_ms});
                // Start timer after sleep so we don't include it as our render time.
                now_ms = self.timer.read() / 1000000;
            }
            // Frame time includes any sleeping so it can be used to calculate fps.
            const frame_time_ms = now_ms - self.last_time_ms;
            self.last_time_ms = now_ms;

            // remove oldest sample from sum first.
            self.frame_time_samples_sum -= self.frame_time_samples[self.frame_time_samples_idx];
            self.frame_time_samples_sum += frame_time_ms;
            self.frame_time_samples[self.frame_time_samples_idx] = frame_time_ms;
            self.frame_time_samples_idx += 1;
            if (self.frame_time_samples_idx == NumSamples) {
                self.frame_time_samples_idx = 0;
            }

            const frame_time_avg = self.frame_time_samples_sum / NumSamples;
            if (frame_time_avg != 0) {
                // Compute fps even when we don't have all samples yet. It's not much different than waiting since the first
                // few frames will be super fast since vsync hasn't kicked in yet.
                self.fps = 1000 / frame_time_avg;
                // Round to target_fps if close. The original measurement isn't very accurate anyway since we are using integers for the calculations.
                if (std.math.absInt(@intCast(i32, self.target_fps) - @intCast(i32, self.fps)) catch unreachable < 5) {
                    self.fps = self.target_fps;
                }
            }
        }

        pub fn getDeltaMs(self: *const Self) u64 {
            return self.frame_time_samples[self.frame_time_samples_idx];
        }

        pub fn getFps(self: *const Self) u64 {
            return self.fps;
        }
    };
}