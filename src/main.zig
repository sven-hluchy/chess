const std = @import("std");
const print = std.debug.print;

const gl = @import("zgl");
const za = @import("zalgebra");

const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const event = @import("event.zig");
const assets = @import("assets.zig");
const util = @import("util.zig");

const Mesh = @import("mesh.zig").Mesh;
const Board = @import("board.zig").Board;

fn getProcAddress(_: c.SDL_GLContext, str: [:0]const u8) ?*const anyopaque {
    return c.SDL_GL_GetProcAddress(str);
}

inline fn setUniform3f(program: gl.Program, comptime name: [:0]const u8, v: Vec3) void {
    program.uniform3f(program.uniformLocation(name), v.x(), v.y(), v.z());
}

inline fn setUniformMat4f(program: gl.Program, comptime name: [:0]const u8, m: Mat4) void {
    program.uniformMatrix4(program.uniformLocation(name), false, @ptrCast(&m.data));
}

inline fn setUniform1f(program: gl.Program, comptime name: [:0]const u8, f: f32) void {
    program.uniform1f(program.uniformLocation(name), f);
}

inline fn setUniform1i(program: gl.Program, comptime name: [:0]const u8, i: i32) void {
    program.uniform1i(program.uniformLocation(name), i);
}

fn vec3Colour(red: u8, green: u8, blue: u8) Vec3 {
    const r: f32 = @floatFromInt(red);
    const g: f32 = @floatFromInt(green);
    const b: f32 = @floatFromInt(blue);
    return Vec3.new(r / 255.0, g / 255.0, b / 255.0);
}

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) == false) {
        print("[Error] SDL_Init: {s}\n", .{c.SDL_GetError()});
    }
    defer c.SDL_Quit();

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 8);

    // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    // _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);

    const window = c.SDL_CreateWindow("title", 800, 600, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        print("[Error] SDL_CreateWindow: {s}\n", .{c.SDL_GetError()});
    }
    defer c.SDL_DestroyWindow(window);

    const ctx = c.SDL_GL_CreateContext(window);
    if (ctx == null) {
        print("[Error] SDL_GL_CreateContext: {s}\n", .{c.SDL_GetError()});
    }
    defer _ = c.SDL_GL_DestroyContext(ctx);

    try gl.loadExtensions(ctx, getProcAddress);

    _ = c.SDL_GL_MakeCurrent(window, ctx);
    gl.viewport(0, 0, 800, 600);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var mesh_data = try assets.MeshData.init(allocator);
    defer mesh_data.deinit();

    gl.enable(.depth_test);
    gl.enable(.multisample);
    gl.cullFace(.back);

    const shadow_program = try assets.loadProgram("res/shadow_vertex.glsl", "res/shadow_fragment.glsl");

    const light_pos = Vec3.new(3.0, 7.0, -2.0);
    const light_ortho = za.orthographic(-10, 10, -10, 10, 1, 20.0);
    const light_view_matrix = za.lookAt(light_pos, Vec3.new(0, 0, 0), Vec3.new(0, 1, 0));

    shadow_program.use();
    setUniformMat4f(shadow_program, "projection", light_ortho);
    setUniformMat4f(shadow_program, "view", light_view_matrix);

    var shadow_fbo = gl.Framebuffer.create();
    defer shadow_fbo.delete();

    const shadow_width = 1024;
    const shadow_height = 1024;
    var depth_tex = gl.Texture.create(.@"2d");
    defer depth_tex.delete();
    depth_tex.bind(.@"2d");
    gl.textureImage2D(.@"2d", 0, .depth_component, shadow_width, shadow_height, .depth_component, .float, null);
    depth_tex.parameter(.min_filter, .linear);
    depth_tex.parameter(.mag_filter, .linear);
    depth_tex.parameter(.wrap_s, .clamp_to_border);
    depth_tex.parameter(.wrap_t, .clamp_to_border);

    gl.bindFramebuffer(shadow_fbo, .buffer);
    gl.framebufferTexture2D(shadow_fbo, .buffer, .depth, .@"2d", depth_tex, 0);
    gl.drawBuffer(.none);
    gl.readBuffer(.none);
    gl.bindFramebuffer(.invalid, .buffer);

    if (gl.checkFramebufferStatus(.buffer) != .complete) {
        print(":(\n", .{});
    }

    // var debug = try assets.loadProgram("res/debug_vs.glsl", "res/debug_fs.glsl");
    // debug.use();
    // setUniform1i(debug, "shadowMap", 0);

    var board = try Board.init(allocator);
    var input_events = event.InputEventBuffer.init(allocator);
    var camera_orientation = Vec3.new(10.0, std.math.pi, 1);    // radius, yaw, pitch
    var view_matrix = util.rebuildViewMatrix(camera_orientation);

    var program = try assets.loadProgram("res/phong_vertex.glsl", "res/phong_fragment.glsl");
    program.use();
    setUniformMat4f(program, "lightProjMatrix", light_ortho);
    setUniformMat4f(program, "lightViewMatrix", light_view_matrix);
    setUniform3f(program, "uLightPos", light_pos);
    setUniformMat4f(program, "viewMatrix", view_matrix);
    setUniform1i(program, "shadowMap", 0);

    try mesh_data.add(.pawn, "res/pawn.obj");
    try mesh_data.add(.knight, "res/knight.obj");
    try mesh_data.add(.bishop, "res/bishop.obj");
    try mesh_data.add(.rook, "res/rook.obj");
    try mesh_data.add(.queen, "res/queen.obj");
    try mesh_data.add(.king, "res/king.obj");
    try mesh_data.add(.tile, "res/tile.obj");

    {
        loop: while (true) {
            var e: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&e)) {
                switch (e.type) {
                    c.SDL_EVENT_QUIT => break :loop,
                    c.SDL_EVENT_WINDOW_RESIZED => {
                        try input_events.window_resized.append(.{
                            .width = @intCast(e.window.data1),
                            .height = @intCast(e.window.data2),
                        });
                        gl.viewport(0, 0, @intCast(e.window.data1), @intCast(e.window.data2));
                    },
                    c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
                        if (e.button.button == c.SDL_BUTTON_LEFT or e.button.button == c.SDL_BUTTON_RIGHT) {
                            try input_events.mouse_down.append(.{
                                .x = e.button.x,
                                .y = e.button.y,
                                .button = switch (e.button.button) {
                                    c.SDL_BUTTON_LEFT => .left,
                                    c.SDL_BUTTON_RIGHT => .right,
                                    else => unreachable,
                                },
                                .state = switch (e.button.down) {
                                    true => .down,
                                    false => .up,
                                }
                            });
                        }
                    },
                    c.SDL_EVENT_KEY_DOWN => {
                        try input_events.key_down.append(e.key.scancode);
                    },
                    c.SDL_EVENT_MOUSE_MOTION => {
                        try input_events.mouse_motion.append(.{
                            .x = e.motion.x,
                            .y = e.motion.y,
                            .xrel = e.motion.xrel,
                            .yrel = e.motion.yrel,
                        });
                    },
                    c.SDL_EVENT_MOUSE_WHEEL => {
                        try input_events.mouse_wheel.append(-e.wheel.y);
                    },
                    else => {},
                }
            }

            const aspect_ratio = input_events.getAspectRatio();
            const projection_matrix = za.perspective(70.0, aspect_ratio, 0.1, 1000.0);
            setUniformMat4f(program, "projectionMatrix", projection_matrix);

            input_events.update(&view_matrix, &projection_matrix, &board, &camera_orientation);
            setUniformMat4f(program, "viewMatrix", view_matrix);

            gl.uniform2ui(program.uniformLocation("highlighted"), @intCast(board.highlighted & 0xffff_ffff), @intCast(board.highlighted >> 32));

            const model_matrix = Mat4.fromTranslate(Vec3.new(-3.5, 0, -3.5));
            const tile_vao = mesh_data.getVao(.tile);
            const tile_vertex_count = mesh_data.getCount(.tile);

            // render into shadow map
            gl.bindFramebuffer(shadow_fbo, .buffer);

            gl.viewport(0, 0, shadow_width, shadow_height);
            gl.clear(.{ .depth = true });
            gl.cullFace(.front);
            shadow_program.use();
            renderPieces(&board, &mesh_data, shadow_program);

            setUniformMat4f(shadow_program, "modelMatrix", model_matrix);
            gl.bindVertexArray(tile_vao);
            gl.drawArraysInstanced(.triangles, 0, tile_vertex_count, Board.width * Board.height);

            gl.bindFramebuffer(.invalid, .buffer);

            // debug render
            // gl.viewport(0, 0, input_events.window_width, input_events.window_height);
            // gl.clear(.{ .color = true, .depth = true});
            // debug.use();
            // gl.activeTexture(.texture_0);
            // gl.bindTexture(depth_tex, .@"2d");
            // renderQuad(quadVao);

            // render normal scene
            gl.viewport(0, 0, input_events.window_width, input_events.window_height);
            gl.cullFace(.back);
            gl.clearColor(0.3, 0.3, 0.4, 1.0);
            gl.clear(.{ .color = true, .depth = true });

            gl.activeTexture(.texture_0);
            gl.bindTexture(depth_tex, .@"2d");
            program.use();
            renderPieces(&board, &mesh_data, program);

            setUniformMat4f(program, "modelMatrix", model_matrix);

            setUniform1i(program, "renderingTiles", 1);
            gl.bindVertexArray(tile_vao);
            gl.drawArraysInstanced(.triangles, 0, tile_vertex_count, Board.width * Board.height);
            setUniform1i(program, "renderingTiles", 0);

            input_events.clear();

            _ = c.SDL_GL_SwapWindow(window);
            _ = c.SDL_Delay(16);
        }
    }
}

