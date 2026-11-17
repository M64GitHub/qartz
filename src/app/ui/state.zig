//! UI state — everything the screen remembers between frames that is not
//! the cart's (the worker owns that, see cart/worker.zig `Status`).

const std = @import("std");
const motion = @import("motion.zig");
const proto = @import("../../cart/protocol.zig");
const rom = @import("../../cart/rom.zig");
const worker = @import("../../cart/worker.zig");

/// The three things on the cart you can point at.
pub const Slot = enum(u2) {
    bank1,
    bank2,
    sram,

    pub fn mem(self: Slot) proto.Memory {
        return if (self == .sram) .sram else .rom;
    }
    /// 1 or 2 (SRAM answers 1: the worker ignores the bank for SRAM).
    pub fn bank(self: Slot) u8 {
        return if (self == .bank2) 2 else 1;
    }
    pub fn label(self: Slot) []const u8 {
        return switch (self) {
            .bank1 => "BANK 1",
            .bank2 => "BANK 2",
            .sram => "SRAM",
        };
    }
    pub fn next(self: Slot) Slot {
        return @enumFromInt((@as(u8, @intFromEnum(self)) + 1) % 3);
    }
    pub fn prev(self: Slot) Slot {
        return @enumFromInt((@as(u8, @intFromEnum(self)) + 2) % 3);
    }
};

/// What a file dialog is open FOR — the picked path goes here.
pub const Intent = enum { read, write, backup };

/// The write confirmation: what is about to go where.
pub const Confirm = struct {
    slot: Slot,
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    file_size: u64 = 0,
    header: ?rom.Header = null,
    verify: bool = true,

    pub fn path(self: *const Confirm) []const u8 {
        return self.path_buf[0..self.path_len];
    }
};

pub const Modal = enum { none, file, confirm, help, quit };

/// A result banner: fades in, holds, dims.
pub const Toast = struct {
    ok: bool = true,
    text: worker.Msg = .{},
    detail: worker.Msg = .{},
    anim: motion.Anim = .{},
};

pub const State = struct {
    frame_no: u64 = 0,
    kitty: bool = false,
    slot: Slot = .bank1,
    modal: Modal = .none,
    intent: Intent = .read,
    intent_slot: Slot = .bank1,
    confirm: Confirm = .{ .slot = .bank1 },
    toast: ?Toast = null,
    /// A cancel of a WRITE needs a second ESC (the bank is left half
    /// flashed); this is the frame the first one landed.
    cancel_armed_at: ?u64 = null,

    // animation clocks
    /// The boot: the logotype scrolls down into place, then blooms.
    boot_anim: motion.Anim = motion.Anim.begin(0, motion.frames(1100)),
    select_anim: motion.Anim = .{},
    power_anim: motion.Anim = .{},
    prev_connected: bool = false,
    seen_finished: u32 = 0,
    flash: motion.Anim = .{},
    flash_ok: bool = true,

    // the one-line transient status (key feedback: "THEME DMG", ...)
    status_buf: [96]u8 = undefined,
    status_len: usize = 0,
    status_at: u64 = 0,

    blink_on: bool = true,

    pub fn setStatus(self: *State, s: []const u8) void {
        const n = @min(s.len, self.status_buf.len);
        @memcpy(self.status_buf[0..n], s[0..n]);
        self.status_len = n;
        self.status_at = self.frame_no;
    }

    pub fn status(self: *const State) ?[]const u8 {
        if (self.status_len == 0) return null;
        if (self.frame_no -| self.status_at > motion.frames(2500)) return null;
        return self.status_buf[0..self.status_len];
    }

    pub fn select(self: *State, s: Slot) void {
        if (s == self.slot) return;
        self.slot = s;
        self.select_anim = motion.Anim.begin(self.frame_no, motion.frames(220));
    }
};
