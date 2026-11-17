//! The terminal app: a 60 fps loop that turns the worker's snapshots and
//! the keyboard into a picture. The worker owns the cart; this file only
//! asks it for jobs and draws what it says.
//!
//! Headless (`--dump-screen`, `--shot`) runs the same loop without a
//! terminal for a fixed number of frames, optionally fed scripted keys
//! (`--keys "30:w,60:enter"`), then prints the text layer or saves the
//! pixel layer as a PNG.

const std = @import("std");
const movy = @import("movy");
const term_mod = @import("term.zig");
const fe = @import("event.zig");
const canvas_mod = @import("ui/canvas.zig");
const theme = @import("ui/theme.zig");
const motion = @import("ui/motion.zig");
const filedialog = @import("ui/filedialog.zig");
const stage = @import("ui/stage.zig");
const view = @import("ui/view.zig");
const state_mod = @import("ui/state.zig");
const config = @import("config.zig");
const worker = @import("../cart/worker.zig");
const proto = @import("../cart/protocol.zig");
const rom = @import("../cart/rom.zig");

const State = state_mod.State;
const Slot = state_mod.Slot;
const Key = movy.input.Key;

const FRAME_NS: i128 = std.time.ns_per_s / 60;

pub const Options = struct {
    scheme: ?[]const u8 = null,
    headless: bool = false,
    frames: u64 = 90,
    cols: usize = 100,
    rows: usize = 30,
    dump: bool = false,
    shot: ?[:0]const u8 = null,
    /// Headless pictures are drawn settled unless this is set.
    motion_on: bool = false,
    /// Scripted keys, `frame:key` comma-separated; key is one character
    /// or left right up down enter esc tab bksp, or `text=abc`.
    keys: []const u8 = "",
};

const ROM_EXTS: []const []const u8 = &.{ ".gb", ".gbc" };
const SAV_EXTS: []const []const u8 = &.{".sav"};
const NO_EXTS: []const []const u8 = &.{};

const Ctx = struct {
    allocator: std.mem.Allocator,
    st: *State,
    w: *worker.Worker,
    s: *const worker.Status,
    dlg: *filedialog.FileDialog,
    cfg: *config.Config,
    quit: bool = false,
};

pub fn run(allocator: std.mem.Allocator, w: *worker.Worker, opts: Options) !u8 {
    var cfg = config.load(allocator);
    defer cfg.deinit();
    const want = opts.scheme orelse cfg.scheme orelse "DMG";
    theme.apply(theme.schemeByName(want) orelse theme.schemeByName("DMG") orelse 0);

    var term: ?term_mod.TermFrontend = null;
    if (!opts.headless) term = term_mod.TermFrontend.init(allocator) catch |e| switch (e) {
        error.TermTooSmall => return 1,
        else => return e,
    };
    defer if (term) |*t| t.deinit(allocator);

    var cols: usize = if (term) |t| t.cols else opts.cols;
    var rows: usize = if (term) |t| t.rows else opts.rows;
    var frame = try movy.Frame.init(allocator, @intCast(cols), @intCast(rows * 2));
    defer frame.deinit();
    frame.setVignette(0.14);
    var canvas = try canvas_mod.TextCanvas.init(allocator, cols, rows);
    defer canvas.deinit();
    var lay = stage.layout(cols, rows);

    var dlg = filedialog.FileDialog{ .gpa = allocator };
    defer dlg.deinit();

    var st = State{ .kitty = if (term) |t| t.kitty else false };
    st.seen_finished = w.snapshot().finished;

    motion.settled = opts.headless and !opts.motion_on;
    defer motion.settled = true;

    var next_deadline: i128 = std.time.nanoTimestamp();
    var ctx: Ctx = .{ .allocator = allocator, .st = &st, .w = w, .s = undefined, .dlg = &dlg, .cfg = &cfg };
    while (!ctx.quit) {
        next_deadline += FRAME_NS;
        var s = w.snapshot();
        ctx.s = &s;

        if (term) |*t| {
            t.pump(st.frame_no);
            while (try t.next()) |ev| switch (ev) {
                .key => |k| onKey(&ctx, k),
                .quit => ctx.quit = true,
                .resize => |sz| {
                    const nframe = try movy.Frame.init(allocator, @intCast(sz.cols), @intCast(sz.rows * 2));
                    errdefer nframe.deinit();
                    nframe.setVignette(0.14);
                    var ncanvas = try canvas_mod.TextCanvas.init(allocator, sz.cols, sz.rows);
                    errdefer ncanvas.deinit();
                    try t.applyResize(allocator, sz.cols, sz.rows);
                    frame.deinit();
                    canvas.deinit();
                    frame = nframe;
                    canvas = ncanvas;
                    cols = sz.cols;
                    rows = sz.rows;
                    lay = stage.layout(cols, rows);
                },
            };
        }
        scriptedKeys(&ctx, opts.keys);
        s = w.snapshot(); // keys may have queued a job
        update(&st, &s);
        theme.tick(st.frame_no);

        frame.beginFrame();
        stage.draw(frame, .{ .lay = &lay, .st = &st, .s = &s });
        frame.composite();
        canvas.clear();
        view.draw(&canvas, .{ .lay = &lay, .st = &st, .s = &s, .dlg = &dlg, .cfg = &cfg });

        if (term) |*t| {
            try t.present(allocator, &canvas, frame, &st);
        } else if (st.frame_no + 1 >= opts.frames) {
            if (opts.dump) {
                const txt = try canvas.dumpAlloc(allocator);
                defer allocator.free(txt);
                std.fs.File.stdout().writeAll(txt) catch {};
            }
            if (opts.shot) |path| try frame.savePng(allocator, path, 4);
            break;
        }

        st.frame_no += 1;
        const now = std.time.nanoTimestamp();
        if (now < next_deadline) {
            std.Thread.sleep(@intCast(next_deadline - now));
        } else next_deadline = now;
    }
    if (ctx.quit) {
        const s = w.snapshot();
        if (s.busy) w.cancel();
    }
    return 0;
}

