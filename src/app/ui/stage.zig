//! The stage — qartz's pixel layer: the three slots of the cart as pixel
//! art (two Game Boy carts and the SRAM on its little board), the PCB
//! bus that joins them to the host panel, and the data packets that run
//! along it during a transfer. Text (labels, the panel) is view.zig's.
//!
//! One pixel is half a text cell tall, so a card `ch` cells tall is
//! `2*ch` pixels: the cells-to-pixels map is x → x, y → 2y.

const std = @import("std");
const movy = @import("movy");
const theme = @import("theme.zig");
const motion = @import("motion.zig");
const state_mod = @import("state.zig");
const worker = @import("../../cart/worker.zig");

const V3 = movy.color.V3;
const v3 = movy.color.v3;
const Frame = movy.Frame;
const Slot = state_mod.Slot;

// ------------------------------------------------------------- layout

pub const Rect = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,

    pub fn cx(self: Rect) usize {
        return self.x + self.w / 2;
    }
};

pub const Layout = struct {
    cols: usize,
    rows: usize,
    /// The card art, in cells.
    cards: [3]Rect,
    /// The row the slot names sit on, right above the cards.
    label_y: usize,
    /// The bus's pixel row.
    bus_py: i32,
    /// The host panel's frame, in cells.
    host: Rect,
    /// Where the bus drops into the host panel (cell x).
    link_x: usize,
    hints_y: usize,
    /// The pixel logotype: top-left cell and scale (0 = no room for it).
    logo_y: usize = 0,
    logo_scale: usize = 0,

    /// The label plate inside a card — the cart's label recess, the
    /// SRAM's chip — in cells. view.zig fills it with text; the art is
    /// drawn around it from the same rectangle, so the two line up.
    pub fn plate(self: *const Layout, i: usize) Rect {
        const c = self.cards[i];
        if (i == 2) {
            const w = c.w * 58 / 100;
            const top = c.h * 38 / 100;
            const bot = c.h * 86 / 100;
            return .{ .x = c.x + (c.w - w) / 2, .y = c.y + top, .w = w, .h = bot -| top };
        }
        const px = c.w * 13 / 100 + 1;
        const top = c.h * 40 / 100;
        const bot = c.h * 84 / 100;
        return .{ .x = c.x + px, .y = c.y + top, .w = c.w -| 2 * px, .h = bot -| top };
    }
};

pub const HOST_H: usize = 6;

pub fn layout(cols: usize, rows: usize) Layout {
    const hints_y = rows - 1;
    const host_y = hints_y - HOST_H;
    const bus_rows: usize = 3;
    const top: usize = 3; // header, breathing row, slot names
    const avail = host_y -| (bus_rows + top);

    // a Game Boy cart is 57 x 65 mm: 0.88 wide per tall, and a cell is
    // two pixels tall, so a card `ch` cells tall is ~1.75*ch cells wide
    var ch: usize = @min(avail, 22);
    const gap_min: usize = 3;
    const cw_max = (cols -| 4 * gap_min) / 3;
    var cw: usize = ch * 176 / 100;
    if (cw > cw_max) {
        cw = cw_max;
        ch = @min(ch, cw * 100 / 176 + 1);
    }
    ch = @max(ch, 6);
    cw = @max(cw, 10);

    var extra = avail -| ch;
    // a tall window gets the logotype above the cards
    var logo_scale: usize = 0;
    var logo_rows: usize = 0;
    for ([_]usize{ 3, 2 }) |sc| {
        const lr = (LOGO_H * sc + 1) / 2 + 2; // the art, the subtitle, a gap
        if (extra >= lr + 2 and LOGO_W * sc + 4 <= cols) {
            logo_scale = sc;
            logo_rows = lr;
            break;
        }
    }
    extra -= logo_rows;
    const cards_y = top + logo_rows + extra / 3;
    const gap = (cols -| 3 * cw) / 4;
    const rem = (cols -| 3 * cw) - 4 * gap;
    var cards: [3]Rect = undefined;
    for (0..3) |i| {
        cards[i] = .{ .x = gap + rem / 2 + i * (cw + gap), .y = cards_y, .w = cw, .h = ch };
    }
    const host_x = @max(gap, 2);
    return .{
        .cols = cols,
        .rows = rows,
        .cards = cards,
        .label_y = cards_y - 1,
        .bus_py = @intCast((cards_y + ch) * 2 + (host_y - (cards_y + ch)) - 1),
        .host = .{ .x = host_x, .y = host_y, .w = cols - 2 * host_x, .h = HOST_H },
        .link_x = cards[1].cx(),
        .hints_y = hints_y,
        .logo_y = 2 + extra / 6,
        .logo_scale = logo_scale,
    };
}

