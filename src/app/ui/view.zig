//! The text layer: header, slot names, the label plates, the host
//! panel, key hints and the overlays. Drawn over the stage's pixels
//! every frame (cells with ch == 0 let the pixels through).

const std = @import("std");
const theme = @import("theme.zig");
const widgets = @import("widgets.zig");
const motion = @import("motion.zig");
const stage = @import("stage.zig");
const state_mod = @import("state.zig");
const filedialog = @import("filedialog.zig");
const TextCanvas = @import("canvas.zig").TextCanvas;
const config = @import("../config.zig");
const proto = @import("../../cart/protocol.zig");
const rom = @import("../../cart/rom.zig");
const worker = @import("../../cart/worker.zig");

const Rgb = theme.Rgb;
const State = state_mod.State;
const Slot = state_mod.Slot;

pub const View = struct {
    lay: *const stage.Layout,
    st: *State,
    s: *const worker.Status,
    dlg: *filedialog.FileDialog,
    cfg: *const config.Config,
};

/// UTF-8 aware put (one cell per codepoint — every glyph used here is
/// single-width). Returns the cells written.
pub fn text(c: *TextCanvas, x: usize, y: usize, s: []const u8, fg: Rgb, bg: Rgb) usize {
    var it = (std.unicode.Utf8View.init(s) catch {
        c.putStr(x, y, s, fg, bg);
        return s.len;
    }).iterator();
    var i: usize = 0;
    while (it.nextCodepoint()) |cp| : (i += 1) c.put(x + i, y, cp, fg, bg);
    return i;
}

