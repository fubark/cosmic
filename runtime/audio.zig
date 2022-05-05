const std = @import("std");
const stdx = @import("stdx");
const Vec3 = stdx.math.Vec3;
const ma = @import("miniaudio");

const log = stdx.log.scoped(.audio);

pub const AudioEngine = struct {
    const Self = @This();

    engine: ma.ma_engine,

    pub fn init(self: *Self) void {
        const res = ma.ma_engine_init(null, &self.engine);
        ma.assertNoError(res);
    }
    
    pub fn deinit(self: *Self) void {
        ma.ma_engine_uninit(&self.engine);
    }

    /// Data is duped so it can be manged.
    pub fn createSound(self: *Self, alloc: std.mem.Allocator, encoding: Sound.Encoding, data: []const u8) !*Sound {
        const new = alloc.create(Sound) catch unreachable;
        new.* = .{
            .sound = undefined,
            .decoder = undefined,
            .data = alloc.dupe(u8, data) catch unreachable,
        };
        errdefer {
            alloc.free(new.data);
            alloc.destroy(new);
        }

        var config = ma.ma_decoder_config_init_default();
        config.encodingFormat = switch (encoding) {
            .Wav => ma.ma_encoding_format_wav,
            .Mp3 => ma.ma_encoding_format_mp3,
            .Flac => ma.ma_encoding_format_flac,
            .Ogg => ma.ma_encoding_format_vorbis,
            // ma will try to detect the encoding.
            .Unknown => ma.ma_encoding_format_unknown,
        };
        var res = ma.ma_decoder_init_memory(new.data.ptr, new.data.len, &config, &new.decoder);
        if (res != ma.MA_SUCCESS) {
            switch (res) {
                ma.MA_NO_BACKEND => return error.InvalidFormat,
                else => ma.assertNoError(res),
            }
        }

        res = ma.ma_sound_init_from_data_source(&self.engine, &new.decoder, 0, null, &new.sound);
        ma.assertNoError(res);

        return new;
    }

    pub fn getNumListeners(self: Self) u32 {
        return ma.ma_engine_get_listener_count(&self.engine);
    }

    pub fn isListenerEnabled(self: Self, idx: u32) bool {
        return ma.ma_engine_listener_is_enabled(&self.engine, idx) == 1;
    }

    pub fn setListenerEnabled(self: *Self, idx: u32, enabled: bool) void {
        ma.ma_engine_listener_set_enabled(&self.engine, idx, if (enabled) 1 else 0);
    }

    pub fn getListenerPosition(self: Self, idx: u32) Vec3 {
        const res = ma.ma_engine_listener_get_position(&self.engine, idx);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setListenerPosition(self: *Self, idx: u32, pos: Vec3) void {
        ma.ma_engine_listener_set_position(&self.engine, idx, pos.x, pos.y, pos.z);
    }

    pub fn getListenerDirection(self: Self, idx: u32) Vec3 {
        const res = ma.ma_engine_listener_get_direction(&self.engine, idx);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setListenerDirection(self: *Self, idx: u32, dir: Vec3) void {
        ma.ma_engine_listener_set_direction(&self.engine, idx, dir.x, dir.y, dir.z);
    }

    pub fn getListenerWorldUp(self: Self, idx: u32) Vec3 {
        const res = ma.ma_engine_listener_get_world_up(&self.engine, idx);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setListenerWorldUp(self: *Self, idx: u32, dir: Vec3) void {
        ma.ma_engine_listener_set_world_up(&self.engine, idx, dir.x, dir.y, dir.z);
    }

    pub fn getListenerVelocity(self: Self, idx: u32) Vec3 {
        const res = ma.ma_engine_listener_get_velocity(&self.engine, idx);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setListenerVelocity(self: *Self, idx: u32, vel: Vec3) void {
        ma.ma_engine_listener_set_velocity(&self.engine, idx, vel.x, vel.y, vel.z);
    }
};

pub const Sound = struct {
    const Self = @This();

    pub const Encoding = enum {
        Wav,
        Mp3,
        Flac,
        Ogg,
        Unknown,
    };

    sound: ma.ma_sound,
    decoder: ma.ma_decoder,
    data: []const u8,

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        ma.ma_sound_uninit(&self.sound);

        const res = ma.ma_decoder_uninit(&self.decoder);
        ma.assertNoError(res);

        alloc.free(self.data);
    }

    pub fn play(self: *Self) void {
        ma.ma_sound_set_looping(&self.sound, 0);
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
        while (true) {
            if (ma.ma_sound_is_playing(&self.sound) == 0) {
                break;
            }
            std.time.sleep(30e6);
        }
        std.debug.assert(ma.ma_sound_at_end(&self.sound) == 1);
    }

    pub fn playBg(self: *Self) void {
        ma.ma_sound_set_looping(&self.sound, 0);
        if (self.isPlayingBg()) {
            self.seekToPcmFrame(0);
        }
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
    }

    pub fn isPlayingBg(self: Self) bool {
        return ma.ma_sound_is_playing(&self.sound) == 1;
    }

    pub fn loopBg(self: *Self) void {
        ma.ma_sound_set_looping(&self.sound, 1);
        if (self.isPlayingBg()) {
            self.seekToPcmFrame(0);
        }
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
    }

    pub fn isLoopingBg(self: Self) bool {
        return ma.ma_sound_is_looping(&self.sound) == 1;
    }

    pub fn pauseBg(self: *Self) void {
        const res = ma.ma_sound_stop(&self.sound);
        ma.assertNoError(res);
    }

    pub fn resumeBg(self: *Self) void {
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
    }

    pub fn stopBg(self: *Self) void {
        const res = ma.ma_sound_stop(&self.sound);
        ma.assertNoError(res);
        self.seekToPcmFrame(0);
    }

    pub fn setVolume(self: *Self, volume: f32) void {
        ma.ma_sound_set_volume(&self.sound, volume);
    }

    pub fn getVolume(self: Self) f32 {
        return ma.ma_sound_get_volume(&self.sound);
    }

    pub fn setGain(self: *Self, gain: f32) void {
        const volume = ma.ma_volume_db_to_linear(gain);
        ma.ma_sound_set_volume(&self.sound, volume);
    }

    pub fn getGain(self: Self) f32 {
        const volume = ma.ma_sound_get_volume(&self.sound);
        return ma.ma_volume_linear_to_db(volume);
    }

    /// Value must be greater than 0.
    pub fn setPitch(self: *Self, pitch: f32) void {
        ma.ma_sound_set_pitch(&self.sound, pitch);
    }

    pub fn getPitch(self: Self) f32 {
        return ma.ma_sound_get_pitch(&self.sound);
    }

    /// -1 (stereo left) to 1 (stereo right). Middle is 0.
    pub fn setPan(self: *Self, pan: f32) void {
        ma.ma_sound_set_pan(&self.sound, pan);
    }

    pub fn getPan(self: Self) f32 {
        return ma.ma_sound_get_pan(&self.sound);
    }

    pub fn getLengthInPcmFrames(self: *Self) !u64 {
        var length: c_ulonglong = undefined;
        const res = ma.ma_sound_get_length_in_pcm_frames(&self.sound, &length);
        ma.assertNoError(res);
        if (length == 0) {
            return error.Unsupported;
        }
        return length;
    }

    pub fn getDataFormat(self: *Self) DataFormat {
        var format: ma.ma_format = undefined;
        var channels: u32 = undefined;
        var sample_rate: u32 = undefined;
        const res = ma.ma_sound_get_data_format(&self.sound, &format, &channels, &sample_rate, null, 0);
        ma.assertNoError(res);
        return .{
            .format = @intToEnum(Format, format),
            .channels = channels,
            .sample_rate = sample_rate,
        };
    }

    /// Returns length in milliseconds.
    pub fn getLength(self: *Self) !u64 {
        const format = self.getDataFormat();
        const len = try self.getLengthInPcmFrames();
        return @floatToInt(u64, @ceil(@intToFloat(f64, len) / @intToFloat(f64, format.sample_rate) * 1000));
    }

    pub fn getCursorPcmFrame(self: *Self) u64 {
        var cursor: c_ulonglong = undefined;
        const res = ma.ma_sound_get_cursor_in_pcm_frames(&self.sound, &cursor);
        ma.assertNoError(res);
        return cursor;
    }

    pub fn seekToPcmFrame(self: *Self, frame_index: u64) void {
        // Since the data source is not managed by the ma_sound,
        // we should invoke ma_data_source_seek_to_pcm_frame instead of ma_sound_seek_to_pcm_frame.
        const res = ma.ma_data_source_seek_to_pcm_frame(&self.decoder, frame_index);
        ma.assertNoError(res);
    }

    pub fn setPosition(self: *Self, x: f32, y: f32, z: f32) void {
        ma.ma_sound_set_position(&self.sound, x, y, z);
    }

    pub fn getPosition(self: Self) Vec3 {
        const res = ma.ma_sound_get_position(&self.sound);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setDirection(self: *Self, x: f32, y: f32, z: f32) void {
        ma.ma_sound_set_direction(&self.sound, x, y, z);
    }

    pub fn getDirection(self: Self) Vec3 {
        const res = ma.ma_sound_get_direction(&self.sound);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }

    pub fn setVelocity(self: *Self, x: f32, y: f32, z: f32) void {
        ma.ma_sound_set_velocity(&self.sound, x, y, z);
    }

    pub fn getVelocity(self: Self) Vec3 {
        const res = ma.ma_sound_get_velocity(&self.sound);
        return .{ .x = res.x, .y = res.y, .z = res.z };
    }
};

const DataFormat = struct {
    format: Format,
    channels: u32,
    sample_rate: u32,
};

const Format = enum(u32) {
    Unknown = ma.ma_format_unknown,
    U8 = ma.ma_format_u8,
    S16 = ma.ma_format_s16,
    S24 = ma.ma_format_s24,
    S32 = ma.ma_format_s32,
    F32 = ma.ma_format_f32,
};