// ------------------------------------------------------------- colours

pub fn toV3(c: theme.Rgb) V3 {
    return v3(
        @as(f32, @floatFromInt(c.r)) / 255.0,
        @as(f32, @floatFromInt(c.g)) / 255.0,
        @as(f32, @floatFromInt(c.b)) / 255.0,
    );
}

pub fn toRgb(c: V3) theme.Rgb {
    return .{
        .r = @intFromFloat(std.math.clamp(c.r, 0, 1) * 255),
        .g = @intFromFloat(std.math.clamp(c.g, 0, 1) * 255),
        .b = @intFromFloat(std.math.clamp(c.b, 0, 1) * 255),
    };
}

fn mix(a: V3, b: V3, t: f32) V3 {
    return a.scale(1 - t).add(b.scale(t));
}

/// The label plate's colour — view.zig fills the plate cells with it,
/// so text and art agree.
pub fn plateColour(lit: f32) V3 {
    const base = mix(theme.BG_BOT, toV3(theme.header_bg), 0.6);
    return mix(base.scale(0.6), mix(base, toV3(theme.accent), 0.10), lit);
}

fn bodyColour(lit: f32) V3 {
    const dark = mix(theme.BG_BOT, toV3(theme.dots), 0.30);
    return mix(dark.scale(0.7), mix(dark, toV3(theme.accent), 0.16), lit);
}

// ------------------------------------------------------------- the frame

/// How lit card `i` is this frame: the power-on sweep, left to right.
pub fn cardLit(st: *const state_mod.State, s: *const worker.Status, i: usize) f32 {
    if (!s.connected) return 0;
    const pt = st.power_anim.t(st.frame_no);
    const stagger = std.math.clamp(pt * 1.8 - @as(f32, @floatFromInt(i)) * 0.35, 0, 1);
    return motion.ease(.ease_out, stagger);
}

/// The plate's fill as text cells see it.
pub fn plateRgb(i: usize, lit: f32) theme.Rgb {
    const c = plateColour(lit);
    return toRgb(if (i == 2) c.scale(0.8) else c);
}

pub const Scene = struct {
    lay: *const Layout,
    st: *const state_mod.State,
    s: *const worker.Status,
};

pub fn draw(f: *Frame, sc: Scene) void {
    const now = sc.st.frame_no;
    background(f);

    // power-on: the cards light left to right when the cart arrives
    for (0..3) |i| {
        const lit = cardLit(sc.st, sc.s, i);
        const slot: Slot = @enumFromInt(i);
        const is_sel = slot == sc.st.slot;
        const sel_t: f32 = if (is_sel) motion.ease(.ease_out, sc.st.select_anim.t(now)) else 0;
        const busy_here = sc.s.busy and jobTouches(sc.s, slot);
        const r = sc.lay.cards[i];
        const x: i32 = @intCast(r.x);
        const y: i32 = @intCast(r.y * 2);
        const w: i32 = @intCast(r.w);
        const h: i32 = @intCast(r.h * 2);
        const pr = sc.lay.plate(i);
        const plate_px: PxRect = .{ .x = @intCast(pr.x), .y = @intCast(pr.y * 2), .w = @intCast(pr.w), .h = @intCast(pr.h * 2) };
        const style: CardStyle = .{
            .plate = plate_px,
            .lit = lit,
            .sel = sel_t,
            .busy = busy_here,
            .now = now,
            .empty = blk: {
                if (slot == .sram) break :blk false;
                const hb = sc.s.banks[i] orelse break :blk true;
                break :blk !hb.valid();
            },
        };
        if (slot == .sram) sramBoard(f, x, y, w, h, style) else cartridge(f, x, y, w, h, style);
    }

    bus(f, sc);
    if (sc.lay.logo_scale > 0) logo(f, sc.lay, sc.st.boot_anim, sc.st.frame_no);

    // a job's end flashes the glass: accent on success, red on failure
    const ft = sc.st.flash.t(now);
    if (ft < 1) {
        f.flash = 0.22 * (1 - motion.ease(.ease_out, ft));
        f.flash_col = if (sc.st.flash_ok) toV3(theme.accent_hot) else toV3(theme.mute_red);
    } else f.flash = 0;
}

