//! Widgets — the shared building blocks of the popup UI. Everything is
//! immediate-mode over TextCanvas, in the house style set by the help
//! overlay: rounded borders, title chip on the top edge, theme colors.
//! Views stay dumb; state lives with the caller.

const std = @import("std");
const theme = @import("theme.zig");
const TextCanvas = @import("canvas.zig").TextCanvas;

/// Rounded popup frame (neovim-float style): cleared interior, ╭─╮
/// border, title chip at the top-left edge. The caller owns everything
/// inside (and any bottom-edge labels).
pub fn frame(
    c: *TextCanvas,
    x0: usize,
    y0: usize,
    w: usize,
    h: usize,
    title: []const u8,
) void {
    if (w < 4 or h < 2) return;
    const bord = theme.accent_hot;
    var dy: usize = 0;
    while (dy < h) : (dy += 1)
        c.putRepeat(x0, y0 + dy, w, ' ', theme.text, theme.bg);
    c.putRepeat(x0 + 1, y0, w - 2, '─', bord, theme.bg);
    c.putRepeat(x0 + 1, y0 + h - 1, w - 2, '─', bord, theme.bg);
    dy = 1;
    while (dy < h - 1) : (dy += 1) {
        c.put(x0, y0 + dy, '│', bord, theme.bg);
        c.put(x0 + w - 1, y0 + dy, '│', bord, theme.bg);
    }
    c.put(x0, y0, '╭', bord, theme.bg);
    c.put(x0 + w - 1, y0, '╮', bord, theme.bg);
    c.put(x0, y0 + h - 1, '╰', bord, theme.bg);
    c.put(x0 + w - 1, y0 + h - 1, '╯', bord, theme.bg);
    if (title.len > 0 and title.len + 6 <= w)
        c.putStr(x0 + 3, y0, title, theme.text_bright, theme.header_bg);
}

// ------------------------------------------------------------ form kit
//
// Focusable widgets for the editor pages (M9): a PURE reducer in the
// keymap.zig mold — movy-free, values stay with the caller, this only
// tracks focus + entry state. The tracker way: ARROWS always navigate
// (grid-wise over (row, col) positions), DIGITS type directly into a
// focused num field (commit on ENTER or focus move), ENTER activates
// buttons / begins-commits text edit. Text edit consumes every
// printable key and claims ESC (revert) — the caller must route keys
// here BEFORE the global ESC-quits rule and the keymap.

/// `cycle` is a BUTTON WHOSE LABEL IS ITS VALUE — the SIDS table's MODEL
/// and PAN switches, where pressing the thing walks a small ring instead
/// of doing something. ENTER still activates it like any button (the
/// caller walks its ring forward), and Shift+arrows STEP it either way:
/// a switch that only moves in one direction is the one control on the
/// page that does not answer to the LSDJ hand every value in DUET does.
pub const FormKind = enum { button, num, text, cycle };

/// One focusable element: caller's id + a grid position for arrow
/// navigation. Rows need not be dense; cols order widgets in a row.
pub const FormWidget = struct {
    id: u8,
    kind: FormKind,
    row: u8,
    col: u8,
};

pub const FormKey = union(enum) {
    up,
    down,
    left,
    right,
    enter,
    esc,
    backspace,
    char: u8,
    /// Shift+arrows on a num or cycle field (LSDJ-style): ±1 left/right,
    /// ±10 up/down. The caller owns the value, so this is an event ask.
    adjust: i16,
};

pub const FormEvent = union(enum) {
    none, // not consumed — let the keymap see it
    moved, // consumed: focus or entry state changed
    activated: u8, // button id (ENTER)
    num_commit: struct { id: u8, val: u32 }, // parsed entry; caller clamps
    num_adjust: struct { id: u8, delta: i16 }, // shift+arrows; caller clamps
    /// Shift+arrows on a `.cycle` switch: the SIGN is the direction the
    /// ring should walk, the MAGNITUDE the coarseness (±1 the arrow keys'
    /// fine step, ±10 up/down's). The caller owns the ring — this only
    /// says which way and how hard.
    cycled: struct { id: u8, delta: i16 },
    edit_begin: u8, // text field wants editing: call startEdit(current)
    text_commit: u8, // editText() holds the result
    text_cancel,
};

pub const TEXT_MAX = 26; // the IT song-name width

