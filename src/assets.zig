const std = @import("std");
const gl = @import("zgl");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

const Mesh = @import("mesh.zig").Mesh;
const Piece = @import("board.zig").Piece;

pub const AssetId = enum {
    pawn,
    bishop,
    knight,
    rook,
    queen,
    king,
    tile,

    pub fn fromPiece(p: Piece) AssetId {
        return switch (p) {
            .pawn => .pawn,
            .bishop => .bishop,
            .knight => .knight,
            .rook => .rook,
            .queen => .queen,
            .king => .king,
        };
    }
};

pub const MeshData = struct {
    vaos: []gl.VertexArray,
    position_vbos: []gl.Buffer,
    normal_vbos: []gl.Buffer,
    ebos: []gl.Buffer,
    index_counts: []usize,
    mesh_count: usize,

    lookup: std.AutoHashMap(AssetId, usize),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const N = 10;
        return .{
            .vaos = try allocator.alloc(gl.VertexArray, N),
            .position_vbos = try allocator.alloc(gl.Buffer, N),
            .normal_vbos = try allocator.alloc(gl.Buffer, N),
            .ebos = try allocator.alloc(gl.Buffer, N),
            .index_counts = try allocator.alloc(usize, N),
            .mesh_count = 0,

            .lookup = std.AutoHashMap(AssetId, usize).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn add(self: *Self, id: AssetId, comptime path: []const u8) !void {
        const mesh = try Mesh.load(self.allocator, path);

        var vao = gl.VertexArray.create();
        vao.bind();

        var vbo_pos = gl.Buffer.create();
        vbo_pos.bind(.array_buffer);
        vbo_pos.data(f32, mesh.vertices.items, .static_draw);
        vao.enableVertexAttribute(0);
        gl.vertexAttribPointer(0, 3, .float, false, 0, 0);

        var vbo_norm = gl.Buffer.create();
        vbo_norm.bind(.array_buffer);
        vbo_norm.data(f32, mesh.normals.items, .static_draw);
        vao.enableVertexAttribute(1);
        gl.vertexAttribPointer(1, 3, .float, false, 0, 0);

        var ebo = gl.Buffer.create();
        ebo.bind(.element_array_buffer);
        ebo.data(usize, mesh.indices.items, .static_draw);

        const index_count = mesh.indices.items.len;

        const i = self.mesh_count;
        self.vaos[i] = vao;
        self.position_vbos[i] = vbo_pos;
        self.normal_vbos[i] = vbo_norm;
        self.ebos[i] = ebo;
        self.index_counts[i] = index_count;

        try self.lookup.put(id, self.mesh_count);
        self.mesh_count += 1;
    }

    pub fn getCount(self: *const Self, id: AssetId) usize {
        return self.index_counts[self.lookup.get(id).?];
    }

    pub fn getVao(self: *const Self, id: AssetId) gl.VertexArray {
        return self.vaos[self.lookup.get(id).?];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.vaos);
        self.allocator.free(self.position_vbos);
        self.allocator.free(self.normal_vbos);
        self.allocator.free(self.ebos);
        self.allocator.free(self.index_counts);
    }
};

pub fn loadShader(path: []const u8, shaderType: gl.ShaderType) !gl.Shader {
    const allocator = std.heap.page_allocator;
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 2048);

    var shader = gl.Shader.create(shaderType);
    shader.source(1, &[1][]const u8{source});
    shader.compile();

    if (shader.get(.compile_status) == 0) {
        const compileLog = shader.getCompileLog(std.heap.page_allocator);
        std.log.err("Error while compiling shader: {!s}\n", .{compileLog});
        return error.shaderCompileError;
    }

    return shader;
}

pub fn loadProgram(vs_path: []const u8, fs_path: []const u8) !gl.Program {
    var program = gl.Program.create();
    const vs = try loadShader(vs_path, .vertex);
    const fs = try loadShader(fs_path, .fragment);
    program.attach(vs);
    program.attach(fs);
    program.link();
    if (program.get(.link_status) == 0) {
        const compileLog = program.getCompileLog(std.heap.page_allocator);
        std.log.err("Error linking program: {!s}\n", .{compileLog});
        return error.programLinkingError;
    }

    return program;
}
