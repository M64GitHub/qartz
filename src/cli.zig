//! The command line: the same worker the TUI drives, polled from a
//! plain loop that draws a one-line progress bar.

const std = @import("std");
const proto = @import("cart/protocol.zig");
const rom = @import("cart/rom.zig");
const worker_mod = @import("cart/worker.zig");
const Worker = worker_mod.Worker;
const signals = @import("signals.zig");

pub const USAGE =
    \\qartz — EMS 64M USB Game Boy cart flasher
    \\
    \\  qartz                              the terminal app
    \\  qartz info                         cart status and what both banks hold
    \\  qartz read rom <1|2> <file.gb>     dump a ROM bank
    \\  qartz read sram <file.sav>         dump the save RAM
    \\  qartz write rom <1|2> <file.gb>    flash a ROM into a bank (then verify)
    \\  qartz write sram <file.sav>        write the save RAM (then verify)
    \\  qartz backup <dir>                 both banks + SRAM into <dir>
    \\
    \\options:
    \\  --no-verify          skip the read-back after a write
    \\  --fake <dir>         use a fake cart kept in <dir> (no hardware)
    \\  --fake-speed <x>     fake cart pace, 1 = real, 0 = instant (default 1)
    \\  --scheme <name>      colour theme (t cycles them in the app; DMG default)
    \\
    \\headless (for tests and screenshots):
    \\  --dump-screen        print the text layer after --frames frames
    \\  --shot <file.png>    save the pixel layer after --frames frames
    \\  --frames <n>  --size <cols>x<rows>  --keys "30:w,60:enter"  --motion
    \\
;

pub fn isCommand(word: []const u8) bool {
    const cmds = [_][]const u8{ "info", "read", "write", "backup", "help" };
    for (cmds) |c| if (std.mem.eql(u8, word, c)) return true;
    return false;
}

fn fail(comptime fmt: []const u8, args: anytype) u8 {
    std.debug.print("qartz: " ++ fmt ++ "\n", args);
    return 2;
}

fn parseBank(s: []const u8) ?u8 {
    if (std.mem.eql(u8, s, "1")) return 1;
    if (std.mem.eql(u8, s, "2")) return 2;
    return null;
}

/// Runs one command; returns the process exit code.
pub fn run(w: *Worker, pos: []const []const u8, verify: bool) u8 {
    const cmd = pos[0];
    if (std.mem.eql(u8, cmd, "help")) {
        std.debug.print("{s}", .{USAGE});
        return 0;
    }
    if (std.mem.eql(u8, cmd, "info")) return info(w);

    var req: worker_mod.Request = .{ .kind = .read, .verify = verify };
    if (std.mem.eql(u8, cmd, "backup")) {
        if (pos.len != 2) return fail("usage: qartz backup <dir>", .{});
        req.kind = .backup;
        req.setPath(pos[1]);
    } else {
        req.kind = if (std.mem.eql(u8, cmd, "read")) .read else .write;
        if (pos.len < 3) return fail("usage: qartz {s} rom <1|2> <file> | {s} sram <file>", .{ cmd, cmd });
        if (std.mem.eql(u8, pos[1], "rom")) {
            if (pos.len != 4) return fail("usage: qartz {s} rom <1|2> <file>", .{cmd});
            req.mem = .rom;
            req.bank = parseBank(pos[2]) orelse return fail("bank must be 1 or 2, not '{s}'", .{pos[2]});
            req.setPath(pos[3]);
        } else if (std.mem.eql(u8, pos[1], "sram")) {
            if (pos.len != 3) return fail("usage: qartz {s} sram <file>", .{cmd});
            req.mem = .sram;
            req.setPath(pos[2]);
        } else return fail("'{s}': expected rom or sram", .{pos[1]});
    }

    if (!waitConnected(w)) return 1;
    if (!w.submit(req)) return fail("the worker is busy", .{});
    return follow(w);
}