pub fn cells(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

fn centered(c: *TextCanvas, cx: usize, y: usize, s: []const u8, fg: Rgb, bg: Rgb) void {
    const n = cells(s);
    _ = text(c, cx -| n / 2, y, s, fg, bg);
}

/// Fit `s` into `max` cells (ASCII-safe: titles and paths), with a
/// trailing '~' when cut.
fn fit(s: []const u8, max: usize, buf: []u8) []const u8 {
    if (s.len <= max) return s;
    if (max == 0) return "";
    const n = @min(max - 1, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = '~';
    return buf[0 .. n + 1];
}

/// $HOME → '~', long paths keep their tail.
pub fn shortPath(path: []const u8, max: usize, buf: []u8) []const u8 {
    var hbuf: [std.fs.max_path_bytes]u8 = undefined;
    var p = path;
    var pre: []const u8 = "";
    if (config.homeDir(&hbuf)) |home| {
        if (home.len > 1 and std.mem.startsWith(u8, p, home)) {
            pre = "~";
            p = p[home.len..];
        }
    }
    if (pre.len + p.len <= max) return std.fmt.bufPrint(buf, "{s}{s}", .{ pre, p }) catch path;
    if (max < 5) return "";
    return std.fmt.bufPrint(buf, "...{s}", .{p[p.len - (max - 3) ..]}) catch path;
}

pub fn draw(c: *TextCanvas, v: View) void {
    header(c, v);
    if (v.lay.logo_scale > 0) {
        const r = stage.logoRect(v.lay);
        centered(c, v.lay.cols / 2, r.y + r.h + 1, "EMS 64M \u{00B7} GAME BOY FLASH CART \u{00B7} USB", theme.text_dim, theme.bg);
    }
    slotNames(c, v);
    for (0..3) |i| plate(c, v, i);
    host(c, v);
    hints(c, v);

    switch (v.st.modal) {
        .none => {},
        .file => {
            filedialog.FileDialog.setDrawConfig(v.cfg);
            v.dlg.draw(c, v.st);
        },
        .confirm => confirm(c, v),
        .help => help(c, v),
        .quit => quitBox(c, v),
    }
}

// ------------------------------------------------------------- header

fn header(c: *TextCanvas, v: View) void {
    c.fillRow(0, theme.text, theme.header_bg);
    c.put(1, 0, '\u{25C6}', theme.accent_hot, theme.header_bg);
    c.putStr(3, 0, "QARTZ", theme.text_bright, theme.header_bg);
    c.putStr(9, 0, "EMS 64M FLASHER", theme.text_dim, theme.header_bg);

    // right: connection chip, the device, the scheme
    var x = c.w;
    const scheme = theme.SCHEMES[theme.active].name;
    x -= scheme.len + 1;
    c.putStr(x, 0, scheme, theme.text_dim, theme.header_bg);
    x -= 3;
    if (v.s.device_label.len > 0 and std.mem.eql(u8, v.s.device_label, "FAKE CART")) {
        x -= v.s.device_label.len;
        c.putStr(x, 0, v.s.device_label, theme.accent_pink, theme.header_bg);
        x -= 3;
    }
    const chip: struct { dot: u21, col: Rgb, word: []const u8 } = if (!v.s.connected)
        .{ .dot = '\u{25CB}', .col = theme.mute_red, .word = "NO CART" }
    else if (v.s.busy)
        .{ .dot = '\u{25CF}', .col = if (v.st.blink_on) theme.accent_hot else theme.accent, .word = "WORKING" }
    else
        .{ .dot = '\u{25CF}', .col = theme.solo_green, .word = "CART READY" };
    x -= chip.word.len;
    c.putStr(x, 0, chip.word, theme.text, theme.header_bg);
    c.put(x - 2, 0, chip.dot, chip.col, theme.header_bg);
}

// ------------------------------------------------------------- the slots

fn slotNames(c: *TextCanvas, v: View) void {
    for (0..3) |i| {
        const slot: Slot = @enumFromInt(i);
        const cx = v.lay.cards[i].cx();
        const y = v.lay.label_y;
        if (slot == v.st.slot) {
            var buf: [24]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "\u{25B8} {s} \u{25C2}", .{slot.label()}) catch slot.label();
            centered(c, cx, y, s, theme.accent_hot, theme.bg);
        } else {
            centered(c, cx, y, slot.label(), theme.text_dim, theme.bg);
        }
    }
}

fn plate(c: *TextCanvas, v: View, i: usize) void {
    const r = v.lay.plate(i);
    if (r.w < 4 or r.h < 1) return;
    const lit = stage.cardLit(v.st, v.s, i);
    const bg = stage.plateRgb(i, lit);
    for (0..r.h) |dy| c.putRepeat(r.x, r.y + dy, r.w, ' ', theme.text, bg);

    var lines: [5]struct { s: []const u8, fg: Rgb } = undefined;
    var n: usize = 0;
    var b0: [48]u8 = undefined;
    var b1: [48]u8 = undefined;
    var b2: [48]u8 = undefined;
    var sb: [16]u8 = undefined;
    var rb: [16]u8 = undefined;
    const inner = r.w -| 2;

    if (!v.s.connected) {
        lines[0] = .{ .s = if (i == 1) "NO CART" else "\u{2014}", .fg = theme.value_off };
        n = 1;
    } else if (i == 2) {
        lines[0] = .{ .s = "SRAM", .fg = theme.text_bright };
        lines[1] = .{ .s = rom.sizeText(proto.SRAM_SIZE, &sb), .fg = theme.text };
        lines[2] = .{ .s = "SAVES", .fg = theme.text_dim };
        n = if (r.h >= 4) 3 else 2;
    } else if (v.s.banks[i]) |h| {
        if (h.valid()) {
            lines[0] = .{ .s = fit(if (h.title().len > 0) h.title() else "UNTITLED", inner, &b0), .fg = theme.text_bright };
            lines[1] = .{ .s = std.fmt.bufPrint(&b1, "{s} \u{00B7} {s}", .{ rom.sizeText(h.rom_size, &sb), mbcShort(h.cart_type) }) catch "", .fg = theme.text };
            const cgb: []const u8 = switch (h.cgb) {
                .dmg => "DMG",
                .cgb_enhanced => "GBC",
                .cgb_only => "GBC ONLY",
            };
            const with_ram = std.fmt.bufPrint(&b2, "{s} \u{00B7} RAM {s}", .{ cgb, rom.sizeText(h.ram_size, &rb) }) catch cgb;
            // a narrow plate drops the RAM size rather than cutting it
            lines[2] = .{ .s = if (h.ram_size > 0 and cells(with_ram) <= inner) with_ram else cgb, .fg = theme.text_dim };
            n = 3;
        } else {
            lines[0] = .{ .s = "EMPTY", .fg = theme.text };
            lines[1] = .{ .s = "no ROM", .fg = theme.text_dim };
            n = 2;
        }
    } else {
        lines[0] = .{ .s = "UNREADABLE", .fg = theme.mute_red };
        n = 1;
    }

    // vertically centred; a short plate keeps the first lines
    const shown = @min(n, r.h);
    const y0 = r.y + (r.h - shown) / 2;
    for (lines[0..shown], 0..) |ln, k| {
        var fb: [48]u8 = undefined;
        const s = if (cells(ln.s) > inner) fit(ln.s, inner, &fb) else ln.s;
        centered(c, r.cx(), y0 + k, s, ln.fg, bg);
    }
}

/// The mapper without its +RAM+BATT tail (the plate is narrow).
fn mbcShort(t: u8) []const u8 {
    const full = rom.cartTypeName(t);
    const plus = std.mem.indexOfScalar(u8, full, '+') orelse return full;
    return full[0..plus];
}

// ------------------------------------------------------------- the host

fn host(c: *TextCanvas, v: View) void {
    const r = v.lay.host;
    const s = v.s;
    var tb: [48]u8 = undefined;
    const title: []const u8 = blk: {
        if (s.busy) if (s.job) |j| {
            const what = targetName(j);
            break :blk switch (j.kind) {
                .backup => std.fmt.bufPrint(&tb, " BACKUP {d}/3 \u{00B7} {s} ", .{ s.step, phaseWord(s.phase) }) catch " BACKUP ",
                .read => std.fmt.bufPrint(&tb, " READING {s} ", .{what}) catch " READING ",
                .write => switch (s.phase) {
                    .verifying => std.fmt.bufPrint(&tb, " VERIFYING {s} ", .{what}) catch " VERIFYING ",
                    else => std.fmt.bufPrint(&tb, " {s} {s} ", .{ if (j.mem == .rom) "FLASHING" else "WRITING", what }) catch " WRITING ",
                },
            };
        };
        break :blk if (s.connected) " READY " else " WAITING FOR CART ";
    };
    widgets.frame(c, r.x, r.y, r.w, r.h, "");
    _ = text(c, r.x + 3, r.y, title, theme.text_bright, theme.header_bg);

    const x = r.x + 3;
    const w = r.w -| 6;
    if (s.busy) {
        busyRows(c, v, x, r.y + 1, w);
        return;
    }

    if (!s.connected) {
        _ = text(c, x, r.y + 1, "Plug in the EMS 64M cart \u{2014} qartz picks it up by itself.", theme.text, theme.bg);
        if (s.conn_err.len > 0)
            _ = text(c, x, r.y + 2, s.conn_err.slice(), theme.mute_red, theme.bg)
        else
            _ = text(c, x, r.y + 2, "USB hubs are fine. No driver needed on macOS.", theme.text_dim, theme.bg);
    } else {
        actionRow(c, v, x, r.y + 1, w);
        slotDetail(c, v, x, r.y + 2, w);
    }
    toastRows(c, v, x, r.y + 3, w);
}

fn phaseWord(p: worker.Phase) []const u8 {
    return switch (p) {
        .idle => "STARTING",
        .reading => "READING",
        .writing => "WRITING",
        .verifying => "VERIFYING",
    };
}

fn targetName(j: worker.Request) []const u8 {
    if (j.kind == .backup) return "EVERYTHING";
    if (j.mem == .sram) return "SRAM";
    return if (j.bank == 1) "BANK 1" else "BANK 2";
}

/// `[r] READ  BANK 1 ▸ FILE   [w] WRITE  FILE ▸ BANK 1   [b] BACKUP`,
/// or the short form when the panel is narrow.
fn actionRow(c: *TextCanvas, v: View, x0: usize, y: usize, w: usize) void {
    var x = x0;
    const sl = v.st.slot.label();
    if (w < 80) {
        x += key(c, x, y, "r");
        x += text(c, x, y, " READ   ", theme.text, theme.bg);
        x += key(c, x, y, "w");
        x += text(c, x, y, " WRITE   ", theme.text, theme.bg);
        x += key(c, x, y, "b");
        x += text(c, x, y, " BACKUP   ", theme.text, theme.bg);
        if (x + sl.len + 2 < x0 + w) _ = text(c, x0 + w - sl.len, y, sl, theme.text_bright, theme.bg);
        return;
    }
    x += key(c, x, y, "r");
    x += text(c, x, y, " READ ", theme.text, theme.bg);
    x += text(c, x, y, sl, theme.text_bright, theme.bg);
    x += text(c, x, y, " \u{25B8} file", theme.text_dim, theme.bg);
    x += 4;
    x += key(c, x, y, "w");
    x += text(c, x, y, " WRITE ", theme.text, theme.bg);
    x += text(c, x, y, "file \u{25B8} ", theme.text_dim, theme.bg);
    x += text(c, x, y, sl, theme.text_bright, theme.bg);
    x += 4;
    x += key(c, x, y, "b");
    x += text(c, x, y, " BACKUP ", theme.text, theme.bg);
    _ = text(c, x, y, "all \u{25B8} folder", theme.text_dim, theme.bg);
}

fn key(c: *TextCanvas, x: usize, y: usize, k: []const u8) usize {
    c.put(x, y, '[', theme.text_dim, theme.bg);
    const n = text(c, x + 1, y, k, theme.accent_hot, theme.bg);
    c.put(x + 1 + n, y, ']', theme.text_dim, theme.bg);
    return n + 2;
}

fn slotDetail(c: *TextCanvas, v: View, x: usize, y: usize, w: usize) void {
    var buf: [160]u8 = undefined;
    const line: []const u8 = switch (v.st.slot) {
        .sram => "128K battery-backed save RAM \u{00B7} shared by both banks",
        else => blk: {
            const h = v.s.banks[@intFromEnum(v.st.slot)] orelse break :blk "this bank's header could not be read";
            if (!h.valid()) break :blk "empty \u{00B7} no valid ROM header \u{00B7} ready to flash";
            var sb: [16]u8 = undefined;
            var rb: [16]u8 = undefined;
            break :blk std.fmt.bufPrint(&buf, "{s} \u{00B7} {s} \u{00B7} {s}{s}{s} \u{00B7} header checksum OK", .{
                if (h.title().len > 0) h.title() else "untitled",
                rom.sizeText(h.rom_size, &sb),
                h.typeName(),
                if (h.ram_size > 0) " \u{00B7} RAM " else "",
                if (h.ram_size > 0) rom.sizeText(h.ram_size, &rb) else "",
            }) catch "";
        },
    };
    var fb: [160]u8 = undefined;
    _ = text(c, x, y, if (cells(line) > w) fit(line, w, &fb) else line, theme.text_dim, theme.bg);
}

fn toastRows(c: *TextCanvas, v: View, x: usize, y: usize, w: usize) void {
    const t = v.st.toast orelse return;
    const k = t.anim.t(v.st.frame_no);
    // fade in from the ground colour
    const ink = if (t.ok) theme.solo_green else theme.mute_red;
    const col = lerp(theme.bg, ink, motion.ease(.ease_out, k));
    c.put(x, y, if (t.ok) '\u{2713}' else '\u{2717}', col, theme.bg);
    var fb: [200]u8 = undefined;
    const m = t.text.slice();
    _ = text(c, x + 2, y, if (m.len > w -| 2) fit(m, w -| 2, &fb) else m, lerp(theme.bg, theme.text_bright, k), theme.bg);
    if (t.detail.len > 0) {
        const d = t.detail.slice();
        _ = text(c, x + 2, y + 1, if (cells(d) > w -| 2) fit(d, w -| 2, &fb) else d, lerp(theme.bg, theme.text_dim, k), theme.bg);
    }
}

fn lerp(a: Rgb, b: Rgb, t: f32) Rgb {
    const u = std.math.clamp(t, 0, 1);
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(a.r)) * (1 - u) + @as(f32, @floatFromInt(b.r)) * u),
        .g = @intFromFloat(@as(f32, @floatFromInt(a.g)) * (1 - u) + @as(f32, @floatFromInt(b.g)) * u),
        .b = @intFromFloat(@as(f32, @floatFromInt(a.b)) * (1 - u) + @as(f32, @floatFromInt(b.b)) * u),
    };
}

