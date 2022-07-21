const stb_perlin = @import("stb_perlin");

pub fn perlinNoise(x: f32, y: f32, z: f32) f32 {
    return stb_perlin.stb_perlin_noise3(x, y, z, 0, 0, 0);
}