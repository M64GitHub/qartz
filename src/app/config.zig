//! User config — ~/.config/qartz/config.zon (ZON, like keys.zon
//! and projects). v1 holds the FILE DIALOG memory:
//!
//!   - 8 favorite directories, SHARED across every open/save dialog
//!     (keys 1-8 jump there, Shift+1-8 stores the current dir)
//!   - the last-used directory per dialog context (project / module /
//!     swm / swi / any), so each dialog reopens where it left off
//!
//!   - THE COLOUR SCHEME (s166): the project page's COLOURS pick —
//!     the user's, never a song's, so it lives here and nowhere else
//!
//! Reads are forgiving (missing file = defaults, unknown fields
//! ignored so newer configs load in older builds); writes go through
//! a temp file + rename so a crash never eats the config.

const std = @import("std");
const builtin = @import("builtin");

pub const N_FAVS = 8;

/// The user's home directory — $HOME on posix, %USERPROFILE% on windows
/// (WTF-16 there, hence the buffer; posix ignores it). Null when unset.
/// Every "~"-shaped path in DUET goes through here so the windows build
/// stays honest (M19).
pub fn homeDir(buf: []u8) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        const w = std.process.getenvW(
            std.unicode.utf8ToUtf16LeStringLiteral("USERPROFILE"),
        ) orelse return null;
        const n = std.unicode.utf16LeToUtf8(buf, w) catch return null;
        return buf[0..n];
    }
    return std.posix.getenv("HOME");
}

/// Which dialog is asking — selects the remembered start directory.
/// Extend freely (wav, theme, ...); unknown fields on disk are ignored.
/// `.import` is THE IMPORT's source picker (s45): it lists the same
/// four module extensions as `.swm` but means the opposite thing —
/// that file is READ FOR PARTS, it does not become the session — and
/// the pick handler dispatches on exactly this.
pub const Context = enum { rom, sram, backup };

/// The on-disk shape: flat scalar fields, "" = unset — hand-editable,
/// and flat because std.zon's comptime parser chokes on array fields
/// (branch quota, and @setEvalBranchQuota can't reach the generic).
const Disk = struct {
    fav1: []const u8 = "",
    fav2: []const u8 = "",
    fav3: []const u8 = "",
    fav4: []const u8 = "",
    fav5: []const u8 = "",
    fav6: []const u8 = "",
    fav7: []const u8 = "",
    fav8: []const u8 = "",
    last_rom: []const u8 = "",
    last_sram: []const u8 = "",
    last_backup: []const u8 = "",
    /// the scheme's name as `theme.SCHEMES` spells it; "" = DUET
    scheme: []const u8 = "",
};

fn favField(disk: anytype, comptime i: usize) @TypeOf(@field(disk, "fav1")) {
    return @field(disk, std.fmt.comptimePrint("fav{d}", .{i + 1}));
}