pub const Form = struct {
    widgets: []const FormWidget,
    focus: usize = 0,
    /// Bit per widget INDEX: 1 = not on screen right now, so the cursor
    /// must not be able to land there. The cockpit's SIDS table draws a
    /// parked chip's PAN switch nowhere at all, and a focus with nothing
    /// under it is an invisible cursor — you press RIGHT, the highlight
    /// vanishes, and the next ENTER acts on a widget you cannot see. The
    /// caller owns the rule (setHidden); the reducer only skips.
    /// 64 bits: the cockpit's duet form has 42 widgets, and while this
    /// was a u32 every switch past index 31 — DUST3/4 and all eight
    /// DUSK — could never be hidden, so a co-play's cursor walked onto
    /// undrawn synth switches and pressed their refusal (s122).
    hidden: u64 = 0,
    editing: bool = false,
    text_buf: [TEXT_MAX]u8 = @splat(' '),
    text_len: usize = 0,
    num_buf: [5]u8 = undefined,
    num_len: usize = 0,

    /// Clamped: a form can be REPLACED under a live focus (the cockpit
    /// swaps between the duet table and the buttons-only SWM one, and
    /// the duet table grew from ten widgets to nineteen with the SIDS
    /// rows). Every caller resets focus today; this makes the one that
    /// forgets a wrong highlight instead of a panic in a tracker.
    pub fn focused(self: *const Form) FormWidget {
        if (self.widgets.len == 0) return .{ .id = 0, .kind = .button, .row = 0, .col = 0 };
        return self.widgets[@min(self.focus, self.widgets.len - 1)];
    }

    pub fn isHidden(self: *const Form, i: usize) bool {
        return i < 64 and (self.hidden >> @intCast(i)) & 1 != 0;
    }

    /// Publish which widgets are off screen. If the focus is standing on
    /// one when the mask changes, it walks LEFT to the nearest visible
    /// widget in the same row (the row is what the user is reading), and
    /// only then anywhere — so a chip switched off from another row
    /// leaves the cursor on that chip's own MODEL switch rather than
    /// somewhere else entirely.
    pub fn setHidden(self: *Form, mask: u64) void {
        self.hidden = mask;
        if (self.widgets.len == 0 or !self.isHidden(self.focus)) return;
        const cur = self.focused();
        var fallback: ?usize = null;
        for (self.widgets, 0..) |w, i| {
            if (self.isHidden(i)) continue;
            if (w.row == cur.row and w.col <= cur.col) {
                self.focus = i; // rows are written left to right
                return;
            }
            if (fallback == null) fallback = i;
        }
        if (fallback) |f| self.focus = f;
    }

    /// Live num-entry digits ("" when idle) — show instead of the value.
    pub fn numEntry(self: *const Form) []const u8 {
        return self.num_buf[0..self.num_len];
    }

    pub fn editText(self: *const Form) []const u8 {
        return self.text_buf[0..self.text_len];
    }

    /// Begin text editing with the current value (answer to .edit_begin).
    pub fn startEdit(self: *Form, current: []const u8) void {
        self.editing = true;
        self.text_len = @min(current.len, TEXT_MAX);
        @memcpy(self.text_buf[0..self.text_len], current[0..self.text_len]);
    }

    pub fn key(self: *Form, k: FormKey) FormEvent {
        if (self.widgets.len == 0) return .none;
        if (self.editing) return self.editKey(k);
        const w = self.focused();
        switch (k) {
            .up => return self.move(-1, 0),
            .down => return self.move(1, 0),
            .left => return self.move(0, -1),
            .right => return self.move(0, 1),
            .enter => switch (w.kind) {
                .button, .cycle => return .{ .activated = w.id },
                .text => return .{ .edit_begin = w.id },
                .num => return self.commitNum() orelse .moved,
            },
            .backspace => if (w.kind == .num and self.num_len > 0) {
                self.num_len -= 1;
                return .moved;
            },
            .char => |ch| if (w.kind == .num and ch >= '0' and ch <= '9') {
                if (self.num_len < self.num_buf.len) {
                    self.num_buf[self.num_len] = ch;
                    self.num_len += 1;
                }
                return .moved;
            },
            .adjust => |d| switch (w.kind) {
                .num => {
                    self.num_len = 0; // a pending entry yields to the nudge
                    return .{ .num_adjust = .{ .id = w.id, .delta = d } };
                },
                .cycle => return .{ .cycled = .{ .id = w.id, .delta = d } },
                .button, .text => {},
            },
            .esc => {},
        }
        return .none;
    }

    fn editKey(self: *Form, k: FormKey) FormEvent {
        const id = self.focused().id;
        switch (k) {
            .enter => {
                self.editing = false;
                return .{ .text_commit = id };
            },
            .esc => {
                self.editing = false;
                return .text_cancel;
            },
            .backspace => {
                if (self.text_len > 0) self.text_len -= 1;
                return .moved;
            },
            .char => |ch| {
                if (ch >= 0x20 and ch < 0x7f and self.text_len < TEXT_MAX) {
                    self.text_buf[self.text_len] = ch;
                    self.text_len += 1;
                }
                return .moved;
            },
            // arrows are swallowed while editing (append-only entry)
            .up, .down, .left, .right, .adjust => return .moved,
        }
    }

    /// Grid move: vertical picks the nearest row in that direction
    /// (closest col wins inside it); horizontal stays in the row. A
    /// pending num entry commits first — the caller gets that event.
    /// Hidden widgets are not there at all: RIGHT off the last visible
    /// one stays put, and a vertical move lands on the nearest column
    /// that is actually drawn.
    fn move(self: *Form, dr: i8, dc: i8) FormEvent {
        const pending = self.commitNum();
        const cur = self.focused();
        var best: ?usize = null;
        for (self.widgets, 0..) |w, i| {
            if (i == self.focus or self.isHidden(i)) continue;
            if (dr != 0) {
                const below = w.row > cur.row;
                if ((dr > 0) != below or w.row == cur.row) continue;
                if (best) |b| {
                    const bw = self.widgets[b];
                    const better_row = if (dr > 0) w.row < bw.row else w.row > bw.row;
                    const same_row = w.row == bw.row;
                    const closer_col = absDiff(w.col, cur.col) < absDiff(bw.col, cur.col);
                    if (better_row or (same_row and closer_col)) best = i;
                } else best = i;
            } else {
                if (w.row != cur.row) continue;
                const right_of = w.col > cur.col;
                if ((dc > 0) != right_of) continue;
                if (best) |b| {
                    const bw = self.widgets[b];
                    const closer = if (dc > 0) w.col < bw.col else w.col > bw.col;
                    if (closer) best = i;
                } else best = i;
            }
        }
        if (best) |b| self.focus = b;
        return pending orelse .moved;
    }

    fn commitNum(self: *Form) ?FormEvent {
        if (self.focused().kind != .num or self.num_len == 0) return null;
        const val = std.fmt.parseInt(u32, self.num_buf[0..self.num_len], 10) catch 0;
        self.num_len = 0;
        return .{ .num_commit = .{ .id = self.focused().id, .val = val } };
    }
};

