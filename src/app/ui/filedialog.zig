//! The file dialog: lifted from DUET (src/app/ui/filedialog.zig), the
//! picker behind every "pick a file" moment there, minus DUET's own
//! needs (the session's file-mode narrowing, SPACE-audition).
//!
//!   ╭ FLASH BANK 1 ─ .gb .gbc ────────────────╮
//!   │ DIR ▾ ~/music/lsdj               [tab favs]│
//!   │ ❯ fuzzy query█                           │
//!   │ ──────────────────────────────────────── │
//!   │ ▸ ../          ▸ subdir/    lsdj.gb   1M │
//!   ╰ ↵ open  ⌫ up  1-8 fav  esc ──────────────╯
//!
//! - typing filters the listing FUZZY (subsequence + word-start bonus,
//!   matched chars highlighted); Enter opens the selection
//! - arrows move, PgUp/PgDn page, Backspace deletes — on an empty query
//!   it goes to the parent directory
//! - 1-8 jump to the favorite dirs (query empty); Tab opens the
//!   favorites dropdown where 's' stores the current dir and 'x' clears
//! - SAVE mode: the query line IS the filename; an existing target arms
//!   a second-ENTER overwrite confirm. An empty save extension picks a
//!   DIRECTORY name (the backup).
//! - the picked file's directory is remembered per context in the user
//!   config, so each dialog kind reopens where it left off
//!
//! The component owns no app state: handleKey() returns .picked and the
//! caller reads pickedPath() and decides what it means.

const std = @import("std");
const movy = @import("movy");
const theme = @import("theme.zig");
const config = @import("../config.zig");
const widgets = @import("widgets.zig");
const TextCanvas = @import("canvas.zig").TextCanvas;

pub const Context = config.Context;

pub const Action = enum { none, closed, picked };

const Entry = struct {
    name: []u8, // gpa-owned
    is_dir: bool,
    size: u64, // files only
};

const QUERY_MAX = 40;
const NAME_MAX = 255;

