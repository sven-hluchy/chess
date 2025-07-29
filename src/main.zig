const std = @import("std");
const print = std.debug.print;

const gl = @import("zgl");
const za = @import("zalgebra");

const Vec3 = za.Vec3;
const Mat4 = za.Mat4;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

const event = @import("event.zig");
const assets = @import("assets.zig");

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

    if (c.TTF_Init() == false) {
        print("[Error] TTF_Init: {s}\n", .{c.SDL_GetError()});
    }
    defer c.TTF_Quit();

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 8);

    const white_colour = vec3Colour(235, 217, 179);
    const black_colour = vec3Colour(129, 84, 56);
    const selection_colour = vec3Colour(19, 196, 163);

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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var mesh_data = try assets.MeshData.init(allocator);
    defer mesh_data.deinit();

    gl.enable(.depth_test);
    gl.enable(.blend);
    gl.enable(.multisample);
    gl.cullFace(.back);

    var board = try Board.init(allocator);
    var program = try assets.loadProgram("res/phong_vertex.glsl", "res/phong_fragment.glsl");

    try mesh_data.add(.pawn, "res/pawn.obj");
    try mesh_data.add(.knight, "res/knight.obj");
    try mesh_data.add(.bishop, "res/bishop.obj");
    try mesh_data.add(.rook, "res/rook.obj");
    try mesh_data.add(.queen, "res/queen.obj");
    try mesh_data.add(.king, "res/king.obj");
    try mesh_data.add(.tile, "res/tile.obj");

    var input_events = event.InputEventBuffer.init(allocator);

    const light_pos = Vec3.new(5.0, 5.0, 0.0);
    // TODO: add shadows
    // const light_view_matrix = za.lookAt(light_pos, Vec3.new(0, 0, 0), Vec3.new(0, 1, 0));

    var view_matrix = za.lookAt(Vec3.new(0, 10, -8), Vec3.new(0, 0, 0), Vec3.new(0, 1, 0));

    program.use();

    setUniform3f(program, "uLightPos", light_pos);
    setUniform3f(program, "whiteColour", white_colour);
    setUniform3f(program, "blackColour", black_colour);
    setUniform3f(program, "selectionColour", selection_colour);

    setUniformMat4f(program, "viewMatrix", view_matrix);

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
                    else => {},
                }
            }

            const aspect_ratio = input_events.getAspectRatio();
            const projection_matrix = za.perspective(70.0, aspect_ratio, 0.1, 1000.0);
            setUniformMat4f(program, "projectionMatrix", projection_matrix);

            input_events.update(&view_matrix, &projection_matrix, &board);
            setUniformMat4f(program, "viewMatrix", view_matrix);

            gl.clearColor(0.3, 0.3, 0.4, 1.0);
            gl.clear(.{ .color = true, .depth = true});

            for (0..board.entryCount()) |index| {
                if (board.isAlive(index) == false) { // not very DoD :(
                    continue;
                }
                const pos = board.positions.items[index];
                const piece = board.pieces.items[index];
                const colour = board.colours.items[index];

                const asset_id = assets.AssetId.fromPiece(piece);
                const piece_vao = mesh_data.getVao(asset_id);
                const piece_vertex_count = mesh_data.getCount(asset_id);

                const x = @as(f32, @floatFromInt(pos.row)) - 3.5;
                const z = @as(f32, @floatFromInt(pos.column)) - 3.5;

                var model_matrix = Mat4.fromTranslate(Vec3.new(x, 0, z));
                if (colour == .black) {
                    setUniform3f(program, "objectColour", black_colour);
                } else if (colour == .white) {
                    setUniform3f(program, "objectColour", white_colour);
                    model_matrix = model_matrix.rotate(180, Vec3.new(0, 1, 0));
                }
                setUniformMat4f(program, "modelMatrix", model_matrix);

                program.use();

                gl.bindVertexArray(piece_vao);
                gl.drawArrays(.triangles, 0, piece_vertex_count);
            }

            gl.uniform1iv(program.uniformLocation("highlighted"), board.highlighted);
            setUniform1i(program, "renderingTiles", 1);

            const tile_vao = mesh_data.getVao(.tile);
            const tile_vertex_count = mesh_data.getCount(.tile);

            const model_matrix = Mat4.fromTranslate(Vec3.new(-3.5, 0, -3.5));
            setUniformMat4f(program, "modelMatrix", model_matrix);
            setUniform3f(program, "objectColour", white_colour);

            gl.bindVertexArray(tile_vao);
            gl.drawArraysInstanced(.triangles, 0, tile_vertex_count, Board.width * Board.height);

            setUniform1i(program, "renderingTiles", 0);

            _ = c.SDL_GL_SwapWindow(window);

            input_events.clear();
            _ = c.SDL_Delay(16);
        }
    }
}