/// Turn the worker's news into animation: the cart arriving, a job
/// ending.
fn update(st: *State, s: *const worker.Status) void {
    if (s.connected and !st.prev_connected)
        st.power_anim = motion.Anim.begin(st.frame_no, motion.frames(900));
    st.prev_connected = s.connected;

    if (s.finished != st.seen_finished) {
        st.seen_finished = s.finished;
        st.cancel_armed_at = null;
        if (s.outcome != .none) {
            const ok = s.outcome == .ok;
            st.toast = .{ .ok = ok, .text = s.msg, .detail = s.detail, .anim = motion.Anim.begin(st.frame_no, motion.frames(350)) };
            st.flash = motion.Anim.begin(st.frame_no, motion.frames(500));
            st.flash_ok = ok;
        }
    }
    if (st.cancel_armed_at) |at| {
        if (st.frame_no -| at > motion.frames(3000)) st.cancel_armed_at = null;
    }
    st.blink_on = (st.frame_no / 30) % 2 == 0;
}

// ------------------------------------------------------------- keys

fn isChar(k: Key, ch: u8) bool {
    return k.type == .Char and k.sequence.len == 1 and k.sequence[0] == ch;
}

fn onKey(ctx: *Ctx, k: Key) void {
    const st = ctx.st;
    if (k.type == .CtrlC or (k.type == .CtrlChar and std.mem.eql(u8, k.sequence, "c"))) {
        if (ctx.s.busy) ctx.w.cancel();
        ctx.quit = true;
        return;
    }
    if (k.event == .Release) return;

    switch (st.modal) {
        .file => {
            switch (ctx.dlg.handleKey(k, ctx.cfg, st)) {
                .picked => onPicked(ctx, ctx.dlg.pickedPath()),
                .closed => st.modal = .none,
                .none => {},
            }
            if (!ctx.dlg.open and st.modal == .file) st.modal = .none;
        },
        .confirm => {
            if (k.event == .Repeat) return;
            if (k.type == .Enter or isChar(k, 'y')) {
                const cf = &st.confirm;
                var req: worker.Request = .{ .kind = .write, .mem = cf.slot.mem(), .bank = cf.slot.bank(), .verify = cf.verify };
                req.setPath(cf.path());
                st.modal = .none;
                submit(ctx, req);
            } else if (isChar(k, 'v')) {
                st.confirm.verify = !st.confirm.verify;
            } else if (k.type == .Escape or isChar(k, 'n')) {
                st.modal = .none;
            }
        },
        .help => if (k.event == .Press) {
            st.modal = .none;
        },
        .quit => {
            if (isChar(k, 'q') or isChar(k, 'y') or k.type == .Enter) {
                ctx.w.cancel();
                ctx.quit = true;
            } else if (k.type == .Escape or isChar(k, 'n')) st.modal = .none;
        },
        .none => mainKey(ctx, k),
    }
}

