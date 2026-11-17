//! The frontend contract (M19 THE WINDOW): what a presenter — the kitty
//! terminal (frontend/term.zig) or the SDL3 window (frontend/sdl.zig) —
//! owes the shared session loop in main.zig, and the event alphabet it
//! feeds back.
//!
//! A frontend is four calls, driven once per 60fps frame:
//!
//!   pump(frame_no)                poll whatever needs polling (terminal
//!                                 size ioctl, scripted harness keys)
//!   next() !?FeEvent              drain pending events, one at a time
//!   applyResize(alloc, cols,rows) rebuild the presenter's own stack at
//!                                 the new grid (Screen+DiffOutput, or
//!                                 pixel texture + letterbox)
//!   present(alloc, canvas, frame, st)
//!                                 put the finished TextCanvas + pixel
//!                                 Frame on the glass
//!
//! plus init/deinit/hasReleases() — and, since XXIV (s139), the two
//! SYSTEM CLIPBOARD verbs, because the clipboard is the presenter's
//! world and not the session's:
//!
//!   readClipboard(alloc) !?[]u8    the OS clipboard's text, null when
//!                                 it holds none (the caller frees)
//!   writeClipboard(alloc, text)   put text on it
//!
//! The terminal shells out to the OS tools (app/clipboard.zig), the
//! window asks SDL; main.zig's `--clipboard-file` stands in for both
//! when a test drives the keys. Everything here is plain data: a
//! frontend never reaches into the session, and the session's key
//! cascade consumes movy-SHAPED keys no matter who synthesized them.

const movy = @import("movy");

// The cell-grid bounds every layout decision is made against — shared
// policy, not a terminal detail: the SDL window enforces the same 80x24
// minimum (as a minimum window size) and the same 300-column cap
// (200 until s156 — m64's ruling: a wide window gets the width).
pub const MIN_COLS: usize = 80;
pub const MIN_ROWS: usize = 24;
pub const MAX_COLS: usize = 300;

pub const Size = struct { cols: usize, rows: usize };

pub const FeEvent = union(enum) {
    /// A key in movy's shape. The GUI synthesizes these with KITTY
    /// semantics — base codepoint + shift flag on .Char, ctrl folded
    /// into the arrow/home/end TYPES (ctrl wins over shift), .CtrlChar
    /// carrying the lowercase character, real Press/Repeat/Release —
    /// so every dispatcher behaves identically under both frontends.
    key: movy.input.Key,
    /// The cell grid changed (terminal resized, window resized, font
    /// size stepped, fullscreen toggled). The loop rebuilds the shared
    /// canvas+frame, then calls the frontend's applyResize.
    resize: Size,
    /// The frontend wants the session to end (window close button).
    quit,
};