fn jobTouches(s: *const worker.Status, slot: Slot) bool {
    const j = s.job orelse return false;
    return switch (j.kind) {
        .backup => true,
        else => (slot == .sram) == (j.mem == .sram) and (slot == .sram or j.bank == slot.bank()),
    };
}

/// A static gradient with a faint PCB dot grid — byte-identical every
/// frame, so the diff output never re-sends it.
fn background(f: *Frame) void {
    const H: usize = @intCast(f.h);
    const W: usize = @intCast(f.w);
    const dot = mix(theme.BG_BOT, toV3(theme.dots), 0.22);
    for (0..H) |yy| {
        const t = @as(f32, @floatFromInt(yy)) / @as(f32, @floatFromInt(@max(H - 1, 1)));
        const row = mix(theme.BG_TOP, theme.BG_BOT, t);
        const line = f.solid[yy * W ..][0..W];
        @memset(line, row);
        if (yy % 6 == 3) {
            var xx: usize = 4;
            while (xx < W) : (xx += 8) line[xx] = dot;
        }
    }
}

const PxRect = struct { x: i32, y: i32, w: i32, h: i32 };

const CardStyle = struct {
    plate: PxRect,
    lit: f32,
    sel: f32,
    busy: bool,
    empty: bool,
    now: u64,

    /// The edge light: brighter when selected, breathing while busy
    /// (stepped, so idle frames stay identical for the diff).
    fn edge(self: CardStyle) V3 {
        const base = toV3(theme.accent).scale(0.18 + 0.50 * self.lit);
        const hot = toV3(theme.accent_hot).scale(0.55 + 0.45 * self.lit);
        var c = mix(base, hot, self.sel);
        if (self.busy) {
            const step = @as(f32, @floatFromInt((self.now / 4) % 16)) / 16.0;
            c = c.scale(0.75 + 0.25 * @sin(step * std.math.tau));
        }
        return c;
    }
};

/// The Game Boy cartridge: notched top-right corner, grip ridges either
/// side of the embossed pill, the label recess, the arrow, the pins.
fn cartridge(f: *Frame, x: i32, y: i32, w: i32, h: i32, st: CardStyle) void {
    const body = bodyColour(st.lit);
    const notch_w = @max(2, @divTrunc(w, 7));
    const notch_h = @max(2, @divTrunc(h, 16));

    // body: two rects make the notch
    f.rect(x, y + notch_h, w, h - notch_h, body);
    f.rect(x, y, w - notch_w, notch_h, body);

    // grip ridges and the embossed pill
    const ridge = body.scale(0.55);
    const hi = mix(body, toV3(theme.accent), 0.25 + 0.25 * st.lit);
    const pill_x0 = x + @divTrunc(w * 26, 100);
    const pill_x1 = x + @divTrunc(w * 74, 100);
    const ry0 = y + @max(2, @divTrunc(h * 7, 100));
    const ry1 = y + @divTrunc(h * 25, 100);
    var ry = ry0;
    while (ry < ry1) : (ry += 2) {
        f.hline(x + 2, ry, pill_x0 - x - 3, ridge);
        f.hline(pill_x1 + 2, ry, x + w - 2 - (pill_x1 + 2) - (if (ry < y + notch_h) notch_w else 0), ridge);
    }
    // the pill: a rounded outline
    f.hline(pill_x0 + 1, ry0, pill_x1 - pill_x0 - 1, hi);
    f.hline(pill_x0 + 1, ry1 - 1, pill_x1 - pill_x0 - 1, hi);
    f.vline(pill_x0, ry0 + 1, ry1 - ry0 - 2, hi);
    f.vline(pill_x1, ry0 + 1, ry1 - ry0 - 2, hi);

    // the label recess: shadow above/left, light below/right
    const lx = st.plate.x;
    const lw = st.plate.w;
    const ly = st.plate.y;
    const lh = st.plate.h;
    f.rect(lx, ly, lw, lh, plateColour(st.lit));
    f.hline(lx - 1, ly - 1, lw + 2, body.scale(0.45));
    f.vline(lx - 1, ly, lh, body.scale(0.45));
    f.hline(lx - 1, ly + lh, lw + 2, mix(body, hi, 0.5));
    f.vline(lx + lw, ly, lh, mix(body, hi, 0.5));

    // the arrow below the label
    const ax = x + @divTrunc(w, 2);
    const ay = y + @divTrunc(h * 89, 100);
    const arrow_h: i32 = @max(2, @divTrunc(h, 14));
    var k: i32 = 0;
    while (k < arrow_h) : (k += 1) {
        const half = arrow_h - 1 - k;
        f.hline(ax - half, ay + k, 2 * half + 1, hi);
    }

    // the outline and its light: the step follows the notch
    const e = st.edge();
    const solid_edge = e.scale(0.9);
    f.hline(x, y, w - notch_w, solid_edge);
    f.vline(x + w - notch_w, y, notch_h, solid_edge);
    f.hline(x + w - notch_w, y + notch_h, notch_w, solid_edge);
    f.vline(x + w - 1, y + notch_h, h - notch_h, solid_edge);
    f.vline(x, y, h, solid_edge);
    f.hline(x, y + h - 1, w, solid_edge);
    glowOutline(f, x, y, w, h, notch_w, notch_h, e.scale(0.10 + 0.22 * st.sel + if (st.busy) @as(f32, 0.12) else 0));

    // the edge-connector pins along the bottom
    const pin = mix(toV3(theme.sid_hdr), body, 0.55 - 0.35 * st.lit);
    var px = x + @divTrunc(w * 14, 100);
    while (px < x + w - @divTrunc(w * 14, 100)) : (px += 2) f.vline(px, y + h - 3, 2, pin);

    // an empty or erased bank wears a diagonal hatch on its label
    if (st.empty and st.lit > 0) {
        var yy: i32 = 0;
        while (yy < lh) : (yy += 1) {
            var xx: i32 = @mod(yy, 6);
            while (xx < lw) : (xx += 6) f.px(lx + xx, ly + yy, mix(plateColour(st.lit), hi, 0.25));
        }
    }
}