pub const FileDialog = struct {
    gpa: std.mem.Allocator,
    open: bool = false,
    ctx: Context = .rom,
    /// The extensions this dialog lists (lowercase, with dot).
    ext_list: []const []const u8 = &.{},
    /// The frame's title word(s), e.g. "FLASH BANK 1".
    title_buf: [40]u8 = undefined,
    title_len: usize = 0,

    dir_buf: [std.fs.max_path_bytes]u8 = undefined,
    dir_len: usize = 0,
    query_buf: [QUERY_MAX]u8 = undefined,
    query_len: usize = 0,

    entries: std.ArrayList(Entry) = .{},
    matches: std.ArrayList(u32) = .{}, // indices into entries, ranked
    sel: usize = 0,
    scroll: usize = 0,
    scan_err: bool = false,

    drop_open: bool = false, // favorites dropdown
    drop_sel: usize = 0,

    // SAVE mode: the query line becomes the FILENAME input — ENTER
    // saves dir/<name><save_ext>, an existing target arms a second-ENTER
    // overwrite confirm. Digit favorite-jumps are disabled (names may
    // start with digits); ENTER on a listed file adopts its stem.
    save_mode: bool = false,
    overwrite_armed: bool = false,
    /// What a save appends ("" = the name is a directory).
    save_ext: []const u8 = "",

    picked_buf: [std.fs.max_path_bytes]u8 = undefined,
    picked_len: usize = 0,

    pub fn deinit(self: *FileDialog) void {
        self.clearEntries();
        self.entries.deinit(self.gpa);
        self.matches.deinit(self.gpa);
    }

    fn clearEntries(self: *FileDialog) void {
        for (self.entries.items) |e| self.gpa.free(e.name);
        self.entries.clearRetainingCapacity();
        self.matches.clearRetainingCapacity();
    }

    pub fn dir(self: *const FileDialog) []const u8 {
        return self.dir_buf[0..self.dir_len];
    }
    pub fn query(self: *const FileDialog) []const u8 {
        return self.query_buf[0..self.query_len];
    }
    pub fn pickedPath(self: *const FileDialog) []const u8 {
        return self.picked_buf[0..self.picked_len];
    }

    /// Open for a context: start in its last-used directory (config),
    /// else the cwd, else '/'.
    pub fn openFor(self: *FileDialog, ctx: Context, title: []const u8, exts_: []const []const u8, cfg: *const config.Config) void {
        self.openAt(ctx, title, exts_, cfg.lastDir(ctx) orelse cwdOrRoot(&self.dir_buf));
    }

    /// Open pinned to a directory (headless verification, tests).
    pub fn openAt(self: *FileDialog, ctx: Context, title: []const u8, exts_: []const []const u8, dir_path: []const u8) void {
        self.ctx = ctx;
        self.ext_list = exts_;
        const n = @min(title.len, self.title_buf.len);
        @memcpy(self.title_buf[0..n], title[0..n]);
        self.title_len = n;
        self.open = true;
        self.drop_open = false;
        self.save_mode = false;
        self.overwrite_armed = false;
        self.query_len = 0;
        self.setDir(dir_path);
        self.rescan(null);
    }

    /// Open in SAVE mode with a pre-filled name (editable; doubles as
    /// the list filter, so an existing same-named file shows up).
    pub fn openForSave(
        self: *FileDialog,
        ctx: Context,
        title: []const u8,
        exts_: []const []const u8,
        cfg: *const config.Config,
        default_name: []const u8,
        save_ext: []const u8,
    ) void {
        self.openFor(ctx, title, exts_, cfg);
        self.save_ext = save_ext;
        self.save_mode = true;
        const n = @min(default_name.len, QUERY_MAX);
        @memcpy(self.query_buf[0..n], default_name[0..n]);
        self.query_len = n;
        self.refilter();
    }

    pub fn saveExt(self: *const FileDialog) []const u8 {
        return self.save_ext;
    }

    fn titleText(self: *const FileDialog) []const u8 {
        return self.title_buf[0..self.title_len];
    }

    pub fn close(self: *FileDialog) void {
        self.open = false;
        self.drop_open = false;
    }

    fn setDir(self: *FileDialog, path: []const u8) void {
        const n = @min(path.len, self.dir_buf.len);
        // (self-copy safe: cwdOrRoot may already fill dir_buf in place)
        std.mem.copyForwards(u8, self.dir_buf[0..n], path[0..n]);
        self.dir_len = n;
    }

    fn exts(self: *const FileDialog) []const []const u8 {
        return self.ext_list;
    }

    /// The extension list as the title shows it: `.gb .gbc`. GENERATED
    /// from `exts()` so the header always says what is being shown.
    fn extList(self: *const FileDialog, buf: []u8) []const u8 {
        var n: usize = 0;
        for (self.exts()) |e| {
            const need = e.len + @as(usize, if (n == 0) 0 else 1);
            if (n + need > buf.len) break;
            if (n > 0) {
                buf[n] = ' ';
                n += 1;
            }
            @memcpy(buf[n..][0..e.len], e);
            n += e.len;
        }
        return buf[0..n];
    }

    fn wantFile(self: *const FileDialog, name: []const u8) bool {
        for (self.exts()) |e| {
            if (name.len > e.len and
                std.ascii.endsWithIgnoreCase(name, e)) return true;
        }
        return false;
    }

    /// Re-list the current directory: subdirs + matching files, dirs
    /// first, case-insensitive alpha. `reselect` picks that name after
    /// the scan (used to land on the dir we just came out of).
    fn rescan(self: *FileDialog, reselect: ?[]const u8) void {
        var sel_name_buf: [NAME_MAX]u8 = undefined;
        var sel_name: ?[]const u8 = null;
        if (reselect) |r| {
            const n = @min(r.len, sel_name_buf.len);
            @memcpy(sel_name_buf[0..n], r[0..n]);
            sel_name = sel_name_buf[0..n];
        }

        self.clearEntries();
        self.scan_err = false;
        self.sel = 0;
        self.scroll = 0;

        var d = std.fs.cwd().openDir(self.dir(), .{ .iterate = true }) catch {
            self.scan_err = true;
            return;
        };
        defer d.close();

        if (!std.mem.eql(u8, self.dir(), "/")) {
            const up = self.gpa.dupe(u8, "..") catch return;
            self.entries.append(self.gpa, .{ .name = up, .is_dir = true, .size = 0 }) catch return;
        }

        var it = d.iterate();
        while (it.next() catch null) |e| {
            if (e.name.len == 0 or e.name[0] == '.') continue;
            var is_dir = e.kind == .directory;
            var size: u64 = 0;
            if (e.kind == .file or e.kind == .sym_link) {
                const stat = d.statFile(e.name) catch continue;
                is_dir = stat.kind == .directory;
                size = stat.size;
            } else if (!is_dir) continue;
            if (!is_dir and !self.wantFile(e.name)) continue;
            const name = self.gpa.dupe(u8, e.name) catch return;
            self.entries.append(self.gpa, .{
                .name = name,
                .is_dir = is_dir,
                .size = size,
            }) catch {
                self.gpa.free(name);
                return;
            };
        }

        std.mem.sort(Entry, self.entries.items, {}, entryLess);
        self.refilter();

        if (sel_name) |want| {
            for (self.matches.items, 0..) |ei, mi| {
                if (std.mem.eql(u8, self.entries.items[ei].name, want)) {
                    self.sel = mi;
                    break;
                }
            }
        }
    }

    fn entryLess(_: void, a: Entry, b: Entry) bool {
        if (a.is_dir != b.is_dir) return a.is_dir; // dirs first ('..' sorts up)
        if (a.is_dir and std.mem.eql(u8, a.name, "..")) return true;
        if (b.is_dir and std.mem.eql(u8, b.name, "..")) return false;
        return std.ascii.lessThanIgnoreCase(a.name, b.name);
    }

    /// Rebuild matches[] from the query: everything (query empty) or
    /// fuzzy-ranked hits, best first; stable by list order on ties.
    fn refilter(self: *FileDialog) void {
        self.matches.clearRetainingCapacity();
        const q = self.query();
        for (self.entries.items, 0..) |e, i| {
            if (q.len == 0) {
                self.matches.append(self.gpa, @intCast(i)) catch return;
                continue;
            }
            if (std.mem.eql(u8, e.name, "..")) continue; // typing = searching
            if (fuzzyScore(e.name, q, null) != null)
                self.matches.append(self.gpa, @intCast(i)) catch return;
        }
        if (q.len > 0) {
            const ctx_sort = SortCtx{ .dlg = self };
            std.mem.sort(u32, self.matches.items, ctx_sort, SortCtx.less);
        }
        self.sel = @min(self.sel, self.matches.items.len -| 1);
        self.scroll = 0;
    }

    const SortCtx = struct {
        dlg: *FileDialog,
        fn less(ctx: SortCtx, a: u32, b: u32) bool {
            const ea = ctx.dlg.entries.items[a];
            const eb = ctx.dlg.entries.items[b];
            const sa = fuzzyScore(ea.name, ctx.dlg.query(), null) orelse -1000;
            const sb = fuzzyScore(eb.name, ctx.dlg.query(), null) orelse -1000;
            if (sa != sb) return sa > sb;
            if (ea.is_dir != eb.is_dir) return ea.is_dir;
            return std.ascii.lessThanIgnoreCase(ea.name, eb.name);
        }
    };

    fn selected(self: *const FileDialog) ?Entry {
        if (self.sel >= self.matches.items.len) return null;
        return self.entries.items[self.matches.items[self.sel]];
    }

    /// dir/name into picked_buf — what pickedPath() hands the caller for
    /// both verbs (ENTER opens it, SPACE auditions it).
    fn fillPicked(self: *FileDialog, name: []const u8) bool {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const joined = if (std.mem.eql(u8, self.dir(), "/"))
            std.fmt.bufPrint(&buf, "/{s}", .{name}) catch return false
        else
            std.fmt.bufPrint(&buf, "{s}/{s}", .{ self.dir(), name }) catch return false;
        @memcpy(self.picked_buf[0..joined.len], joined);
        self.picked_len = joined.len;
        return true;
    }

    fn descend(self: *FileDialog, name: []const u8) void {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const joined = if (std.mem.eql(u8, self.dir(), "/"))
            std.fmt.bufPrint(&buf, "/{s}", .{name}) catch return
        else
            std.fmt.bufPrint(&buf, "{s}/{s}", .{ self.dir(), name }) catch return;
        self.setDir(joined);
        self.query_len = 0;
        self.rescan(null);
    }

    fn parent(self: *FileDialog) void {
        var from_buf: [NAME_MAX]u8 = undefined;
        const base = std.fs.path.basename(self.dir());
        const n = @min(base.len, from_buf.len);
        @memcpy(from_buf[0..n], base[0..n]);
        const up = std.fs.path.dirname(self.dir()) orelse return;
        self.setDir(if (up.len == 0) "/" else up);
        self.query_len = 0;
        self.rescan(from_buf[0..n]);
    }

    fn jumpFavorite(self: *FileDialog, slot: usize, cfg: *const config.Config, st: anytype) void {
        var buf: [32]u8 = undefined;
        const fav = cfg.favorite(slot) orelse {
            st.setStatus(std.fmt.bufPrint(&buf, "FAV {d}: EMPTY (tab, s sets)", .{slot + 1}) catch "FAV EMPTY");
            return;
        };
        self.setDir(fav);
        self.query_len = 0;
        self.rescan(null);
        st.setStatus(std.fmt.bufPrint(&buf, "FAV {d}", .{slot + 1}) catch "FAV");
    }

    /// One key while the dialog is open. Consumes everything; returns
    /// what happened so the caller can react to .picked / .closed.
    pub fn handleKey(
        self: *FileDialog,
        k: anytype,
        cfg: *config.Config,
        st: anytype,
    ) Action {
        if (k.event == .Release) return .none;
        // held keys repeat only where repeating is navigation
        if (k.event == .Repeat) switch (k.type) {
            .Up, .Down, .PageUp, .PageDown, .Backspace => {},
            else => return .none,
        };

        if (self.drop_open) return self.handleDropKey(k, cfg, st);

        // the overwrite confirm survives exactly one keypress: the
        // second ENTER (checked below via was_armed)
        const was_armed = self.overwrite_armed;
        self.overwrite_armed = false;

        switch (k.type) {
            .Escape => {
                self.close();
                return .closed;
            },
            .Up => self.sel -|= 1,
            .Down => {
                if (self.sel + 1 < self.matches.items.len) self.sel += 1;
            },
            .PageUp => self.sel -|= self.listRows(),
            .PageDown => self.sel = @min(
                self.sel + self.listRows(),
                self.matches.items.len -| 1,
            ),
            .Home => self.sel = 0,
            .End => self.sel = self.matches.items.len -| 1,
            .Tab => {
                self.drop_open = true;
                self.drop_sel = 0;
            },
            .Backspace => {
                if (self.query_len > 0) {
                    self.query_len -= 1;
                    self.refilter();
                } else self.parent();
            },
            .Left => {
                if (self.query_len == 0) self.parent();
            },
            .Right => {
                if (self.query_len == 0) {
                    if (self.selected()) |e| {
                        if (e.is_dir and !std.mem.eql(u8, e.name, ".."))
                            self.descend(e.name);
                    }
                }
            },
            .Enter => {
                if (self.save_mode) return self.saveEnter(cfg, was_armed);
                const e = self.selected() orelse return .none;
                if (e.is_dir) {
                    if (std.mem.eql(u8, e.name, "..")) self.parent() else self.descend(e.name);
                    return .none;
                }
                if (!self.fillPicked(e.name)) return .none;
                cfg.setLastDir(self.ctx, self.dir());
                self.close();
                return .picked;
            },
            .Char => {
                if (k.sequence.len != 1) return .none;
                const ch = k.sequence[0];
                if (!self.save_mode and ch >= '1' and ch <= '8' and self.query_len == 0) {
                    self.jumpFavorite(ch - '1', cfg, st);
                    return .none;
                }
                if (ch >= 32 and ch < 127 and self.query_len < QUERY_MAX) {
                    self.query_buf[self.query_len] = ch;
                    self.query_len += 1;
                    self.refilter();
                }
            },
            else => {},
        }
        self.followScroll();
        return .none;
    }

    /// ENTER in save mode: navigate dirs, adopt a selected file's stem
    /// into the empty name, or save dir/<name><save_ext> — arming a
    /// second-ENTER confirm when the target exists.
    fn saveEnter(self: *FileDialog, cfg: *config.Config, was_armed: bool) Action {
        if (self.selected()) |e| {
            if (e.is_dir) {
                if (std.mem.eql(u8, e.name, "..")) self.parent() else self.descend(e.name);
                return .none;
            }
            if (self.query_len == 0) {
                // adopt the selected file's stem as the name
                const stem = std.fs.path.stem(e.name);
                const n = @min(stem.len, QUERY_MAX);
                @memcpy(self.query_buf[0..n], stem[0..n]);
                self.query_len = n;
                self.refilter();
                return .none;
            }
        }
        if (self.query_len == 0) return .none;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const name = self.query();
        const want_ext = self.saveExt();
        const ext = if (want_ext.len == 0 or std.ascii.endsWithIgnoreCase(name, want_ext)) "" else want_ext;
        const joined = std.fmt.bufPrint(&buf, "{s}/{s}{s}", .{
            self.dir(), name, ext,
        }) catch return .none;
        if (!was_armed) {
            const target_exists = if (std.fs.cwd().access(joined, .{})) true else |_| false;
            if (target_exists) {
                self.overwrite_armed = true;
                return .none;
            }
        }
        @memcpy(self.picked_buf[0..joined.len], joined);
        self.picked_len = joined.len;
        cfg.setLastDir(self.ctx, self.dir());
        self.close();
        return .picked;
    }

    fn handleDropKey(self: *FileDialog, k: anytype, cfg: *config.Config, st: anytype) Action {
        var buf: [96]u8 = undefined;
        switch (k.type) {
            .Escape, .Tab => self.drop_open = false,
            .Up => self.drop_sel -|= 1,
            .Down => {
                if (self.drop_sel + 1 < config.N_FAVS) self.drop_sel += 1;
            },
            .Enter => {
                self.drop_open = false;
                self.jumpFavorite(self.drop_sel, cfg, st);
            },
            .Char => {
                if (k.sequence.len != 1) return .none;
                const ch = k.sequence[0];
                switch (ch) {
                    '1'...'8' => {
                        self.drop_open = false;
                        self.jumpFavorite(ch - '1', cfg, st);
                    },
                    's' => {
                        cfg.setFavorite(self.drop_sel, self.dir());
                        st.setStatus(std.fmt.bufPrint(&buf, "FAV {d} = {s}", .{
                            self.drop_sel + 1, shortPath(self.dir(), 48, &buf2),
                        }) catch "FAV SET");
                    },
                    'x' => {
                        if (cfg.favorites[self.drop_sel]) |old| {
                            cfg.gpa.free(old);
                            cfg.favorites[self.drop_sel] = null;
                            cfg.save();
                            st.setStatus("FAV CLEARED");
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        return .none;
    }

    // -------------------------------------------------------- geometry

    pub const Rect = struct { x0: usize, y0: usize, w: usize, h: usize };

    /// The popup rectangle in text cells (main.zig shades the pixel
    /// layer behind it with the same box).
    pub fn rect(cw: usize, ch: usize) Rect {
        const w: usize = @min(cw -| 8, 64);
        const h: usize = @min(ch -| 4, 20);
        return .{ .x0 = (cw - w) / 2, .y0 = (ch - h) / 2, .w = w, .h = h };
    }

    fn listRows(self: *const FileDialog) usize {
        _ = self;
        return 20 - 6; // rect() caps h at 20; recomputed per draw anyway
    }

    fn followScroll(self: *FileDialog) void {
        // final clamping happens in draw() where the real height is known
        if (self.sel < self.scroll) self.scroll = self.sel;
    }

    // ------------------------------------------------------------ draw

    var buf2: [96]u8 = undefined; // shortPath scratch for status lines

    pub fn draw(self: *FileDialog, c: *TextCanvas, st: anytype) void {
        if (!self.open) return;
        const r = rect(c.w, c.h);
        if (r.w < 30 or r.h < 9) return;
        const x0 = r.x0;
        const y0 = r.y0;

        var tbuf: [96]u8 = undefined;
        var ebuf: [64]u8 = undefined;
        const title_text = if (self.save_mode)
            std.fmt.bufPrint(&tbuf, " {s}: name{s} ", .{ self.titleText(), if (self.save_ext.len > 0) self.save_ext else "/" }) catch " SAVE "
        else
            std.fmt.bufPrint(&tbuf, " {s} ({s}) ", .{ self.titleText(), self.extList(&ebuf) }) catch " OPEN ";
        widgets.frame(c, x0, y0, r.w, r.h, title_text);
        if (self.save_mode and self.overwrite_armed) {
            const warn = " EXISTS - ENTER overwrites ";
            if (warn.len + 4 < r.w)
                c.putStr(x0 + r.w - warn.len - 2, y0 + r.h - 1, warn, theme.cursor_fg, theme.cursor_bg);
        } else {
            const hint = if (self.save_mode)
                " type name  enter save  bksp edit  esc "
            else
                " enter open  bksp up  1-8 fav  esc ";
            // narrow popups get the short form rather than nothing
            const shown = if (hint.len + 4 < r.w)
                hint
            else if (self.save_mode)
                " enter save  esc "
            else
                " enter open  esc ";
            if (shown.len + 4 < r.w)
                c.putStr(x0 + r.w - shown.len - 2, y0 + r.h - 1, shown, theme.text_dim, theme.header_bg);
        }
        // DIR row
        var pbuf: [96]u8 = undefined;
        c.putStr(x0 + 2, y0 + 1, "DIR", theme.text_dim, theme.bg);
        c.put(x0 + 6, y0 + 1, '\u{25BE}', theme.text_dim, theme.bg);
        const path_w = r.w -| 22;
        c.putStr(x0 + 8, y0 + 1, shortPath(self.dir(), path_w, &pbuf), theme.accent_hot, theme.bg);
        c.putStr(x0 + r.w - 11, y0 + 1, "[tab favs]", theme.text_dim, theme.bg);

        // query row
        c.put(x0 + 2, y0 + 2, '\u{276F}', theme.accent, theme.bg);
        c.putStr(x0 + 4, y0 + 2, self.query(), theme.text_bright, theme.bg);
        if (st.blink_on)
            c.put(x0 + 4 + self.query_len, y0 + 2, '\u{2588}', theme.focus_bg, theme.bg);
        c.putRepeat(x0 + 1, y0 + 3, r.w - 2, '─', theme.dots, theme.bg);

        // list
        const list_y = y0 + 4;
        const list_h = r.h - 5 - 1; // rows between separator and bottom border
        const total = self.matches.items.len;
        if (self.sel >= total and total > 0) self.sel = total - 1;
        if (self.sel < self.scroll) self.scroll = self.sel;
        if (total > 0 and self.sel >= self.scroll + list_h)
            self.scroll = self.sel - list_h + 1;

        if (self.scan_err) {
            c.putStr(x0 + 3, list_y + 1, "cannot read this directory", theme.accent_hot, theme.bg);
        } else if (total == 0) {
            if (self.save_mode and self.query_len > 0) {
                // the name is new here: say what ENTER is about to do
                var mb: [96]u8 = undefined;
                const ext = if (self.save_ext.len == 0 or std.ascii.endsWithIgnoreCase(self.query(), self.save_ext)) "" else self.save_ext;
                const msg = std.fmt.bufPrint(&mb, "enter saves {s}{s}{s} here", .{ self.query(), ext, if (self.save_ext.len == 0) "/" else "" }) catch "enter saves here";
                c.putStr(x0 + 3, list_y + 1, msg[0..@min(msg.len, r.w -| 6)], theme.accent, theme.bg);
            } else {
                const msg = if (self.query_len > 0) "no matches" else "nothing to open here";
                c.putStr(x0 + 3, list_y + 1, msg, theme.text_dim, theme.bg);
            }
        }

        var row: usize = 0;
        while (row < list_h and self.scroll + row < total) : (row += 1) {
            const mi = self.scroll + row;
            const e = self.entries.items[self.matches.items[mi]];
            const y = list_y + row;
            const is_sel = mi == self.sel;
            const row_bg = if (is_sel) theme.playhead_bg else theme.bg;
            if (is_sel) c.putRepeat(x0 + 1, y, r.w - 2, ' ', theme.text, row_bg);

            const name_x = x0 + 4;
            const name_w = r.w -| 12;
            if (e.is_dir) {
                c.put(x0 + 2, y, '\u{25B8}', theme.accent, row_bg);
                const shown = e.name[0..@min(e.name.len, name_w)];
                c.putStr(name_x, y, shown, if (is_sel) theme.text_bright else theme.accent, row_bg);
                if (e.name.len < name_w and !std.mem.eql(u8, e.name, ".."))
                    c.put(name_x + e.name.len, y, '/', theme.text_dim, row_bg);
            } else {
                const shown = e.name[0..@min(e.name.len, name_w)];
                c.putStr(name_x, y, shown, if (is_sel) theme.text_bright else theme.text, row_bg);
                // matched chars over the base color
                var pos: [QUERY_MAX]u8 = undefined;
                if (self.query_len > 0) {
                    if (fuzzyScore(e.name, self.query(), &pos)) |_| {
                        for (pos[0..self.query_len]) |p| {
                            if (p < shown.len)
                                c.put(name_x + p, y, shown[p], theme.accent_hot, row_bg);
                        }
                    }
                }
                extBadge(c, name_x, y, shown, row_bg, is_sel);
                var sbuf: [8]u8 = undefined;
                const hs = humanSize(e.size, &sbuf);
                c.putStr(x0 + r.w - 2 - hs.len, y, hs, theme.text_dim, row_bg);
            }
        }
        widgets.scrollbar(c, x0 + r.w - 1, list_y, list_h, total, list_h, self.scroll);

        if (self.drop_open) self.drawDropdown(c, x0, y0, r.w);
    }

    /// Favorites dropdown under the DIR row: slot key, path (or empty
    /// hint); 's' stores the current dir, 'x' clears the slot.
    fn drawDropdown(self: *FileDialog, c: *TextCanvas, x0: usize, y0: usize, w: usize) void {
        const dw = w - 6;
        const dx = x0 + 3;
        const dy = y0 + 2;
        widgets.frame(c, dx, dy, dw, config.N_FAVS + 2, " FAVORITES ");
        const hint = " enter go  s set  x clear ";
        if (hint.len + 4 < dw)
            c.putStr(dx + dw - hint.len - 2, dy + config.N_FAVS + 1, hint, theme.text_dim, theme.header_bg);
        // (cfg isn't stored on self — the caller passes it to handleKey;
        // draw reads through the pending pointer set in drawWithCfg)
        var pbuf: [96]u8 = undefined;
        var i: usize = 0;
        while (i < config.N_FAVS) : (i += 1) {
            const y = dy + 1 + i;
            const is_sel = i == self.drop_sel;
            const bg = if (is_sel) theme.playhead_bg else theme.bg;
            if (is_sel) c.putRepeat(dx + 1, y, dw - 2, ' ', theme.text, bg);
            var kbuf: [4]u8 = undefined;
            const key = std.fmt.bufPrint(&kbuf, "{d}", .{i + 1}) catch "?";
            c.putStr(dx + 2, y, key, theme.sid_hdr, bg);
            const fav = if (draw_cfg) |cf| cf.favorite(i) else null;
            if (fav) |path| {
                c.putStr(dx + 5, y, shortPath(path, dw -| 8, &pbuf), if (is_sel) theme.text_bright else theme.text, bg);
            } else {
                c.put(dx + 5, y, '\u{2014}', theme.text_dim, bg);
            }
        }
    }

    /// draw() needs the config for the favorites dropdown; main sets it
    /// once per frame right before drawing (single-threaded UI).
    var draw_cfg: ?*const config.Config = null;
    pub fn setDrawConfig(cfg: *const config.Config) void {
        draw_cfg = cfg;
    }
};

// ------------------------------------------------------------- helpers

fn cwdOrRoot(buf: *[std.fs.max_path_bytes]u8) []const u8 {
    return std.process.getCwd(buf) catch "/";
}

/// $HOME becomes '~'; long paths keep their TAIL ("…/deep/inside").
fn shortPath(path: []const u8, max: usize, buf: *[96]u8) []const u8 {
    var p = path;
    var pre: []const u8 = "";
    var hbuf: [std.fs.max_path_bytes]u8 = undefined;
    if (config.homeDir(&hbuf)) |home| {
        if (home.len > 1 and std.mem.startsWith(u8, p, home)) {
            pre = "~";
            p = p[home.len..];
        }
    }
    const need = pre.len + p.len;
    const cap = @min(max, buf.len);
    if (need <= cap) {
        const s = std.fmt.bufPrint(buf, "{s}{s}", .{ pre, p }) catch return path;
        return s;
    }
    if (cap < 5) return "";
    const tail = p[p.len - (cap - 3) ..];
    const s = std.fmt.bufPrint(buf, "...{s}", .{tail}) catch return path;
    return s;
}

fn humanSize(n: u64, buf: *[8]u8) []const u8 {
    if (n < 10_000)
        return std.fmt.bufPrint(buf, "{d}", .{n}) catch "?";
    if (n < 10_000_000)
        return std.fmt.bufPrint(buf, "{d}k", .{n / 1000}) catch "?";
    return std.fmt.bufPrint(buf, "{d}M", .{n / 1_000_000}) catch "?";
}

/// Color the ".ext" tail with the file type's identity color.
fn extBadge(c: *TextCanvas, x: usize, y: usize, shown: []const u8, bg: theme.Rgb, is_sel: bool) void {
    const dot = std.mem.lastIndexOfScalar(u8, shown, '.') orelse return;
    const ext = shown[dot..];
    const col = if (std.ascii.eqlIgnoreCase(ext, ".gb"))
        theme.accent_hot
    else if (std.ascii.eqlIgnoreCase(ext, ".gbc"))
        theme.accent_pink
    else if (std.ascii.eqlIgnoreCase(ext, ".sav"))
        theme.ins_col
    else
        return;
    _ = is_sel;
    c.putStr(x + dot, y, ext, col, bg);
}

/// Case-insensitive subsequence match with ranking: consecutive runs
/// and word starts (after . _ - / or position 0) score up, scattered
/// matches score down. Returns null when `q` is not a subsequence.
/// `positions` (len >= q.len) receives the matched byte indices.
pub fn fuzzyScore(name: []const u8, q: []const u8, positions: ?*[QUERY_MAX]u8) ?i32 {
    if (q.len == 0 or q.len > QUERY_MAX) return 0;
    var score: i32 = 0;
    var ni: usize = 0;
    var last_hit: isize = -2;
    for (q, 0..) |qc, qi| {
        const ql = std.ascii.toLower(qc);
        var found = false;
        while (ni < name.len) : (ni += 1) {
            if (std.ascii.toLower(name[ni]) != ql) continue;
            found = true;
            if (positions) |p| p[qi] = @intCast(@min(ni, 254));
            const at_start = ni == 0 or switch (name[ni - 1]) {
                '.', '_', '-', ' ', '/' => true,
                else => false,
            };
            if (at_start) score += 8;
            if (@as(isize, @intCast(ni)) == last_hit + 1) score += 5; // run
            score -= @intCast(@min(ni / 4, 8)); // late matches cost a bit
            last_hit = @intCast(ni);
            ni += 1;
            break;
        }
        if (!found) return null;
    }
    return score;
}

test "fuzzy: subsequence + ranking basics" {
    // matches and misses
    try std.testing.expect(fuzzyScore("congabeat.it", "cbt", null) != null);
    try std.testing.expect(fuzzyScore("congabeat.it", "xq", null) == null);
    // word starts beat scattered hits
    const a = fuzzyScore("bass-funkfil.swi", "bf", null).?;
    const b = fuzzyScore("aabaaafaaa.swi", "bf", null).?;
    try std.testing.expect(a > b);
    // empty query matches everything
    try std.testing.expect(fuzzyScore("anything", "", null) != null);
}
