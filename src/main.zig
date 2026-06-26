const vec = @import("vec");
const std = @import("std");
const math = std.math;

const Io = std.Io;
const Vec3 = vec.Vec3;

// # Image
// Params
const aspect_ratio: f32 = 16.0 / 9.0;
const image_width: u32 = 600;
// Constants
const image_height: u32 = @max(1, @as(u32, @trunc(@as(f32, image_width) / aspect_ratio)));
// #

// # Quality
// Params
const samples_per_pixel: u32 = 100;
const max_bounces: u32 = 50;
// Constants
const pixel_samples_scale: f32 = 1.0 / @as(f32, @floatFromInt(samples_per_pixel));
// #

// # Camera
// Params
const camera_center = Vec3.init(0.0, 0, 0.3);
const focal_length = 1.0;
// #

// # Viewport
// Params
const viewport_height = 2.0;
// Constants
const viewport_width = viewport_height * (@as(f32, image_width) / image_height);

const viewport_u = Vec3.init(viewport_width, 0, 0);
const viewport_v = Vec3.init(0, -viewport_height, 0);

const pixel_delta_u = viewport_u.divScalar(image_width);
const pixel_delta_v = viewport_v.divScalar(image_height);

const viewport_upper_left =
    camera_center
        .sub(Vec3.init(0, 0, focal_length))
        .sub(viewport_u.divScalar(2))
        .sub(viewport_v.divScalar(2));

const pixel00_loc =
    viewport_upper_left
        .add(pixel_delta_u.add(pixel_delta_v).mulScalar(0.5));
// #

const Ray = struct {
    origin: Vec3,
    dir: Vec3,

    pub inline fn at(self: Ray, t: f32) Vec3 {
        return self.origin.add(self.dir.mulScalar(t));
    }
};

const Interval = struct {
    min: f32,
    max: f32,

    pub inline fn init(min: f32, max: f32) Interval {
        return .{ .min = min, .max = max };
    }
    pub inline fn empty() Interval {
        return .{ .min = math.floatMax(f32), .max = -math.floatMax(f32) };
    }
    pub inline fn all() Interval {
        return .{ .min = -math.floatMax(f32), .max = math.floatMax(f32) };
    }

    pub inline fn size(self: Interval) f32 {
        return self.max - self.min;
    }
    pub inline fn contains(self: Interval, point: f32) bool {
        return self.min <= point and point <= self.max;
    }
    pub inline fn surrounds(self: Interval, point: f32) bool {
        return self.min < point and point < self.max;
    }
};

/// A simple RGB color.
/// Using `extern union` guarantees standard C-ABI layout and it contains
/// a Vec3 (v) field that is shared in memory with the channels to permit
/// vector operations as well as easy access of r,g,b values without any
/// overhead.
const Color = extern union {
    v: Vec3,
    channels: extern struct {
        r: f32,
        g: f32,
        b: f32,
    },

    pub inline fn init(r: f32, g: f32, b: f32) Color {
        return .{ .channels = .{ .r = r, .g = g, .b = b } };
    }

    pub inline fn from_vec(v: Vec3) Color {
        return .{ .v = v };
    }

    pub inline fn add(self: Color, c: Color) Color {
        return .{ .v = self.v.add(c.v) };
    }
};

const HitRecord = struct {
    p: Vec3,
    normal: Vec3,
    t: f32,
    front_face: bool,
    material: Material,

    pub inline fn init(t: f32, p: Vec3, normal: Vec3, ray: Ray, material: Material) HitRecord {
        // NOTE: Outward normal is assumed to have unit length.
        const front_face = ray.dir.dot(normal) < 0;

        return HitRecord{
            .t = t,
            .p = p,
            .normal = if (front_face) normal else normal.neg(),
            .front_face = front_face,
            .material = material,
        };
    }

    pub inline fn debug_print(self: HitRecord) void {
        std.debug.print(
            "p.x={d}, p.y={d}, p.z={d}, n.x={d}, n.y={d}, n.z={d}, front_face={}\n",
            .{ self.p.x, self.p.y, self.p.z, self.normal.x, self.normal.y, self.normal.z, self.front_face },
        );
    }
};

