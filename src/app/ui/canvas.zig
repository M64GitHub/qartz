//! TextCanvas — the tracker's text layer, decoupled from movy.
//!
//! All UI text is drawn into this cell grid, then either blitted onto the
//! movy output surface (interactive) or dumped as plain text (--dump-screen,
//! and later: UI regression tests). Cells with ch == 0 are transparent: the
//! pixel/glow layer shows through them.

const std = @import("std");
const movy = @import("movy");

pub const Rgb = movy.core.types.Rgb;

pub const Cell = struct {
    ch: u21 = 0, // 0 = transparent (pixels show through)
    fg: Rgb = .{},
    bg: Rgb = .{},
};

/// XVIII.h — WHAT A DRAW PUT WHERE. A pane that scrolls has to know two
/// numbers about the thing it is scrolling: how far down the content
/// reaches, and which row the CURSOR is on. Asking each face would be
/// six answers that can drift from six draws (this repo's oldest bug
/// shape), so nothing is asked: the probe WATCHES the draw. A cursor is
/// a BLOCK — one of two background colours behind a cell, the same two
/// in every pane of this program — and the caller names them, so the
/// canvas stays a dumb surface with no idea what a theme is.
pub const CursorProbe = struct {
    /// the two backgrounds that mean "the cursor is here"
    a: Rgb,
    b: Rgb,
    /// THE CONTENT ENDED. Every face closes with a hint line pinned to
    /// the bottom of the pane, and that row is FURNITURE: counting it
    /// as the deepest content would say the pane always has one more
    /// row below, forever. It cannot be recognised by its ROW — a face
    /// that does not know how tall it is draws its own last line
    /// straight onto the same one, and THAT is content, the whole
    /// reason the pane scrolls — so it is recognised by ORDER instead:
    /// `endContent` before the hint, and everything after is chrome.
    closed: bool = false,
    /// the deepest row anything was drawn on (CONTENT rows, so the
    /// answer does not move when the view scrolls)
    reach: usize = 0,
    /// ... and the rows the cursor block covered
    top: usize = 0,
    bot: usize = 0,
    seen: bool = false,

    fn saw(self: *CursorProbe, y: usize, bg: Rgb) void {
        if (self.closed) return;
        if (y > self.reach) self.reach = y;
        if (!std.meta.eql(bg, self.a) and !std.meta.eql(bg, self.b)) return;
        if (!self.seen) {
            self.top = y;
            self.bot = y;
            self.seen = true;
            return;
        }
        self.top = @min(self.top, y);
        self.bot = @max(self.bot, y);
    }
};

/// XXVIII D3 THE COMMIT FLASH: WHERE THE KEYS WERE on the last drawn
/// frame, in SCREEN cells — so an edit that lands can light the spot it
/// landed on. Two sources: a face that KNOWS its cursor says so
/// (`markKeys`, the pattern grid's cell), and every other face is read
/// off its own colours — the first run of cells painted in one of
/// `keys_grounds` (the A1 focus and typing grounds, set by the session
/// each frame). A module global, not a canvas field: the panes draw
/// through shorter VIEWS of the same cells, and the spot is the
/// screen's. The session resets it before each frame's draw.
pub const KeysSpot = struct {
    y: usize = 0,
    x0: usize = 0,
    x1: usize = 0, // exclusive; x1 == x0 = nothing seen
    marked: bool = false, // a face said so: no colour guess overrides it

    pub fn empty(self: KeysSpot) bool {
        return self.x1 <= self.x0;
    }
};
pub var keys_spot: KeysSpot = .{};
pub var keys_grounds: [2]?Rgb = .{ null, null };

