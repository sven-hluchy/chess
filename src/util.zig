const std = @import("std");

const za = @import("zalgebra");

pub fn yPlaneIntersection(c: za.Vec3, d: za.Vec3) ?za.Vec2 {
    if (d.y() == 0) {
        return null;
    }
    const t = -c.y() / d.y();
    if (t < 0) {
        return null;
    }

    return za.Vec2.new(c.x() + d.x() * t, c.z() + d.z() * t);
}

pub inline fn clampf(v: f32, lo: f32, hi: f32) f32 {
    return if (v < lo) lo else (if (v > hi) hi else v);
}

pub fn rebuildViewMatrix(o: za.Vec3) za.Mat4 {
    const radius = o.data[0];
    const yaw = o.data[1];
    const pitch = o.data[2];

    const x = radius * @cos(pitch) * @sin(yaw);
    const y = radius * @sin(pitch);
    const z = radius * @cos(pitch) * @cos(yaw);
    const eye = za.Vec3.new(x, y, z);
    return za.lookAt(eye, za.Vec3.new(0, 0, 0), za.Vec3.up());
}
