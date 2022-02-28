const std = @import("std");
const ma = @import("miniaudio");

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

        var config = ma.ma_decoder_config_init_default();
        config.encodingFormat = switch (encoding) {
            .Wav => ma.ma_encoding_format_wav,
            // ma will try to detect the encoding.
            .Unknown => ma.ma_encoding_format_unknown,
        };
        var res = ma.ma_decoder_init_memory(new.data.ptr, new.data.len, &config, &new.decoder);
        if (res != ma.MA_SUCCESS) {
            switch (res) {
                else => ma.assertNoError(res),
            }
        }

        res = ma.ma_sound_init_from_data_source(&self.engine, &new.decoder, 0, null, &new.sound);
        ma.assertNoError(res);

        return new;
    }
};

pub const Sound = struct {
    const Self = @This();

    const Encoding = enum {
        Wav,
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
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
        while (true) {
            if (ma.ma_sound_is_playing(&self.sound) == 0) {
                break;
            }
            std.time.sleep(30);
        }
        std.debug.assert(ma.ma_sound_at_end(&self.sound) == 1);
    }

    pub fn playBg(self: *Self) void {
        const res = ma.ma_sound_start(&self.sound);
        ma.assertNoError(res);
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
};
