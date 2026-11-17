//! The Game Boy cartridge header ($0100-$014F) — what a bank holds, read
//! from its first 0x150 bytes, and the two checksums that prove a dump.

const std = @import("std");

pub const HEADER_LEN: usize = 0x150;

const LOGO_OFF = 0x104;
const TITLE_OFF = 0x134;
const CGB_OFF = 0x143;
const SGB_OFF = 0x146;
const TYPE_OFF = 0x147;
const ROM_SIZE_OFF = 0x148;
const RAM_SIZE_OFF = 0x149;
const VERSION_OFF = 0x14c;
const HCHK_OFF = 0x14d;
const GCHK_OFF = 0x14e;

/// The first bytes of the Nintendo logo every bootable ROM carries.
const LOGO_HEAD = [_]u8{ 0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B };

pub const Cgb = enum { dmg, cgb_enhanced, cgb_only };

pub const Header = struct {
    title_buf: [16]u8 = @splat(0),
    title_len: u8 = 0,
    cgb: Cgb = .dmg,
    sgb: bool = false,
    cart_type: u8 = 0,
    /// Bytes, from the size code; 0 when the code is unknown.
    rom_size: u32 = 0,
    ram_size: u32 = 0,
    version: u8 = 0,
    logo_ok: bool = false,
    header_checksum_ok: bool = false,
    global_checksum: u16 = 0,

    pub fn title(self: *const Header) []const u8 {
        return self.title_buf[0..self.title_len];
    }

    /// A bank whose header doesn't check out is empty or erased (all
    /// $FF) or holds something that is not a Game Boy ROM.
    pub fn valid(self: *const Header) bool {
        return self.header_checksum_ok;
    }

    pub fn typeName(self: *const Header) []const u8 {
        return cartTypeName(self.cart_type);
    }
};

/// Parse a header from the first 0x150 bytes of a bank or file. Null if
/// the slice is too short to hold one.
pub fn parse(bytes: []const u8) ?Header {
    if (bytes.len < HEADER_LEN) return null;
    var h: Header = .{};

    h.cgb = switch (bytes[CGB_OFF]) {
        0x80 => .cgb_enhanced,
        0xC0 => .cgb_only,
        else => .dmg,
    };
    // A CGB flag lives in the title's 16th byte, and newer carts spend
    // bytes 12-15 on a manufacturer code; stop at the first NUL or
    // non-printable either way.
    const max_title: usize = if (h.cgb == .dmg) 16 else 15;
    var n: usize = 0;
    while (n < max_title) : (n += 1) {
        const ch = bytes[TITLE_OFF + n];
        if (ch < 0x20 or ch > 0x7e) break;
        h.title_buf[n] = ch;
    }
    while (n > 0 and h.title_buf[n - 1] == ' ') n -= 1;
    h.title_len = @intCast(n);

    h.sgb = bytes[SGB_OFF] == 0x03;
    h.cart_type = bytes[TYPE_OFF];
    h.rom_size = romSizeFromCode(bytes[ROM_SIZE_OFF]);
    h.ram_size = ramSizeFromCode(bytes[RAM_SIZE_OFF]);
    h.version = bytes[VERSION_OFF];
    h.logo_ok = std.mem.eql(u8, bytes[LOGO_OFF..][0..LOGO_HEAD.len], &LOGO_HEAD);

    var sum: u8 = 0;
    for (bytes[TITLE_OFF..HCHK_OFF]) |b| sum = sum -% b -% 1;
    h.header_checksum_ok = sum == bytes[HCHK_OFF];
    h.global_checksum = std.mem.readInt(u16, bytes[GCHK_OFF..][0..2], .big);
    return h;
}

pub fn romSizeFromCode(code: u8) u32 {
    return switch (code) {
        0...8 => @as(u32, 32 * 1024) << @intCast(code),
        0x52 => 1179648,
        0x53 => 1310720,
        0x54 => 1572864,
        else => 0,
    };
}

pub fn ramSizeFromCode(code: u8) u32 {
    return switch (code) {
        1 => 2 * 1024,
        2 => 8 * 1024,
        3 => 32 * 1024,
        4 => 128 * 1024,
        5 => 64 * 1024,
        else => 0,
    };
}