fn busyRows(c: *TextCanvas, v: View, x: usize, y: usize, w: usize) void {
    const s = v.s;
    const j = s.job orelse return;

    // row 1: what goes where
    var pb: [160]u8 = undefined;
    var lb: [200]u8 = undefined;
    const p = shortPath(j.path(), w -| 24, &pb);
    const line = switch (j.kind) {
        .read => std.fmt.bufPrint(&lb, "{s} \u{25B8} {s}", .{ targetName(j), p }) catch "",
        .write => std.fmt.bufPrint(&lb, "{s} \u{25B8} {s}", .{ p, targetName(j) }) catch "",
        .backup => std.fmt.bufPrint(&lb, "BANK 1 + BANK 2 + SRAM \u{25B8} {s}", .{p}) catch "",
    };
    _ = text(c, x, y, line, theme.text, theme.bg);

    // row 2: the bar, eighth-block smooth
    const pct = std.fmt.bufPrint(&pb, " {d:>3}%", .{@as(u32, @intFromFloat(s.fraction() * 100))}) catch "";
    const bar_w = w -| pct.len;
    progressBar(c, x, y + 1, bar_w, s.fraction());
    c.putStr(x + bar_w, y + 1, pct, theme.text_bright, theme.bg);

    // row 3: numbers
    const now = std.time.nanoTimestamp();
    const secs = @as(f64, @floatFromInt(now - s.started_ns)) / std.time.ns_per_s;
    var db: [16]u8 = undefined;
    var tb: [16]u8 = undefined;
    const rate = if (secs > 0.3 and s.phase != .idle) @as(f64, @floatFromInt(s.done)) / secs else 0;
    var eb: [24]u8 = undefined;
    const eta: []const u8 = if (rate > 0 and s.total > s.done) blk: {
        const left: u64 = @intFromFloat(@as(f64, @floatFromInt(s.total - s.done)) / rate);
        break :blk std.fmt.bufPrint(&eb, "{d}:{d:0>2} left", .{ left / 60, left % 60 }) catch "";
    } else "";
    const nums = std.fmt.bufPrint(&lb, "{s} / {s}   {d:.1} KB/s   {s}", .{
        rom.sizeText(s.done, &db), rom.sizeText(s.total, &tb), rate / 1024.0, eta,
    }) catch "";
    _ = text(c, x, y + 2, nums, theme.text_dim, theme.bg);
    const esc_hint = "esc cancel";
    c.putStr(x + w -| esc_hint.len, y + 2, esc_hint, theme.text_dim, theme.bg);

    // row 4: a write's cancel needs saying twice
    if (v.st.cancel_armed_at != null) {
        const warn = if (j.mem == .rom)
            "ESC again aborts \u{2014} the bank is left half-flashed"
        else
            "ESC again aborts \u{2014} the SRAM is left half-written";
        _ = text(c, x, y + 3, warn, theme.mute_red, theme.bg);
    }
}