fn absDiff(a: u8, b: u8) u8 {
    return if (a > b) a - b else b - a;
}

// ---------------------------------------------------- rules and joins
//
// The house furniture, shared by every page that wants a chapter or a
// quiet separator. It lived in `projview` for one session (s60); the
// song screen wanted the same three things the day after, which is the
// usual sign that something belongs in the kit.

/// `── SETUP ─────────` — a page's inner chapter line. The rule glyphs
/// are furniture (`theme.section_rule`) and FADE toward the right edge:
/// a hairline dissolving into the dark reads as structure without
/// drawing a box around anything. The WORD is one colour in every
/// section (`theme.section_hdr`) — the identity colours (ice for the IT
/// half, ember for the SID half) belong to the ROWS that carry those
/// facts, and a heading borrowing one makes a page look coloured by
/// accident instead of by law (m64, s60).
pub fn sectionRule(c: *TextCanvas, x0: usize, y: usize, w: usize, word: []const u8) void {
    var i: usize = 0;
    while (i < w) : (i += 1) {
        const q = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(w -| 1, 1)));
        // theme.mix clamps, so everything left of the fade point is solid
        const f = (q - theme.section_fade) / (1.0 - theme.section_fade);
        c.put(x0 + i, y, 0x2500, theme.mix(theme.section_rule, theme.bg, f), theme.bg); // ─
    }
    if (word.len > 0) c.putStr(x0 + 2, y, word, theme.section_hdr, theme.bg);
}

