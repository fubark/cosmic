const stdx = @import("stdx");
const t = stdx.testing;

const graphics = @import("../../graphics.zig");

pub const TexShaderVertex = struct {
    pos: struct {
        x: f32,
        y: f32,
        z: f32,
        // TODO: Might be able to remove w and set to 1 in shader.
        w: f32,
    },

    /// Used for lighting.
    normal: struct {
        x: f32,
        y: f32,
        z: f32,
    },

    uv: struct {
        x: f32,
        y: f32,
    },

    color: struct {
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    },

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
        self.pos.x = x;
        self.pos.y = y;
        self.pos.z = 0;
        self.pos.w = 1;
    }

    pub fn setXYZ(self: *Self, x: f32, y: f32, z: f32) void {
        self.pos.x = x;
        self.pos.y = y;
        self.pos.z = z;
        self.pos.w = 1;
    }

    pub fn setColor(self: *Self, color: graphics.Color) void {
        self.color.r = @intToFloat(f32, color.channels.r) / 255;
        self.color.g = @intToFloat(f32, color.channels.g) / 255;
        self.color.b = @intToFloat(f32, color.channels.b) / 255;
        self.color.a = @intToFloat(f32, color.channels.a) / 255;
    }

    pub fn setNormal(self: *Self, normal: stdx.math.Vec3) void {
        self.normal.x = normal.x;
        self.normal.y = normal.y;
        self.normal.z = normal.z;
    }

    pub fn setUV(self: *Self, u: f32, v: f32) void {
        self.uv.x = u;
        self.uv.y = v;
    }
};

test "TexShaderVertex" {
    try t.eq(@sizeOf(TexShaderVertex), 4*4 + 4*3 + 4*2 + 4*4 + 2*4 + 4);
    try t.eq(@offsetOf(TexShaderVertex, "pos"), 0);
    try t.eq(@offsetOf(TexShaderVertex, "normal"), 4*4);
    try t.eq(@offsetOf(TexShaderVertex, "uv"), 4*4 + 4*3);
    try t.eq(@offsetOf(TexShaderVertex, "color"), 4*4 + 4*3 + 4*2);
    try t.eq(@offsetOf(TexShaderVertex, "joints"), 4*4 + 4*3 + 4*2 + 4*4);
    try t.eq(@offsetOf(TexShaderVertex, "weights"), 4*4 + 4*3 + 4*2 + 4*4 + 2*4);
}