pub const Config = struct {
    gpa: std.mem.Allocator,
    favorites: [N_FAVS]?[]u8 = @splat(null),
    last: std.EnumArray(Context, ?[]u8) =
        std.EnumArray(Context, ?[]u8).initFill(null),
    /// The COLOURS pick (s166), null = never picked (DUET).
    scheme: ?[]u8 = null,

    pub fn deinit(self: *Config) void {
        for (&self.favorites) |*f| {
            if (f.*) |s| self.gpa.free(s);
            f.* = null;
        }
        var it = self.last.iterator();
        while (it.next()) |e| {
            if (e.value.*) |s| self.gpa.free(s);
            e.value.* = null;
        }
        if (self.scheme) |sc| self.gpa.free(sc);
        self.scheme = null;
    }

    pub fn favorite(self: *const Config, slot: usize) ?[]const u8 {
        if (slot >= N_FAVS) return null;
        return self.favorites[slot];
    }

    /// Store `dir` in a favorite slot (dupes; frees the old one) and save.
    pub fn setFavorite(self: *Config, slot: usize, dir: []const u8) void {
        if (slot >= N_FAVS) return;
        const copy = self.gpa.dupe(u8, dir) catch return;
        if (self.favorites[slot]) |old| self.gpa.free(old);
        self.favorites[slot] = copy;
        self.save();
    }

    /// Remember the COLOURS pick and write the config at once — a
    /// scheme is picked by eye, so it has to survive the next start.
    pub fn setScheme(self: *Config, name: []const u8) void {
        const copy = self.gpa.dupe(u8, name) catch return;
        if (self.scheme) |old| self.gpa.free(old);
        self.scheme = copy;
        self.save();
    }

    pub fn lastDir(self: *const Config, ctx: Context) ?[]const u8 {
        return self.last.get(ctx);
    }

    /// Remember the directory a file was picked from (dupes) and save.
    pub fn setLastDir(self: *Config, ctx: Context, dir: []const u8) void {
        const copy = self.gpa.dupe(u8, dir) catch return;
        if (self.last.get(ctx)) |old| self.gpa.free(old);
        self.last.set(ctx, copy);
        self.save();
    }

    /// Write ~/.config/qartz/config.zon (temp + rename). Failures
    /// only cost the memory of favorites — never the session — so they
    /// warn on stderr and move on.
    pub fn save(self: *const Config) void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = configPath(&path_buf) orelse return;
        const dir_path = std.fs.path.dirname(path) orelse return;
        std.fs.cwd().makePath(dir_path) catch |err| {
            std.debug.print("config: cannot create {s}: {}\n", .{ dir_path, err });
            return;
        };

        var disk: Disk = .{};
        inline for (0..N_FAVS) |i| {
            @field(disk, std.fmt.comptimePrint("fav{d}", .{i + 1})) =
                self.favorites[i] orelse "";
        }
        disk.last_rom = self.last.get(.rom) orelse "";
        disk.last_sram = self.last.get(.sram) orelse "";
        disk.last_backup = self.last.get(.backup) orelse "";
        disk.scheme = self.scheme orelse "";

        var aw = std.Io.Writer.Allocating.init(self.gpa);
        defer aw.deinit();
        std.zon.stringify.serialize(disk, .{}, &aw.writer) catch return;

        var dir = std.fs.cwd().openDir(dir_path, .{}) catch return;
        defer dir.close();
        var af = dir.atomicFile(std.fs.path.basename(path), .{ .write_buffer = &.{} }) catch |err| {
            std.debug.print("config: cannot write {s}: {}\n", .{ path, err });
            return;
        };
        defer af.deinit();
        af.file_writer.interface.writeAll(aw.writer.buffered()) catch return;
        af.finish() catch |err| {
            std.debug.print("config: cannot write {s}: {}\n", .{ path, err });
            return;
        };
    }
};

/// Load the config; a missing/broken file is simply the default config
/// (broken warns — the user typed something into it).
pub fn load(gpa: std.mem.Allocator) Config {
    var cfg = Config{ .gpa = gpa };
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = configPath(&path_buf) orelse return cfg;
    const src = std.fs.cwd().readFileAllocOptions(
        gpa,
        path,
        1 << 20,
        null,
        .of(u8),
        0,
    ) catch return cfg;
    defer gpa.free(src);

    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);
    const raw = std.zon.parse.fromSlice(Disk, gpa, src, &diag, .{
        .ignore_unknown_fields = true,
    }) catch {
        std.debug.print("config: {s}: parse failed — using defaults\n", .{path});
        return cfg;
    };
    defer std.zon.parse.free(gpa, raw);

    inline for (0..N_FAVS) |i| {
        const f = favField(raw, i);
        if (f.len > 0) cfg.favorites[i] = gpa.dupe(u8, f) catch null;
    }
    setIf(&cfg, .rom, raw.last_rom);
    setIf(&cfg, .sram, raw.last_sram);
    setIf(&cfg, .backup, raw.last_backup);
    if (raw.scheme.len > 0) cfg.scheme = gpa.dupe(u8, raw.scheme) catch null;
    return cfg;
}

fn setIf(cfg: *Config, ctx: Context, val: []const u8) void {
    if (val.len == 0) return;
    cfg.last.set(ctx, cfg.gpa.dupe(u8, val) catch null);
}

fn configPath(buf: *[std.fs.max_path_bytes]u8) ?[]u8 {
    // tests and screenshots point this elsewhere so they never touch the
    // user's own favorites, last dirs and theme
    if (std.posix.getenv("QARTZ_CONFIG")) |p| {
        if (p.len > buf.len) return null;
        @memcpy(buf[0..p.len], p);
        return buf[0..p.len];
    }
    var hbuf: [std.fs.max_path_bytes]u8 = undefined;
    const home = homeDir(&hbuf) orelse return null;
    return std.fmt.bufPrint(buf, "{s}/.config/qartz/config.zon", .{home}) catch null;
}
