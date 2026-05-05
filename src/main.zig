const vec = @import("vec");
const std = @import("std");

const Io = std.Io;
const Vec3 = vec.Vec3;

const Ray = struct {
    origin: Vec3,
    dir: Vec3,
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

    pub fn init(r: f32, g: f32, b: f32) Color {
        return .{ .channels = .{ .r = r, .g = g, .b = b } };
    }

    pub fn from_vec(v: Vec3) Color {
        return .{ .v = v };
    }
};

fn hit_sphere(center: Vec3, radius: f32, ray: Ray) bool {
    const oc = center.sub(ray.origin);
    const a = Vec3.dot(ray.dir, ray.dir);
    const b = -2.0 * Vec3.dot(ray.dir, oc);
    const c = Vec3.dot(oc, oc) - radius * radius;
    const discriminant = b * b - 4 * a * c;
    // Discriminant -> 0  => No roots, no intersection
    //              -> 1  => Exactly one intersection
    //              -> >1 => One or more intersections (passing through the sphere)
    return (discriminant >= 0);
}

fn ray_color(ray: Ray) Color {
    // Sphere - Always red
    if (hit_sphere(Vec3.init(0, 0, -1), 0.5, ray))
        return Color.init(1, 0, 0);

    // Sky - lerp between white and blue depending on y-direction
    const unit_direction = Vec3.unit_vector(ray.dir);
    const a = 0.5 * (unit_direction.y + 1.0);
    const c1 = Color.init(1.0, 1.0, 1.0).v.mulScalar(1.0 - a);
    const c2 = Color.init(0.5, 0.7, 1.0).v.mulScalar(a);
    return Color.from_vec(c1.add(c2));
}

fn write_color(writer: *Io.Writer, color: Color) !void {
    const ir = @trunc(255.999 * color.channels.r);
    const ig = @trunc(255.999 * color.channels.g);
    const ib = @trunc(255.999 * color.channels.b);
    try writer.print("{d} {d} {d}\n", .{ ir, ig, ib });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    // Image
    const aspect_ratio = 16.0 / 9.0;
    const image_width = 400;
    const image_height = @max(1, @as(u32, @trunc(@as(f32, image_width) / aspect_ratio)));

    // Camera
    const focal_length = 1.0;
    const camera_center = Vec3.init(0, 0, 0);

    // Viewport
    const viewport_height = 2.0;
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

    var pixel00_loc =
        viewport_upper_left
            .add(pixel_delta_u.add(pixel_delta_v).mulScalar(0.5));

    // Header
    try stdout_writer.print("P3\n{d} {d}\n255\n", .{ image_width, image_height });

    // Image
    for (0..image_height) |j| {
        // std.debug.print("\rScanlines remaining: {d}\n", .{(image_height - j)});
        for (0..image_width) |i| {
            const pixel_center =
                pixel00_loc
                    .add(pixel_delta_u.mulScalar(@floatFromInt(i)))
                    .add(pixel_delta_v.mulScalar(@floatFromInt(j)));

            const ray: Ray = .{
                .origin = camera_center,
                .dir = pixel_center.sub(camera_center),
            };

            const color = ray_color(ray);

            try write_color(stdout_writer, color);
        }
    }

    try stdout_writer.flush();
}
