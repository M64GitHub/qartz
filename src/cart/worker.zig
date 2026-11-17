//! The worker: one thread that OWNS the cart. Nothing else touches the
//! device, so there is no locking around USB at all.
//!
//! Idle, it watches the bus twice a second — opens the cart when it
//! appears (and reads both bank headers), lets go when it vanishes. A
//! submitted job (read / write+verify / backup) runs to completion,
//! failure or cancel, publishing progress as it goes.
//!
//! The UI (or the CLI) reads everything through `snapshot()`: a copy of
//! `Status` taken under the mutex, once per frame.

const std = @import("std");
const proto = @import("protocol.zig");
const rom = @import("rom.zig");
const usb = @import("usb.zig");
const fake = @import("fake.zig");

pub const Memory = proto.Memory;

pub const Device = union(enum) {
    usb: usb.Usb,
    fake: fake.Fake,

    pub fn deinit(self: *Device) void {
        switch (self.*) {
            inline else => |*d| d.deinit(),
        }
    }
    pub fn open(self: *Device) usb.Error!void {
        switch (self.*) {
            inline else => |*d| return d.open(),
        }
    }
    pub fn close(self: *Device) void {
        switch (self.*) {
            inline else => |*d| d.close(),
        }
    }
    pub fn isOpen(self: *Device) bool {
        return switch (self.*) {
            inline else => |*d| d.isOpen(),
        };
    }
    pub fn present(self: *Device) bool {
        return switch (self.*) {
            inline else => |*d| d.present(),
        };
    }
    pub fn read(self: *Device, mem: Memory, addr: u32, buf: []u8) usb.Error!void {
        switch (self.*) {
            inline else => |*d| return d.read(mem, addr, buf),
        }
    }
    pub fn write(self: *Device, mem: Memory, addr: u32, data: []const u8) usb.Error!void {
        switch (self.*) {
            inline else => |*d| return d.write(mem, addr, data),
        }
    }
};

