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

const MoveMask = u64;

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

inline fn absSub(a: usize, b: usize) usize {
    return if (a > b) a - b else b - a;
}

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

    // just uncheckd `isValidOffset`
    pub fn offsetBy(self: *const Position, dx: i32, dy: i32) usize {
        const new_row = @as(i32, @intCast(self.row)) + dx;
        const new_col = @as(i32, @intCast(self.column)) + dy;
        return Position.new(@intCast(new_row), @intCast(new_col)).toIndex();
    }

    pub fn isValidOffset(self: *const Position, dx: i32, dy: i32) ?usize {
        const new_row = @as(i32, @intCast(self.row)) + dx;
        const new_col = @as(i32, @intCast(self.column)) + dy;

        if (new_row < 0 or new_col < 0 or new_row >= Board.width or new_col >= Board.height) {
            return null;
        }
        return Position.new(@intCast(new_row), @intCast(new_col)).toIndex();
    }
};

pub const Board = struct {
    pub const width: usize = 8;
    pub const height: usize = 8;

    pieces: std.ArrayList(Piece),
    positions: std.ArrayList(Position),
    colours: std.ArrayList(Colour),
    alive: std.ArrayList(bool),
    has_moved: std.ArrayList(bool),

    highlighted: u64,
    castling: u64,

    position_lookup: std.AutoHashMap(usize, usize),
    selected_piece_id: ?usize,
    turn_number: usize,
    turn: Colour,

    const Self = @This();

    inline fn setNth(index: usize) u64 {
        return @as(u64, 1) << @intCast(index);
    }

    fn isOccupied(self: *const Self, index: usize, colour: Colour) enum { no, enemy, friend } {
        if (self.getPieceIdAt(index)) |id| {
            if (colour != self.colours.items[id]) {
                return .enemy;
            } else {
                return .friend;
            }
        }
        return .no;
    }
    
    fn getPawnMoves(self: *const Self, id: usize) MoveMask {
        const pos = self.positions.items[id];
        const colour = self.colours.items[id];
        const has_moved = self.has_moved.items[id];

        var mask: MoveMask = 0;

        const factor: i32 = if (colour == .white) 1 else -1;

        if (pos.isValidOffset(0, 1 * factor)) |index1| {
            if (self.hasPieceAt(index1) == false) {
                mask |= setNth(index1);
                // pawns can't jump
                if (has_moved == false) {
                    if (pos.isValidOffset(0, 2 * factor)) |index2| {
                        if (self.hasPieceAt(index2) == false) {
                            mask |= setNth(index2);
                        }
                    }
                }
            }
        }

        const capture_moves = [_]Offset{
            Offset.new(1, 1 * factor),
            Offset.new(-1, 1 * factor),
        };

        for (capture_moves) |move| {
            if (pos.isValidOffset(move.x, move.y)) |index| {
                if (self.isOccupied(index, colour) == .enemy) {
                    mask |= setNth(index);
                }
            }
        }

        return mask;
    }

    fn getKnightMoves(self: *const Self, id: usize) MoveMask {
        const pos = self.positions.items[id];
        const colour = self.colours.items[id];

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

        var mask: MoveMask = 0;

        for (knight_moves) |move| {
            if (pos.isValidOffset(move.x, move.y)) |index| {
                if (self.isOccupied(index, colour) == .enemy or self.hasPieceAt(index) == false) {
                    mask |= setNth(index);
                }
            }
        }

        return mask;
    }

    fn getBishopMoves(self: *const Self, id: usize) MoveMask {
        const bishop_mould = [_]Offset{
            Offset.new(1, 1),
            Offset.new(-1, 1),
            Offset.new(-1, -1),
            Offset.new(1, -1),
        };

        return self.growFromMould(id, &bishop_mould, 4);
    }

    fn getRookMoves(self: *const Self, id: usize) MoveMask {
        const rook_mould = [_]Offset{
            Offset.new(0, 1),
            Offset.new(-1, 0),
            Offset.new(0, -1),
            Offset.new(1, 0),
        };

        return self.growFromMould(id, &rook_mould, 4);
    }

    fn getQueenMoves(self: *const Self, id: usize) MoveMask {
        const queen_mould = [_]Offset{
            Offset.new(1, 0),
            Offset.new(-1, 0),
            Offset.new(0, 1),
            Offset.new(0, -1),

            Offset.new(1, 1),
            Offset.new(-1, 1),
            Offset.new(-1, -1),
            Offset.new(1, -1),
        };

        return self.growFromMould(id, &queen_mould, 8);
    }

    fn getKingMoves(self: *Self, id: usize) MoveMask {
        const pos = self.positions.items[id];
        const colour = self.colours.items[id];

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

        var mask: MoveMask = 0;

        for (king_moves) |move| {
            if (pos.isValidOffset(move.x, move.y)) |index| {
                if (self.isOccupied(index, colour) == .enemy or self.hasPieceAt(index) == false) {
                    mask |= setNth(index);
                }
            }
        }

        self.castling = self.canCastle(id);
        mask |= self.castling;

        return mask;
    }

    pub fn highlightMoves(self: *Self, id: usize) void {
        const piece = self.pieces.items[id];
        const alive = self.alive.items[id];

        if (alive == false) { // the dead don't move
            return;
        }

        const move_mask = switch (piece) {
            .pawn => self.getPawnMoves(id),
            .knight => self.getKnightMoves(id), // there is a Bob Seger joke here somewhere, I just can't find it
            .bishop => self.getBishopMoves(id),
            .rook => self.getRookMoves(id),
            .queen => self.getQueenMoves(id),
            .king => self.getKingMoves(id),
        };

        self.highlighted |= move_mask;
    }

    fn firstSeenPiece(self: *const Self, id: usize, dir: Offset) ?usize {
        const pos = self.positions.items[id];
        for (0..7) |d| {
            const move = dir.scale(@intCast(d + 1));
            if (pos.isValidOffset(move.x, move.y)) |index| {
                if (self.hasPieceAt(index)) {
                    return self.getPieceIdAt(index);
                }
            }
        }
        return null;
    }

    fn canCastle(self: *const Self, id: usize) MoveMask {
        const pos = self.positions.items[id];
        const has_moved = self.has_moved.items[id];
        const colour = self.colours.items[id];

        if (has_moved == true) {
            return 0;
        }

        var mask: MoveMask = 0;

        const queenside_piece_id = self.firstSeenPiece(id, Offset.new(1, 0));
        const kingside_piece_id = self.firstSeenPiece(id, Offset.new(-1, 0));

        if (queenside_piece_id) |qid| {
            const qs = self.has_moved.items[qid] == false and self.colours.items[qid] == colour and self.pieces.items[qid] == .rook;
            if (qs) {
                if (pos.isValidOffset(2, 0)) |index| {
                    mask |= setNth(index);
                }
            }

        }

        if (kingside_piece_id) |kid| {
            const ks = self.has_moved.items[kid] == false and self.colours.items[kid] == colour and self.pieces.items[kid] == .rook;
            if (ks) {
                if (pos.isValidOffset(-2, 0)) |index| {
                    mask |= setNth(index);
                }
            }
        }

        return mask;
    }

    fn growFromMould(self: *const Self, id: usize, mould: []const Offset, comptime R: usize) MoveMask {
        var move_mask: u64 = 0;
        const pos = self.positions.items[id];
        const colour = self.colours.items[id];

        var mask: [R]bool = .{ false } ** R;
        var em: [R]bool = .{ false } ** R;
        for (0..7) |d| {
            for (0..R) |r| {
                if (mask[r] == false and em[r] == false) {
                    const move = mould[r].scale(@intCast(d + 1));
                    if (pos.isValidOffset(move.x, move.y)) |index| {
                        switch (self.isOccupied(index, colour)) {
                            .enemy => {
                                em[r] = true;
                            },
                            .friend => {
                                mask[r] = true;
                                continue;
                            },
                            .no => {},
                        }
                        move_mask |= setNth(index);
                    } else {
                        mask[r] = true;
                    }
                }
            }
        }
        return move_mask;
    }

    fn pieceAtIndexIsUnmovedRook(self: *const Self, index: usize) bool {
        if (getPieceIdAt(index)) |id| {
            const piece = self.pieces.items[id];
            const has_moved = self.has_moved.items[id];
            return piece == .rook and has_moved == false;
        }
        return false;
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

    pub fn castle(self: *Self, king_id: usize, index: usize) void {
        const Side = enum { kingside, queenside };
        const colour = self.colours.items[king_id];
        const king_pos = self.positions.items[king_id];

        const side: Side = if (Position.fromIndex(index).row == 1) .kingside else .queenside;

        const y = if (colour == .white) @as(usize, 0) else @as(usize, 7);
        const rook_pos = if (side == .queenside) Position.new(7, y) else Position.new(0, y);
        const rook_id = self.position_lookup.get(rook_pos.toIndex()).?;
        const rook_offset = if (side == .queenside) @as(i32, -3) else @as(i32, 2);
        const king_offset = if (side == .queenside) @as(i32, 2) else @as(i32, -2);

        const new_king_pos = king_pos.offsetBy(king_offset, 0);
        const new_rook_pos = rook_pos.offsetBy(rook_offset, 0);

        // kind of painful
        self.has_moved.items[king_id] = true;
        self.has_moved.items[rook_id] = true;
        self.positions.items[king_id] = Position.fromIndex(new_king_pos);
        self.positions.items[rook_id] = Position.fromIndex(new_rook_pos);
        _ = self.position_lookup.remove(king_pos.toIndex());
        _ = self.position_lookup.remove(rook_pos.toIndex());
        self.position_lookup.put(new_king_pos, king_id) catch unreachable;
        self.position_lookup.put(new_rook_pos, rook_id) catch unreachable;

        self.turn_number += 1;
        self.turn = if (self.turn == .white) .black else .white;
    }

    pub fn movePiece(self: *Self, old_pos: Position, target_index: usize) void {
        const new_pos = Position.fromIndex(target_index);
        if (new_pos.eq(old_pos)) {
            self.unselectPiece();
            self.clearHighlightedTiles();
            return;
        }
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
            }
        }
        self.unselectPiece();
        self.clearHighlightedTiles();
    }

    pub inline fn isHighlighted(self: *const Self, index: usize) bool {
        return (self.highlighted >> @intCast(index)) & 1 == 1;
    }

    pub inline fn clearHighlightedTiles(self: *Self) void {
        self.highlighted = 0;
        self.castling = 0;
        self.selected_piece_id = null;
    }

    pub inline fn isCastling(self: *Self, index: usize) bool {
        return (self.castling >> @intCast(index)) & 1 == 1;
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
        var board = Board{
            .positions = std.ArrayList(Position).init(allocator),
            .pieces = std.ArrayList(Piece).init(allocator),
            .colours = std.ArrayList(Colour).init(allocator),
            .alive = std.ArrayList(bool).init(allocator),
            .has_moved = std.ArrayList(bool).init(allocator),
            .position_lookup = std.AutoHashMap(usize, usize).init(allocator),
            .highlighted = 0,
            .castling = 0,
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