const Sphere = struct {
    center: Vec3,
    radius: f32,
    material: Material,

    pub fn hit(self: Sphere, ray: Ray, interval: Interval) ?HitRecord {
        const oc = self.center.sub(ray.origin);
        const a = ray.dir.lengthSq();
        const h = ray.dir.dot(oc);
        const c = oc.lengthSq() - self.radius * self.radius;
        const discriminant = h * h - a * c;

        if (discriminant < 0)
            return null;

        const sqrtd = @sqrt(discriminant);

        var root = (h - sqrtd) / a;
        if (!interval.surrounds(root)) {
            // Maybe the other root is within limits
            root = (h + sqrtd) / a;
            if (!interval.surrounds(root)) {
                // Nope, no intersection
                return null;
            }
        }

        const p = ray.at(root);
        const normal = p.sub(self.center).divScalar(self.radius);

        return HitRecord.init(root, p, normal, ray, self.material);
    }
};

const Lambertian = struct {
    albedo: Vec3,
};

const Metal = struct {
    albedo: Vec3,
    fuzz: f32,
};

const ScatterResult = struct {
    attenuation: Vec3,
    scattered: Ray,
};

const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,

    pub fn scatter(self: Material, rand: std.Random, ray: Ray, hr: HitRecord) ?ScatterResult {
        switch (self) {
            .lambertian => |l| {
                var scatter_dir = hr.normal.add(Vec3.random_unit_vector(rand));
                if (scatter_dir.near_zero()) {
                    scatter_dir = hr.normal;
                }
                return ScatterResult{
                    .attenuation = l.albedo,
                    .scattered = Ray{
                        .origin = hr.p,
                        .dir = scatter_dir,
                    },
                };
            },
            .metal => |m| {
                const reflected = ray.dir.reflect(hr.normal);
                const fuzz_sphere = Vec3.random_unit_vector(rand).mulScalar(@min(m.fuzz, 1.0));
                const scatter_dir = reflected.add(fuzz_sphere);
                if (scatter_dir.dot(hr.normal) > 0) {
                    return ScatterResult{
                        .attenuation = m.albedo,
                        .scattered = Ray{
                            .origin = hr.p,
                            .dir = scatter_dir,
                        },
                    };
                } else {
                    // Reflection absorbed (scattered inside the material)
                    return null;
                }
            },
        }
    }
};

inline fn rgb_to_albedo(comptime r: f32, comptime g: f32, comptime b: f32) Vec3 {
    const r_norm = r / 255.0;
    const g_norm = g / 255.0;
    const b_norm = b / 255.0;

    return Vec3.init(r_norm * r_norm, g_norm * g_norm, b_norm * b_norm);
}

