//! TermFrontend — the kitty-class terminal presenter, lifted from DUET
//! (src/app/frontend/term.zig) minus its clipboard verbs.
//!
//! Owns: raw mode + alternate screen + kitty keyboard protocol, the
//! mouse-report suppression, movy's Screen + threaded DiffOutput, the
//! ~2.5 s resize poll (one ioctl — m64's "nothing slowed down
//! unnecessarily"), and the panic-restore hook. The shared TextCanvas
//! and pixel Frame stay in the session loop — this file only puts them
//! on the glass.

const std = @import("std");
const movy = @import("movy");
const canvas_mod = @import("ui/canvas.zig");
const fe = @import("event.zig");

/// zig `defer`s don't run on @panic — without this a crash strands the
/// user in a raw-mode alt-screen with a hidden cursor and kitty flags
/// pushed. main.zig's panic override calls panicCleanup(); the GUI exe
/// keeps the default handler (nothing to restore).
pub var active = false;

pub fn panicCleanup() void {
    if (active) {
        active = false;
        movy.input.disableKittyKeyboard();
        movy.terminal.endAlternateScreen();
        movy.terminal.endRawMode();
        movy.terminal.cursorOn();
    }
}

/// EAT THE QUIT KEY'S OWN RELEASE REPORT before handing the terminal
/// back (m64, s62: *"I see this typed into the terminal: ';1:3u'"*).
///
/// With the kitty protocol on we ask for event types (`CSI >11u`), so
/// ESC down sends `CSI 27;1u` and ESC UP sends `CSI 27;1:3u`. We quit on
/// the DOWN — so the UP lands in the tty a few milliseconds later, after
/// we are gone, and the SHELL reads it: readline swallows `ESC [ 2 7` as
/// an unknown sequence and prints the rest at the prompt. Measured
/// through a pty running a real `sh`: the leak starts at a gap of about
/// **10 ms**, which is every keypress a human makes.
///
/// `CSI <u` alone cannot fix it. It stops the terminal generating NEW
/// reports; it cannot recall one already on the wire. So: pop the flags,
/// then ask Primary Device Attributes and **read until its reply**.
/// Everything the terminal queued before it processed the pop sits in
/// front of that reply, so draining to it drains exactly what would have
/// leaked — and anything after the pop is never generated at all. That
/// ordering is what makes this a fix rather than a timing guess; the
/// deadline below is only a guarantee against a terminal that never
/// answers DA, never the mechanism.
fn drainPendingInput() void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[c") catch return;
    var pfd = [_]std.posix.pollfd{.{
        .fd = std.posix.STDIN_FILENO,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    var buf: [512]u8 = undefined;
    // the DA reply is `ESC [ ? ... c`; nothing else we might swallow on
    // the way ends in 'c' after a `?`, and a kitty report ends in 'u'
    var seen_q = false;
    var waited_ms: i32 = 0;
    while (waited_ms < 150) {
        const n = std.posix.poll(&pfd, 10) catch return;
        if (n == 0) {
            waited_ms += 10;
            continue;
        }
        const got = std.posix.read(std.posix.STDIN_FILENO, &buf) catch return;
        if (got == 0) return;
        for (buf[0..got]) |b| {
            if (b == '?') seen_q = true;
            if (seen_q and b == 'c') return; // the DA reply: we are past it
        }
    }
}

pub const TermFrontend = struct {
    screen: movy.Screen,
    dout: *movy.DiffOutput,
    kitty: bool,
    cols: usize,
    rows: usize,
    term_w: usize, // last seen terminal width (centering)
    pending_resize: ?fe.Size = null,

    pub fn init(allocator: std.mem.Allocator) !TermFrontend {
        const term = try movy.terminal.getSize();
        if (term.width < fe.MIN_COLS or term.height < fe.MIN_ROWS) {
            std.debug.print(
                "qartz needs at least {d}x{d} cells (yours is {d}x{d}).\n",
                .{ fe.MIN_COLS, fe.MIN_ROWS, term.width, term.height },
            );
            return error.TermTooSmall;
        }
        const cols: usize = @min(term.width, fe.MAX_COLS);
        const rows: usize = term.height;

        try movy.terminal.beginRawMode();
        errdefer movy.terminal.endRawMode();
        try movy.terminal.beginAlternateScreen();
        errdefer movy.terminal.endAlternateScreen();
        active = true;
        errdefer active = false;

        // movy's raw mode enables all-motion mouse reporting; we don't want the flood
        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[?1003l\x1b[?1006l\x1b[?1000l") catch 0;

        // NO kitty keyboard protocol in qartz (DUET turns it on for real key
        // releases, which a flasher has no use for). Under it, kitty reports
        // a shifted key as its BASE key + a shift flag — `?` arrives as `/`,
        // `T` as `t`, and a typed file name loses its capitals. Plain input
        // delivers what the keyboard layout actually types, on any layout.
        const kitty = false;

        var screen = try movy.Screen.init(allocator, cols, rows);
        errdefer screen.deinit(allocator);
        screen.setScreenMode(movy.Screen.Mode.bgcolor);
        screen.bg_color = .{ .r = 0, .g = 0, .b = 0 };
        screen.setXY(@intCast((term.width - cols) / 2), 0);

        // NOTE: DiffOutput does not retain the screen pointer past init —
        // the old resize path already moved the Screen under a live
        // DiffOutput, so moving both into the returned struct is safe.
        const dout = try movy.DiffOutput.init(allocator, &screen, .threaded);

        return .{
            .screen = screen,
            .dout = dout,
            .kitty = kitty,
            .cols = cols,
            .rows = rows,
            .term_w = term.width,
        };
    }


    pub fn deinit(self: *TermFrontend, allocator: std.mem.Allocator) void {
        self.dout.deinit(); // joins the writer thread first
        self.screen.deinit(allocator);
        // the pop FIRST, then drain to the DA reply — still in raw mode,
        // because canonical mode would line-buffer what we are eating
        if (self.kitty) movy.input.disableKittyKeyboard();
        drainPendingInput();
        active = false;
        movy.terminal.endAlternateScreen();
        movy.terminal.endRawMode();
        // ... and give the SHELL its cursor back, in panicCleanup's
        // order. `Screen.deinit` does show it, but from INSIDE the
        // alternate screen — whether that survives the `?47l` is the
        // terminal's business, and leaving a user without a cursor is
        // not a thing to leave to chance.
        movy.terminal.cursorOn();
    }

    /// True kitty terminals report key releases; the session's jam
    /// gate-offs and hold fallbacks key off this.
    pub fn hasReleases(self: *const TermFrontend) bool {
        return self.kitty;
    }

    /// Terminal resize is POLLED every ~2.5 s (one ioctl), no SIGWINCH
    /// plumbing. A change (including a width-only change beyond the
    /// column cap — the centering offset moves) queues a resize event.
    pub fn pump(self: *TermFrontend, frame_no: u64) void {
        if (frame_no % 150 != 0) return;
        const tsz = movy.terminal.getSize() catch return; // probe failed: keep the current stack
        const ncols: usize = @min(tsz.width, fe.MAX_COLS);
        const nrows: usize = tsz.height;
        if ((ncols != self.cols or nrows != self.rows or tsz.width != self.term_w) and
            tsz.width >= fe.MIN_COLS and tsz.height >= fe.MIN_ROWS)
        {
            self.term_w = tsz.width;
            self.pending_resize = .{ .cols = ncols, .rows = nrows };
        }
    }

    pub fn next(self: *TermFrontend) !?fe.FeEvent {
        if (self.pending_resize) |sz| {
            self.pending_resize = null;
            return .{ .resize = sz };
        }
        while (try movy.input.get()) |ev| switch (ev) {
            .key => |k| return .{ .key = k },
            .mouse => {},
        };
        return null;
    }

    /// Rebuild Screen + DiffOutput at the new grid. Build-new-first: an
    /// error propagates out with the old stack intact and alive for the
    /// session's defers.
    pub fn applyResize(self: *TermFrontend, allocator: std.mem.Allocator, cols: usize, rows: usize) !void {
        var nscreen = try movy.Screen.init(allocator, cols, rows);
        errdefer nscreen.deinit(allocator);
        nscreen.setScreenMode(movy.Screen.Mode.bgcolor);
        nscreen.bg_color = .{ .r = 0, .g = 0, .b = 0 };
        nscreen.setXY(@intCast((self.term_w - cols) / 2), 0);
        const ndout = try movy.DiffOutput.init(allocator, &nscreen, .threaded);
        self.dout.deinit(); // joins the old writer thread first
        self.screen.deinit(allocator);
        self.screen = nscreen;
        self.dout = ndout;
        self.cols = cols;
        self.rows = rows;
        // THE CURSOR COMES BACK ON A RESIZE, and that is the whole of
        // m64's *"we never switch the cursor off"* (s62): `Screen.init`
        // hides it and `Screen.deinit` SHOWS it again, so build-new-
        // first runs them in exactly the wrong order — hide, hide, SHOW
        // — and the block cursor sits in the grid for the rest of the
        // session. Proven by tracing the pty stream for `?25l`/`?25h`.
        movy.terminal.cursorOff();
        // stale glyphs can sit outside the new paint area (the centering
        // offset moved) — hard-clear once
        _ = std.posix.write(std.posix.STDOUT_FILENO, "\x1b[2J\x1b[H") catch 0;
    }

    /// Pixel surface into the half-block cells, glyph cells on top,
    /// dirty rows to the writer thread (drops frames instead of
    /// blocking).
    pub fn present(
        self: *TermFrontend,
        allocator: std.mem.Allocator,
        canvas: *canvas_mod.TextCanvas,
        frame: *movy.Frame,
        st: anytype,
    ) !void {
        _ = st;
        try self.screen.renderInit();
        try self.screen.addRenderSurface(allocator, frame.surface);
        self.screen.render();
        canvas.blitTo(self.screen.output_surface);
        try self.dout.output(&self.screen);
    }
};