fn mainKey(ctx: *Ctx, k: Key) void {
    const st = ctx.st;
    const s = ctx.s;
    switch (k.type) {
        .Left => st.select(st.slot.prev()),
        .Right, .Tab => st.select(st.slot.next()),
        .ShiftTab => st.select(st.slot.prev()),
        .Escape => {
            if (s.busy) cancel(ctx) else st.toast = null;
        },
        .Char => {
            if (k.sequence.len != 1) return;
            switch (k.sequence[0]) {
                'h' => st.select(st.slot.prev()),
                'l' => st.select(st.slot.next()),
                '1' => st.select(.bank1),
                '2' => st.select(.bank2),
                '3' => st.select(.sram),
                'r' => if (ready(ctx)) openRead(ctx),
                'w' => if (ready(ctx)) openWrite(ctx),
                'b' => if (ready(ctx)) openBackup(ctx),
                't', 'T' => cycleTheme(ctx, k.sequence[0] == 't'),
                '?' => st.modal = .help,
                'q' => {
                    if (s.busy) st.modal = .quit else ctx.quit = true;
                },
                else => {},
            }
        },
        else => {},
    }
}

/// A new job needs a cart and an idle worker; say which one is missing.
fn ready(ctx: *Ctx) bool {
    if (!ctx.s.connected) {
        ctx.st.setStatus("no cart connected");
        return false;
    }
    if (ctx.s.busy) {
        ctx.st.setStatus("busy \u{2014} esc cancels");
        return false;
    }
    return true;
}

fn cancel(ctx: *Ctx) void {
    const st = ctx.st;
    const j = ctx.s.job orelse return;
    // aborting a WRITE leaves the bank half-flashed: say it twice
    if (j.kind == .write) {
        if (st.cancel_armed_at == null) {
            st.cancel_armed_at = st.frame_no;
            return;
        }
    }
    st.cancel_armed_at = null;
    ctx.w.cancel();
}

fn cycleTheme(ctx: *Ctx, forward: bool) void {
    const n = theme.SCHEMES.len;
    const i = if (forward) (theme.active + 1) % n else (theme.active + n - 1) % n;
    theme.fadeTo(i, ctx.st.frame_no);
    ctx.cfg.setScheme(theme.SCHEMES[i].name);
    var buf: [96]u8 = undefined;
    ctx.st.setStatus(std.fmt.bufPrint(&buf, "{s} \u{00B7} {s}", .{ theme.SCHEMES[i].name, theme.SCHEMES[i].blurb }) catch "theme");
}

// ------------------------------------------------------------- actions

fn openRead(ctx: *Ctx) void {
    const st = ctx.st;
    const slot = st.slot;
    var nb: [64]u8 = undefined;
    var tb: [40]u8 = undefined;
    const title = std.fmt.bufPrint(&tb, "READ {s} TO", .{slot.label()}) catch "READ TO";
    st.intent = .read;
    st.intent_slot = slot;
    if (slot == .sram) {
        ctx.dlg.openForSave(.sram, title, SAV_EXTS, ctx.cfg, defaultName(ctx.s, .bank1, "sram", &nb), ".sav");
    } else {
        const h = ctx.s.banks[@intFromEnum(slot)];
        const ext: []const u8 = if (h != null and h.?.valid() and h.?.cgb == .cgb_only) ".gbc" else ".gb";
        ctx.dlg.openForSave(.rom, title, ROM_EXTS, ctx.cfg, defaultName(ctx.s, slot, if (slot == .bank1) "bank1" else "bank2", &nb), ext);
    }
    st.modal = .file;
}

fn openWrite(ctx: *Ctx) void {
    const st = ctx.st;
    const slot = st.slot;
    var tb: [40]u8 = undefined;
    st.intent = .write;
    st.intent_slot = slot;
    if (slot == .sram) {
        ctx.dlg.openFor(.sram, "WRITE SRAM FROM", SAV_EXTS, ctx.cfg);
    } else {
        const title = std.fmt.bufPrint(&tb, "FLASH {s} FROM", .{slot.label()}) catch "FLASH FROM";
        ctx.dlg.openFor(.rom, title, ROM_EXTS, ctx.cfg);
    }
    st.modal = .file;
}

fn openBackup(ctx: *Ctx) void {
    var nb: [64]u8 = undefined;
    ctx.st.intent = .backup;
    ctx.dlg.openForSave(.backup, "BACK UP EVERYTHING TO", NO_EXTS, ctx.cfg, backupName(&nb), "");
    ctx.st.modal = .file;
}

fn onPicked(ctx: *Ctx, path: []const u8) void {
    const st = ctx.st;
    st.modal = .none;
    const slot = st.intent_slot;
    switch (st.intent) {
        .read => {
            var req: worker.Request = .{ .kind = .read, .mem = slot.mem(), .bank = slot.bank() };
            req.setPath(path);
            submit(ctx, req);
        },
        .backup => {
            var req: worker.Request = .{ .kind = .backup };
            req.setPath(path);
            submit(ctx, req);
        },
        .write => prepareConfirm(ctx, slot, path),
    }
}