/// The SRAM: a DIP chip and its coin cell on a little board.
fn sramBoard(f: *Frame, x: i32, y: i32, w: i32, h: i32, st: CardStyle) void {
    const board = mix(bodyColour(st.lit), toV3(theme.solo_green), 0.06 * st.lit);
    f.rect(x + 1, y + 1, w - 2, h - 2, board);
    // traces on the board
    const trace = mix(board, toV3(theme.accent), 0.20 + 0.15 * st.lit);
    var ty = y + 4;
    while (ty < y + h - 4) : (ty += 5) {
        f.hline(x + 3, ty, @divTrunc(w, 6), trace);
        f.hline(x + w - 3 - @divTrunc(w, 6), ty + 2, @divTrunc(w, 6), trace);
    }

    // the chip: dark body, silver legs both sides, the pin-1 notch
    const cw = st.plate.w;
    const cx = st.plate.x;
    const cy = st.plate.y;
    const ch = st.plate.h;
    const leg = mix(toV3(theme.text_dim), board, 0.5 - 0.3 * st.lit);
    var ly = cy + 2;
    while (ly < cy + ch - 1) : (ly += 3) {
        f.hline(cx - 2, ly, 2, leg);
        f.hline(cx + cw, ly, 2, leg);
    }
    f.rect(cx, cy, cw, ch, plateColour(st.lit).scale(0.8));
    f.rect(cx + @divTrunc(cw, 2) - 2, cy, 4, 1, board);

    // the coin cell: a glowing ring
    const bx: f32 = @floatFromInt(x + @divTrunc(w, 2));
    const by: f32 = @floatFromInt(y + @divTrunc(h * 20, 100));
    const br: f32 = @floatFromInt(@max(2, @divTrunc(h, 9)));
    const cell = mix(toV3(theme.text_dim), toV3(theme.text_bright), 0.4 * st.lit);
    ring(f, bx, by, br, cell);
    f.gring(bx, by, br, toV3(theme.accent).scale(0.05 + 0.10 * st.lit));

    // outline like the carts (no notch)
    const e = st.edge();
    f.rectOutline(x, y, w, h, e.scale(0.9));
    glowOutline(f, x, y, w, h, 0, 0, e.scale(0.10 + 0.22 * st.sel + if (st.busy) @as(f32, 0.12) else 0));
}

fn ring(f: *Frame, cx: f32, cy: f32, r: f32, c: V3) void {
    const steps: usize = @intFromFloat(@max(12, r * 8));
    for (0..steps) |i| {
        const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * std.math.tau;
        f.px(@intFromFloat(@round(cx + @cos(a) * r)), @intFromFloat(@round(cy + @sin(a) * r)), c);
    }
}

