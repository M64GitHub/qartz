//! The EMS 64M USB cart's wire protocol — everything a transfer needs to
//! know, and nothing about USB itself (usb.zig) or files (job.zig).
//!
//! Ported from ems-qart (rbino/ems-qart, src/EmsCart.*), which got it
//! from ems-flasher. Every transfer is a 9-byte command on the bulk OUT
//! endpoint: one command byte, then the cart address and the byte count,
//! both big-endian u32. A read answers with exactly `count` bytes on the
//! bulk IN endpoint; a write carries its data right behind the command
//! in the same OUT transfer.
//!
//! The cart holds two independent 4 MB flash banks (a ROM per bank) and
//! one 128 KB SRAM shared by both.

const std = @import("std");

pub const VID: u16 = 0x4670;
pub const PID: u16 = 0x9394;
pub const INTERFACE: c_int = 0;
pub const EP_OUT: u8 = 0x02; // 2 | LIBUSB_ENDPOINT_OUT
pub const EP_IN: u8 = 0x81; // 1 | LIBUSB_ENDPOINT_IN

/// The block sizes ems-qart and ems-flasher use; the firmware is only
/// known to answer these.
pub const READ_BLOCK: usize = 4096;
pub const WRITE_BLOCK: usize = 32;

pub const BANK_SIZE: u32 = 0x400000; // 4 MB per bank
pub const SRAM_SIZE: u32 = 0x020000; // 128 KB
pub const BANKS: u8 = 2;

pub const Memory = enum {
    rom,
    sram,

    pub fn label(self: Memory) []const u8 {
        return switch (self) {
            .rom => "ROM",
            .sram => "SRAM",
        };
    }
};

pub const Command = enum(u8) {
    write_sram = 0x4d,
    read_sram = 0x6d,
    write_rom = 0x57,
    read_rom = 0xff,
};

pub fn readCommand(mem: Memory) Command {
    return switch (mem) {
        .rom => .read_rom,
        .sram => .read_sram,
    };
}

pub fn writeCommand(mem: Memory) Command {
    return switch (mem) {
        .rom => .write_rom,
        .sram => .write_sram,
    };
}

pub const CMD_LEN: usize = 9;

pub fn encode(cmd: Command, addr: u32, count: u32) [CMD_LEN]u8 {
    var out: [CMD_LEN]u8 = undefined;
    out[0] = @intFromEnum(cmd);
    std.mem.writeInt(u32, out[1..5], addr, .big);
    std.mem.writeInt(u32, out[5..9], count, .big);
    return out;
}

/// Cart address of a bank's first byte (bank is 1 or 2, as printed on
/// the UI and in ems-qart).
pub fn bankBase(bank: u8) u32 {
    std.debug.assert(bank >= 1 and bank <= BANKS);
    return @as(u32, bank - 1) * BANK_SIZE;
}

/// How many bytes a region holds: a whole bank, or the SRAM.
pub fn capacity(mem: Memory) u32 {
    return switch (mem) {
        .rom => BANK_SIZE,
        .sram => SRAM_SIZE,
    };
}

test "command encoding is ems-flasher's" {
    const c = encode(.read_rom, 0x400000, 4096);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00 }, &c);
    const w = encode(.write_sram, 0x1234, 32);
    try std.testing.expectEqualSlices(u8, &.{ 0x4d, 0x00, 0x00, 0x12, 0x34, 0x00, 0x00, 0x00, 0x20 }, &w);
    try std.testing.expectEqual(@as(u32, 0), bankBase(1));
    try std.testing.expectEqual(@as(u32, 0x400000), bankBase(2));
}