/// The same hairline standing UP — the seam between two panels side by
/// side (the song screen's order list and its channel table). It fades
/// DOWNWARD for the same reason its twin fades right: the far end of a
/// rule is where the page stops having anything to say.
pub fn panelRule(c: *TextCanvas, x: usize, y0: usize, h: usize) void {
    var i: usize = 0;
    while (i < h) : (i += 1) {
        const q = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(h -| 1, 1)));
        const f = (q - theme.section_fade) / (1.0 - theme.section_fade);
        c.put(x, y0 + i, 0x2502, theme.mix(theme.section_rule, theme.bg, f), theme.bg); // │
    }
}

/// THE QUIET JOIN. `·` in the furniture colour where a formatted line
/// separates one fact from the next — the facts stay bright and the
/// punctuation recedes, which is the difference between a line you scan
/// and a line you read. `putStr` is byte-wise (it always has been), so a
/// middot cannot travel INSIDE a formatted string; this sentinel byte
/// can, and `putJoined` swaps it for the glyph at draw time. One byte,
/// one cell — every column downstream still lands where it was counted.
pub const DOT = " \x01 ";

pub fn putJoined(c: *TextCanvas, x: usize, y: usize, s: []const u8, fg: theme.Rgb) void {
    for (s, 0..) |b, i| {
        if (b == 1) {
            c.put(x + i, y, 0x00B7, theme.dots, theme.bg); // ·
        } else c.put(x + i, y, b, fg, theme.bg);
    }
}

/// A BUTTON IS A CHIP (XXVIII A2): `[ LABEL ]` is drawn as a tinted
/// ground the width of the bracketed word, and the brackets themselves
/// are inked IN THAT GROUND — the eye sees a chip, the text layer (every
/// dump, every test, every doc quoting `[ OPEN ]`) still says "button"
/// in the same cells. Focus is the one focus look (theme § ONE
/// "SELECTED" LANGUAGE).
pub fn button(c: *TextCanvas, x: usize, y: usize, label: []const u8, is_focused: bool) void {
    const fg = if (is_focused) theme.focus_fg else theme.text_bright;
    const bg = if (is_focused) theme.focus_bg else theme.button_bg;
    c.putStr(x, y, "[ ", bg, bg);
    c.putStr(x + 2, y, label, fg, bg);
    c.putStr(x + 2 + label.len, y, " ]", bg, bg);
}

/// The compact twin: `text` is already bracketed (`[CLEAR]`, `[OSC]`),
/// drawn on the chip ground with its first and last byte inked away.
/// `fg`/`bg` are the caller's (a chip can be lit, armed or refused);
/// pass `theme.button_bg` for a resting one.
pub fn chip(c: *TextCanvas, x: usize, y: usize, text: []const u8, fg: theme.Rgb, bg: theme.Rgb) void {
    if (text.len < 2 or text[0] != '[' or text[text.len - 1] != ']') {
        c.putStr(x, y, text, fg, bg);
        return;
    }
    c.put(x, y, '[', bg, bg);
    c.putStr(x + 1, y, text[1 .. text.len - 1], fg, bg);
    c.put(x + text.len - 1, y, ']', bg, bg);
}

/// A value chip, w cells wide: focused wears the focus look; OPEN for
/// typing it is the ice box with the pink caret (the TYPING look).
/// Value is padded/truncated to fit.
pub fn valueChip(
    c: *TextCanvas,
    x: usize,
    y: usize,
    w: usize,
    value: []const u8,
    is_focused: bool,
    is_editing: bool,
) void {
    const fg = if (is_editing) theme.cursor_fg else if (is_focused) theme.focus_fg else theme.text;
    const bg = if (is_editing) theme.type_bg else if (is_focused) theme.focus_bg else theme.header_bg;
    c.putRepeat(x, y, w, ' ', fg, bg);
    const n = @min(value.len, w);
    c.putStr(x, y, value[0..n], fg, bg);
    // the DUET pink — accent_hot vanished against the focus bg (m64)
    if (is_editing and n < w) c.put(x + n, y, 0x2588, theme.accent_pink, bg); // █
}

// ---------------------------------------------------------------- tests

const t = std.testing;

const TEST_WIDGETS = [_]FormWidget{
    .{ .id = 0, .kind = .text, .row = 0, .col = 0 }, // NAME
    .{ .id = 1, .kind = .button, .row = 1, .col = 0 }, // NEW
    .{ .id = 2, .kind = .button, .row = 1, .col = 1 }, // SAVE
    .{ .id = 3, .kind = .num, .row = 2, .col = 0 }, // SPEED
    .{ .id = 4, .kind = .num, .row = 2, .col = 1 }, // TEMPO
};

