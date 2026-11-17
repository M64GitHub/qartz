//! qartz — flash EMS 64M USB Game Boy carts from the terminal.
//!
//! A Zig + movy port of ems-qart (rbino/ems-qart). `qartz` alone opens
//! the terminal app; `qartz info|read|write|backup` are the scriptable
//! commands (cli.zig).

const std = @import("std");
const cli = @import("cli.zig");
const worker_mod = @import("cart/worker.zig");
const usb = @import("cart/usb.zig");
const fake = @import("cart/fake.zig");

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var fake_dir: ?[]const u8 = null;
    var fake_speed: f32 = 1.0;
    var verify = true;
    var pos: std.ArrayList([]const u8) = .empty;
    defer pos.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--fake")) {
            i += 1;
            if (i >= args.len) return usage("--fake needs a directory");
            fake_dir = args[i];
        } else if (std.mem.eql(u8, a, "--fake-speed")) {
            i += 1;
            if (i >= args.len) return usage("--fake-speed needs a number");
            fake_speed = std.fmt.parseFloat(f32, args[i]) catch return usage("--fake-speed needs a number");
        } else if (std.mem.eql(u8, a, "--no-verify")) {
            verify = false;
        } else if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            std.debug.print("{s}", .{cli.USAGE});
            return 0;
        } else if (std.mem.startsWith(u8, a, "--")) {
            std.debug.print("qartz: unknown option {s}\n\n{s}", .{ a, cli.USAGE });
            return 2;
        } else {
            try pos.append(allocator, a);
        }
    }

    const dev: worker_mod.Device = if (fake_dir) |d|
        .{ .fake = fake.Fake.init(d, fake_speed) catch |e| {
            std.debug.print("qartz: can't open fake cart {s}: {s}\n", .{ d, @errorName(e) });
            return 1;
        } }
    else
        .{ .usb = usb.Usb.init() catch {
            std.debug.print("qartz: libusb failed to start\n", .{});
            return 1;
        } };

    var w = worker_mod.Worker.init(allocator, dev);
    try w.start();
    defer w.deinit();

    if (pos.items.len > 0) {
        if (!cli.isCommand(pos.items[0])) {
            std.debug.print("qartz: unknown command '{s}'\n\n{s}", .{ pos.items[0], cli.USAGE });
            return 2;
        }
        return cli.run(&w, pos.items, verify);
    }

    std.debug.print("the terminal app is next — try `qartz info`\n", .{});
    return 0;
}

fn usage(msg: []const u8) u8 {
    std.debug.print("qartz: {s}\n\n{s}", .{ msg, cli.USAGE });
    return 2;
}

test {
    _ = @import("cart/protocol.zig");
    _ = @import("cart/rom.zig");
}