pub fn progressBar(c: *TextCanvas, x: usize, y: usize, w: usize, f: f32) void {
    const eighths = [_]u21{ ' ', '\u{258F}', '\u{258E}', '\u{258D}', '\u{258C}', '\u{258B}', '\u{258A}', '\u{2589}' };
    const total: usize = @intFromFloat(std.math.clamp(f, 0, 1) * @as(f32, @floatFromInt(w * 8)));
    const full = total / 8;
    const part = total % 8;
    const track = theme.playhead_bg;
    for (0..w) |i| {
        if (i < full) {
            c.put(x + i, y, '\u{2588}', theme.accent_hot, track);
        } else if (i == full and part > 0) {
            c.put(x + i, y, eighths[part], theme.accent_hot, track);
        } else {
            c.put(x + i, y, ' ', theme.text, track);
        }
    }
}

// ------------------------------------------------------------- hints

fn hints(c: *TextCanvas, v: View) void {
    const y = v.lay.hints_y;
    var x: usize = 1;
    const pairs = if (v.s.busy)
        [_][2][]const u8{ .{ "esc", "cancel" }, .{ "t", "theme" }, .{ "?", "help" }, .{ "q", "quit" }, .{ "", "" }, .{ "", "" }, .{ "", "" } }
    else
        [_][2][]const u8{ .{ "\u{2190}\u{2192}", "slot" }, .{ "r", "read" }, .{ "w", "write" }, .{ "b", "backup" }, .{ "t", "theme" }, .{ "?", "help" }, .{ "q", "quit" } };
    for (pairs) |pr| {
        if (pr[0].len == 0) continue;
        x += text(c, x, y, pr[0], theme.accent, theme.bg);
        x += 1;
        x += text(c, x, y, pr[1], theme.text_dim, theme.bg);
        x += 3;
    }
    if (v.st.status()) |s| {
        const n = cells(s);
        if (x + n + 2 < c.w) _ = text(c, c.w - n - 1, y, s, theme.accent_hot, theme.bg);
    }
}

