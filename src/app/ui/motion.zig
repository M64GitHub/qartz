//! THE FRAME CLOCK (XXVIII D, s169) — the one clock every UI animation
//! reads.
//!
//! The session loop counts drawn frames (`hud.State.frame_no`, ~60 a
//! second) and has since the first cursor blink; an animation is a START
//! frame and a LENGTH in frames, and its progress is read off that count,
//! never off wall time. That is the whole of the block's law (m64, s166c:
//! *"animation runs off one frame clock, never wall time in a dump"*), and
//! it has two consequences worth writing down:
//!
//! - **A headless picture draws the SETTLED state.** `settled` is true
//!   unless the live loop says otherwise, so `--dump-screen`, `--shot`,
//!   the test roots and a `--gui-shot` all see every animation at its
//!   end — the picture a moment later would have shown, and the one
//!   lib-ab has always pinned. The live loop clears it; `--gui-motion`
//!   clears it inside a scripted shot too, to draw a FRAME STRIP.
//! - **A frame strip is exact.** A scripted key lands on a fixed frame
//!   and the clock is the frame count, so `--gui-motion --gui-shot
//!   60:2:12` draws the same twelve frames on every machine — motion can
//!   be judged on a sheet like a still (`tools/ui-motion.py`).
//!
//! A slow frame makes the motion slower rather than skipping it: at 60 fps
//! that is the right trade for a UI, and it keeps the two roads one.

const std = @import("std");

/// Frames per second the session loop paces to (main.zig's FRAME_NS).
pub const FPS: u32 = 60;

/// Every animation at its end state. TRUE by default: only the live
/// session loop (and a `--gui-motion` shot) turns motion on.
pub var settled: bool = true;

/// Milliseconds -> frames on the clock, at least one.
pub fn frames(ms: u32) u32 {
    return @max(1, (ms * FPS + 500) / 1000);
}

/// One animation: started at frame `start`, `len` frames long. The zero
/// value is an animation that never ran — settled.
pub const Anim = struct {
    start: u64 = 0,
    len: u32 = 0,

    pub fn begin(now: u64, len: u32) Anim {
        return .{ .start = now, .len = len };
    }

    /// 0 at the start frame, 1 at the end and ever after (and always 1
    /// when `settled`).
    pub fn t(self: Anim, now: u64) f32 {
        if (settled or self.len == 0) return 1;
        const e = now -| self.start;
        if (e >= self.len) return 1;
        return @as(f32, @floatFromInt(e)) / @as(f32, @floatFromInt(self.len));
    }

    pub fn running(self: Anim, now: u64) bool {
        return self.t(now) < 1;
    }
};

/// The curves on offer (m64 picks by eye, s169).
pub const Curve = enum { linear, ease_out, ease_in_out };

pub fn ease(c: Curve, x: f32) f32 {
    const u = std.math.clamp(x, 0, 1);
    return switch (c) {
        .linear => u,
        .ease_out => 1 - (1 - u) * (1 - u) * (1 - u),
        .ease_in_out => u * u * (3 - 2 * u),
    };
}

test "the frame clock: settled draws the end, live walks the frames" {
    const was = settled;
    defer settled = was;
    const a = Anim.begin(100, 10);
    settled = true;
    try std.testing.expectEqual(@as(f32, 1), a.t(100));
    settled = false;
    try std.testing.expectEqual(@as(f32, 0), a.t(100));
    try std.testing.expectEqual(@as(f32, 0.5), a.t(105));
    try std.testing.expectEqual(@as(f32, 1), a.t(110));
    try std.testing.expectEqual(@as(f32, 1), a.t(99_999));
    try std.testing.expect(!(Anim{}).running(5));
    try std.testing.expectEqual(@as(u32, 15), frames(250));
    try std.testing.expectEqual(@as(u32, 9), frames(150));
    try std.testing.expectEqual(@as(f32, 1), ease(.ease_out, 1));
}