/// The worker opens the cart on its first look at the bus; give a slow
/// hub a moment.
fn waitConnected(w: *Worker) bool {
    var waited: u32 = 0;
    // one header read may have to time out (5 s) before a deaf cart is
    // reported as such
    while (waited < 8000) : (waited += 50) {
        if (signals.requested()) return false;
        const s = w.snapshot();
        if (s.connected) return true;
        if (s.conn_err.len > 0) {
            std.debug.print("qartz: {s}\n", .{s.conn_err.slice()});
            return false;
        }
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
    std.debug.print("qartz: no cart found (is it plugged in?)\n", .{});
    return false;
}

fn info(w: *Worker) u8 {
    if (!waitConnected(w)) return 1;
    const s = w.snapshot();
    std.debug.print("{s} connected\n", .{s.device_label});
    for (s.banks, 0..) |hb, i| {
        std.debug.print("  bank {d}: ", .{i + 1});
        const h = hb orelse {
            std.debug.print("unreadable\n", .{});
            continue;
        };
        if (!h.valid()) {
            std.debug.print("empty (no valid ROM header)\n", .{});
            continue;
        }
        var rb: [16]u8 = undefined;
        var sb: [16]u8 = undefined;
        std.debug.print("{s}  {s}  {s}  RAM {s}{s}\n", .{
            if (h.title().len > 0) h.title() else "(untitled)",
            rom.sizeText(h.rom_size, &rb),
            h.typeName(),
            if (h.ram_size > 0) rom.sizeText(h.ram_size, &sb) else "none",
            switch (h.cgb) {
                .dmg => "",
                .cgb_enhanced => "  GBC",
                .cgb_only => "  GBC only",
            },
        });
    }
    return 0;
}

fn follow(w: *Worker) u8 {
    const tty = std.posix.isatty(std.posix.STDERR_FILENO);
    var seen = w.snapshot().finished;
    // the job is queued; wait for it to finish, drawing as it goes
    var last_draw: i128 = 0;
    var stopping = false;
    while (true) {
        const s = w.snapshot();
        // Ctrl+C: never abandon the cart mid-block — cancel, then wait for
        // the worker to finish the block it is on
        if (signals.requested() and !stopping) {
            stopping = true;
            w.cancel();
            if (tty) std.debug.print("\r\x1b[2K", .{});
            std.debug.print("stopping after the current block...\n", .{});
        }
        if (s.finished != seen and !s.busy) {
            seen = s.finished;
            if (tty) std.debug.print("\r\x1b[2K", .{});
            switch (s.outcome) {
                .ok => {
                    std.debug.print("{s}  ({d}.{d}s)\n", .{ s.msg.slice(), s.elapsed_ms / 1000, (s.elapsed_ms % 1000) / 100 });
                    if (s.detail.len > 0) std.debug.print("  {s}\n", .{s.detail.slice()});
                    return 0;
                },
                .cancelled => {
                    std.debug.print("cancelled\n", .{});
                    return 130;
                },
                else => {
                    std.debug.print("qartz: {s}\n", .{s.msg.slice()});
                    return 1;
                },
            }
        }
        const now = std.time.nanoTimestamp();
        if (tty and s.busy and now - last_draw > 100 * std.time.ns_per_ms) {
            last_draw = now;
            drawBar(&s, now);
        }
        std.Thread.sleep(30 * std.time.ns_per_ms);
    }
}

fn drawBar(s: *const worker_mod.Status, now: i128) void {
    const label = switch (s.phase) {
        .idle => "starting ",
        .reading => "reading  ",
        .writing => "writing  ",
        .verifying => "verifying",
    };
    const W = 32;
    const f = s.fraction();
    const fill: usize = @intFromFloat(f * W);
    var bar: [W * 3]u8 = undefined;
    var n: usize = 0;
    for (0..W) |i| {
        const g = if (i < fill) "█" else "░";
        @memcpy(bar[n..][0..g.len], g);
        n += g.len;
    }
    const secs = @as(f64, @floatFromInt(now - s.started_ns)) / std.time.ns_per_s;
    const kbs = if (secs > 0.2) @as(f64, @floatFromInt(s.done)) / 1024.0 / secs else 0;
    var db: [16]u8 = undefined;
    var tb: [16]u8 = undefined;
    var step_buf: [16]u8 = undefined;
    const step = if (s.steps > 0) std.fmt.bufPrint(&step_buf, "[{d}/{d}] ", .{ s.step, s.steps }) catch "" else "";
    std.debug.print("\r\x1b[2K{s}{s} {s} {d:>3}%  {s}/{s}  {d:.0} KB/s", .{
        step,                    label,                 bar[0..n],
        @as(u32, @intFromFloat(f * 100)),
        rom.sizeText(s.done, &db), rom.sizeText(s.total, &tb), kbs,
    });
}