/// Look at the file before anything touches the cart: size, header.
fn prepareConfirm(ctx: *Ctx, slot: Slot, path: []const u8) void {
    const st = ctx.st;
    const cap = proto.capacity(slot.mem());
    var cf: state_mod.Confirm = .{ .slot = slot, .verify = st.confirm.verify };
    const n = @min(path.len, cf.path_buf.len);
    @memcpy(cf.path_buf[0..n], path[0..n]);
    cf.path_len = n;

    var f = std.fs.cwd().openFile(path, .{}) catch |e| {
        failToast(st, "can't open {s} ({s})", .{ std.fs.path.basename(path), @errorName(e) });
        return;
    };
    defer f.close();
    cf.file_size = (f.stat() catch {
        failToast(st, "can't read {s}", .{std.fs.path.basename(path)});
        return;
    }).size;
    if (cf.file_size == 0) {
        failToast(st, "{s} is empty", .{std.fs.path.basename(path)});
        return;
    }
    if (cf.file_size > cap) {
        var sb: [16]u8 = undefined;
        failToast(st, "{s} doesn't fit: {s} holds {s}", .{ std.fs.path.basename(path), slot.mem().label(), rom.sizeText(cap, &sb) });
        return;
    }
    if (slot != .sram) {
        var hbuf: [rom.HEADER_LEN]u8 = undefined;
        const got = f.preadAll(&hbuf, 0) catch 0;
        cf.header = rom.parse(hbuf[0..got]);
    }
    st.confirm = cf;
    st.modal = .confirm;
}

fn failToast(st: *State, comptime fmt: []const u8, args: anytype) void {
    var t: state_mod.Toast = .{ .ok = false, .anim = motion.Anim.begin(st.frame_no, motion.frames(350)) };
    t.text.set(fmt, args);
    st.toast = t;
    st.flash = motion.Anim.begin(st.frame_no, motion.frames(500));
    st.flash_ok = false;
}

fn submit(ctx: *Ctx, req: worker.Request) void {
    ctx.st.toast = null;
    if (!ctx.w.submit(req)) ctx.st.setStatus("busy \u{2014} try again when it's done");
}

/// A bank's title as a file name ("LSDj-v9.4.2"), else `fallback`.
fn defaultName(s: *const worker.Status, slot: Slot, fallback: []const u8, buf: []u8) []const u8 {
    const h = s.banks[@intFromEnum(slot)] orelse return fallback;
    if (!h.valid() or h.title().len == 0) return fallback;
    var n: usize = 0;
    for (h.title()) |ch| {
        if (n >= buf.len) break;
        buf[n] = if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_') ch else '_';
        n += 1;
    }
    return buf[0..n];
}

fn backupName(buf: []u8) []const u8 {
    const secs: u64 = @intCast(@max(0, std.time.timestamp()));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const day = es.getEpochDay().calculateYearDay();
    const md = day.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.bufPrint(buf, "qartz-backup-{d}-{d:0>2}-{d:0>2}-{d:0>2}{d:0>2}", .{
        day.year, md.month.numeric(), md.day_index + 1, ds.getHoursIntoDay(), ds.getMinutesIntoHour(),
    }) catch "qartz-backup";
}

// ------------------------------------------------------------- scripted

fn scriptedKeys(ctx: *Ctx, script: []const u8) void {
    if (script.len == 0) return;
    var it = std.mem.splitScalar(u8, script, ',');
    while (it.next()) |item| {
        const colon = std.mem.indexOfScalar(u8, item, ':') orelse continue;
        const at = std.fmt.parseInt(u64, item[0..colon], 10) catch continue;
        if (at != ctx.st.frame_no) continue;
        const name = item[colon + 1 ..];
        if (std.mem.startsWith(u8, name, "text=")) {
            const t = name[5..];
            for (0..t.len) |i| onKey(ctx, .{ .type = .Char, .sequence = t[i .. i + 1] });
            continue;
        }
        const named = [_]struct { []const u8, movy.input.KeyType }{
            .{ "left", .Left },   .{ "right", .Right }, .{ "up", .Up },          .{ "down", .Down },
            .{ "enter", .Enter }, .{ "esc", .Escape },  .{ "tab", .Tab },        .{ "bksp", .Backspace },
        };
        var done = false;
        for (named) |nk| {
            if (std.mem.eql(u8, name, nk[0])) {
                onKey(ctx, .{ .type = nk[1], .sequence = "" });
                done = true;
            }
        }
        if (!done and name.len == 1) onKey(ctx, .{ .type = .Char, .sequence = name });
    }
}
