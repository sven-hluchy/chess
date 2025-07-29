const std = @import("std");
const print = std.debug.print;

pub const Piece = enum {
    pawn,
    bishop,
    knight,
    rook,
    queen,
    king,

    pub fn toString(self: Piece) []const u8 {
        return switch (self) {
            .pawn => "pawn",
            .bishop => "bishop",
            .knight => "knight",
            .rook => "rook",
            .queen => "queen",
            .king => "king",
        };
    }
};

const Colour = enum {
    black,
    white,
};

const Offset = struct {
    x: i32,
    y: i32,

    pub fn new(x: i32, y: i32) Offset {
        return .{ .x = x, .y = y };
    }

    pub fn scale(self: *const Offset, s: i32) Offset {
        return Offset.new(self.x * s, self.y * s);
    }
};

const pawn_moves_not_yet_moved = [_]Offset{
    Offset.new(0, 1),
    Offset.new(0, 2),
};

const pawn_moves = [_]Offset{
    Offset.new(0, 1),
};

const pawn_moves_capture_left = [_]Offset{
    Offset.new(0, 1),
    Offset.new(1, 1),
};

const pawn_moves_capture_right = [_]Offset{
    Offset.new(0, 1),
    Offset.new(-1, 1),
};

const pawn_moves_capture_both = [_]Offset{
    Offset.new(0, 1),
    Offset.new(1, 1),
    Offset.new(0, 1),
    Offset.new(-1, 1),
};

const knight_moves = [_]Offset{
    Offset.new(2, 1),
    Offset.new(-2, 1),
    Offset.new(1, 2),
    Offset.new(-1, 2),

    Offset.new(2, -1),
    Offset.new(1, -2),
    Offset.new(1, -2),
    Offset.new(-1, -2),
};

const bishop_mold = [_]Offset{
    Offset.new(1, 1),
    Offset.new(-1, 1),
    Offset.new(-1, -1),
    Offset.new(1, -1),
};

const rook_mold = [_]Offset{
    Offset.new(0, 1),
    Offset.new(-1, 0),
    Offset.new(0, -1),
    Offset.new(1, 0),
};

const queen_mold = [_]Offset{
    Offset.new(1, 0),
    Offset.new(-1, 0),
    Offset.new(0, 1),
    Offset.new(0, -1),

    Offset.new(1, 1),
    Offset.new(-1, 1),
    Offset.new(-1, -1),
    Offset.new(1, -1),
};

const king_moves = [_]Offset{
    Offset.new(1, 0),
    Offset.new(-1, 0),
    Offset.new(0, 1),
    Offset.new(0, -1),

    Offset.new(1, 1),
    Offset.new(-1, 1),
    Offset.new(-1, -1),
    Offset.new(1, -1),
};

