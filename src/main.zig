const std = @import("std");
const sdl = @import("sdl.zig");

const canvas_width: i32 = 512;
const canvas_height: i32 = 512;

const view_width: i32 = 1;
const view_height: i32 = 1;

const inf: f32 = std.math.floatMax(f32);
const d: i32 = 1;

const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }
};

const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(self.x + other.x, self.y + other.y, self.z + other.z);
    }

    fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3.init(self.x - other.x, self.y - other.y, self.z - other.z);
    }

    fn scale(self: Vec3, s: f32) Vec3 {
        return Vec3.init(self.x * s, self.y * s, self.z * s);
    }

    fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    fn length(self: Vec3) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
};

const Light = struct {
    const Type = enum {
        ambient,
        directional,
        point,
    };

    type: Type = .point,
    intensity: f32 = 0.0,
    position: Vec3 = .{},
    direction: Vec3 = .{},
};

const background_color: Color = .{};

const Sphere = struct {
    center: Vec3,
    radius: f32,
    color: Color,
};

const spheres: [4]Sphere = .{
    .{ .center = Vec3.init(0, -1, 3), .radius = 1, .color = Color.init(255, 0, 0, 255) },
    .{ .center = Vec3.init(2, 0, 4), .radius = 1, .color = Color.init(0, 0, 255, 255) },
    .{ .center = Vec3.init(-2, 0, 4), .radius = 1, .color = Color.init(0, 255, 0, 255) },
    .{ .center = Vec3.init(0, -5001, 0), .radius = 5000, .color = Color.init(255, 255, 0, 255) },
};

const lights: [3]Light = .{
    .{ .type = .ambient, .intensity = 0.2 },
    .{ .type = .point, .intensity = 0.6, .position = Vec3.init(2, 1, 0) },
    .{ .type = .directional, .intensity = 0.2, .direction = Vec3.init(1, 4, 4) },
};

pub fn main() !void {
    const format = sdl.SDL_PIXELFORMAT_RGB888;
    var bpp: i32 = 0;
    var rmask: u32 = 0;
    var gmask: u32 = 0;
    var bmask: u32 = 0;
    var amask: u32 = 0;
    _ = sdl.SDL_PixelFormatEnumToMasks(format, &bpp, &rmask, &gmask, &bmask, &amask);
    const surface = sdl.SDL_CreateRGBSurfaceWithFormat(0, canvas_width, canvas_height, bpp, format);

    const origin: Vec3 = .{};
    var x: i32 = -canvas_width / 2;
    while (x < (canvas_width / 2)) : (x += 1) {
        var y: i32 = -canvas_height / 2;
        while (y < (canvas_height / 2)) : (y += 1) {
            const pos = canvasToViewport(x, y);
            const color = traceRay(origin, pos, 1, inf);
            putColor(surface, x, y, color);
        }
    }

    _ = sdl.IMG_SavePNG(surface, "image.png");
}

pub fn canvasToViewport(x: i32, y: i32) Vec3 {
    const x_float: f32 = @floatFromInt(x);
    const y_float: f32 = @floatFromInt(y);
    const vw: f32 = @floatFromInt(view_width);
    const vh: f32 = @floatFromInt(view_height);
    const cw: f32 = @floatFromInt(canvas_width);
    const ch: f32 = @floatFromInt(canvas_height);
    return Vec3{ .x = x_float * vw / cw, .y = y_float * vh / ch, .z = d };
}

fn clampColor(value: f32) u8 {
    return @intFromFloat(@min(255, @max(0, value)));
}

pub fn traceRay(origin: Vec3, direction: Vec3, tmin: f32, tmax: f32) Color {
    var closest_t = inf;
    var closest_sphere: ?*const Sphere = null;
    for (&spheres) |*sphere| {
        const hit = intersectRaySphere(origin, direction, sphere);
        if (hit.t1 > tmin and hit.t1 < tmax and hit.t1 < closest_t) {
            closest_t = hit.t1;
            closest_sphere = sphere;
        }
        if (hit.t2 > tmin and hit.t2 < tmax and hit.t2 < closest_t) {
            closest_t = hit.t2;
            closest_sphere = sphere;
        }
    }

    if (closest_sphere) |cs| {
        const P = origin.add(direction.scale(closest_t));
        var N = P.sub(cs.center);
        N = N.scale(1 / N.length());
        const intensity = computeLighting(P, N);

        const r = clampColor(@as(f32, @floatFromInt(cs.color.r)) * intensity);
        const g = clampColor(@as(f32, @floatFromInt(cs.color.g)) * intensity);
        const b = clampColor(@as(f32, @floatFromInt(cs.color.b)) * intensity);
        const a: u8 = cs.color.a;
        return Color.init(r, g, b, a);
    }

    return background_color;
}

const HitResult = struct {
    t1: f32,
    t2: f32,
};

pub fn intersectRaySphere(origin: Vec3, direction: Vec3, sphere: *const Sphere) HitResult {
    const r = sphere.*.radius;
    const co = origin.sub(sphere.*.center);

    const a = direction.dot(direction);
    const b = 2 * co.dot(direction);
    const c = co.dot(co) - r * r;

    const discriminant: f32 = b * b - 4 * a * c;
    if (discriminant < 0) {
        return .{ .t1 = inf, .t2 = inf };
    }

    return .{
        .t1 = -b + @sqrt(discriminant) / (2 * a),
        .t2 = -b - @sqrt(discriminant) / (2 * a),
    };
}

pub fn computeLighting(pos: Vec3, normal: Vec3) f32 {
    var i: f32 = 0.0;

    for (lights) |light| {
        switch (light.type) {
            .ambient => i += light.intensity,
            else => {
                const L = if (light.type == .point) light.position.sub(pos) else light.direction;
                const n_dot_l = normal.dot(L);
                if (n_dot_l > 0) {
                    i += light.intensity * n_dot_l / (normal.length() * L.length());
                }
            },
        }
    }

    return i;
}

pub fn putColor(surface: *sdl.SDL_Surface, x: i32, y: i32, color: Color) void {
    const sx: i32 = canvas_width / 2 + x;
    const sy: i32 = canvas_height / 2 - y;
    const index: usize = @intCast(sy * canvas_width + sx);
    var pixels: [*]u32 = @ptrCast(@alignCast(surface.pixels));
    pixels[index] = sdl.SDL_MapRGB(surface.format, color.r, color.g, color.b);
}