test "form: grid navigation walks rows and columns" {
    var f = Form{ .widgets = &TEST_WIDGETS };
    try t.expectEqual(@as(u8, 0), f.focused().id);
    _ = f.key(.down);
    try t.expectEqual(@as(u8, 1), f.focused().id);
    _ = f.key(.right);
    try t.expectEqual(@as(u8, 2), f.focused().id);
    _ = f.key(.down);
    try t.expectEqual(@as(u8, 4), f.focused().id); // closest col: TEMPO
    _ = f.key(.left);
    try t.expectEqual(@as(u8, 3), f.focused().id);
    _ = f.key(.down); // no row below: stay
    try t.expectEqual(@as(u8, 3), f.focused().id);
    _ = f.key(.up);
    _ = f.key(.up);
    _ = f.key(.up);
    try t.expectEqual(@as(u8, 0), f.focused().id);
}

test "form: buttons activate, unknown keys fall through" {
    var f = Form{ .widgets = &TEST_WIDGETS, .focus = 1 };
    const ev = f.key(.enter);
    try t.expectEqual(@as(u8, 1), ev.activated);
    try t.expectEqual(FormEvent.none, f.key(.{ .char = 'q' })); // keymap's
}

test "form: num entry accumulates, commits on enter and on move" {
    var f = Form{ .widgets = &TEST_WIDGETS, .focus = 3 };
    _ = f.key(.{ .char = '1' });
    _ = f.key(.{ .char = '2' });
    try t.expectEqualStrings("12", f.numEntry());
    _ = f.key(.backspace);
    _ = f.key(.{ .char = '5' });
    const ev = f.key(.enter);
    try t.expectEqual(@as(u32, 15), ev.num_commit.val);
    try t.expectEqual(@as(u8, 3), ev.num_commit.id);
    // commit-on-move: value event arrives, focus has already moved
    _ = f.key(.{ .char = '7' });
    const ev2 = f.key(.right);
    try t.expectEqual(@as(u32, 7), ev2.num_commit.val);
    try t.expectEqual(@as(u8, 4), f.focused().id);
}

test "form: shift-adjust nudges num fields, falls through elsewhere" {
    var f = Form{ .widgets = &TEST_WIDGETS, .focus = 3 };
    const ev = f.key(.{ .adjust = 10 });
    try t.expectEqual(@as(i16, 10), ev.num_adjust.delta);
    try t.expectEqual(@as(u8, 3), ev.num_adjust.id);
    // a pending digit entry yields to the nudge
    _ = f.key(.{ .char = '9' });
    _ = f.key(.{ .adjust = -1 });
    try t.expectEqualStrings("", f.numEntry());
    // buttons/text: not consumed
    f.focus = 1;
    try t.expectEqual(FormEvent.none, f.key(.{ .adjust = 1 }));
}

// The SIDS table's two switches are VALUES wearing a button's chrome, so
// they answer to both hands: ENTER walks the ring forward (all a button
// can say), Shift+arrows step it whichever way the arrow points. m64,
// session 59: "as opposed to pressing enter".
test "form: a cycle switch answers ENTER and shift-arrows both" {
    const ROWS = [_]FormWidget{
        .{ .id = 0, .kind = .cycle, .row = 0, .col = 0 }, // MODEL
        .{ .id = 1, .kind = .cycle, .row = 0, .col = 1 }, // PAN
        .{ .id = 2, .kind = .button, .row = 1, .col = 0 }, // SAVE
    };
    var f = Form{ .widgets = &ROWS };
    try t.expectEqual(@as(u8, 0), f.key(.enter).activated);
    const fine = f.key(.{ .adjust = -1 });
    try t.expectEqual(@as(i16, -1), fine.cycled.delta);
    try t.expectEqual(@as(u8, 0), fine.cycled.id);
    _ = f.key(.right);
    try t.expectEqual(@as(u8, 1), f.key(.{ .adjust = 1 }).cycled.id);
    try t.expectEqual(@as(i16, 10), f.key(.{ .adjust = 10 }).cycled.delta);
    // a plain button is not a value: the keymap still gets the key
    f.focus = 2;
    try t.expectEqual(FormEvent.none, f.key(.{ .adjust = 1 }));
}

