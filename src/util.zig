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