pub const Board = struct {
    pub const width: usize = 8;
    pub const height: usize = 8;

    const Position = struct {
        row: usize,
        column: usize,

        pub fn new(x: usize, y: usize) Position {
            return .{
                .row = x,
                .column = y,
            };
        }

        pub fn fromIndex(index: usize) Position {
            return Position.new(index % Board.width, index / Board.width);
        }

        pub fn toIndex(self: *const Position) usize {
            return self.column * Board.width + self.row;
        }

        pub fn eq(self: *const Position, other: Position) bool {
            return self.row == other.row and self.column == other.column;
        }

        // should handle the whole i32-usize casting shit with _some_ grace
        // if the target tile is not a valid usize, the move is not valid
        pub fn moveBy(self: *const Position, move: Offset) ?Position {
            const r: i32 = @intCast(self.row);
            const c: i32 = @intCast(self.column);

            const new_row = r + move.x;
            const new_col = c + move.y;

            if (new_row < 0 or new_col < 0 or new_row >= Board.width or new_col >= Board.height) {
                return null;
            }

            return Position.new(@intCast(new_row), @intCast(new_col));
        }
    };

    pieces: std.ArrayList(Piece),
    positions: std.ArrayList(Position),
    colours: std.ArrayList(Colour),
    alive: std.ArrayList(bool),
    has_moved: std.ArrayList(bool),

    highlighted: []i32, // should be []bool, opengl doesn't like that though

    position_lookup: std.AutoHashMap(usize, usize),
    selected_piece_id: ?usize,
    turn_number: usize,
    turn: Colour,

    const Self = @This();

    fn pawnMoveDistance(self: *const Self, id: usize) usize {
        const pawn_pos = self.positions.items[id];
        const pawn_colour = self.colours.items[id];
        const has_pawn_moved = self.has_moved.items[id];

        const n: usize = if (has_pawn_moved == false) 2 else 1;
        const s: i32 = if (pawn_colour == .white) 1 else -1;
        for (0..n) |index| {
            const maybePos = pawn_pos.moveBy(Offset.new(0, @as(i32, @intCast(index + 1)) * s));
            if (maybePos) |pos| {
                if (self.hasPieceAt(pos.toIndex())) {
                    return index;
                }
            }
        }
        return n;
    }

    fn canPawnCapture(self: *const Self, id: usize) enum { no, left, right, both } {
        const pawn_pos = self.positions.items[id];
        const colour = self.colours.items[id];

        const capture_moves_white = [_]Offset{
            Offset.new(1, 1),
            Offset.new(-1, 1),
        };

        const capture_moves_black = [_]Offset{
            Offset.new(-1, -1),
            Offset.new(1, -1),
        };

        var can_capture: u8 = 0;

        const moves = if (colour == .white) capture_moves_white else capture_moves_black;
        for (0.., moves) |index, move| {
            const maybePos = pawn_pos.moveBy(move);
            if (maybePos) |pos| {
                if (self.getPieceIdAt(pos.toIndex())) |other_id| {
                    if (self.colours.items[other_id] != colour) {
                        can_capture |= @intCast(index + 1);
                    }
                }
            }
        }

        return switch (can_capture) {
            0b01 => .left,
            0b10 => .right,
            0b11 => .both,
            else => .no,
        };
    }

    fn validMove(self: *Self, id: usize, move: Offset) bool {
        // if there is a piece that has a different colour or if there is no piece
        if (move.x == 0 and move.y == 0) {
            return false;
        }

        const current_pos = self.positions.items[id];
        const new_pos = current_pos.moveBy(move);
        if (new_pos == null) {
            return false;
        }

        const index = new_pos.?.toIndex();
        if (self.hasPieceAt(index) == false) {
            return true;
        }

        const colour = self.colours.items[id];
        if (self.getPieceIdAt(index)) |piece_id| {
            const piece_colour = self.colours.items[piece_id];
            if (colour != piece_colour and piece_id != id) {
                return true;
            }
        }

        return false;
    }

    pub fn getPossibleMoves(self: *Self, id: usize) []const Offset {
        const piece = self.pieces.items[id];

        switch (piece) {
            .pawn => {
                return switch (self.canPawnCapture(id)) {
                    .left => &pawn_moves_capture_left,
                    .right => &pawn_moves_capture_right,
                    .both => &pawn_moves_capture_both,
                    .no => switch (self.pawnMoveDistance(id)) {
                        0 => &.{},
                        1 => &pawn_moves,
                        2 => &pawn_moves_not_yet_moved,
                        else => unreachable,
                    },
                };
            },
            .knight => { return &knight_moves; },
            .bishop => { return &bishop_mold; },
            .rook => { return &rook_mold; },
            .queen => { return &queen_mold; },
            .king => { return &king_moves; },
        }
    }

    pub fn highlightMoves(self: *Self, id: usize) void {
        const piece = self.pieces.items[id];
        const pos = self.positions.items[id];
        const colour = self.colours.items[id];
        const alive = self.alive.items[id];

        if (alive == false) { // the dead don't move
            return;
        }

        switch (piece) {
            .pawn, .king, .knight => {
                const moves = self.getPossibleMoves(id);
                for (moves) |move| {
                    var m = move;
                    if (piece == .pawn and colour == .black) {
                        m = m.scale(-1);
                    }
                    if (self.validMove(id, m)) {
                        const index = pos.moveBy(m).?.toIndex();
                        self.highlightTile(index);
                    }
                }
            },
            .bishop, .queen, .rook => {
                // :D
                const mold = self.getPossibleMoves(id);
                // const n = if (piece == .queen) 8 else 4;
                var mask: [8]bool = .{ false } ** 8;
                var em: [8]bool = .{ false } ** 8;
                for (0..7) |d| {
                    for (0..if (piece == .queen) 8 else 4) |r| {
                        if (mask[r] == false and em[r] == false) {
                            const move = mold[r].scale(@intCast(d + 1));
                            if (self.validMove(id, move)) {
                                const index = pos.moveBy(move).?.toIndex();
                                if (self.hasPieceAt(index)) {
                                    em[r] = true;
                                }
                                self.highlightTile(index);
                            } else {
                                mask[r] = true;
                            }
                        }
                    }
                }
            },
        }
    }

    fn addPiece(self: *Self, colour: Colour, row: usize, col: usize, piece: Piece) !void {
        const pos = Position{ .row = row, .column = col };
        const index = pos.toIndex();
        const id = self.entryCount();
        try self.pieces.append(piece);
        try self.positions.append(pos);
        try self.colours.append(colour);
        try self.alive.append(true);
        try self.has_moved.append(false);
        try self.position_lookup.put(index, id);
    }

    pub fn movePiece(self: *Self, old_pos: Position, target_index: usize) void {
        const new_pos = Position.fromIndex(target_index);
        if (new_pos.eq(old_pos)) {
            self.unselectPiece();
            self.clearHighlightedTiles();
            return;
        }
        // due to how `validMove` is written, this can only be an enemy piece (or the piece itself)
        const maybeId = self.position_lookup.get(old_pos.toIndex());
        if (maybeId) |id| {
            if (self.colours.items[id] == self.turn) {
                if (self.getPieceIdAt(new_pos.toIndex())) |captured_piece_id| {
                    if (id != captured_piece_id) {
                        self.alive.items[captured_piece_id] = false;
                    }
                }
                self.has_moved.items[id] = true;
                self.positions.items[id] = new_pos;
                _ = self.position_lookup.remove(old_pos.toIndex());
                self.position_lookup.put(new_pos.toIndex(), id) catch unreachable;

                self.turn_number += 1;
                self.turn = if (self.turn == .white) .black else .white;

                print("`{s}` moved, `{s}` to play\n", .{ self.pieces.items[id].toString(), if (self.turn == .white) "white" else "black" });
            }
        }
        self.unselectPiece();
        self.clearHighlightedTiles();
    }

    pub inline fn isHighlighted(self: *const Self, index: usize) bool {
        return self.highlighted[index] == 1;
    }

    pub inline fn highlightTile(self: *Self, index: usize) void {
        self.highlighted[index] = 1;
    }

    pub inline fn clearHighlightedTiles(self: *Self) void {
        for (self.highlighted) |*h| {
            h.* = 0;
        }
        self.selected_piece_id = null;
    }

    pub inline fn selectPiece(self: *Self, id: usize) void {
        self.selected_piece_id = id;
    }

    pub inline fn unselectPiece(self: *Self) void {
        self.selected_piece_id = null;
    }

    pub inline fn getPieceIdAt(self: *const Self, index: usize) ?usize {
        return self.position_lookup.get(index);
    }

    pub inline fn hasPieceAt(self: *const Self, index: usize) bool {
        return self.position_lookup.contains(index);
    }

    pub inline fn entryCount(self: *const Self) usize {
        return self.pieces.items.len;
    }

    pub inline fn isAlive(self: *const Self, index: usize) bool {
        return self.alive.items[index];
    }

    pub fn init(allocator: std.mem.Allocator) !Board {
        const highlightMask = try allocator.alloc(i32, Self.width * Self.height);
        for (highlightMask) |*h| {
            h.* = 0;
        }
        var board = Board{
            .positions = std.ArrayList(Position).init(allocator),
            .pieces = std.ArrayList(Piece).init(allocator),
            .colours = std.ArrayList(Colour).init(allocator),
            .alive = std.ArrayList(bool).init(allocator),
            .has_moved = std.ArrayList(bool).init(allocator),
            .position_lookup = std.AutoHashMap(usize, usize).init(allocator),
            .highlighted = highlightMask,
            .selected_piece_id = null,
            .turn_number = 1,
            .turn = .white,
        };

        try board.addPiece(.white, 0, 0, .rook);
        try board.addPiece(.white, 1, 0, .knight);
        try board.addPiece(.white, 2, 0, .bishop);
        try board.addPiece(.white, 3, 0, .king);
        try board.addPiece(.white, 4, 0, .queen);
        try board.addPiece(.white, 5, 0, .bishop);
        try board.addPiece(.white, 6, 0, .knight);
        try board.addPiece(.white, 7, 0, .rook);
        for (0..8) |offset| {
            try board.addPiece(.white, offset, 1, .pawn);
        }

        try board.addPiece(.black, 0, 7, .rook);
        try board.addPiece(.black, 1, 7, .knight);
        try board.addPiece(.black, 2, 7, .bishop);
        try board.addPiece(.black, 3, 7, .king);
        try board.addPiece(.black, 4, 7, .queen);
        try board.addPiece(.black, 5, 7, .bishop);
        try board.addPiece(.black, 6, 7, .knight);
        try board.addPiece(.black, 7, 7, .rook);
        for (0..Board.width) |offset| {
            try board.addPiece(.black, offset, 6, .pawn);
        }

        return board;
    }
};
