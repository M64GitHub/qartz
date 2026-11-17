//! A cart that lives in a directory — `rom.bin` (both 4 MB banks) and
//! `sram.bin` (128 KB) — so the whole app can be driven, filmed and
//! tested with no hardware. `--fake <dir>` selects it.
//!
//! It answers at roughly the real cart's pace (scaled by `speed`), and a
//! file named `unplugged` in the directory pulls the cable.

const std = @import("std");
const proto = @import("protocol.zig");
const usb = @import("usb.zig");

pub const Fake = struct {
    dir: std.fs.Dir,
    rom: ?std.fs.File = null,
    sram: ?std.fs.File = null,
    /// 1.0 = the real cart's measured pace; 0 = instant.
    speed: f32 = 1.0,

    /// Opens (creating if needed) the fake cart directory. A fresh cart
    /// is erased flash ($FF) and empty SRAM.
    pub fn init(path: []const u8, speed: f32) !Fake {
        try std.fs.cwd().makePath(path);
        var dir = try std.fs.cwd().openDir(path, .{});
        errdefer dir.close();
        try ensureFile(dir, "rom.bin", @as(u32, proto.BANK_SIZE) * proto.BANKS, 0xff);
        try ensureFile(dir, "sram.bin", proto.SRAM_SIZE, 0x00);
        return .{ .dir = dir, .speed = speed };
    }

    fn ensureFile(dir: std.fs.Dir, name: []const u8, size: u32, fill: u8) !void {
        if (dir.statFile(name)) |st| {
            if (st.size == size) return;
        } else |_| {}
        var f = try dir.createFile(name, .{});
        defer f.close();
        var block: [64 * 1024]u8 = @splat(fill);
        var left: u32 = size;
        while (left > 0) {
            const n = @min(left, block.len);
            try f.writeAll(block[0..n]);
            left -= n;
        }
    }

    pub fn deinit(self: *Fake) void {
        self.close();
        self.dir.close();
    }

    pub fn present(self: *Fake) bool {
        self.dir.access("unplugged", .{}) catch return true;
        return false;
    }

    pub fn isOpen(self: *const Fake) bool {
        return self.rom != null;
    }

    pub fn open(self: *Fake) usb.Error!void {
        if (self.rom != null) return;
        if (!self.present()) return error.NoCart;
        self.rom = self.dir.openFile("rom.bin", .{ .mode = .read_write }) catch return error.Io;
        self.sram = self.dir.openFile("sram.bin", .{ .mode = .read_write }) catch {
            self.rom.?.close();
            self.rom = null;
            return error.Io;
        };
    }

    pub fn close(self: *Fake) void {
        if (self.rom) |f| f.close();
        if (self.sram) |f| f.close();
        self.rom = null;
        self.sram = null;
    }

    fn file(self: *Fake, mem: proto.Memory) usb.Error!std.fs.File {
        if (!self.present()) {
            self.close();
            return error.Disconnected;
        }
        return (switch (mem) {
            .rom => self.rom,
            .sram => self.sram,
        }) orelse error.Disconnected;
    }

    fn pace(self: *Fake, ns: u64) void {
        if (self.speed <= 0) return;
        std.Thread.sleep(@intFromFloat(@as(f32, @floatFromInt(ns)) / self.speed));
    }

    pub fn read(self: *Fake, mem: proto.Memory, addr: u32, buf: []u8) usb.Error!void {
        const f = try self.file(mem);
        const n = f.preadAll(buf, addr) catch return error.Io;
        if (n != buf.len) return error.Short;
        // measured: 1 MB in ~24 s through a hub = ~94 ms per 4 KB block
        self.pace(94 * std.time.ns_per_ms * buf.len / proto.READ_BLOCK);
    }

    pub fn write(self: *Fake, mem: proto.Memory, addr: u32, data: []const u8) usb.Error!void {
        const f = try self.file(mem);
        // plain overwrite: what a successful write leaves behind
        f.pwriteAll(data, addr) catch return error.Io;
        self.pace(std.time.ns_per_ms);
    }
};
