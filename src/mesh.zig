const std = @import("std");
const gl = @import("zgl");

const Vector3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Mesh = struct {
    vertices: std.ArrayList(f32),
    normals: std.ArrayList(f32),
    indices: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const reader = file.reader();

        var buffer: [64]u8 = undefined;

        var verticesRaw = std.ArrayList(Vector3).init(allocator);
        defer verticesRaw.deinit();

        var normalsRaw = std.ArrayList(Vector3).init(allocator);
        defer normalsRaw.deinit();

        var vertices = std.ArrayList(f32).init(allocator);
        var normals = std.ArrayList(f32).init(allocator);
        var indices = std.ArrayList(usize).init(allocator);

        while (true) {
            const line = reader.readUntilDelimiter(&buffer, '\n') catch |err| {
                if (err == error.EndOfStream) break else return err;
            };

            if (line[0] == '#' or line[0] == 'o') {
                continue;
            } else if (line[0] == 's') {
                vertices = try std.ArrayList(f32).initCapacity(allocator, verticesRaw.items.len * 3);
                normals = try std.ArrayList(f32).initCapacity(allocator, verticesRaw.items.len * 3);
                indices = try std.ArrayList(usize).initCapacity(allocator, verticesRaw.items.len);
                continue;
            }

            var parts = std.mem.splitSequence(u8, line, " ");
            const prefix = parts.next().?;
            if (std.mem.eql(u8, prefix, "v")) {
                const strs: [3][]const u8 = .{ parts.next().?, parts.next().?, parts.next().? };
                try verticesRaw.append(.{
                    .x = std.fmt.parseFloat(f32, strs[0]) catch unreachable,
                    .y = std.fmt.parseFloat(f32, strs[1]) catch unreachable,
                    .z = std.fmt.parseFloat(f32, strs[2]) catch unreachable,
                });
            } else if (std.mem.eql(u8, prefix, "vn")) {
                const strs: [3][]const u8 = .{ parts.next().?, parts.next().?, parts.next().? };
                try normalsRaw.append(.{
                    .x = std.fmt.parseFloat(f32, strs[0]) catch unreachable,
                    .y = std.fmt.parseFloat(f32, strs[1]) catch unreachable,
                    .z = std.fmt.parseFloat(f32, strs[2]) catch unreachable,
                });
            } else if (std.mem.eql(u8, prefix, "f")) {
                while (parts.next()) |next| {
                    var items = std.mem.splitSequence(u8, next, "//");
                    const vertexIndex = (std.fmt.parseInt(usize, items.next().?, 10) catch unreachable) - 1;
                    const normalIndex = (std.fmt.parseInt(usize, items.next().?, 10) catch unreachable) - 1;

                    try vertices.append(verticesRaw.items[vertexIndex].x);
                    try vertices.append(verticesRaw.items[vertexIndex].y);
                    try vertices.append(verticesRaw.items[vertexIndex].z);

                    try normals.append(normalsRaw.items[normalIndex].x);
                    try normals.append(normalsRaw.items[normalIndex].y);
                    try normals.append(normalsRaw.items[normalIndex].z);

                    try indices.append(vertexIndex);
                }
            }
        }

        return .{
            .vertices = vertices,
            .normals = normals,
            .indices = indices,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.normals);
        self.indices.deinit();
    }
};