fn glowOutline(f: *Frame, x: i32, y: i32, w: i32, h: i32, nw: i32, nh: i32, c: V3) void {
    f.ghline(x, y, w - nw, c);
    f.ghline(x, y + h - 1, w, c);
    f.gvline(x, y, h, c);
    f.gvline(x + w - 1, y + nh, h - nh, c);
    if (nw > 0) {
        f.gvline(x + w - nw, y, nh, c);
        f.ghline(x + w - nw, y + nh, nw, c);
    }
}

// ------------------------------------------------------------- the bus

const Point = struct { x: i32, y: i32 };

/// The route a transfer takes: host → bus → the slot's pins.
fn route(lay: *const Layout, slot: usize, out: *[4]Point) []Point {
    const card = lay.cards[slot];
    const cx: i32 = @intCast(card.cx());
    const card_bot: i32 = @intCast((card.y + card.h) * 2);
    const host_top: i32 = @intCast(lay.host.y * 2 - 1);
    const lx: i32 = @intCast(lay.link_x);
    out[0] = .{ .x = lx, .y = host_top };
    out[1] = .{ .x = lx, .y = lay.bus_py };
    out[2] = .{ .x = cx, .y = lay.bus_py };
    out[3] = .{ .x = cx, .y = card_bot };
    return out[0..4];
}

fn routeLen(pts: []const Point) f32 {
    var n: f32 = 0;
    for (pts[0 .. pts.len - 1], pts[1..]) |a, b|
        n += @floatFromInt(@abs(b.x - a.x) + @abs(b.y - a.y));
    return n;
}

/// The point `d` pixels along the route.
fn along(pts: []const Point, d: f32) Point {
    var left = d;
    for (pts[0 .. pts.len - 1], pts[1..]) |a, b| {
        const seg: f32 = @floatFromInt(@abs(b.x - a.x) + @abs(b.y - a.y));
        if (left <= seg or seg == 0) {
            const t = if (seg == 0) 0 else left / seg;
            return .{
                .x = a.x + @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(b.x - a.x)) * t))),
                .y = a.y + @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(b.y - a.y)) * t))),
            };
        }
        left -= seg;
    }
    return pts[pts.len - 1];
}

fn segment(f: *Frame, a: Point, b: Point, c: V3, glow: ?V3) void {
    if (a.x == b.x) {
        const y0 = @min(a.y, b.y);
        const n = @abs(b.y - a.y) + 1;
        f.vline(a.x, y0, @intCast(n), c);
        if (glow) |g| f.gvline(a.x, y0, @intCast(n), g);
    } else {
        const x0 = @min(a.x, b.x);
        const n = @abs(b.x - a.x) + 1;
        f.hline(x0, a.y, @intCast(n), c);
        if (glow) |g| f.ghline(x0, a.y, @intCast(n), g);
    }
}