fn ray_color(rand: std.Random, ray: Ray, bounce: u32) Color {
    if (bounce > max_bounces) {
        return Color.init(0, 0, 0);
    }

    const spheres = [_]Sphere{
        .{
            // Center
            .center = Vec3.init(0, 0, -1.2),
            .radius = 0.5,
            .material = .{
                .lambertian = .{
                    .albedo = Vec3.init(0.1, 0.2, 0.5),
                },
            },
        },
        .{
            // Left
            .center = Vec3.init(-1.0, 0, -1.0),
            .radius = 0.5,
            .material = .{
                .metal = .{
                    .albedo = Vec3.init(0.8, 0.8, 0.8),
                    .fuzz = 0.3,
                },
            },
        },
        .{
            // Right
            .center = Vec3.init(1.0, 0, -1.0),
            .radius = 0.5,
            .material = .{
                .metal = .{
                    .albedo = Vec3.init(0.8, 0.6, 0.2),
                    .fuzz = 1.0,
                },
            },
        },
        .{
            // Ground
            .center = Vec3.init(0, -100.5, -1),
            .radius = 100,
            .material = .{
                .lambertian = .{
                    .albedo = Vec3.init(0.8, 0.8, 0.0),
                },
            },
        },
    };

    var hit_record: ?HitRecord = null;
    var interval = Interval.init(0.001, math.inf(f32));

    // TODO: Only checking spheres for now
    for (spheres) |s| {
        if (s.hit(ray, interval)) |hr| {
            interval.max = hr.t;
            hit_record = hr;
        }
    }

    if (hit_record) |hr| {
        if (hr.material.scatter(rand, ray, hr)) |result| {
            const final_vec = ray_color(rand, result.scattered, bounce + 1).v.mul(result.attenuation);
            return Color.from_vec(final_vec);
        } else {
            // Ray fully absorbed
            return Color.init(0, 0, 0);
        }
    }

    // Sky - lerp between white and blue depending on y-direction
    const unit_direction = Vec3.unit_vector(ray.dir);
    const a = 0.5 * (unit_direction.y + 1.0);
    const c1 = Color.init(1.0, 1.0, 1.0).v.mulScalar(1.0 - a);
    const c2 = Color.init(0.5, 0.7, 1.0).v.mulScalar(a);

    return Color.from_vec(c1.add(c2));
}

inline fn linear_to_gamma(linear_component: f32) f32 {
    if (linear_component > 0) {
        return math.sqrt(linear_component);
    } else {
        return 0;
    }
}

inline fn write_color(writer: *Io.Writer, color: Color) !void {
    const r = linear_to_gamma(color.channels.r);
    const g = linear_to_gamma(color.channels.g);
    const b = linear_to_gamma(color.channels.b);
    const ir = @trunc(256 * math.clamp(r, 0, 0.999));
    const ig = @trunc(256 * math.clamp(g, 0, 0.999));
    const ib = @trunc(256 * math.clamp(b, 0, 0.999));
    try writer.print("{d} {d} {d}\n", .{ ir, ig, ib });
}

fn render_row(
    timestamp: u64, // For random
    j: usize, // The current row (y-coordinate)
    framebuffer: []Color, // Shared memory buffer
) void {
    var prng = std.Random.DefaultPrng.init(timestamp + j);
    const rand = prng.random();

    for (0..image_width) |i| {
        var pixel_color = Color.init(0, 0, 0);

        for (0..samples_per_pixel) |_| {
            const offset = Vec3.init(
                std.Random.float(rand, f32) - 0.5,
                std.Random.float(rand, f32) - 0.5,
                0,
            );

            const offset_i: f32 = @floatFromInt(i);
            const offset_j: f32 = @floatFromInt(j);

            const pixel_sample = pixel00_loc
                .add(pixel_delta_u.mulScalar(offset_i + offset.x))
                .add(pixel_delta_v.mulScalar(offset_j + offset.y));

            const ray_direction = pixel_sample.sub(camera_center);
            const r = Ray{ .origin = camera_center, .dir = ray_direction };

            pixel_color = pixel_color.add(ray_color(rand, r, 0));
        }

        pixel_color.v.mulScalarMut(pixel_samples_scale);
        framebuffer[j * image_width + i] = pixel_color;
    }
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var allocator = std.heap.page_allocator;
    const framebuffer = try allocator.alloc(Color, image_width * image_height);
    defer allocator.free(framebuffer);

    var group: std.Io.Group = .init;
    defer group.cancel(init.io);

    for (0..image_height) |j| {
        const timestamp: u64 = @intCast(Io.Clock.real.now(init.io).nanoseconds);
        group.async(init.io, render_row, .{ timestamp, j, framebuffer });
    }

    group.await(init.io) catch {};

    try stdout_writer.print("P3\n{d} {d}\n255\n", .{ image_width, image_height });

    for (framebuffer) |pixel| {
        try write_color(stdout_writer, pixel);
    }

    try stdout_writer.flush();
}