pub const TextCanvas = struct {
    w: usize,
    h: usize,
    cells: []Cell,
    allocator: std.mem.Allocator,

    // ---- XVIII.h THE PANE VIEWPORT ---------------------------------
    //
    // `h` is the height the DRAWING code lays out in; these four say
    // where that layout lands on the real screen. A plain canvas leaves
    // them alone and every road below is the identity.
    /// content rows scrolled off the top
    off: usize = 0,
    /// the first SCREEN row this view may write (the rows above belong
    /// to the page header, which does not scroll)
    top: usize = 0,
    /// one past the last SCREEN row it may write; 0 means `h`
    vis: usize = 0,
    /// the pane's furniture rows at the foot of `vis` — content stops
    /// short of them while `content` is set (`viewScroll` / `endContent`)
    tail: usize = 0,
    content: bool = false,
    /// MEASURE ONLY: run the whole draw, store nothing, and let the
    /// probe read the geometry back. The scroll is decided from this
    /// and the real draw follows in the same frame, so a dump of one
    /// frame is the same picture as a session's
    dry: bool = false,
    probe: ?*CursorProbe = null,

    pub fn init(allocator: std.mem.Allocator, w: usize, h: usize) !TextCanvas {
        const cells = try allocator.alloc(Cell, w * h);
        @memset(cells, Cell{});
        return .{ .w = w, .h = h, .cells = cells, .allocator = allocator };
    }

    pub fn deinit(self: *TextCanvas) void {
        self.allocator.free(self.cells);
    }

    /// A SHORTER VIEW of the same cells — same buffer, same rows, a
    /// smaller `h`. XVIII THE SCOPE's band docks to the bottom of the
    /// working pane, and m64's layout rule is SCROLL BEFORE SACRIFICE
    /// (s92): rather than teach every face where the band is, the face
    /// is handed a screen that really IS that much shorter, so its
    /// bottom-anchored rows (the sample editor's parameter block, every
    /// page's hint line) move up instead of being covered.
    ///
    /// The view BORROWS the cells: never deinit one.
    pub fn viewH(self: *const TextCanvas, h: usize) TextCanvas {
        return .{
            .w = self.w,
            .h = @min(h, self.h),
            .cells = self.cells,
            .allocator = self.allocator,
        };
    }

    /// XVIII.h — A SCROLLED WINDOW onto the same cells. The face lays
    /// out in `h + off` rows, as tall as it wants to be, and this view
    /// drops the result `off` rows higher on the real screen, keeping
    /// only the band `[top, h)`.
    ///
    /// THE ARITHMETIC IS WHY IT IS THIS SHAPE: the content is exactly
    /// `off` rows taller than the window, so the face's bottom-anchored
    /// rows — its own hint at `h-3`, which s115 shortened the pane to
    /// keep on screen — land back on the same screen rows they had
    /// before. Nothing is pinned by hand; the scroll simply does not
    /// reach them.
    ///
    /// The view BORROWS the cells: never deinit one.
    ///
    /// `tail` is the pane's FURNITURE — the rows at its foot (the hint,
    /// the page rule, the footer bar) that content may never reach.
    /// Until `endContent` the view drops every content row that would
    /// land there (s123): a face whose rows outran the window drew its
    /// tail over the hint line and the rule whenever the cursor sat at
    /// the top, where nothing had scrolled it.
    pub fn viewScroll(self: *const TextCanvas, off: usize, top: usize, tail: usize) TextCanvas {
        const vis = @min(self.h, if (self.vis == 0) self.h else self.vis);
        return .{
            .w = self.w,
            .h = vis + off,
            .cells = self.cells,
            .allocator = self.allocator,
            .off = off,
            .top = top,
            .vis = vis,
            .tail = tail,
            .content = true,
        };
    }

    /// XVIII.h — EVERYTHING FROM HERE IS THE PANE'S FURNITURE, not
    /// content the scroll has to be able to reach. Called once by each
    /// face, immediately before its hint line. A no-op off a measuring
    /// canvas, which is every canvas but one.
    pub fn endContent(self: *TextCanvas) void {
        if (self.probe) |pr| pr.closed = true;
        self.content = false; // the furniture may reach the foot now
    }

    /// ... and the MEASURING twin of `viewScroll`: the same layout
    /// space, no cells at all, the probe reading what the draw asked
    /// for. THE HEIGHT IS THE PANE'S OWN and never the scrolled one —
    /// a face that hangs its block off the bottom must measure as
    /// fitting, or the pane it is on could never scroll back.
    pub fn measure(w: usize, h: usize, probe: *CursorProbe) TextCanvas {
        return .{
            .w = w,
            .h = h,
            .cells = &.{},
            .allocator = undefined,
            .dry = true,
            .probe = probe,
        };
    }

    pub fn clear(self: *TextCanvas) void {
        @memset(self.cells, Cell{});
    }

    pub fn put(self: *TextCanvas, x: usize, y: usize, ch: u21, fg: Rgb, bg: Rgb) void {
        if (x >= self.w) return;
        // A MEASURING PASS TAKES ROWS THE REAL ONE WOULD DROP. A face
        // with a fixed layout draws past the bottom of a short pane and
        // those cells are simply lost on screen; if the measure lost
        // them too, the pane could never learn there was anything down
        // there to scroll to.
        if (self.dry) {
            if (self.probe) |pr| pr.saw(y, bg);
            return;
        }
        if (y >= self.h) return;
        if (y < self.off) return; // scrolled off the top
        const sy = y - self.off;
        const vis = if (self.vis == 0) self.h else self.vis;
        if (sy < self.top or sy >= vis) return;
        // content stops where the pane's furniture begins (viewScroll)
        if (self.content and sy >= vis -| self.tail) return;
        self.cells[sy * self.w + x] = .{ .ch = ch, .fg = fg, .bg = bg };
        // D3: the first run of a keys ground is where the keys are
        if (!keys_spot.marked) for (keys_grounds) |g| {
            const kg = g orelse continue;
            if (!std.meta.eql(kg, bg)) continue;
            const sp = &keys_spot;
            if (sp.empty()) {
                sp.* = .{ .y = sy, .x0 = x, .x1 = x + 1 };
            } else if (sp.y == sy and x == sp.x1) sp.x1 = x + 1;
            break;
        };
    }

    /// D3: this face KNOWS where the keys are — `n` cells from (x, y) in
    /// its own layout — and no colour guess may override it.
    pub fn markKeys(self: *const TextCanvas, x: usize, y: usize, n: usize) void {
        if (self.dry or y < self.off) return;
        const sy = y - self.off;
        const vis = if (self.vis == 0) self.h else self.vis;
        if (sy < self.top or sy >= vis or x >= self.w) return;
        keys_spot = .{ .y = sy, .x0 = x, .x1 = @min(self.w, x + n), .marked = true };
    }

    /// D3: lean every cell of the run toward `col` by `k` (ground and
    /// ink alike, the ink toward `ink` so the glyph stays readable on
    /// a light flash).
    pub fn flashRun(self: *TextCanvas, sp: KeysSpot, col: Rgb, ink: Rgb, k: f32) void {
        if (sp.empty() or sp.y >= self.h or k <= 0) return;
        var x = sp.x0;
        while (x < @min(sp.x1, self.w)) : (x += 1) {
            const cell = &self.cells[sp.y * self.w + x];
            cell.bg = lerp(cell.bg, col, k);
            cell.fg = lerp(cell.fg, ink, k);
            if (cell.ch == 0) cell.ch = ' ';
        }
    }

    /// ASCII ONLY — byte-wise, like movy's putStrXY. That is the right
    /// default (names from .it/.swi files are arbitrary DOS-charset
    /// bytes, not UTF-8), so the rule for OUR strings is: keep them
    /// ASCII. A '—' or '·' in a literal here renders as several
    /// garbage cells; use put()/putRepeat() with a u21 codepoint when
    /// a real glyph is wanted.
    pub fn putStr(self: *TextCanvas, x: usize, y: usize, s: []const u8, fg: Rgb, bg: Rgb) void {
        for (s, 0..) |b, i| self.put(x + i, y, b, fg, bg);
    }

    pub fn putRepeat(self: *TextCanvas, x: usize, y: usize, n: usize, ch: u21, fg: Rgb, bg: Rgb) void {
        var i: usize = 0;
        while (i < n) : (i += 1) self.put(x + i, y, ch, fg, bg);
    }

    /// Paint a full row of spaces (opaque background bar).
    pub fn fillRow(self: *TextCanvas, y: usize, fg: Rgb, bg: Rgb) void {
        self.putRepeat(0, y, self.w, ' ', fg, bg);
    }

    pub fn blitTo(self: *const TextCanvas, surface: anytype) void {
        var y: usize = 0;
        while (y < self.h) : (y += 1) {
            var x: usize = 0;
            while (x < self.w) : (x += 1) {
                const cell = self.cells[y * self.w + x];
                if (cell.ch == 0) continue;
                surface.putUtf8XY(cell.ch, x, y, cell.fg, cell.bg);
            }
        }
    }

    /// Plain-text render (colors dropped) — for --dump-screen and tests.
    pub fn dumpAlloc(self: *const TextCanvas, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .{};
        errdefer out.deinit(allocator);
        var buf: [4]u8 = undefined;
        var y: usize = 0;
        while (y < self.h) : (y += 1) {
            var x: usize = 0;
            while (x < self.w) : (x += 1) {
                const ch = self.cells[y * self.w + x].ch;
                if (ch == 0) {
                    try out.append(allocator, ' ');
                } else {
                    const len = std.unicode.utf8Encode(ch, &buf) catch blk: {
                        buf[0] = '?';
                        break :blk 1;
                    };
                    try out.appendSlice(allocator, buf[0..len]);
                }
            }
            try out.append(allocator, '\n');
        }
        return out.toOwnedSlice(allocator);
    }
};

fn lerp(a: Rgb, b: Rgb, t: f32) Rgb {
    const f = struct {
        fn one(x: u8, y: u8, u: f32) u8 {
            const xf: f32 = @floatFromInt(x);
            const yf: f32 = @floatFromInt(y);
            return @intFromFloat(xf + (yf - xf) * std.math.clamp(u, 0, 1) + 0.5);
        }
    };
    return .{ .r = f.one(a.r, b.r, t), .g = f.one(a.g, b.g, t), .b = f.one(a.b, b.b, t) };
}
