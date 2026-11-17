//! The real cart, over libusb. One handle, interface 0 claimed, bulk
//! transfers with timeouts (ems-qart waited forever — a pulled cable
//! hung the app).

const std = @import("std");
const proto = @import("protocol.zig");
const c = @cImport(@cInclude("libusb.h"));

pub const Error = error{
    UsbInit,
    NoCart,
    Access,
    Busy,
    Disconnected,
    Timeout,
    Io,
    Short,
};

/// A 4 KB read takes ~90 ms on the EMS firmware; a stuck one is broken.
const TIMEOUT_MS: c_uint = 5000;

fn mapErr(r: c_int) Error {
    return switch (r) {
        c.LIBUSB_ERROR_ACCESS => error.Access,
        c.LIBUSB_ERROR_NO_DEVICE => error.Disconnected,
        c.LIBUSB_ERROR_NOT_FOUND => error.NoCart,
        c.LIBUSB_ERROR_BUSY => error.Busy,
        c.LIBUSB_ERROR_TIMEOUT => error.Timeout,
        else => error.Io,
    };
}

pub const Usb = struct {
    ctx: ?*c.libusb_context = null,
    handle: ?*c.libusb_device_handle = null,

    pub fn init() Error!Usb {
        var u: Usb = .{};
        if (c.libusb_init(&u.ctx) < 0) return error.UsbInit;
        return u;
    }

    pub fn deinit(self: *Usb) void {
        self.close();
        c.libusb_exit(self.ctx);
        self.ctx = null;
    }

    pub fn isOpen(self: *const Usb) bool {
        return self.handle != null;
    }

    /// Is an EMS cart on the bus right now (opened or not)?
    pub fn present(self: *Usb) bool {
        var list: [*c]?*c.libusb_device = undefined;
        const n = c.libusb_get_device_list(self.ctx, &list);
        if (n < 0) return false;
        defer c.libusb_free_device_list(list, 1);
        for (0..@intCast(n)) |i| {
            if (isCart(list[i])) return true;
        }
        return false;
    }

    fn isCart(dev: ?*c.libusb_device) bool {
        var desc: c.libusb_device_descriptor = undefined;
        if (c.libusb_get_device_descriptor(dev, &desc) != 0) return false;
        return desc.idVendor == proto.VID and desc.idProduct == proto.PID;
    }

    pub fn open(self: *Usb) Error!void {
        if (self.handle != null) return;
        var list: [*c]?*c.libusb_device = undefined;
        const n = c.libusb_get_device_list(self.ctx, &list);
        if (n < 0) return error.Io;
        defer c.libusb_free_device_list(list, 1);
        for (0..@intCast(n)) |i| {
            const dev = list[i];
            if (!isCart(dev)) continue;
            var h: ?*c.libusb_device_handle = null;
            const r = c.libusb_open(dev, &h);
            if (r != 0) return mapErr(r);
            const cr = c.libusb_claim_interface(h, proto.INTERFACE);
            if (cr != 0) {
                c.libusb_close(h);
                return mapErr(cr);
            }
            self.handle = h;
            return;
        }
        return error.NoCart;
    }

    pub fn close(self: *Usb) void {
        if (self.handle) |h| {
            _ = c.libusb_release_interface(h, proto.INTERFACE);
            c.libusb_close(h);
            self.handle = null;
        }
    }

    fn bulk(h: *c.libusb_device_handle, ep: u8, data: []u8) Error!void {
        var got: c_int = 0;
        const r = c.libusb_bulk_transfer(h, ep, data.ptr, @intCast(data.len), &got, TIMEOUT_MS);
        if (r != 0) return mapErr(r);
        if (got != data.len) return error.Short;
    }

    /// One read command: `buf.len` bytes (≤ READ_BLOCK) from `addr`.
    pub fn read(self: *Usb, mem: proto.Memory, addr: u32, buf: []u8) Error!void {
        const h = self.handle orelse return error.Disconnected;
        std.debug.assert(buf.len <= proto.READ_BLOCK);
        var cmd = proto.encode(proto.readCommand(mem), addr, @intCast(buf.len));
        try bulk(h, proto.EP_OUT, &cmd);
        try bulk(h, proto.EP_IN, buf);
    }

    /// One write command: exactly WRITE_BLOCK bytes at `addr`.
    pub fn write(self: *Usb, mem: proto.Memory, addr: u32, data: []const u8) Error!void {
        const h = self.handle orelse return error.Disconnected;
        std.debug.assert(data.len == proto.WRITE_BLOCK);
        var pkt: [proto.CMD_LEN + proto.WRITE_BLOCK]u8 = undefined;
        pkt[0..proto.CMD_LEN].* = proto.encode(proto.writeCommand(mem), addr, proto.WRITE_BLOCK);
        @memcpy(pkt[proto.CMD_LEN..], data);
        try bulk(h, proto.EP_OUT, &pkt);
    }
};
