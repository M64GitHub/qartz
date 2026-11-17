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
const app = @import("app/app.zig");
const term = @import("app/term.zig");

/// zig `defer`s don't run on @panic: restore the terminal first, or a
/// crash strands the shell in raw mode on the alternate screen.
pub const panic = std.debug.FullPanic(panicRestore);

fn panicRestore(msg: []const u8, first_trace_addr: ?usize) noreturn {
    term.panicCleanup();
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var fake_dir: ?[]const u8 = null;
    var fake_speed: f32 = 1.0;
    var verify = true;
    var opts: app.Options = .{};
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
        } else if (std.mem.eql(u8, a, "--scheme")) {
            i += 1;
            if (i >= args.len) return usage("--scheme needs a name");
            opts.scheme = args[i];
        } else if (std.mem.eql(u8, a, "--dump-screen")) {
            opts.headless = true;
            opts.dump = true;
        } else if (std.mem.eql(u8, a, "--shot")) {
            i += 1;
            if (i >= args.len) return usage("--shot needs a .png path");
            opts.headless = true;
            opts.shot = args[i];
        } else if (std.mem.eql(u8, a, "--frames")) {
            i += 1;
            if (i >= args.len) return usage("--frames needs a number");
            opts.frames = std.fmt.parseInt(u64, args[i], 10) catch return usage("--frames needs a number");
        } else if (std.mem.eql(u8, a, "--size")) {
            i += 1;
            if (i >= args.len) return usage("--size needs COLSxROWS");
            const x = std.mem.indexOfScalar(u8, args[i], 'x') orelse return usage("--size needs COLSxROWS");
            opts.cols = std.fmt.parseInt(usize, args[i][0..x], 10) catch return usage("--size needs COLSxROWS");
            opts.rows = std.fmt.parseInt(usize, args[i][x + 1 ..], 10) catch return usage("--size needs COLSxROWS");
        } else if (std.mem.eql(u8, a, "--keys")) {
            i += 1;
            if (i >= args.len) return usage("--keys needs a script");
            opts.keys = args[i];
        } else if (std.mem.eql(u8, a, "--motion")) {
            opts.motion_on = true;
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

    return app.run(allocator, &w, opts);
}

fn usage(msg: []const u8) u8 {
    std.debug.print("qartz: {s}\n\n{s}", .{ msg, cli.USAGE });
    return 2;
}

test {
    _ = @import("cart/protocol.zig");
    _ = @import("cart/rom.zig");
    _ = @import("app/ui/filedialog.zig");
    _ = @import("app/ui/motion.zig");
}
