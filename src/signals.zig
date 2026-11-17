//! Stop signals. Closing the terminal window (SIGHUP), SIGTERM and Ctrl+C
//! in the CLI must not kill qartz mid-transfer: a cart abandoned halfway
//! through a read hangs — it stops answering even USB control requests —
//! until it is unplugged. The handler only raises a flag; the loops see
//! it, cancel the job, and the worker finishes the block in flight before
//! the process exits.

const std = @import("std");

pub var stop: std.atomic.Value(bool) = .init(false);

fn handler(_: i32) callconv(.c) void {
    stop.store(true, .release);
}

pub fn install() void {
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = handler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
    std.posix.sigaction(std.posix.SIG.HUP, &act, null);
}

pub fn requested() bool {
    return stop.load(.acquire);
}