fn bus(f: *Frame, sc: Scene) void {
    const lay = sc.lay;
    const lit: f32 = if (sc.s.connected) 1 else 0.35;
    const trace = mix(theme.BG_BOT, toV3(theme.accent), 0.22 * lit);

    // the trunk under all three slots, each slot's drop, the host link
    const x0: i32 = @intCast(lay.cards[0].cx());
    const x1: i32 = @intCast(lay.cards[2].cx());
    f.hline(x0, lay.bus_py, x1 - x0 + 1, trace);
    for (lay.cards) |card| {
        const cx: i32 = @intCast(card.cx());
        const bot: i32 = @intCast((card.y + card.h) * 2);
        f.vline(cx, bot, lay.bus_py - bot, trace);
        // a via where the drop meets the trunk
        f.px(cx - 1, lay.bus_py, trace.scale(1.4));
        f.px(cx + 1, lay.bus_py, trace.scale(1.4));
    }
    const host_top: i32 = @intCast(lay.host.y * 2 - 1);
    f.vline(@intCast(lay.link_x), lay.bus_py, host_top - lay.bus_py + 1, trace);

    // the selected (or working) slot's route lights up
    const sel: usize = blk: {
        if (sc.s.busy) if (sc.s.job) |j| {
            if (j.kind == .backup) {
                // backup walks bank1, bank2, sram
                break :blk @min(2, sc.s.step -| 1);
            }
            break :blk if (j.mem == .sram) 2 else j.bank - 1;
        };
        break :blk @intFromEnum(sc.st.slot);
    };
    var buf: [4]Point = undefined;
    const pts = route(lay, sel, &buf);
    const hot = toV3(theme.accent_hot);
    const active = if (sc.s.busy) mix(trace, hot, 0.55) else mix(trace, toV3(theme.accent), 0.45 * lit);
    const glow_c: ?V3 = if (sc.s.busy) hot.scale(0.05) else if (sc.s.connected) toV3(theme.accent).scale(0.025) else null;
    for (pts[0 .. pts.len - 1], pts[1..]) |a, b| segment(f, a, b, active, glow_c);

    if (!sc.s.busy) return;

    // packets: bright heads riding the route, their trails are the glow
    // buffer's persistence. Reads flow cart → host, writes host → cart.
    const len = routeLen(pts);
    const toward_cart = if (sc.s.job) |j| (j.kind == .write and sc.s.phase == .writing) else false;
    const t = @as(f32, @floatFromInt(sc.st.frame_no)) / 60.0;
    const speed: f32 = 0.55; // route lengths per second
    const n_packets: usize = @max(4, @as(usize, @intFromFloat(len / 6)));
    for (0..n_packets) |i| {
        var p = @mod(t * speed + @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n_packets)), 1.0);
        if (!toward_cart) p = 1 - p;
        const pt = along(pts, p * len);
        f.px(pt.x, pt.y, toV3(theme.text_bright));
        f.gpx(pt.x, pt.y, hot.scale(0.9));
        f.gpx(pt.x - 1, pt.y, hot.scale(0.25));
        f.gpx(pt.x + 1, pt.y, hot.scale(0.25));
        f.gpx(pt.x, pt.y - 1, hot.scale(0.25));
        f.gpx(pt.x, pt.y + 1, hot.scale(0.25));
    }
}

// ------------------------------------------------------------- the logotype

pub const LOGO_W: usize = 5 * 5 + 4 * 2; // five 5-wide letters, 2-wide gaps
pub const LOGO_H: usize = 7;

const GLYPHS = [5][7]*const [5]u8{
    .{ ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#" }, // Q
    .{ ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" }, // A
    .{ "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" }, // R
    .{ "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.." }, // T
    .{ "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####" }, // Z
};

/// Q A R T Z in fat pixels: a top-to-bottom ramp from the hot accent
/// into the scheme's second colour, with a steady bloom under it.
pub fn logoRect(lay: *const Layout) Rect {
    const sc = lay.logo_scale;
    const w = LOGO_W * sc;
    return .{ .x = (lay.cols -| w) / 2, .y = lay.logo_y, .w = w, .h = (LOGO_H * sc + 1) / 2 };
}

fn logo(f: *Frame, lay: *const Layout, boot: motion.Anim, now: u64) void {
    const sc: i32 = @intCast(lay.logo_scale);
    const r = logoRect(lay);
    const x0: i32 = @intCast(r.x);
    // the boot: it slides down from above the screen, a step at a time
    // like a ROM's boot logo, and blooms when it lands
    const bt = boot.t(now);
    const land: i32 = @intCast(r.y * 2);
    const travel: f32 = @floatFromInt(land + @as(i32, @intCast(LOGO_H)) * sc + 4);
    const y0: i32 = land - @as(i32, @intFromFloat(@floor((1 - motion.ease(.linear, @min(1, bt * 1.25))) * travel / 2) * 2));
    const bloom: f32 = if (bt >= 0.8 and bt < 1) (1 - (bt - 0.8) / 0.2) * 0.35 else 0;
    const top = toV3(theme.accent_hot);
    const bot = theme.LOGO_PINK;
    for (GLYPHS, 0..) |g, li| {
        const gx = x0 + @as(i32, @intCast(li)) * 7 * sc;
        for (g, 0..) |row, ry| {
            const t = @as(f32, @floatFromInt(ry)) / 6.0;
            const col = mix(top, bot, t);
            for (row, 0..) |cell, rx| {
                if (cell != '#') continue;
                const px = gx + @as(i32, @intCast(rx)) * sc;
                const py = y0 + @as(i32, @intCast(ry)) * sc;
                f.rect(px, py, sc, sc, col);
                f.grect(px, py, sc, sc, col.scale(0.06 + bloom));
            }
        }
    }
}