fn getQuadVao() gl.VertexArray {
    const v = [_]f32{
        -1.0, 1.0, 0.0, 0.0, 1.0,
        -1.0, -1.0, 0.0, 0.0, 0.0,
        1.0, 1.0, 0.0, 1.0, 1.0,
        1.0, -1.0, 0.0, 1.0, 0.0
    };
    const vao = gl.VertexArray.create();
    vao.bind();

    const vbo = gl.Buffer.create();
    vbo.bind(.array_buffer);
    vbo.data(f32, &v, .static_draw);
    vao.enableVertexAttribute(0);
    gl.vertexAttribPointer(0, 3, .float, false, 5 * @sizeOf(f32), 0);
    vao.enableVertexAttribute(1);
    gl.vertexAttribPointer(1, 2, .float, false, 5 * @sizeOf(f32), 3 * @sizeOf(f32));
    return vao;
}

fn renderQuad(vao: gl.VertexArray) void {
    gl.bindVertexArray(vao);
    gl.drawArrays(.triangle_strip, 0, 4);
    gl.bindVertexArray(.invalid);
}

fn renderPieces(board: *Board, mesh_data: *assets.MeshData, program: gl.Program) void {
    for (0..board.entryCount()) |index| {
        if (board.isAlive(index) == false) { // not very DoD :(
            continue;
        }

        const piece = board.pieces.items[index];
        const pos = board.positions.items[index];
        const colour = board.colours.items[index];

        const asset_id = assets.AssetId.fromPiece(piece);
        const piece_vao = mesh_data.getVao(asset_id);
        const piece_vertex_count = mesh_data.getCount(asset_id);

        const x: f32 = @floatFromInt(pos.row);
        const z: f32 = @floatFromInt(pos.column);

        program.use();
        var model_matrix = Mat4.fromTranslate(Vec3.new(x - 3.5, 0, z - 3.5));
        setUniform1f(program, "white", if (colour == .white) 1.0 else 0.0);
        if (colour == .white) {
            model_matrix = model_matrix.rotate(180, Vec3.new(0, 1, 0));
        }

        setUniformMat4f(program, "modelMatrix", model_matrix);

        gl.bindVertexArray(piece_vao);
        gl.drawArrays(.triangles, 0, piece_vertex_count);
    }
}