test "form: text edit begins, commits, cancels, claims esc" {
    var f = Form{ .widgets = &TEST_WIDGETS };
    const beg = f.key(.enter);
    try t.expectEqual(@as(u8, 0), beg.edit_begin);
    f.startEdit("untitled");
    try t.expect(f.editing);
    _ = f.key(.backspace);
    _ = f.key(.{ .char = '!' });
    try t.expectEqualStrings("untitle!", f.editText());
    const ev = f.key(.enter);
    try t.expectEqual(@as(u8, 0), ev.text_commit);
    try t.expect(!f.editing);
    // cancel path
    _ = f.key(.enter);
    f.startEdit("abc");
    _ = f.key(.{ .char = 'x' });
    try t.expectEqual(FormEvent.text_cancel, f.key(.esc));
    try t.expect(!f.editing);
}

// A parked chip's PAN switch is drawn NOWHERE — the cockpit prints its
// parked-cell count over that spot instead. Focus must not be able to
// stand there: m64 walked RIGHT off an "off" chip and the highlight
// disappeared into a widget with no pixels.
test "form: hidden widgets are not there — no landing, no crossing" {
    const ROWS = [_]FormWidget{
        .{ .id = 0, .kind = .num, .row = 0, .col = 0 }, // IT COLS
        .{ .id = 1, .kind = .button, .row = 1, .col = 0 }, // chip 1 MODEL
        .{ .id = 2, .kind = .button, .row = 1, .col = 1 }, // chip 1 PAN
        .{ .id = 3, .kind = .button, .row = 2, .col = 0 }, // chip 2 MODEL
        .{ .id = 4, .kind = .button, .row = 2, .col = 1 }, // chip 2 PAN (off)
    };
    var f = Form{ .widgets = &ROWS, .focus = 3 };
    f.setHidden(1 << 4); // chip 2 is parked
    _ = f.key(.right); // RIGHT off its MODEL: nothing to reach
    try t.expectEqual(@as(u8, 3), f.focused().id);
    // DOWN from the live chip's PAN lands on the parked chip's MODEL —
    // its own row, the only field it has
    f.focus = 2;
    _ = f.key(.down);
    try t.expectEqual(@as(u8, 3), f.focused().id);
    // and UP from there goes back to something visible
    _ = f.key(.up);
    try t.expectEqual(@as(u8, 1), f.focused().id);
    // switching a chip off UNDER the focus re-homes it (same row first)
    f.focus = 4;
    f.setHidden(1 << 4);
    try t.expectEqual(@as(u8, 3), f.focused().id);
    // switching it back on makes the PAN reachable again
    f.setHidden(0);
    f.focus = 3;
    _ = f.key(.right);
    try t.expectEqual(@as(u8, 4), f.focused().id);
}

/// Right-edge scrollbar for a list: dim track, accent thumb sized and
/// placed proportionally. Draws nothing when everything is visible.
pub fn scrollbar(
    c: *TextCanvas,
    x: usize,
    y0: usize,
    h: usize,
    total: usize,
    visible: usize,
    offset: usize,
) void {
    if (total <= visible or h == 0) return;
    const th = @max((visible * h) / total, 1); // thumb height
    const range = h - th;
    const denom = total - visible;
    const ty = y0 + if (denom == 0) 0 else @min((offset * range + denom / 2) / denom, range);
    var y: usize = y0;
    while (y < y0 + h) : (y += 1)
        c.put(x, y, '│', theme.dots, theme.bg);
    y = ty;
    while (y < ty + th) : (y += 1)
        c.put(x, y, '█', theme.accent, theme.bg);
}

// A form can be REPLACED under a live focus — the cockpit swaps between
// the duet table and the buttons-only SWM one, and the duet table grew
// from ten widgets to nineteen when the SIDS rows landed. Every caller
// resets focus today; the clamp is what keeps the one that forgets from
// panicking a tracker mid-song.
test "form: focus survives a shrinking widget table" {
    const SMALL = [_]FormWidget{
        .{ .id = 7, .kind = .button, .row = 0, .col = 0 },
        .{ .id = 8, .kind = .button, .row = 0, .col = 1 },
    };
    var f = Form{ .widgets = &TEST_WIDGETS, .focus = TEST_WIDGETS.len - 1 };
    f.widgets = &SMALL; // the swap the cockpit does
    try std.testing.expectEqual(@as(u8, 8), f.focused().id);
    _ = f.key(.left); // and navigation still lands somewhere real
    try std.testing.expect(f.focus < f.widgets.len);

    // an empty table answers without indexing anything
    f.widgets = &.{};
    try std.testing.expectEqual(FormEvent.none, f.key(.enter));
}
