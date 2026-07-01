const std = @import("std");
const math = std.math;

/// An efficient 3D Vector struct.
/// Using `extern struct` guarantees standard C-ABI layout (contiguous in memory, no padding),
/// so it safely and freely casts to `[3]f32` without union boilerplate.
pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    /// Initialize a new Vec3
    pub inline fn init(x: f32, y: f32, z: f32) Self {
        return .{ .x = x, .y = y, .z = z };
    }

    pub inline fn unit_vector(v: Vec3) Vec3 {
        return v.divScalar(v.length());
    }

    pub inline fn random(rand: std.Random) Vec3 {
        return .{
            .x = rand.float(f32),
            .y = rand.float(f32),
            .z = rand.float(f32),
        };
    }

    pub inline fn random_unit_vector(rand: std.Random) Vec3 {
        while (true) {
            const p = random(rand);
            const lsq = p.lengthSq();
            if (1e-21 < lsq and lsq <= 1) {
                return p.divScalar(math.sqrt(lsq));
            }
        }
    }

    pub inline fn random_on_hemisphere(rand: std.Random, normal: Vec3) Vec3 {
        const on_unit_sphere = random_unit_vector(rand);
        if (on_unit_sphere.dot(normal) > 0) {
            return on_unit_sphere;
        } else {
            return on_unit_sphere.neg();
        }
    }

    pub inline fn near_zero(self: Vec3) bool {
        return @abs(self.x) < 1e-7 and @abs(self.y) < 1e-7 and @abs(self.z) < 1e-7;
    }

    // --- Array Access Helpers ---

    /// Cast safely to a constant array slice (useful for graphics APIs like OpenGL/Vulkan)
    pub inline fn asArray(self: *const Self) *const [3]f32 {
        return @ptrCast(self);
    }

    /// Cast safely to a mutable array (useful for index-based mutations)
    pub inline fn asArrayMut(self: *Self) *[3]f32 {
        return @ptrCast(self);
    }

    // --- SIMD Interop ---

    /// Converts to a built-in SIMD vector for fast hardware-accelerated math
    pub inline fn toSimd(self: Self) @Vector(3, f32) {
        return .{ self.x, self.y, self.z };
    }

    /// Initializes from a SIMD vector
    pub inline fn fromSimd(v: @Vector(3, f32)) Self {
        return .{ .x = v[0], .y = v[1], .z = v[2] };
    }

    // --- Vector-Vector Math Operations ---

    pub inline fn add(a: Self, b: Self) Self {
        return fromSimd(a.toSimd() + b.toSimd());
    }

    pub inline fn sub(a: Self, b: Self) Self {
        return fromSimd(a.toSimd() - b.toSimd());
    }

    pub inline fn mul(a: Self, b: Self) Self {
        return fromSimd(a.toSimd() * b.toSimd());
    }

    pub inline fn div(a: Self, b: Self) Self {
        return fromSimd(a.toSimd() / b.toSimd());
    }

    // --- Mutating Vector-Vector Math Operations ---

    pub inline fn addMut(self: *Self, b: Self) void {
        self.* = self.add(b);
    }

    pub inline fn subMut(self: *Self, b: Self) void {
        self.* = self.sub(b);
    }

    pub inline fn mulMut(self: *Self, b: Self) void {
        self.* = self.mul(b);
    }

    pub inline fn divMut(self: *Self, b: Self) void {
        self.* = self.div(b);
    }

    // --- Vector-Scalar Math Operations ---

    pub inline fn addScalar(self: Self, scalar: f32) Self {
        const s_vec: @Vector(3, f32) = @splat(scalar);
        return fromSimd(self.toSimd() + s_vec);
    }

    pub inline fn subScalar(self: Self, scalar: f32) Self {
        const s_vec: @Vector(3, f32) = @splat(scalar);
        return fromSimd(self.toSimd() - s_vec);
    }

    pub inline fn mulScalar(self: Self, scalar: f32) Self {
        const s_vec: @Vector(3, f32) = @splat(scalar);
        return fromSimd(self.toSimd() * s_vec);
    }

    pub inline fn divScalar(self: Self, scalar: f32) Self {
        const s_vec: @Vector(3, f32) = @splat(scalar);
        return fromSimd(self.toSimd() / s_vec);
    }

    // --- Mutating Vector-Scalar Math Operations ---

    pub inline fn addScalarMut(self: *Self, scalar: f32) void {
        self.* = self.addScalar(scalar);
    }

    pub inline fn subScalarMut(self: *Self, scalar: f32) void {
        self.* = self.subScalar(scalar);
    }

    pub inline fn mulScalarMut(self: *Self, scalar: f32) void {
        self.* = self.mulScalar(scalar);
    }

    pub inline fn divScalarMut(self: *Self, scalar: f32) void {
        self.* = self.divScalar(scalar);
    }

    // --- Geometric Operations ---

    pub inline fn dot(a: Self, b: Self) f32 {
        // @reduce folds the SIMD vector into a single value using addition
        return @reduce(.Add, a.toSimd() * b.toSimd());
    }

    pub inline fn cross(a: Self, b: Self) Self {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub inline fn lengthSq(self: Self) f32 {
        return self.dot(self);
    }

    pub inline fn length(self: Self) f32 {
        return @sqrt(self.lengthSq());
    }

    pub inline fn normalize(self: Self) Self {
        const len = self.length();
        if (len == 0.0) return self;
        return self.mulScalar(1.0 / len);
    }

    pub inline fn neg(self: Self) Self {
        return Vec3{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }

    pub inline fn reflect(self: Self, normal: Vec3) Self {
        // Normal is assumed to be unit length
        return self.sub(normal.mulScalar(2*dot(self, normal)));
    }

    pub inline fn refract(self: Self, normal: Vec3, etai_over_etat: f32) Self {
        const cos_theta = @min(self.neg().dot(normal), 1.0);
        const perpendicular = self.add(normal.mulScalar(cos_theta)).mulScalar(etai_over_etat);
        const parallel = normal.mulScalar(-@sqrt(@abs(1.0 - perpendicular.lengthSq())));
        return perpendicular.add(parallel);
    }
};

// --- Tests ---

test "Vec3 vector-scalar operations" {
    const v = Vec3.init(1.0, 2.0, 3.0);

    // Addition
    const v_add = v.addScalar(5.0);
    try std.testing.expectEqual(@as(f32, 6.0), v_add.x);
    try std.testing.expectEqual(@as(f32, 7.0), v_add.y);
    try std.testing.expectEqual(@as(f32, 8.0), v_add.z);

    // Subtraction
    const v_sub = v.subScalar(1.0);
    try std.testing.expectEqual(@as(f32, 0.0), v_sub.x);
    try std.testing.expectEqual(@as(f32, 1.0), v_sub.y);
    try std.testing.expectEqual(@as(f32, 2.0), v_sub.z);

    // Multiplication
    const v_mul = v.mulScalar(2.0);
    try std.testing.expectEqual(@as(f32, 2.0), v_mul.x);
    try std.testing.expectEqual(@as(f32, 4.0), v_mul.y);
    try std.testing.expectEqual(@as(f32, 6.0), v_mul.z);

    // Division
    const v_div = v.divScalar(2.0);
    try std.testing.expectEqual(@as(f32, 0.5), v_div.x);
    try std.testing.expectEqual(@as(f32, 1.0), v_div.y);
    try std.testing.expectEqual(@as(f32, 1.5), v_div.z);
}

test "Vec3 mutating vector-scalar operations" {
    var v = Vec3.init(1.0, 2.0, 3.0);

    v.addScalarMut(5.0);
    try std.testing.expectEqual(@as(f32, 6.0), v.x);
    try std.testing.expectEqual(@as(f32, 7.0), v.y);
    try std.testing.expectEqual(@as(f32, 8.0), v.z);

    v.subScalarMut(2.0);
    try std.testing.expectEqual(@as(f32, 4.0), v.x);
    try std.testing.expectEqual(@as(f32, 5.0), v.y);
    try std.testing.expectEqual(@as(f32, 6.0), v.z);

    v.mulScalarMut(2.0);
    try std.testing.expectEqual(@as(f32, 8.0), v.x);
    try std.testing.expectEqual(@as(f32, 10.0), v.y);
    try std.testing.expectEqual(@as(f32, 12.0), v.z);

    v.divScalarMut(4.0);
    try std.testing.expectEqual(@as(f32, 2.0), v.x);
    try std.testing.expectEqual(@as(f32, 2.5), v.y);
    try std.testing.expectEqual(@as(f32, 3.0), v.z);
}

test "Vec3 vector-vector operations" {
    const a = Vec3.init(1.0, 2.0, 3.0);
    const b = Vec3.init(4.0, 5.0, 6.0);

    const sum = a.add(b);
    try std.testing.expectEqual(@as(f32, 5.0), sum.x);
    try std.testing.expectEqual(@as(f32, 7.0), sum.y);
    try std.testing.expectEqual(@as(f32, 9.0), sum.z);
}