/// A short, fixed-size message (no allocation crosses the thread line).
pub const Msg = struct {
    buf: [192]u8 = undefined,
    len: u8 = 0,

    pub fn set(self: *Msg, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(&self.buf, fmt, args) catch self.buf[0..];
        self.len = @intCast(s.len);
    }
    pub fn clear(self: *Msg) void {
        self.len = 0;
    }
    pub fn slice(self: *const Msg) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const Kind = enum { read, write, backup };

pub const Request = struct {
    kind: Kind,
    mem: Memory = .rom,
    bank: u8 = 1,
    /// read: the file to create; write: the file to flash; backup: a
    /// directory to create the three files in.
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    verify: bool = true,

    pub fn path(self: *const Request) []const u8 {
        return self.path_buf[0..self.path_len];
    }
    pub fn setPath(self: *Request, p: []const u8) void {
        const n = @min(p.len, self.path_buf.len);
        @memcpy(self.path_buf[0..n], p[0..n]);
        self.path_len = n;
    }
};

pub const Phase = enum { idle, reading, writing, verifying };
pub const Outcome = enum { none, ok, failed, cancelled };

pub const Status = struct {
    connected: bool = false,
    device_label: []const u8 = "EMS 64M",
    /// Bank headers as of the last connect / write; null = unreadable.
    banks: [2]?rom.Header = .{ null, null },
    /// Why an attached cart could not be opened (empty = just absent).
    conn_err: Msg = .{},

    busy: bool = false,
    phase: Phase = .idle,
    job: ?Request = null,
    /// Backup walks three regions; `step` counts them (1-based).
    step: u8 = 0,
    steps: u8 = 0,
    done: u32 = 0,
    total: u32 = 0,
    started_ns: i128 = 0,

    /// Bumped every time a job ends; the UI watches it for toasts.
    finished: u32 = 0,
    outcome: Outcome = .none,
    msg: Msg = .{},
    detail: Msg = .{},
    elapsed_ms: u64 = 0,

    pub fn fraction(self: *const Status) f32 {
        if (self.total == 0) return 0;
        return @as(f32, @floatFromInt(self.done)) / @as(f32, @floatFromInt(self.total));
    }
};

pub const Worker = struct {
    allocator: std.mem.Allocator,
    dev: Device,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    status: Status = .{},
    pending: ?Request = null,
    quit: bool = false,
    cancel_flag: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, dev: Device) Worker {
        var w: Worker = .{ .allocator = allocator, .dev = dev };
        w.status.device_label = switch (dev) {
            .usb => "EMS 64M",
            .fake => "FAKE CART",
        };
        return w;
    }

    pub fn start(self: *Worker) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn deinit(self: *Worker) void {
        self.mutex.lock();
        self.quit = true;
        self.cond.signal();
        self.mutex.unlock();
        self.cancel_flag.store(true, .release);
        if (self.thread) |t| t.join();
        self.dev.deinit();
    }

    pub fn snapshot(self: *Worker) Status {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.status;
    }

    /// False when a job is already queued or running.
    pub fn submit(self: *Worker, req: Request) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.status.busy or self.pending != null) return false;
        self.pending = req;
        self.status.busy = true; // busy from the moment it is queued
        self.cancel_flag.store(false, .release);
        self.cond.signal();
        return true;
    }

    pub fn cancel(self: *Worker) void {
        self.cancel_flag.store(true, .release);
    }

    // ------------------------------------------------------------ thread

    fn run(self: *Worker) void {
        self.watch();
        while (true) {
            self.mutex.lock();
            if (!self.quit and self.pending == null)
                self.cond.timedWait(&self.mutex, 500 * std.time.ns_per_ms) catch {};
            if (self.quit) {
                self.mutex.unlock();
                break;
            }
            const req = self.pending;
            self.pending = null;
            self.mutex.unlock();

            if (req) |r| self.runJob(r) else self.watch();
        }
        self.dev.close();
    }

    /// Hotplug by polling: open on arrival, let go on departure.
    fn watch(self: *Worker) void {
        if (self.dev.isOpen()) {
            if (!self.dev.present()) self.disconnect();
            return;
        }
        if (!self.dev.present()) {
            self.mutex.lock();
            self.status.conn_err.clear();
            self.mutex.unlock();
            return;
        }
        self.dev.open() catch |err| {
            self.mutex.lock();
            defer self.mutex.unlock();
            switch (err) {
                error.Access => self.status.conn_err.set("USB access denied (on Linux: install the udev rule)", .{}),
                error.Busy => self.status.conn_err.set("cart is in use by another program (ems-qart?)", .{}),
                else => self.status.conn_err.set("cart found but it won't open ({s})", .{@errorName(err)}),
            }
            return;
        };
        const banks = self.readHeaders();
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status.connected = true;
        self.status.conn_err.clear();
        self.status.banks = banks;
    }

    fn disconnect(self: *Worker) void {
        self.dev.close();
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status.connected = false;
        self.status.banks = .{ null, null };
    }

    fn readHeaders(self: *Worker) [2]?rom.Header {
        var out: [2]?rom.Header = .{ null, null };
        for (0..proto.BANKS) |i| {
            var buf: [512]u8 = undefined;
            self.dev.read(.rom, proto.bankBase(@intCast(i + 1)), &buf) catch continue;
            out[i] = rom.parse(&buf);
        }
        return out;
    }

    fn setProgress(self: *Worker, phase: Phase, done: u32, total: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status.phase = phase;
        self.status.done = done;
        self.status.total = total;
    }

    fn setStep(self: *Worker, step: u8, steps: u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status.step = step;
        self.status.steps = steps;
    }

    const JobError = usb.Error || error{
        Cancelled,
        VerifyFailed,
        FileTooBig,
        EmptyFile,
        OutOfMemory,
        FileError,
    };

    fn runJob(self: *Worker, req: Request) void {
        const t0 = std.time.nanoTimestamp();
        self.mutex.lock();
        self.status.job = req;
        self.status.step = 0;
        self.status.steps = 0;
        self.status.done = 0;
        self.status.total = 0;
        self.status.started_ns = t0;
        self.status.detail.clear();
        self.mutex.unlock();

        var detail: Msg = .{};
        var msg: Msg = .{};
        const result: JobError!void = blk: {
            if (!self.dev.isOpen()) self.dev.open() catch |e| break :blk e;
            break :blk switch (req.kind) {
                .read => self.doRead(req, &msg, &detail),
                .write => self.doWrite(req, &msg, &detail),
                .backup => self.doBackup(req, &msg, &detail),
            };
        };
        const outcome: Outcome = if (result) |_| .ok else |err| switch (err) {
            error.Cancelled => .cancelled,
            else => .failed,
        };
        if (result) |_| {} else |err| {
            describe(err, &msg, &detail);
            switch (err) {
                error.Disconnected, error.Timeout, error.Io, error.Short => self.disconnect(),
                else => {},
            }
        }
        // a write changed what the banks hold
        const banks: ?[2]?rom.Header = if (req.kind == .write and req.mem == .rom and self.dev.isOpen())
            self.readHeaders()
        else
            null;

        self.mutex.lock();
        defer self.mutex.unlock();
        if (banks) |b| self.status.banks = b;
        self.status.busy = false;
        self.status.phase = .idle;
        self.status.outcome = outcome;
        self.status.msg = msg;
        if (detail.len > 0) self.status.detail = detail;
        self.status.elapsed_ms = @intCast(@divTrunc(std.time.nanoTimestamp() - t0, std.time.ns_per_ms));
        self.status.finished +%= 1;
    }

    fn describe(err: JobError, msg: *Msg, detail: *Msg) void {
        switch (err) {
            error.Cancelled => msg.set("cancelled", .{}),
            error.NoCart => msg.set("no cart connected", .{}),
            error.Access => msg.set("USB access denied", .{}),
            error.Busy => msg.set("cart is in use by another program", .{}),
            error.Disconnected => msg.set("the cart was unplugged", .{}),
            error.Timeout => msg.set("the cart stopped answering", .{}),
            error.Io, error.Short => msg.set("USB transfer failed", .{}),
            error.UsbInit => msg.set("libusb failed to start", .{}),
            error.FileTooBig => if (msg.len == 0) msg.set("file is too big for that memory", .{}),
            error.EmptyFile => msg.set("file is empty", .{}),
            error.OutOfMemory => msg.set("out of memory", .{}),
            error.FileError => if (msg.len == 0) msg.set("file error", .{}),
            error.VerifyFailed => if (msg.len == 0) msg.set("verify failed", .{}),
        }
        _ = detail;
    }

    fn cancelled(self: *Worker) bool {
        return self.cancel_flag.load(.acquire);
    }

    /// How much a read should fetch: a ROM bank's header knows its size;
    /// an unreadable or blank bank gets read whole.
    fn readSize(self: *Worker, mem: Memory, bank: u8) u32 {
        if (mem == .sram) return proto.SRAM_SIZE;
        self.mutex.lock();
        const h = self.status.banks[bank - 1];
        self.mutex.unlock();
        if (h) |hh| {
            if (hh.valid() and hh.rom_size > 0 and hh.rom_size <= proto.BANK_SIZE) return hh.rom_size;
        }
        return proto.BANK_SIZE;
    }

    fn base(mem: Memory, bank: u8) u32 {
        return if (mem == .rom) proto.bankBase(bank) else 0;
    }

    /// Read a region into a fresh buffer, publishing progress.
    fn fetch(self: *Worker, mem: Memory, addr: u32, size: u32) JobError![]u8 {
        const buf = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(buf);
        var off: u32 = 0;
        self.setProgress(.reading, 0, size);
        while (off < size) {
            if (self.cancelled()) return error.Cancelled;
            const n: u32 = @min(proto.READ_BLOCK, size - off);
            try self.dev.read(mem, addr + off, buf[off..][0..n]);
            off += n;
            self.setProgress(.reading, off, size);
        }
        return buf;
    }

    /// Write whole, or not at all: `<path>.part`, then rename.
    fn saveFile(path: []const u8, data: []const u8, msg: *Msg) JobError!void {
        var part_buf: [std.fs.max_path_bytes + 8]u8 = undefined;
        const part = std.fmt.bufPrint(&part_buf, "{s}.part", .{path}) catch return error.FileError;
        const cwd = std.fs.cwd();
        {
            var f = cwd.createFile(part, .{}) catch |e| {
                msg.set("can't create {s} ({s})", .{ std.fs.path.basename(path), @errorName(e) });
                return error.FileError;
            };
            defer f.close();
            f.writeAll(data) catch |e| {
                msg.set("can't write {s} ({s})", .{ std.fs.path.basename(path), @errorName(e) });
                cwd.deleteFile(part) catch {};
                return error.FileError;
            };
        }
        cwd.rename(part, path) catch |e| {
            msg.set("can't save {s} ({s})", .{ std.fs.path.basename(path), @errorName(e) });
            cwd.deleteFile(part) catch {};
            return error.FileError;
        };
    }

    fn checksumLine(data: []const u8, detail: *Msg) void {
        const h = rom.parse(data) orelse return;
        if (!h.valid()) {
            detail.set("no valid ROM header in this bank", .{});
            return;
        }
        const sum = rom.globalChecksum(data);
        if (sum == h.global_checksum)
            detail.set("{s} · global checksum {X:0>4} OK", .{ h.title(), sum })
        else
            detail.set("{s} · global checksum {X:0>4}, header says {X:0>4}", .{ h.title(), sum, h.global_checksum });
    }

    fn doRead(self: *Worker, req: Request, msg: *Msg, detail: *Msg) JobError!void {
        const size = self.readSize(req.mem, req.bank);
        const data = try self.fetch(req.mem, base(req.mem, req.bank), size);
        defer self.allocator.free(data);
        try saveFile(req.path(), data, msg);
        var sb: [16]u8 = undefined;
        msg.set("saved {s} ({s})", .{ std.fs.path.basename(req.path()), rom.sizeText(size, &sb) });
        if (req.mem == .rom) checksumLine(data, detail);
    }

    fn doWrite(self: *Worker, req: Request, msg: *Msg, detail: *Msg) JobError!void {
        const cap = proto.capacity(req.mem);
        const name = std.fs.path.basename(req.path());
        const file_data = std.fs.cwd().readFileAlloc(self.allocator, req.path(), cap + 1) catch |e| switch (e) {
            error.FileTooBig => {
                var sb: [16]u8 = undefined;
                msg.set("{s} doesn't fit: {s} holds {s}", .{ name, req.mem.label(), rom.sizeText(cap, &sb) });
                return error.FileTooBig;
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                msg.set("can't read {s} ({s})", .{ name, @errorName(e) });
                return error.FileError;
            },
        };
        defer self.allocator.free(file_data);
        if (file_data.len == 0) return error.EmptyFile;
        if (file_data.len > cap) {
            var sb: [16]u8 = undefined;
            msg.set("{s} doesn't fit: {s} holds {s}", .{ name, req.mem.label(), rom.sizeText(cap, &sb) });
            return error.FileTooBig;
        }

        // whole blocks only: pad the tail like erased flash / empty SRAM
        const len: u32 = @intCast(std.mem.alignForward(usize, file_data.len, proto.WRITE_BLOCK));
        const data = try self.allocator.alloc(u8, len);
        defer self.allocator.free(data);
        @memcpy(data[0..file_data.len], file_data);
        @memset(data[file_data.len..], if (req.mem == .rom) 0xff else 0x00);

        const addr = base(req.mem, req.bank);
        var off: u32 = 0;
        self.setProgress(.writing, 0, len);
        while (off < len) : (off += proto.WRITE_BLOCK) {
            if (self.cancelled()) return error.Cancelled;
            try self.dev.write(req.mem, addr + off, data[off..][0..proto.WRITE_BLOCK]);
            if (off % 1024 == 0) self.setProgress(.writing, off, len);
        }
        self.setProgress(.writing, len, len);

        if (req.verify) {
            var vbuf: [proto.READ_BLOCK]u8 = undefined;
            off = 0;
            self.setProgress(.verifying, 0, len);
            while (off < len) {
                if (self.cancelled()) return error.Cancelled;
                const n: u32 = @min(proto.READ_BLOCK, len - off);
                try self.dev.read(req.mem, addr + off, vbuf[0..n]);
                if (!std.mem.eql(u8, vbuf[0..n], data[off..][0..n])) {
                    const i = std.mem.indexOfDiff(u8, vbuf[0..n], data[off..][0..n]).?;
                    msg.set("verify failed at ${X:0>6}: wrote {X:0>2}, read {X:0>2}", .{ addr + off + @as(u32, @intCast(i)), data[off + i], vbuf[i] });
                    return error.VerifyFailed;
                }
                off += n;
                self.setProgress(.verifying, off, len);
            }
        }
        var sb: [16]u8 = undefined;
        if (req.mem == .rom)
            msg.set("flashed {s} to bank {d} ({s}){s}", .{ name, req.bank, rom.sizeText(len, &sb), if (req.verify) ", verified" else "" })
        else
            msg.set("wrote {s} to SRAM ({s}){s}", .{ name, rom.sizeText(len, &sb), if (req.verify) ", verified" else "" });
        if (req.mem == .rom) checksumLine(data, detail);
    }

    /// Everything on the cart into one directory: bank1.gb, bank2.gb,
    /// sram.sav. Files are named after the ROM titles when they have one.
    fn doBackup(self: *Worker, req: Request, msg: *Msg, detail: *Msg) JobError!void {
        const dir = req.path();
        std.fs.cwd().makePath(dir) catch |e| {
            msg.set("can't create {s} ({s})", .{ dir, @errorName(e) });
            return error.FileError;
        };
        var names: [3][std.fs.max_path_bytes]u8 = undefined;
        var saved: usize = 0;
        for (0..3) |i| {
            self.setStep(@intCast(i + 1), 3);
            const mem: Memory = if (i < 2) .rom else .sram;
            const bank: u8 = if (i < 2) @intCast(i + 1) else 1;
            var stem_buf: [64]u8 = undefined;
            const stem = if (mem == .sram) "sram" else self.backupStem(bank, &stem_buf);
            const path = std.fmt.bufPrint(&names[i], "{s}/{s}{s}", .{ dir, stem, if (mem == .sram) ".sav" else ".gb" }) catch return error.FileError;
            const data = try self.fetch(mem, base(mem, bank), self.readSize(mem, bank));
            defer self.allocator.free(data);
            try saveFile(path, data, msg);
            saved += 1;
        }
        msg.set("backed up both banks + SRAM to {s}", .{dir});
        detail.clear();
    }

    fn backupStem(self: *Worker, bank: u8, buf: []u8) []const u8 {
        self.mutex.lock();
        const h = self.status.banks[bank - 1];
        self.mutex.unlock();
        if (h) |hh| {
            if (hh.valid() and hh.title().len > 0) {
                var n: usize = 0;
                const pre = std.fmt.bufPrint(buf, "bank{d}-", .{bank}) catch return "bank";
                n = pre.len;
                for (hh.title()) |ch| {
                    if (n >= buf.len) break;
                    buf[n] = if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_') ch else '_';
                    n += 1;
                }
                return buf[0..n];
            }
        }
        return std.fmt.bufPrint(buf, "bank{d}", .{bank}) catch "bank";
    }
};
