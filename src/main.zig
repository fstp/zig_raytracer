const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const image_width = 256;
    const image_height = 256;

    try stdout_writer.print("P3\n{d} {d}\n255\n", .{image_width, image_height});

    for (0..image_height) |j| {
        for (0..image_width) |i| {
            const r = @as(f32, @floatFromInt(i)) / (image_width - 1);
            const g = @as(f32, @floatFromInt(j)) / (image_height - 1);
            const b = 0.0;

            const ir = @trunc(255.999 * r);
            const ig = @trunc(255.999 * g);
            const ib = @trunc(255.999 * b);

            try stdout_writer.print("{d} {d} {d}\n", .{ ir, ig, ib });
        }
    }

    try stdout_writer.flush();
}