// ------------------------------------------------------------- overlays

fn box(c: *TextCanvas, w: usize, h: usize, title: []const u8) stage.Rect {
    const bw = @min(w, c.w -| 4);
    const bh = @min(h, c.h -| 2);
    const r: stage.Rect = .{ .x = (c.w - bw) / 2, .y = (c.h - bh) / 2, .w = bw, .h = bh };
    // widgets.frame prints its title byte-wise (ASCII); ours carry '·'
    widgets.frame(c, r.x, r.y, r.w, r.h, "");
    _ = text(c, r.x + 3, r.y, title, theme.text_bright, theme.header_bg);
    return r;
}

fn confirm(c: *TextCanvas, v: View) void {
    const cf = &v.st.confirm;
    var tb: [32]u8 = undefined;
    const title = std.fmt.bufPrint(&tb, " {s} {s} ", .{ if (cf.slot == .sram) "WRITE" else "FLASH", cf.slot.label() }) catch " WRITE ";
    const r = box(c, 66, 12, title);
    const x = r.x + 3;
    const w = r.w -| 6;
    var pb: [160]u8 = undefined;
    var lb: [200]u8 = undefined;
    var sb: [16]u8 = undefined;

    _ = text(c, x, r.y + 2, "FROM", theme.text_dim, theme.bg);
    _ = text(c, x + 6, r.y + 2, shortPath(cf.path(), w -| 6, &pb), theme.text_bright, theme.bg);
    if (cf.slot != .sram) {
        if (cf.header) |h| {
            if (h.valid()) {
                const l = std.fmt.bufPrint(&lb, "{s} \u{00B7} {s} \u{00B7} {s}", .{
                    if (h.title().len > 0) h.title() else "untitled", rom.sizeText(h.rom_size, &sb), h.typeName(),
                }) catch "";
                _ = text(c, x + 6, r.y + 3, l, theme.text, theme.bg);
            } else _ = text(c, x + 6, r.y + 3, "\u{26A0} no valid Game Boy header in this file", theme.mute_red, theme.bg);
        }
    } else {
        const l = std.fmt.bufPrint(&lb, "{s} save file", .{rom.sizeText(@intCast(cf.file_size), &sb)}) catch "";
        _ = text(c, x + 6, r.y + 3, l, theme.text, theme.bg);
    }

    _ = text(c, x, r.y + 5, "OVER", theme.text_dim, theme.bg);
    const over: []const u8 = switch (cf.slot) {
        .sram => "the save RAM \u{2014} both banks' saves live here",
        else => blk: {
            const h = v.s.banks[@intFromEnum(cf.slot)] orelse break :blk "(unreadable)";
            if (!h.valid()) break :blk "an empty bank";
            break :blk std.fmt.bufPrint(&lb, "{s} ({s})", .{ if (h.title().len > 0) h.title() else "untitled", rom.sizeText(h.rom_size, &sb) }) catch "";
        },
    };
    _ = text(c, x + 6, r.y + 5, over, theme.text, theme.bg);

    c.put(x, r.y + 7, '[', theme.text_dim, theme.bg);
    c.put(x + 1, r.y + 7, if (cf.verify) '\u{2713}' else ' ', theme.accent_hot, theme.bg);
    c.put(x + 2, r.y + 7, ']', theme.text_dim, theme.bg);
    _ = text(c, x + 4, r.y + 7, "verify after writing (reads it all back)", theme.text, theme.bg);

    var hx = x;
    hx += key(c, hx, r.y + r.h - 3, "enter");
    hx += text(c, hx, r.y + r.h - 3, if (cf.slot == .sram) " write   " else " flash   ", theme.text, theme.bg);
    hx += key(c, hx, r.y + r.h - 3, "v");
    hx += text(c, hx, r.y + r.h - 3, " verify   ", theme.text, theme.bg);
    hx += key(c, hx, r.y + r.h - 3, "esc");
    _ = text(c, hx, r.y + r.h - 3, " cancel", theme.text, theme.bg);
}

