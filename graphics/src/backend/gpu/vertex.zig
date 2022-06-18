const stdx = @import("stdx");
const t = stdx.testing;

const graphics = @import("../../graphics.zig");

pub const TexShaderVertex = packed struct {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    // TODO: Might be able to remove w and set to 1 in shader.
    pos_w: f32,
    /// Used for lighting.
    norm_x: f32,
    norm_y: f32,
    norm_z: f32,
    uv_x: f32,
    uv_y: f32,
    color_r: f32,
    color_g: f32,
    color_b: f32,
    color_a: f32,

    /// Animation joints. 
    joints: packed union {
        // Split up into components for cpu manipulation.
        components: packed struct {
            joint_0: u16,
            joint_1: u16,
            joint_2: u16,
            joint_3: u16,
        },
        // Sent over to gpu with custom endian encoding that matches shader decoder.
        // Indexes to dynamic joint matrices.
        compact: packed struct {
            joint_0: u32,
            joint_1: u32,
        },
    },

    /// Animation weights.
    weights: u32, // First weight is least significant byte.

    const Self = @This();

    pub fn setXY(self: *Self, x: f32, y: f32) void {
        self.pos_x = x;
        self.pos_y = y;
        self.pos_z = 0;
        self.pos_w = 1;
    }

    pub fn setXYZ(self: *Self, x: f32, y: f32, z: f32) void {
        self.pos_x = x;
        self.pos_y = y;
        self.pos_z = z;
        self.pos_w = 1;
    }

    pub fn setColor(self: *Self, color: graphics.Color) void {
        self.color_r = @intToFloat(f32, color.channels.r) / 255;
        self.color_g = @intToFloat(f32, color.channels.g) / 255;
        self.color_b = @intToFloat(f32, color.channels.b) / 255;
        self.color_a = @intToFloat(f32, color.channels.a) / 255;
    }

    pub fn setUV(self: *Self, u: f32, v: f32) void {
        self.uv_x = u;
        self.uv_y = v;
    }
};

test "TexShaderVertex" {
    try t.eq(@sizeOf(TexShaderVertex), 4*4 + 4*3 + 4*2 + 4*4 + 2*4 + 4);
    try t.eq(@offsetOf(TexShaderVertex, "pos_x"), 0);
    try t.eq(@offsetOf(TexShaderVertex, "norm_x"), 4*4);
    try t.eq(@offsetOf(TexShaderVertex, "uv_x"), 4*4 + 4*3);
    try t.eq(@offsetOf(TexShaderVertex, "color_r"), 4*4 + 4*3 + 4*2);
    try t.eq(@offsetOf(TexShaderVertex, "joints"), 4*4 + 4*3 + 4*2 + 4*4);
    try t.eq(@offsetOf(TexShaderVertex, "weights"), 4*4 + 4*3 + 4*2 + 4*4 + 2*4);
}