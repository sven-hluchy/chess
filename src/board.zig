const std = @import("std");
const print = std.debug.print;

pub const Piece = enum {
    pawn,
    bishop,
    knight,
    rook,
    queen,
    king,
};

pub const Colour = enum {
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

const pawn_moves_white_not_yet_moved = [_]Offset{
    Offset.new(0, 1),
    Offset.new(0, 2),
};

const pawn_moves_white = [_]Offset{
    Offset.new(0, 1),
};

const pawn_moves_black_not_yet_moved = [_]Offset{
    Offset.new(0, -1),
    Offset.new(0, -2),
};

const pawn_moves_black = [_]Offset{
    Offset.new(0, -1),
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

    const Self = @This();

    fn validMove(self: *Self, id: usize, move: Offset) bool {
        // if there is a piece that has a different colour or if there is no piece
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
            if (colour != piece_colour) {
                return true;
            }
        }

        return false;
    }

    pub fn getPossibleMoves(self: *Self, id: usize) []const Offset {
        const piece = self.pieces.items[id];
        const colour = self.colours.items[id];
        const has_moved = self.has_moved.items[id];

        switch (piece) {
            .pawn => {
                if (colour == .white) {
                    return if (has_moved) &pawn_moves_white else &pawn_moves_white_not_yet_moved;
                } else {
                    return if (has_moved) &pawn_moves_black else &pawn_moves_black_not_yet_moved;
                }
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
        const alive = self.alive.items[id];

        if (alive == false) { // the dead don't move
            return;
        }

        switch (piece) {
            .pawn, .king, .knight => {
                const moves = self.getPossibleMoves(id);
                print("has {d} possible moves: {any}\n", .{ moves.len, moves });
                for (moves) |move| {
                    if (self.validMove(id, move)) {
                        self.highlightTile(pos.moveBy(move).?.toIndex());
                    }
                }
            },
            .bishop, .queen, .rook => {
                // :D
                const mold = self.getPossibleMoves(id);
                var mask: [8]bool = .{ false } ** 8;
                var em: [8]bool = .{ false } ** 8;
                for (0..7) |d| {
                    for (0..4) |r| {
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
        // due to how `validMove` is written, this can only be an enemy piece
        if (self.getPieceIdAt(new_pos.toIndex())) |captured_piece_id| {
            self.alive.items[captured_piece_id] = false;
        }
        const maybeId = self.position_lookup.get(old_pos.toIndex());
        if (maybeId) |id| {
            print("moving piece with id {d} from {any} to {any}\n", .{ id, old_pos, new_pos });
            self.has_moved.items[id] = true;
            self.positions.items[id] = new_pos;
            _ = self.position_lookup.remove(old_pos.toIndex());
            self.position_lookup.put(new_pos.toIndex(), id) catch unreachable;
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
