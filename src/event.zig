const std = @import("std");
const print = std.debug.print;

const gl = @import("zgl");
const za = @import("zalgebra");

const Vec3 = za.Vec3;

const util = @import("util.zig");

const Board = @import("board.zig").Board;

pub const InputEventBuffer = struct {
    const MousePress = struct {
        x: f32,
        y: f32,
        state: MouseButtonState,
        button: MouseButton,
    };

    const MouseButton = enum {
        left,
        right,
    };

    const MouseButtonState = enum {
        down,
        up,
    };

    const MouseMotion = struct {
        x: f32,
        y: f32,
        xrel: f32,
        yrel: f32,
    };

    const WindowResize = struct {
        width: usize,
        height: usize,
    };

    mouse_down: std.ArrayList(MousePress),
    key_down: std.ArrayList(u32),
    mouse_motion: std.ArrayList(MouseMotion),
    window_resized: std.ArrayList(WindowResize),

    mouse_button_state: []MouseButtonState,
    mouse_position: za.Vec2,

    window_width: usize,
    window_height: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) InputEventBuffer {
        const mbs = allocator.alloc(MouseButtonState, 2) catch unreachable;
        for (mbs) |*m| {
            m.* = .up;
        }
        return .{
            .mouse_down = std.ArrayList(MousePress).init(allocator),
            .key_down = std.ArrayList(u32).init(allocator),
            .mouse_motion = std.ArrayList(MouseMotion).init(allocator),
            .mouse_button_state = mbs,
            .mouse_position = za.Vec2.new(0.0, 0.0),
            .window_width = 0,
            .window_height = 0,
            .window_resized = std.ArrayList(WindowResize).init(allocator),
        };
    }

    pub fn clear(self: *InputEventBuffer) void {
        self.mouse_down.clearAndFree();
        self.key_down.clearAndFree();
        self.mouse_motion.clearAndFree();
        self.window_resized.clearAndFree();
    }

    pub inline fn getAspectRatio(self: *const Self) f32 {
        return @as(f32, @floatFromInt(self.window_width)) / @as(f32, @floatFromInt(self.window_height));
    }


    pub fn update(self: *Self, view_matrix: *za.Mat4, projection_matrix: *const za.Mat4, board: *Board, camera_orientation: *Vec3) void {
        for (self.mouse_down.items) |mouse| {
            self.mouse_button_state[@intFromEnum(mouse.button)] = mouse.state;

            if (mouse.state == .down and mouse.button == .left) {
                const M = view_matrix.inv().data;
                const c = Vec3.new(M[3][0], M[3][1], M[3][2]);

                const w: f32 = @floatFromInt(self.window_width);
                const h: f32 = @floatFromInt(self.window_height);

                const ndc = za.Vec4.new((2.0 * mouse.x) / w - 1.0, 1.0 - (2.0 * mouse.y) / h, 1.0, 1.0);
                var unprojected = (projection_matrix.mul(view_matrix.*)).inv().mulByVec4(ndc);
                unprojected = unprojected.scale(1 / unprojected.w());
                const d = unprojected.toVec3().sub(c).norm();

                const point = util.yPlaneIntersection(c, d);
                if (point) |p| {
                    const x: i32 = @intFromFloat(p.x() + 4);
                    const y: i32 = @intFromFloat(p.y() + 4);
                    if (x >= 0 and x < 8 and y >= 0 and y < 8) {
                        const index = @as(usize, @intCast(y)) * Board.width + @as(usize, @intCast(x));

                        if (board.isHighlighted(index)) {
                            // should never fail because there can only be highlighted tiles when there is a piece selected
                            const id = board.selected_piece_id.?;
                            const old_pos = board.positions.items[id];
                            board.movePiece(old_pos, index);
                        } else if (board.getPieceIdAt(index)) |id| {
                            board.clearHighlightedTiles();

                            board.selectPiece(id);
                            board.highlightTile(index);
                            board.highlightMoves(id);
                        }
                    }
                }
            }
        }

        for (self.window_resized.items) |window| {
            self.window_width = window.width;
            self.window_height = window.height;
        }

        for (self.key_down.items) |key| {
            print("key {} was pressed\n", .{key});
        }

        for (self.mouse_motion.items) |motion| {
            if (self.mouse_button_state[0] == .down) {
                const max_pitch = za.toRadians(@as(f32, 80.0));
                const sens = za.toRadians(@as(f32, 0.1));
                const od = &camera_orientation.data;

                od[1] -= motion.xrel * sens;
                od[2] = util.clampf(od[2] + motion.yrel * sens, -max_pitch, max_pitch);

                view_matrix.* = util.rebuildViewMatrix(camera_orientation.*);
            }
        }
    }
};