fn help(c: *TextCanvas, v: View) void {
    _ = v;
    const r = box(c, 64, 18, " QARTZ \u{00B7} HELP ");
    const x = r.x + 3;
    const rows = [_][2][]const u8{
        .{ "\u{2190} \u{2192}  1 2 3", "pick a slot: BANK 1, BANK 2, SRAM" },
        .{ "r", "read the slot into a file" },
        .{ "w", "write a file into the slot (then verify)" },
        .{ "b", "back up both banks + SRAM into a folder" },
        .{ "t  T", "next / previous colour theme" },
        .{ "esc", "cancel a running transfer" },
        .{ "q", "quit" },
    };
    for (rows, 0..) |row, i| {
        _ = text(c, x, r.y + 2 + i, row[0], theme.accent_hot, theme.bg);
        _ = text(c, x + 14, r.y + 2 + i, row[1], theme.text, theme.bg);
    }
    const notes = [_][]const u8{
        "The EMS 64M holds two 4 MB ROM banks, and both share",
        "the one 128K SRAM (where LSDj keeps its songs).",
        "Reads stop at the ROM's own size; writes are verified by",
        "reading every byte back. The cart is found by itself.",
    };
    for (notes, 0..) |n, i| _ = text(c, x, r.y + 10 + i, n, theme.text_dim, theme.bg);
    _ = text(c, x, r.y + r.h - 2, "any key closes", theme.text_dim, theme.bg);
}

fn quitBox(c: *TextCanvas, v: View) void {
    _ = v;
    const r = box(c, 52, 7, " QUIT? ");
    const x = r.x + 3;
    _ = text(c, x, r.y + 2, "A transfer is running. Quit and abort it?", theme.text, theme.bg);
    var hx = x;
    hx += key(c, hx, r.y + 4, "q");
    hx += text(c, hx, r.y + 4, " quit   ", theme.text, theme.bg);
    hx += key(c, hx, r.y + 4, "esc");
    _ = text(c, hx, r.y + 4, " keep going", theme.text, theme.bg);
}