/// The global checksum: the 16-bit sum of every byte of the ROM except
/// the two that store it. Real hardware ignores it, which is exactly why
/// it is a good test of a complete dump.
pub fn globalChecksum(rom: []const u8) u16 {
    var sum: u16 = 0;
    for (rom, 0..) |b, i| {
        if (i == GCHK_OFF or i == GCHK_OFF + 1) continue;
        sum +%= b;
    }
    return sum;
}

pub fn cartTypeName(t: u8) []const u8 {
    return switch (t) {
        0x00 => "ROM ONLY",
        0x01 => "MBC1",
        0x02 => "MBC1+RAM",
        0x03 => "MBC1+RAM+BATT",
        0x05 => "MBC2",
        0x06 => "MBC2+BATT",
        0x08 => "ROM+RAM",
        0x09 => "ROM+RAM+BATT",
        0x0B => "MMM01",
        0x0C => "MMM01+RAM",
        0x0D => "MMM01+RAM+BATT",
        0x0F => "MBC3+RTC+BATT",
        0x10 => "MBC3+RTC+RAM+BATT",
        0x11 => "MBC3",
        0x12 => "MBC3+RAM",
        0x13 => "MBC3+RAM+BATT",
        0x19 => "MBC5",
        0x1A => "MBC5+RAM",
        0x1B => "MBC5+RAM+BATT",
        0x1C => "MBC5+RUMBLE",
        0x1D => "MBC5+RUMBLE+RAM",
        0x1E => "MBC5+RUMBLE+RAM+BATT",
        0x20 => "MBC6",
        0x22 => "MBC7",
        0xFC => "POCKET CAMERA",
        0xFD => "BANDAI TAMA5",
        0xFE => "HuC3",
        0xFF => "HuC1+RAM+BATT",
        else => "UNKNOWN",
    };
}

/// Human byte size: "128K", "1M", "4M", "1.1M".
pub fn sizeText(bytes: u32, buf: []u8) []const u8 {
    if (bytes >= 1024 * 1024) {
        if (bytes % (1024 * 1024) == 0)
            return std.fmt.bufPrint(buf, "{d}M", .{bytes / (1024 * 1024)}) catch "?";
        const tenths = (@as(u64, bytes) * 10 + 512 * 1024) / (1024 * 1024);
        return std.fmt.bufPrint(buf, "{d}.{d}M", .{ tenths / 10, tenths % 10 }) catch "?";
    }
    if (bytes >= 1024) return std.fmt.bufPrint(buf, "{d}K", .{bytes / 1024}) catch "?";
    return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "?";
}

fn testHeader() [HEADER_LEN]u8 {
    var b: [HEADER_LEN]u8 = @splat(0);
    @memcpy(b[LOGO_OFF..][0..LOGO_HEAD.len], &LOGO_HEAD);
    @memcpy(b[TITLE_OFF..][0..11], "LSDj-v8.5.1");
    b[TYPE_OFF] = 0x1B;
    b[ROM_SIZE_OFF] = 5;
    b[RAM_SIZE_OFF] = 4;
    var sum: u8 = 0;
    for (b[TITLE_OFF..HCHK_OFF]) |x| sum = sum -% x -% 1;
    b[HCHK_OFF] = sum;
    return b;
}

test "header: title, sizes, type, checksum" {
    const b = testHeader();
    const h = parse(&b).?;
    try std.testing.expectEqualStrings("LSDj-v8.5.1", h.title());
    try std.testing.expectEqual(@as(u32, 1024 * 1024), h.rom_size);
    try std.testing.expectEqual(@as(u32, 128 * 1024), h.ram_size);
    try std.testing.expectEqualStrings("MBC5+RAM+BATT", h.typeName());
    try std.testing.expect(h.header_checksum_ok and h.logo_ok and h.valid());

    var bad = b;
    bad[TITLE_OFF] ^= 1;
    try std.testing.expect(!parse(&bad).?.valid());
    try std.testing.expect(parse(b[0..0x100]) == null);
}

test "an erased bank is not valid" {
    const ff: [HEADER_LEN]u8 = @splat(0xff);
    const h = parse(&ff).?;
    try std.testing.expect(!h.valid());
    try std.testing.expectEqual(@as(usize, 0), h.title().len);
}

test "sizes print short" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("128K", sizeText(128 * 1024, &buf));
    try std.testing.expectEqualStrings("4M", sizeText(4 * 1024 * 1024, &buf));
    try std.testing.expectEqualStrings("1.1M", sizeText(1179648, &buf));
}
