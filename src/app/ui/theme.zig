//! Theme — oldschool sci-fi: ice blue & white on black. One place to retune.
//!
//! Two color spaces: `Rgb` (u8) for text cells, `V3` (linear float) for the
//! pixel/glow layer. movy has no bold/underline — emphasis is done purely
//! with color.

const std = @import("std");
const movy = @import("movy");
const motion = @import("motion.zig");

pub const Rgb = movy.core.types.Rgb;
pub const V3 = movy.color.V3;
pub const v3 = movy.color.v3;

// ------------------------------------------------------ THE COLOUR SCHEMES
//
// s166 (m64: "maybe a second colorscheme? ... just user setting"). Every
// colour a page is painted with below is a `pub var` holding the ACTIVE
// scheme's value; `Palette` lists them, and its field DEFAULTS are DUET,
// the ice-on-black the program was born in. A scheme is DUET with what it
// changes: `.{ .bg = ..., ... }`. `apply` copies one in and re-derives the
// aliases (`sw_phrase` is `text_bright`, whatever that is today). The
// colours that CARRY MEANING rather than mood stay constants in every
// scheme: the four FX units' hues, the clip red, MUTE red / SOLO green and
// the two synth families' strips — a scheme may move the room, never the
// facts. The SID's own warm colour IS the scheme's since s166b: it only
// has to differ from the PCM side, and each scheme picks its own.
// And `bg` stays black in every one: the terminal's clear and the GUI's
// letterbox are black, and a page ground that differed would frame itself.
// Nothing here is saved with a song: the pick is the user's config.

pub const Palette = struct {
    bg: Rgb = Rgb{ .r = 0, .g = 0, .b = 0 },
    header_bg: Rgb = Rgb{ .r = 3, .g = 10, .b = 26 },
    text: Rgb = Rgb{ .r = 168, .g = 208, .b = 248 },
    text_dim: Rgb = Rgb{ .r = 88, .g = 126, .b = 180 },
    text_bright: Rgb = Rgb{ .r = 236, .g = 246, .b = 255 },
    value_off: Rgb = Rgb{ .r = 78, .g = 82, .b = 92 },
    table_hdr: Rgb = Rgb{ .r = 120, .g = 160, .b = 214 },
    accent: Rgb = Rgb{ .r = 86, .g = 168, .b = 255 },
    accent_hot: Rgb = Rgb{ .r = 150, .g = 224, .b = 255 },
    accent_pink: Rgb = Rgb{ .r = 224, .g = 128, .b = 255 },
    pink_dim: Rgb = Rgb{ .r = 158, .g = 98, .b = 192 },
    sep: Rgb = Rgb{ .r = 46, .g = 90, .b = 148 },
    note_col: Rgb = Rgb{ .r = 236, .g = 246, .b = 255 },
    ins_col: Rgb = Rgb{ .r = 120, .g = 200, .b = 255 },
    vol_col: Rgb = Rgb{ .r = 140, .g = 180, .b = 240 },
    fx_col: Rgb = Rgb{ .r = 100, .g = 150, .b = 220 },
    fx_duet: Rgb = Rgb{ .r = 120, .g = 230, .b = 170 },
    dots: Rgb = Rgb{ .r = 46, .g = 74, .b = 118 },
    rownum: Rgb = Rgb{ .r = 88, .g = 126, .b = 180 },
    rownum_beat: Rgb = Rgb{ .r = 150, .g = 200, .b = 255 },
    cursor_bg: Rgb = Rgb{ .r = 188, .g = 226, .b = 255 },
    cursor_bg_blink: Rgb = Rgb{ .r = 96, .g = 140, .b = 190 },
    cursor_fg: Rgb = Rgb{ .r = 4, .g = 12, .b = 28 },
    playhead_bg: Rgb = Rgb{ .r = 10, .g = 28, .b = 58 },
    playhead_sid_bg: Rgb = Rgb{ .r = 7, .g = 38, .b = 40 },
    playhead_echo_bg: Rgb = Rgb{ .r = 10, .g = 22, .b = 44 },
    cursor_row_bg: Rgb = Rgb{ .r = 13, .g = 32, .b = 66 },
    cursor_row_bg_sid: Rgb = Rgb{ .r = 17, .g = 23, .b = 36 },
    row_beat_bg: Rgb = Rgb{ .r = 9, .g = 15, .b = 28 },
    mark_bg: Rgb = Rgb{ .r = 46, .g = 96, .b = 120 },
    marker_bg: Rgb = Rgb{ .r = 150, .g = 100, .b = 24 },
    lap_bg: Rgb = Rgb{ .r = 24, .g = 13, .b = 36 },
    chan_hdr: Rgb = Rgb{ .r = 70, .g = 110, .b = 170 },
    sid_hdr: Rgb = Rgb{ .r = 255, .g = 196, .b = 96 },
    mode_badge: Rgb = Rgb{ .r = 255, .g = 196, .b = 96 },
    phrase_end: Rgb = Rgb{ .r = 40, .g = 62, .b = 96 },
    phrase_len: Rgb = Rgb{ .r = 74, .g = 104, .b = 150 },
    env_dot_txt: Rgb = Rgb{ .r = 255, .g = 244, .b = 158 },
    mute_red: Rgb = Rgb{ .r = 235, .g = 84, .b = 74 },
    solo_green: Rgb = Rgb{ .r = 92, .g = 224, .b = 128 },
    BG_TOP: V3 = v3(0.004, 0.010, 0.030),
    BG_BOT: V3 = v3(0.010, 0.026, 0.058),
    GLOW_STRIP: V3 = v3(0.10, 0.35, 0.80),
    CURSOR_GLOW: V3 = v3(0.12, 0.40, 0.85),
    MOTE: V3 = v3(0.05, 0.20, 0.42),
    LOGO_ICE: V3 = v3(0.55, 0.85, 1.00),
    LOGO_PINK: V3 = v3(0.88, 0.42, 1.00),
    VIZ_BAR_LO: V3 = v3(0.014, 0.065, 0.38),
    VIZ_TIP: V3 = v3(1.00, 0.68, 1.00),
    VIZ_PEAK: V3 = v3(0.62, 0.86, 1.00),
    VIZ_SLOT: V3 = v3(0.014, 0.030, 0.075),
    VIZ_SCOPE: V3 = v3(0.55, 0.95, 1.00),
    VIZ_SCOPE_GLOW: V3 = v3(0.42, 0.16, 0.85),
    VIZ_BASELINE: V3 = v3(0.06, 0.16, 0.38),
    WAVE_SLOT: V3 = v3(0.010, 0.022, 0.055),
    WAVE_BASE: V3 = v3(0.05, 0.13, 0.30),
    WAVE_LOOP_BG: V3 = v3(0.075, 0.020, 0.095),
    WAVE_SUS_BG: V3 = v3(0.020, 0.045, 0.090),
    WAVE_MARK_SUS: V3 = v3(0.34, 0.72, 1.00),
    WAVE_SEAM: V3 = v3(1.00, 0.90, 1.00),
    ENV_NODE: V3 = v3(0.62, 0.88, 1.00),
    STRIP_SLOT: V3 = v3(0.011, 0.022, 0.050),
    STRIP_PCM_LO: V3 = v3(0.05, 0.17, 0.45),
    MIX_MASTER_LO: V3 = v3(0.10, 0.14, 0.28),
    MIX_MASTER_HI: V3 = v3(0.88, 0.95, 1.00),
    PULSE_BEAT: V3 = v3(0.55, 0.20, 0.75),
    PULSE_NOTE: V3 = v3(0.16, 0.45, 0.95),
    // THE CHIPS' OWN WARM COLOUR (s166b, m64: "we can also include
    // SID-amber into the palette. It is just a differentiator"): the
    // density strip's SID half, the chip's ADSR minis, the SID note flash
    // — with `sid_hdr`/`mode_badge` the one colour that says "chip here"
    STRIP_SID_LO: V3 = v3(0.26, 0.11, 0.010),
    STRIP_SID_HI: V3 = v3(1.00, 0.74, 0.28),
    MIX_ADSR: V3 = v3(0.62, 0.38, 0.10),
    PULSE_NOTE_SID: V3 = v3(0.85, 0.50, 0.12),
};

/// The ice-on-black DUET was born in — and every scheme's starting point.
pub const DUET: Palette = .{};

pub const Scheme = struct {
    name: []const u8,
    /// One line for the picker's `▸` row: what it looks like.
    blurb: []const u8,
    pal: Palette,
};

fn c(r: u8, g: u8, b: u8) Rgb {
    return .{ .r = r, .g = g, .b = b };
}

/// SID-WIZARD — the C64 editor's own DEFAULT theme (SID-Wizard 1.97,
/// `displayer2.inc` ColorThemes row 0): light-grey notes (C64 15), the
/// grey furniture (12, 11), the cyan instrument column (3) and the light
/// green instrument numbers (13), on black. The C64 colours are Pepto's,
/// lifted a step for a modern panel; light green is the highlight.
const SIDWIZ: Palette = .{
    .header_bg = c(26, 26, 26),
    .text = c(168, 168, 168),
    .text_dim = c(112, 112, 112),
    .text_bright = c(232, 232, 232),
    .value_off = c(78, 78, 78),
    .table_hdr = c(150, 150, 150),
    .accent = c(112, 164, 178), // C64 cyan
    .accent_hot = c(170, 222, 150),
    .accent_pink = c(154, 210, 132), // C64 light green: the highlight
    .pink_dim = c(102, 150, 84),
    .sep = c(68, 68, 68), // C64 dark grey
    .note_col = c(210, 210, 210),
    .ins_col = c(112, 164, 178),
    .vol_col = c(154, 210, 132),
    .fx_col = c(128, 128, 128),
    .dots = c(58, 58, 58),
    .rownum = c(88, 88, 88),
    .rownum_beat = c(154, 210, 132),
    .cursor_bg = c(154, 210, 132),
    .cursor_bg_blink = c(88, 141, 67), // C64 green
    .cursor_fg = c(0, 0, 0),
    .playhead_bg = c(30, 44, 28),
    .playhead_sid_bg = c(40, 40, 22),
    .playhead_echo_bg = c(26, 32, 26),
    .cursor_row_bg = c(40, 40, 40),
    .cursor_row_bg_sid = c(30, 30, 30),
    .row_beat_bg = c(20, 20, 20),
    .mark_bg = c(64, 96, 56),
    .lap_bg = c(32, 24, 36),
    .chan_hdr = c(128, 128, 128),
    .phrase_end = c(52, 52, 52),
    .phrase_len = c(96, 96, 96),
    .BG_TOP = v3(0.010, 0.010, 0.010),
    .BG_BOT = v3(0.030, 0.030, 0.030),
    .GLOW_STRIP = v3(0.30, 0.55, 0.25),
    .CURSOR_GLOW = v3(0.34, 0.62, 0.28),
    .MOTE = v3(0.16, 0.18, 0.16),
    .LOGO_ICE = v3(0.86, 0.88, 0.86),
    .LOGO_PINK = v3(0.52, 0.86, 0.42),
    .VIZ_BAR_LO = v3(0.05, 0.12, 0.04),
    .VIZ_TIP = v3(0.86, 1.00, 0.80),
    .VIZ_PEAK = v3(0.80, 0.84, 0.80),
    .VIZ_SLOT = v3(0.030, 0.030, 0.030),
    .VIZ_SCOPE = v3(0.70, 1.00, 0.60),
    .VIZ_SCOPE_GLOW = v3(0.20, 0.48, 0.16),
    .VIZ_BASELINE = v3(0.15, 0.17, 0.15),
    .WAVE_SLOT = v3(0.020, 0.020, 0.020),
    .WAVE_BASE = v3(0.15, 0.17, 0.15),
    .WAVE_LOOP_BG = v3(0.050, 0.090, 0.040),
    .WAVE_SUS_BG = v3(0.040, 0.070, 0.080),
    .WAVE_MARK_SUS = v3(0.44, 0.64, 0.70),
    .WAVE_SEAM = v3(0.95, 1.00, 0.95),
    .ENV_NODE = v3(0.80, 0.90, 0.80),
    .STRIP_SLOT = v3(0.025, 0.025, 0.025),
    .STRIP_PCM_LO = v3(0.10, 0.14, 0.16),
    .MIX_MASTER_LO = v3(0.12, 0.14, 0.12),
    .MIX_MASTER_HI = v3(0.90, 0.95, 0.90),
    .PULSE_BEAT = v3(0.30, 0.55, 0.25),
    .PULSE_NOTE = v3(0.34, 0.50, 0.56),
};

/// IMPULSE — Impulse Tracker's own default palette ("Camouflage", the
/// VGA values x4): the cream and tan of its panels as the text, its
/// green pattern data, yellow instrument numbers and the magenta it
/// marks with, on the black of its pattern screen.
const IMPULSE: Palette = .{
    .header_bg = c(52, 48, 44), // IT 15
    .text = c(206, 200, 170),
    .text_dim = c(160, 132, 106),
    .text_bright = c(236, 240, 232), // IT 11
    .value_off = c(100, 88, 80),
    .table_hdr = c(200, 172, 140),
    .accent = c(72, 180, 136), // IT 10, teal
    .accent_hot = c(252, 252, 84), // IT 5, yellow
    .accent_pink = c(200, 40, 110), // IT 4, magenta
    .pink_dim = c(150, 50, 100),
    .sep = c(124, 88, 68), // IT 1, brown
    .note_col = c(104, 196, 108), // IT 6, the pattern's green
    .ins_col = c(220, 220, 90),
    .vol_col = c(72, 180, 136),
    .fx_col = c(180, 148, 120), // IT 2, tan
    .dots = c(62, 54, 48),
    .rownum = c(124, 88, 68),
    .rownum_beat = c(220, 200, 150),
    .cursor_bg = c(232, 232, 200), // IT 3, the panel cream
    .cursor_bg_blink = c(160, 160, 140),
    .cursor_fg = c(0, 0, 0),
    .playhead_bg = c(48, 38, 24),
    .playhead_sid_bg = c(42, 42, 20),
    .playhead_echo_bg = c(34, 30, 24),
    .cursor_row_bg = c(56, 44, 34),
    .cursor_row_bg_sid = c(38, 36, 34),
    .row_beat_bg = c(24, 20, 16),
    .mark_bg = c(110, 84, 60),
    .lap_bg = c(44, 20, 32),
    .chan_hdr = c(180, 148, 120),
    .phrase_end = c(62, 50, 40),
    .phrase_len = c(124, 100, 80),
    .BG_TOP = v3(0.012, 0.010, 0.008),
    .BG_BOT = v3(0.036, 0.028, 0.020),
    .GLOW_STRIP = v3(0.55, 0.40, 0.20),
    .CURSOR_GLOW = v3(0.60, 0.50, 0.25),
    .MOTE = v3(0.24, 0.17, 0.10),
    .LOGO_ICE = v3(0.92, 0.91, 0.78),
    .LOGO_PINK = v3(0.72, 0.06, 0.36),
    .VIZ_BAR_LO = v3(0.10, 0.07, 0.03),
    .VIZ_TIP = v3(1.00, 0.95, 0.60),
    .VIZ_PEAK = v3(0.90, 0.90, 0.75),
    .VIZ_SLOT = v3(0.030, 0.025, 0.020),
    .VIZ_SCOPE = v3(0.95, 0.95, 0.60),
    .VIZ_SCOPE_GLOW = v3(0.50, 0.34, 0.10),
    .VIZ_BASELINE = v3(0.20, 0.15, 0.10),
    .WAVE_SLOT = v3(0.020, 0.017, 0.014),
    .WAVE_BASE = v3(0.20, 0.15, 0.10),
    .WAVE_LOOP_BG = v3(0.090, 0.020, 0.050),
    .WAVE_SUS_BG = v3(0.030, 0.070, 0.050),
    .WAVE_MARK_SUS = v3(0.25, 0.65, 0.48),
    .WAVE_SEAM = v3(1.00, 1.00, 0.85),
    .ENV_NODE = v3(0.90, 0.90, 0.75),
    .STRIP_SLOT = v3(0.025, 0.020, 0.015),
    .STRIP_PCM_LO = v3(0.08, 0.18, 0.09),
    .MIX_MASTER_LO = v3(0.15, 0.12, 0.08),
    .MIX_MASTER_HI = v3(0.95, 0.93, 0.80),
    .PULSE_BEAT = v3(0.55, 0.08, 0.30),
    .PULSE_NOTE = v3(0.25, 0.60, 0.30),
};

/// PHOSPHOR — an amber monitor: every line one hue in steps of glow, the
/// way a green-screen terminal's cousin drew it. The colours that carry
/// facts (the FX units, MUTE red, SOLO green) keep theirs.
const PHOSPHOR: Palette = .{
    .header_bg = c(26, 16, 4),
    .text = c(230, 160, 60),
    .text_dim = c(150, 96, 30),
    .text_bright = c(255, 214, 140),
    .value_off = c(92, 58, 20),
    .table_hdr = c(200, 136, 50),
    .accent = c(255, 180, 70),
    .accent_hot = c(255, 224, 150),
    .accent_pink = c(255, 170, 40),
    .pink_dim = c(170, 100, 30),
    .sep = c(110, 70, 20),
    .note_col = c(255, 214, 140),
    .ins_col = c(240, 170, 70),
    .vol_col = c(210, 140, 55),
    .fx_col = c(180, 115, 40),
    .dots = c(70, 44, 14),
    .rownum = c(140, 90, 30),
    .rownum_beat = c(255, 190, 90),
    .cursor_bg = c(255, 200, 110),
    .cursor_bg_blink = c(160, 110, 40),
    .cursor_fg = c(0, 0, 0),
    .playhead_bg = c(52, 32, 6),
    .playhead_sid_bg = c(58, 38, 6),
    .playhead_echo_bg = c(36, 22, 6),
    .cursor_row_bg = c(44, 28, 8),
    .cursor_row_bg_sid = c(32, 22, 10),
    .row_beat_bg = c(20, 12, 4),
    .mark_bg = c(120, 76, 20),
    .lap_bg = c(40, 22, 10),
    .chan_hdr = c(170, 110, 40),
    .sid_hdr = c(255, 232, 128),
    .mode_badge = c(255, 232, 128),
    .phrase_end = c(60, 38, 12),
    .phrase_len = c(120, 78, 26),
    .BG_TOP = v3(0.012, 0.007, 0.002),
    .BG_BOT = v3(0.035, 0.020, 0.005),
    .GLOW_STRIP = v3(0.80, 0.45, 0.10),
    .CURSOR_GLOW = v3(0.85, 0.50, 0.12),
    .MOTE = v3(0.25, 0.14, 0.03),
    .LOGO_ICE = v3(1.00, 0.86, 0.52),
    .LOGO_PINK = v3(0.92, 0.46, 0.05),
    .VIZ_BAR_LO = v3(0.12, 0.06, 0.01),
    .VIZ_TIP = v3(1.00, 0.90, 0.60),
    .VIZ_PEAK = v3(1.00, 0.80, 0.45),
    .VIZ_SLOT = v3(0.030, 0.018, 0.005),
    .VIZ_SCOPE = v3(1.00, 0.80, 0.40),
    .VIZ_SCOPE_GLOW = v3(0.60, 0.30, 0.05),
    .VIZ_BASELINE = v3(0.20, 0.12, 0.03),
    .WAVE_SLOT = v3(0.020, 0.012, 0.004),
    .WAVE_BASE = v3(0.20, 0.12, 0.03),
    .WAVE_LOOP_BG = v3(0.090, 0.050, 0.010),
    .WAVE_SUS_BG = v3(0.060, 0.040, 0.010),
    .WAVE_MARK_SUS = v3(1.00, 0.75, 0.35),
    .WAVE_SEAM = v3(1.00, 0.95, 0.80),
    .ENV_NODE = v3(1.00, 0.85, 0.55),
    .STRIP_SLOT = v3(0.025, 0.015, 0.005),
    .STRIP_PCM_LO = v3(0.18, 0.10, 0.02),
    .MIX_MASTER_LO = v3(0.15, 0.09, 0.02),
    .MIX_MASTER_HI = v3(1.00, 0.90, 0.70),
    .PULSE_BEAT = v3(0.60, 0.30, 0.05),
    .PULSE_NOTE = v3(0.70, 0.45, 0.10),
};

// ------------------------------------------------ THE DERIVED SCHEMES (s166b)
//
// Seventy hand-set values per scheme is how a palette drifts: a row bar a
// shade too warm, a dot that outshines its label. The six named schemes
// below are each FIFTEEN decisions — a ground hue, the text ramp, three
// accents, the four cell classes, the cursor, the chip colour, the logo's
// two ends — and `derive` spends them the same way every time: surfaces
// are the ground hue darkened, glows are the accents lit, the hierarchy
// (dots < sep < dim < text < bright) holds by construction. `lift` is the
// contrast knob: above 1 the furniture and the rules stand forward and the
// row bars sink (the high-contrast schemes); below 1 it all melts back.

const Keys = struct {
    ground: Rgb, // the hue every dark surface is made of
    text: Rgb,
    dim: Rgb,
    bright: Rgb,
    accent: Rgb, // links, headers' second voice, the PCM glow
    hot: Rgb, // the selected thing
    mark: Rgb, // the highlight: an active field, specials, the beat pulse
    note: Rgb,
    ins: Rgb,
    vol: Rgb,
    fx: Rgb,
    cursor: Rgb,
    sid: Rgb, // the chips' own warm colour
    logo_a: V3, // the logotype's top — and the waveform's crest
    logo_b: V3, // ... its bottom, and the quiet end of the wave
    lift: f32 = 1.0,
    /// how far the dark SURFACES (header, chips, row bars) rise: a
    /// NEUTRAL ground reads darker than a saturated one at the same
    /// value, so a grey scheme lifts them to be seen at all
    surface: f32 = 1.0,
};

fn darken(x: Rgb, f: f32) Rgb {
    return mix(c(0, 0, 0), x, f);
}

fn lit(x: Rgb, f: f32) V3 {
    return v3(
        @as(f32, @floatFromInt(x.r)) / 255.0 * f,
        @as(f32, @floatFromInt(x.g)) / 255.0 * f,
        @as(f32, @floatFromInt(x.b)) / 255.0 * f,
    );
}

fn derive(k: Keys) Palette {
    @setEvalBranchQuota(20000);
    const white = v3(1, 1, 1);
    const grey = c(k.ground.r / 3 + k.ground.g / 3 + k.ground.b / 3, k.ground.r / 3 + k.ground.g / 3 + k.ground.b / 3, k.ground.r / 3 + k.ground.g / 3 + k.ground.b / 3);
    // the row bars sink a little as the furniture lifts — never so far that
    // the beat grid or a value chip's ground goes (s166b: at 0.55 VOLTAGE
    // lost its beat rows and OBSIDIAN its chips)
    const bar = @max(0.85, 2.0 - k.lift) * k.surface;
    return .{
        .header_bg = darken(k.ground, 0.11 * bar),
        .text = k.text,
        .text_dim = k.dim,
        .text_bright = k.bright,
        .value_off = mix(darken(k.dim, 0.55), darken(grey, 0.55), 0.5),
        .table_hdr = mix(k.dim, k.text, 0.45),
        .accent = k.accent,
        .accent_hot = k.hot,
        .accent_pink = k.mark,
        .pink_dim = darken(k.mark, 0.68),
        .sep = darken(k.ground, 0.48 * k.lift),
        .note_col = k.note,
        .ins_col = k.ins,
        .vol_col = k.vol,
        .fx_col = k.fx,
        .dots = darken(k.ground, 0.30 * k.lift),
        .rownum = k.dim,
        .rownum_beat = mix(k.accent, k.bright, 0.35),
        .cursor_bg = k.cursor,
        .cursor_bg_blink = darken(k.cursor, 0.55),
        .cursor_fg = darken(k.ground, 0.05),
        .playhead_bg = darken(k.ground, 0.24 * bar),
        .playhead_sid_bg = mix(darken(k.ground, 0.12 * bar), darken(k.sid, 0.20 * bar), 0.6),
        .playhead_echo_bg = darken(k.ground, 0.17 * bar),
        .cursor_row_bg = darken(k.ground, 0.30 * bar),
        .cursor_row_bg_sid = darken(grey, 0.24 * bar),
        .row_beat_bg = darken(k.ground, 0.10 * bar),
        .mark_bg = darken(k.accent, 0.42),
        .lap_bg = darken(k.mark, 0.15),
        .chan_hdr = mix(k.dim, k.accent, 0.30),
        .sid_hdr = k.sid,
        .mode_badge = k.sid,
        .phrase_end = darken(k.ground, 0.40 * k.lift),
        .phrase_len = darken(k.dim, 0.80),
        .BG_TOP = lit(k.ground, 0.014),
        .BG_BOT = lit(k.ground, 0.040),
        .GLOW_STRIP = lit(k.accent, 0.80),
        .CURSOR_GLOW = lit(k.accent, 0.85),
        .MOTE = lit(k.ground, 0.36),
        .LOGO_ICE = k.logo_a,
        .LOGO_PINK = k.logo_b,
        .VIZ_BAR_LO = lit(k.accent, 0.20),
        .VIZ_TIP = mixV3(k.logo_b, white, 0.55),
        .VIZ_PEAK = mixV3(k.logo_a, white, 0.30),
        .VIZ_SLOT = lit(k.ground, 0.06),
        .VIZ_SCOPE = k.logo_a,
        .VIZ_SCOPE_GLOW = lit(k.mark, 0.60),
        .VIZ_BASELINE = lit(k.ground, 0.32),
        .WAVE_SLOT = lit(k.ground, 0.035),
        .WAVE_BASE = lit(k.ground, 0.36),
        .WAVE_LOOP_BG = lit(k.mark, 0.10),
        .WAVE_SUS_BG = lit(k.accent, 0.10),
        .WAVE_MARK_SUS = lit(k.accent, 1.0),
        .WAVE_SEAM = mixV3(k.logo_a, white, 0.70),
        .ENV_NODE = mixV3(k.logo_a, white, 0.30),
        .STRIP_SLOT = lit(k.ground, 0.045),
        .STRIP_PCM_LO = lit(k.accent, 0.30),
        .MIX_MASTER_LO = lit(k.ground, 0.30),
        .MIX_MASTER_HI = mixV3(k.logo_a, white, 0.50),
        .PULSE_BEAT = lit(k.mark, 0.60),
        .PULSE_NOTE = lit(k.accent, 0.80),
        .STRIP_SID_LO = lit(k.sid, 0.26),
        .STRIP_SID_HI = lit(k.sid, 1.0),
        .MIX_ADSR = lit(k.sid, 0.62),
        .PULSE_NOTE_SID = lit(k.sid, 0.82),
    };
}

/// NEBULA — a violet cloud with a pink star in it. Smooth: lavender text,
/// soft furniture, the chips in peach-gold.
const NEBULA = derive(.{
    .ground = c(120, 70, 210),
    .text = c(200, 184, 240),
    .dim = c(132, 108, 188),
    .bright = c(244, 236, 255),
    .accent = c(172, 124, 255),
    .hot = c(222, 196, 255),
    .mark = c(255, 118, 200),
    .note = c(240, 232, 255),
    .ins = c(192, 152, 255),
    .vol = c(164, 172, 250),
    .fx = c(150, 124, 212),
    .cursor = c(218, 194, 255),
    .sid = c(255, 192, 122),
    .logo_a = v3(0.82, 0.68, 1.00),
    .logo_b = v3(1.00, 0.36, 0.74),
    .lift = 0.9,
});

/// ABYSS — the deep sea: teal glass, aquamarine light, a coral reef for
/// the chips. Smooth.
const ABYSS = derive(.{
    .ground = c(24, 132, 156),
    .text = c(150, 214, 216),
    .dim = c(78, 144, 156),
    .bright = c(226, 252, 250),
    .accent = c(56, 208, 214),
    .hot = c(156, 246, 236),
    .mark = c(88, 240, 188),
    .note = c(222, 250, 248),
    .ins = c(100, 220, 232),
    .vol = c(122, 190, 214),
    .fx = c(82, 160, 176),
    .cursor = c(160, 240, 232),
    .sid = c(255, 150, 112),
    .logo_a = v3(0.56, 1.00, 0.94),
    .logo_b = v3(0.10, 0.46, 0.86),
    .lift = 0.9,
});

/// AURORA — northern lights over a polar night: green that shimmers
/// into violet, crisp.
const AURORA = derive(.{
    .ground = c(40, 92, 118),
    .text = c(200, 234, 224),
    .dim = c(110, 160, 160),
    .bright = c(246, 255, 252),
    .accent = c(80, 250, 168),
    .hot = c(190, 255, 222),
    .mark = c(182, 124, 255),
    .note = c(236, 255, 248),
    .ins = c(120, 250, 188),
    .vol = c(152, 200, 255),
    .fx = c(122, 170, 182),
    .cursor = c(146, 255, 204),
    .sid = c(255, 206, 112),
    .logo_a = v3(0.46, 1.00, 0.70),
    .logo_b = v3(0.66, 0.36, 1.00),
    .lift = 1.1,
});

/// EMBER — the last hour of a fire: rose and coral over a dark red glow,
/// the chips in gold. Smooth.
const EMBER = derive(.{
    .ground = c(168, 48, 44),
    .text = c(232, 192, 180),
    .dim = c(168, 112, 106),
    .bright = c(255, 240, 230),
    .accent = c(242, 112, 90),
    .hot = c(255, 204, 150),
    .mark = c(255, 88, 124),
    .note = c(255, 238, 228),
    .ins = c(250, 152, 122),
    .vol = c(222, 142, 144),
    .fx = c(190, 112, 102),
    .cursor = c(255, 202, 172),
    .sid = c(255, 214, 104),
    .logo_a = v3(1.00, 0.80, 0.60),
    .logo_b = v3(0.86, 0.14, 0.26),
    .lift = 0.9,
});

/// VOLTAGE — HIGH CONTRAST: white on black with an electric-cyan arc, a
/// hot magenta spark and a volt-yellow cursor. Nothing melts.
const VOLTAGE = derive(.{
    .ground = c(44, 46, 72),
    .text = c(236, 236, 246),
    .dim = c(154, 156, 182),
    .bright = c(255, 255, 255),
    .accent = c(0, 228, 255),
    .hot = c(255, 255, 84),
    .mark = c(255, 40, 168),
    .note = c(255, 255, 255),
    .ins = c(0, 228, 255),
    .vol = c(176, 255, 92),
    .fx = c(255, 132, 222),
    .cursor = c(0, 228, 255),
    .sid = c(255, 162, 0),
    .logo_a = v3(0.00, 0.90, 1.00),
    .logo_b = v3(1.00, 0.14, 0.64),
    .lift = 1.45,
});

/// OBSIDIAN — HIGH CONTRAST in black glass: white text, greys for the
/// furniture, one ultramarine vein and a white cursor.
const OBSIDIAN = derive(.{
    .ground = c(62, 62, 70),
    .text = c(222, 222, 226),
    .dim = c(138, 138, 146),
    .bright = c(255, 255, 255),
    .accent = c(118, 158, 255),
    .hot = c(204, 222, 255),
    .mark = c(236, 236, 244),
    .note = c(255, 255, 255),
    .ins = c(170, 192, 255),
    .vol = c(196, 196, 202),
    .fx = c(150, 150, 160),
    .cursor = c(255, 255, 255),
    .sid = c(255, 192, 92),
    .logo_a = v3(1.00, 1.00, 1.00),
    .logo_b = v3(0.34, 0.50, 1.00),
    .lift = 1.4,
    .surface = 2.0,
});

/// DMG — qartz's own: the original Game Boy's four-shade LCD green
/// (#0F380F #306230 #8BAC0F #9BBC0F), lit from behind like a backlight
/// mod — one hue, many glows.
const DMG: Palette = .{
    .header_bg = c(8, 26, 8),
    .text = c(155, 188, 15),
    .text_dim = c(86, 120, 30),
    .text_bright = c(214, 240, 120),
    .value_off = c(48, 74, 24),
    .table_hdr = c(139, 172, 15),
    .accent = c(139, 172, 15),
    .accent_hot = c(200, 236, 90),
    .accent_pink = c(236, 250, 170),
    .pink_dim = c(110, 140, 40),
    .sep = c(48, 98, 48),
    .note_col = c(214, 240, 120),
    .ins_col = c(170, 210, 60),
    .vol_col = c(120, 160, 40),
    .fx_col = c(100, 140, 30),
    .dots = c(36, 70, 30),
    .rownum = c(86, 120, 30),
    .rownum_beat = c(170, 210, 60),
    .cursor_bg = c(190, 226, 80),
    .cursor_bg_blink = c(100, 140, 30),
    .cursor_fg = c(15, 56, 15),
    .playhead_bg = c(20, 52, 18),
    .playhead_sid_bg = c(24, 58, 18),
    .playhead_echo_bg = c(14, 36, 14),
    .cursor_row_bg = c(18, 44, 16),
    .cursor_row_bg_sid = c(16, 34, 14),
    .row_beat_bg = c(8, 20, 8),
    .mark_bg = c(48, 98, 48),
    .lap_bg = c(14, 30, 12),
    .chan_hdr = c(110, 150, 30),
    .sid_hdr = c(236, 250, 170),
    .mode_badge = c(236, 250, 170),
    .phrase_end = c(30, 60, 24),
    .phrase_len = c(70, 104, 30),
    .BG_TOP = v3(0.002, 0.010, 0.002),
    .BG_BOT = v3(0.008, 0.030, 0.008),
    .GLOW_STRIP = v3(0.30, 0.55, 0.04),
    .CURSOR_GLOW = v3(0.40, 0.70, 0.06),
    .MOTE = v3(0.10, 0.20, 0.03),
    .LOGO_ICE = v3(0.62, 0.80, 0.10),
    .LOGO_PINK = v3(0.85, 0.98, 0.45),
};

pub const SCHEMES = [_]Scheme{
    .{ .name = "DUET", .blurb = "ice and pink on black - the default", .pal = DUET },
    .{ .name = "SID-WIZARD", .blurb = "SID-Wizard's own greys, light green highlights", .pal = SIDWIZ },
    .{ .name = "IMPULSE", .blurb = "Impulse Tracker's palette - cream, green, magenta", .pal = IMPULSE },
    .{ .name = "PHOSPHOR", .blurb = "an amber monitor - one hue, many glows", .pal = PHOSPHOR },
    .{ .name = "NEBULA", .blurb = "a violet cloud with a pink star in it", .pal = NEBULA },
    .{ .name = "ABYSS", .blurb = "deep-sea teal, aquamarine light, coral chips", .pal = ABYSS },
    .{ .name = "AURORA", .blurb = "northern lights - green into violet, crisp", .pal = AURORA },
    .{ .name = "EMBER", .blurb = "the last hour of a fire - rose, coral, gold", .pal = EMBER },
    .{ .name = "VOLTAGE", .blurb = "high contrast - white, electric cyan, magenta", .pal = VOLTAGE },
    .{ .name = "OBSIDIAN", .blurb = "high contrast black glass - white, one blue vein", .pal = OBSIDIAN },
    .{ .name = "DMG", .blurb = "the original Game Boy LCD, backlit - four greens", .pal = DMG },
};

/// The scheme in force (an index into SCHEMES).
pub var active: usize = 0;

/// Case and hyphens do not matter: `sidwizard`, `SID-Wizard`.
pub fn schemeByName(name: []const u8) ?usize {
    for (SCHEMES, 0..) |sc, i| {
        if (sameName(sc.name, name)) return i;
    }
    return null;
}

fn sameName(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and a[i] == '-') i += 1;
        while (j < b.len and b[j] == '-') j += 1;
        if (i == a.len or j == b.len) return i == a.len and j == b.len;
        if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[j])) return false;
        i += 1;
        j += 1;
    }
}

// ------------------------------------------------------- THE MOTION KNOBS
//
// XXVIII D (s169). Every animation runs on the FRAME CLOCK (motion.zig) —
// a length in milliseconds becomes frames at 60 fps, and a headless
// picture always draws the end state. The CURVES are m64's to pick by
// feel in his own terminal: `.linear`, `.ease_out` (fast, then settling)
// or `.ease_in_out` (soft at both ends). Edit, rebuild, look.

/// D1 THE SCHEME CROSSFADE: every palette colour lerps from the old
/// scheme to the new one. The config write is at once either way.
pub const scheme_fade_ms: u32 = 500;
pub const scheme_fade_curve: motion.Curve = .ease_out;

/// D3 THE COMMIT FLASH: an edit that lands (a cell, a nudged value, a
/// kept name) lights the spot the keys were on in `flash_colour`, and
/// the light decays over `flash_ms`. `flash_peak` is how far toward
/// the flash colour the ground goes at the first frame (1 = all the way).
pub const flash_ms: u32 = 150;
pub const flash_curve: motion.Curve = .ease_in_out;
pub const flash_peak: f32 = 0.85;

/// D4 THE STATUS MESSAGE: fades IN from the header's ground, holds at
/// full white, DIMS to the furniture colour (`text_dim`) and vanishes
/// where it always did (4 s — his ruling, s169; the pink safety confirm
/// only fades in, it never dims: its window is still armed). `status_out_ms`
/// is a last fade to the ground before it goes (0 = it just goes).
pub const status_in_ms: u32 = 120;
pub const status_hold_ms: u32 = 1500;
pub const status_dim_ms: u32 = 800;
pub const status_out_ms: u32 = 200;
pub const status_curve: motion.Curve = .ease_out;

/// The flash's colour, re-read every frame (it follows the scheme).
pub fn flashColour() Rgb {
    return accent_hot;
}

/// Paint with scheme `i` from the next frame on, AT ONCE — the start of a
/// session and `--scheme`. Out of range = DUET. (`fadeTo` is the eye's.)
pub fn apply(i: usize) void {
    active = if (i < SCHEMES.len) i else 0;
    fade = .{};
    paint(&SCHEMES[active].pal);
}

/// D1: walk to scheme `i` over `scheme_fade_ms`, starting at frame `now`
/// from whatever is on the glass THIS frame (a fade interrupted by the
/// next press starts from where it had got to, never with a jump).
pub fn fadeTo(i: usize, now: u64) void {
    inline for (std.meta.fields(Palette)) |f| @field(fade_from, f.name) = @field(@This(), f.name);
    active = if (i < SCHEMES.len) i else 0;
    fade = motion.Anim.begin(now, motion.frames(scheme_fade_ms));
    tick(now);
}

/// Once a frame, before anything is drawn: the crossfade's colours for
/// frame `now` (nothing to do once it has landed).
pub fn tick(now: u64) void {
    if (fade.len == 0) return;
    const t = motion.ease(scheme_fade_curve, fade.t(now));
    const to = &SCHEMES[active].pal;
    if (t >= 1) {
        fade = .{};
        paint(to);
        return;
    }
    var p: Palette = undefined;
    inline for (std.meta.fields(Palette)) |f| {
        const a = @field(fade_from, f.name);
        const b = @field(to, f.name);
        @field(p, f.name) = if (f.type == V3) mixV3(a, b, t) else mix(a, b, t);
    }
    paint(&p);
}

var fade: motion.Anim = .{};
var fade_from: Palette = .{};

fn paint(p: *const Palette) void {
    inline for (std.meta.fields(Palette)) |f| @field(@This(), f.name) = @field(p, f.name);
    sw_phrase = text_bright;
    VIZ_BAR_HI = LOGO_PINK;
    WAVE_MARK = LOGO_PINK;
    env_spark = accent;
    env_spark_ghost = dots;
    section_rule = dots;
    section_hdr = text;
    STRIP_PCM_HI = LOGO_ICE;
    focus_bg = accent_pink;
    focus_fg = bg;
    type_bg = cursor_bg;
    chosen_bg = cursor_bg_blink;
    chosen_fg = cursor_fg;
    button_bg = mix(header_bg, accent, button_tint);
    dots_off = mix(dots, bg, dots_off_dim);
}

// ------------------------------------------------------------- text (Rgb)
pub var bg: Rgb = DUET.bg;
pub var header_bg: Rgb = DUET.header_bg;

pub var text: Rgb = DUET.text;
pub var text_dim: Rgb = DUET.text_dim;
pub var text_bright: Rgb = DUET.text_bright;
/// A VALUE NOBODY IS READING — a knob under a bypassed stage (s67).
/// `text_dim` is the LABEL's blue, so dimming a value to it painted the
/// console's lower half one uniform colour: label and value the same
/// ink, row after row, and nothing to tell an address from a number
/// (m64: *"the lower half of the screen is an all-blueish text block"*).
/// This is GREY and darker than the label, so a dead value recedes
/// behind the word that names it instead of merging with it. A STATE
/// row's own word (`BYP`/`ON`) never wears it — that word IS the news.
pub var value_off: Rgb = DUET.value_off;
/// A TABLE'S HEADER ROW (s92) — the MOD face's `LFO SHAPE RATE ...`
/// lines, the RESOLUTION and MACRO headers, the TABLES titles. One step
/// brighter than `text_dim` so a header reads as a header over its
/// rows, and clearly short of `accent_hot`, which stays the SELECTED
/// thing's colour.
pub var table_hdr: Rgb = DUET.table_hdr;
pub var accent: Rgb = DUET.accent;
pub var accent_hot: Rgb = DUET.accent_hot;
pub var accent_pink: Rgb = DUET.accent_pink; // special markers (SW legato "L=")
pub var pink_dim: Rgb = DUET.pink_dim; // special note values (===/^^^/~~~)
pub var sep: Rgb = DUET.sep;

// pattern cell classes
pub var note_col: Rgb = DUET.note_col;
pub var ins_col: Rgb = DUET.ins_col;
pub var vol_col: Rgb = DUET.vol_col;
pub var fx_col: Rgb = DUET.fx_col;
/// M33 — DUET's own four send commands (`a`-`d`) wherever a cell shows
/// one. ONE colour for all four (m64's ruling): the point is not to
/// tell the units apart — the letter does that — it is to say at a
/// glance that this is not IT's `Axx`. Green: nothing else in a cell
/// is, and it is the room's colour on the console's meters.
pub var fx_duet: Rgb = DUET.fx_duet;
pub var dots: Rgb = DUET.dots;
/// THE OFF-BEAT DOTS (XXVIII A6): the empty-cell texture one step toward
/// the page on every row that is not a beat (nor the cursor bar, the
/// playhead or a mark), so the beat grid reads at a glance. Re-derived
/// by apply() from each scheme's own `dots`.
pub const dots_off_dim: f32 = 0.40;
pub var dots_off: Rgb = mix(DUET.dots, DUET.bg, dots_off_dim);
pub var rownum: Rgb = DUET.rownum;
pub var rownum_beat: Rgb = DUET.rownum_beat;

// ------------------------------------ ONE "SELECTED" LANGUAGE (XXVIII A1)
// Three states, one look each, on every page (m64, s166c): FOCUS is
// where the keys go — the pink the grid's edit field has always worn,
// now on a list row, a chip, a button, a card's field; TYPING is a field
// opened for text — the ice ground with the pink caret; CHOSEN is what is
// picked while the keys are somewhere else — the quiet blue a list keeps
// when the editor beside it has the cursor. The grid keeps its own pair
// (the pink field inside the ice cell, and the ice row bar) by his word.
// All five re-derived by apply() from the scheme's own colours.
pub var focus_bg: Rgb = DUET.accent_pink;
pub var focus_fg: Rgb = DUET.bg;
pub var type_bg: Rgb = DUET.cursor_bg;
pub var chosen_bg: Rgb = DUET.cursor_bg_blink;
pub var chosen_fg: Rgb = DUET.cursor_fg;
/// A BUTTON IS A CHIP (XXVIII A2): the value chips' tinted ground, a
/// step toward the accent so a verb reads as pressable beside a value.
pub const button_tint: f32 = 0.16;
pub var button_bg: Rgb = mix(DUET.header_bg, DUET.accent, button_tint);

pub var cursor_bg: Rgb = DUET.cursor_bg;
pub var cursor_bg_blink: Rgb = DUET.cursor_bg_blink;
pub var cursor_fg: Rgb = DUET.cursor_fg;
pub var playhead_bg: Rgb = DUET.playhead_bg;
pub var playhead_sid_bg: Rgb = DUET.playhead_sid_bg; // SID playhead: teal-green twin
pub var playhead_echo_bg: Rgb = DUET.playhead_echo_bg; // IT clock crossing SW tracks: dim blue echo
pub var cursor_row_bg: Rgb = DUET.cursor_row_bg; // full-row bar under the edit cursor
pub var cursor_row_bg_sid: Rgb = DUET.cursor_row_bg_sid; // ...dimmed/grayed over SID channels
pub var row_beat_bg: Rgb = DUET.row_beat_bg; // the beat lift (the TUNE's grid, XII)
// THE MARK (XII): the block is a WASH over whatever the row context
// already painted, never a replacement — so the playhead and the
// cursor bar stay readable straight through a marked block, and the
// tint says "these fields" on a field-granular one. `mark_bg_live` is
// the block that is still following the cursor: the same hue, further
// up, because a block that is still growing is the thing you are
// looking at.
pub var mark_bg: Rgb = DUET.mark_bg;
pub const MARK_TINT: f32 = 0.42;
pub const MARK_TINT_LIVE: f32 = 0.58;
/// THE MARKERS (XXI.d): a sync marker is an OVERLAY on its cell — a
/// wash over the row context like the mark's, in the amber of the SID
/// badge, so it reads as "a fact about the song here" and never as a
/// selection.
pub var marker_bg: Rgb = DUET.marker_bg;
pub const MARKER_TINT: f32 = 0.45;

pub var lap_bg: Rgb = DUET.lap_bg; // POLY lap start: violet wrap marker
pub var chan_hdr: Rgb = DUET.chan_hdr;
pub var sid_hdr: Rgb = DUET.sid_hdr; // SID channel badge (warm amber vs the blue PCM scheme)
pub var mode_badge: Rgb = DUET.mode_badge; // the header's file-mode chip [IT]/[SWM]/[DUET]/[CO] (s42)
/// The ":03" phrase caption on an SW column header — WHICH SWM pattern
/// that track is standing in. Bright against the amber label, because
/// the number is the payload and the label is the address (m64, s25).
pub var sw_phrase: Rgb = DUET.text_bright; // = text_bright, re-derived by apply()
/// THE PHRASE AXIS (M26). `phrase_end` inks the boundary rule a column
/// wears on the first row its own pattern does not have — dimmer than
/// the dots, because it marks an ABSENCE and must never compete with a
/// row that has content. `phrase_len` inks the `↕NN` chip in the column
/// header: metadata about the column, so it reads quieter than the
/// phrase number, which is the payload.
pub var phrase_end: Rgb = DUET.phrase_end;
pub var phrase_len: Rgb = DUET.phrase_len;

// ------------------------------------------------------------ pixels (V3)
pub var BG_TOP: V3 = DUET.BG_TOP;
pub var BG_BOT: V3 = DUET.BG_BOT;
pub var GLOW_STRIP: V3 = DUET.GLOW_STRIP;
pub var CURSOR_GLOW: V3 = DUET.CURSOR_GLOW;
pub var MOTE: V3 = DUET.MOTE;

// ------------------------------------------------------ THE LOGO PALETTE
// The two colors the D U E T logo is lerped between (logoview draws the
// mask as ICE at the top fading to PINK at the bottom). They are the
// program's identity, so anything that wants "our colors" takes them
// from here rather than inventing a near-miss: the visualizer bars end
// on the pink, the sample editor's waveform runs the whole ramp.
pub var LOGO_ICE: V3 = DUET.LOGO_ICE;
pub var LOGO_PINK: V3 = DUET.LOGO_PINK;

/// THE WATERMARK (s60, `logoview.drawMark`): how far the logotype is
/// lerped from the page's backdrop toward its own colours where a page
/// has empty room to spare — the cockpit's band under FILES. Two knobs
/// because they do different jobs: the SOLID is the mark's presence,
/// and the GLOW is whether it belongs to the room's light at all. Keep
/// the glow tiny — a filled shape feeding the blur from its interior
/// drifts white (the M11 rule), and a watermark that blooms stops being
/// one. Raise `logo_mark` to make it read from further away.
pub const logo_mark: f32 = 0.13;
pub const logo_mark_glow: f32 = 0.012;
/// ... and how much of the page's WIDTH the mark may span. The band it
/// stands in grows with the terminal, and the logotype would grow with
/// it until a signature had become a poster behind the page — this is
/// the line between the two. Toward 1.0 is the poster.
pub const logo_mark_width: f32 = 0.45;
/// ... and the hard ceiling on pixels-per-mask-pixel, which is the knob
/// that actually decides the mark's CHARACTER. The logotype is an
/// OUTLINE, so its strokes thicken with the scale: at `s = 1` (the
/// `--help` masthead's 1:1) they are hairlines, at 2 they are still a
/// drawn mark, and from 3 up they are slabs — a shape rather than a
/// signature, and the page reads as if it had a background. **m64's
/// eye, s60: cap it at 2** ("I find it can get smaller in such
/// situations by capping s max 2, this looks nice"). Zooming the font
/// out no longer grows the mark past this; it just leaves more air
/// around it.
pub const logo_mark_max_s: f32 = 2.0;
/// ... and the FLOOR, in output pixels of the logotype's ink (s63,
/// m64: *"when it does not fit in the calculated size - let it try the
/// lower sizes, it might fit then"*). Above `s = 1` the mark scales in
/// whole mask pixels; below it, in whole OUTPUT pixels — 7 is the ink's
/// own height, so 6 is one rung down and the last one where the four
/// letters still read as letters rather than a bar of light. A page
/// with less room than this keeps its empty rows: *a page with nothing
/// to spare spares nothing.*
pub const logo_mark_min_px: i32 = 6;

// ------------------------------------------------- visualizer pixels (V3)
pub var VIZ_BAR_LO: V3 = DUET.VIZ_BAR_LO; // bar base: deep blue
pub var VIZ_BAR_HI: V3 = DUET.LOGO_PINK; // = LOGO_PINK, re-derived by apply() // bar tip: the DUET pink
pub var VIZ_TIP: V3 = DUET.VIZ_TIP; // hot 1px tip highlight
pub var VIZ_PEAK: V3 = DUET.VIZ_PEAK; // falling peak caps (ice)
pub var VIZ_SLOT: V3 = DUET.VIZ_SLOT; // empty bar slot ghost
pub var VIZ_SCOPE: V3 = DUET.VIZ_SCOPE; // scope beam core
pub var VIZ_SCOPE_GLOW: V3 = DUET.VIZ_SCOPE_GLOW; // beam phosphor (violet)
pub var VIZ_BASELINE: V3 = DUET.VIZ_BASELINE; // baseline / graticule

// --------------------------------- sample-editor waveform (V3, pixels)
// THE WAVE IS THE LOGO (m64's call): its amplitude ramp runs the same
// two colors the logotype is lerped between, ordered by brightness —
// DEEP PINK where the sample is quiet, ICE CYAN at the crests. So a
// waveform reads as loudness at a glance and wears the program's own
// face while doing it.
//
// The markers keep their jobs: LOOP wears the pink at full strength
// (against a darkened wave it still shouts), SUSTAIN the accent blue,
// and the focused one goes near-white — which is the one hue the ramp
// never reaches.
pub var WAVE_SLOT: V3 = DUET.WAVE_SLOT; // the box behind the wave
pub var WAVE_BASE: V3 = DUET.WAVE_BASE; // zero line

/// HOW THE WAVE GLOWS — and why it is the EDGE that does it.
///
/// Frame.composite clamps solid+glow PER CHANNEL, so a bright color
/// loses its hue from the top down: ice is (0.55, 0.85, 1.00), and once
/// the glow at a pixel passes ~0.15 both G and B sit at 1.0 together
/// and the crest reads WHITE, not cyan. A filled waveform feeds the
/// blur from every interior pixel at once, and the glow buffer's decay
/// re-seeds each frame (~3.6x in steady state), so the wash gets worse
/// the WIDER the terminal — which is why a small --shot looked right
/// while m64's real window did not.
///
/// So the body barely feeds the buffer and the ENVELOPE EDGE carries
/// the light. That is also how neon works: the tube's edge is the
/// source, the inside is just bright glass.
pub const wave_glow_body: f32 = 0.020; // per interior pixel (keep small)
pub const wave_glow_rim: f32 = 0.045; // per edge pixel, at silence
pub const wave_glow_rim_amp: f32 = 0.110; // ... plus this much at a crest
pub var WAVE_LOOP_BG: V3 = DUET.WAVE_LOOP_BG; // loop span wash
pub var WAVE_SUS_BG: V3 = DUET.WAVE_SUS_BG; // sustain span wash
pub var WAVE_MARK: V3 = DUET.LOGO_PINK; // = LOGO_PINK, re-derived by apply() // loop markers
pub var WAVE_MARK_SUS: V3 = DUET.WAVE_MARK_SUS; // sustain markers
pub var WAVE_SEAM: V3 = DUET.WAVE_SEAM; // the focused marker / splice seam

/// The waveform's amplitude ramp, in TWO independent parts — which is
/// what makes "pink is the darkest, cyan the brightest" literally true
/// instead of approximately:
///
///   HUE walks the logotype's own path, LOGO_PINK -> LOGO_ICE. The
///   straight lerp between them IS the logo's gradient (all three
///   gammas at 1.0); green climbing latest holds the middle on the
///   pink -> lavender -> periwinkle side of it and saves the cyan for
///   crests that earned it.
///
///   BRIGHTNESS rides amplitude on top: WAVE_QUIET of full at silence,
///   full at a crest. This is the contrast knob — lower it and quiet
///   passages sink further into the dark pink.
pub const wave_gamma_r: f32 = 1.0;
pub const wave_gamma_g: f32 = 1.6;
pub const wave_gamma_b: f32 = 0.9;
pub const wave_gamma_v: f32 = 1.0; // the brightness curve
pub const WAVE_QUIET: f32 = 0.22; // how dark silence sits

pub fn waveRamp(q: f32) V3 {
    const t = std.math.clamp(q, 0.0, 1.0);
    const hue = V3{
        .r = LOGO_PINK.r + (LOGO_ICE.r - LOGO_PINK.r) * std.math.pow(f32, t, wave_gamma_r),
        .g = LOGO_PINK.g + (LOGO_ICE.g - LOGO_PINK.g) * std.math.pow(f32, t, wave_gamma_g),
        .b = LOGO_PINK.b + (LOGO_ICE.b - LOGO_PINK.b) * std.math.pow(f32, t, wave_gamma_b),
    };
    return hue.scale(WAVE_QUIET + (1.0 - WAVE_QUIET) * std.math.pow(f32, t, wave_gamma_v));
}

// ------------------------- the I## envelope graph (V3, pixels; I.2c)
// The stroke runs waveRamp by |value| — the same logo ramp the wave
// wears, so a full-level node crests into ice and a quiet one sits in
// the dark pink. The glow rides THE STROKE, never a fill (§ movy).
pub var ENV_NODE: V3 = DUET.ENV_NODE; // a node's tick mark
pub const env_glow_stroke: f32 = 0.10; // per stroke pixel
pub const env_glow_node: f32 = 0.30; // ... the cursor's node
pub const env_dim: f32 = 0.45; // how far an OFF envelope recedes
pub const ENV_DOT = v3(1.00, 0.96, 0.62); // the LIVE position dot (I.2e)
pub var env_dot_txt: Rgb = DUET.env_dot_txt; // ... its ruler twin ◆
pub const env_glow_dot: f32 = 0.45; // the dot outglows the cursor node

// ---------------- the GENERAL card's envelope SPARKLINES (text; s40)
// A 12-cell `▁▂▄▆█` glance of each envelope's shape, right on the
// card — the graph pages hold the truth, this is the trailer. An OFF
// envelope keeps its shape as a GHOST (the mixer's ghost-bar rule:
// silence still shows the shape, in the furniture colour).
pub var env_spark: Rgb = DUET.accent; // = accent, re-derived by apply()
pub var env_spark_ghost: Rgb = DUET.dots; // = dots, re-derived by apply()

// -------------------------- labeled SECTION RULES (text; s40, s60)
// `── SETUP ──────` — a page's inner chapters. The rule glyphs are
// furniture (the dots colour, one step below `sep` so the page's own
// frame still outranks them), and since s60 they FADE OUT toward the
// right edge: a hairline that ends in the dark reads as structure
// without drawing a box around anything.
//
// The WORD is ONE colour in every section (s60, m64: *"the coloring
// seems arbitrary ... maybe we can just make the separator colors
// uniform"*). It used to wear the section's own identity — amber for
// SETUP, label blue for FILES — and that is exactly the rule to drop:
// DUET's two identity colours (ICE for the IT half, EMBER for the SID
// half) belong to the ROWS that carry those facts, and a heading
// borrowing one makes a page look coloured by accident instead of by
// law. The hierarchy that remains reads top to bottom: rule glyphs
// (dimmest) < field labels (`chan_hdr`) < section headings (this) <
// the values themselves.
pub var section_rule: Rgb = DUET.dots; // = dots, re-derived by apply()
pub var section_hdr: Rgb = DUET.text; // = text, re-derived by apply()

// ------------------------------- THE CPU METER's two thresholds (s64)
//
// The title bar's `CPU nn%` is the audio callback's share of its own
// budget, so the numbers are not taste: **100 % is the dropout line.**
// It turns EMBER at half the budget — where a spare chip or a heavier
// sampling method is still an easy yes — and PINK at three quarters,
// which is the last place a warning is any use.
pub const CPU_WARN_PCT: u16 = 50;
pub const CPU_HOT_PCT: u16 = 75;
/// Where along a rule the fade begins, as a fraction of its length
/// (0 = fading from the label itself, 1 = no fade). The left end stays
/// solid so the word always sits on a real line.
pub const section_fade: f32 = 0.45;

// ------------------- the song screen's DENSITY STRIP (V3, pixels)
//
// The order list's map of what plays where. It began as ANSI shading
// (`·░▒▓`) and moved to the PIXEL layer in session 24 (m64), because
// four glyphs are four steps and a gradient is as many as the eye can
// take — and because a colour can say PCM-or-SID at the same time as
// it says how much, which a shade cannot.
//
// Drawn as the LOWER half of each cell: the strip reads as a lane of
// small blocks, one per order position, rather than as a solid column
// you have to count rows down. The upper half keeps the empty-lane
// colour so the track is visible where nothing plays.
pub var STRIP_SLOT: V3 = DUET.STRIP_SLOT; // the lane, unplayed
pub var STRIP_PCM_LO: V3 = DUET.STRIP_PCM_LO; // one note in the pattern
pub var STRIP_PCM_HI: V3 = DUET.LOGO_ICE; // = LOGO_ICE, re-derived by apply() // wall to wall
pub var STRIP_SID_LO: V3 = DUET.STRIP_SID_LO; // ... and the SID half,
pub var STRIP_SID_HI: V3 = DUET.STRIP_SID_HI; //     amber like its columns
/// DUST's own third identity (XIII.b+). Its slots are whole SID chips,
/// but on a console that shows SID1..4 and SYN1..4 side by side the two
/// have to be told apart at a glance — so the synth gets a hue of its
/// own rather than a second amber.
pub const STRIP_SYN_LO = v3(0.17, 0.06, 0.32);
pub const STRIP_SYN_HI = v3(0.80, 0.56, 1.00);
/// ... and DUSK's fourth (XIV.b+): the console can show four families
/// side by side now — PCM ice, chip amber, DUST violet — so the
/// wavetable synth wears the hour it is named for, a sunset rose that
/// reads warm beside the violet without drifting into the amber.
pub const STRIP_DUSK_LO = v3(0.26, 0.07, 0.15);
pub const STRIP_DUSK_HI = v3(1.00, 0.52, 0.62);
/// Below 1.0 the low end of the ramp opens up, which is where a sparse
/// pattern lives — the difference between "two notes" and "nothing" is
/// the one this strip most needs to show.
pub const strip_gamma: f32 = 0.55;
pub const strip_glow: f32 = 0.075; // busy sections bloom, quiet ones do not
/// HOW MUCH OF THE DENSITY COLOUR THE UPPER PIXEL GETS — the one knob
/// worth keeping switchable, because it is the whole character of the
/// strip:
///
///   0.0  a HALF BLOCK. The upper pixel keeps the empty-lane colour, so
///        every order position reads as a separate cell you can count.
///   1.0  a FULL BLOCK: one continuous ribbon. The gradient has twice
///        the area to work in and the song's SHAPE reads at a glance —
///        at the cost of not seeing where one position ends.
///   in between: both. Body and a gradient, with a faint seam still
///        marking the rows.
///
/// 0.80 is m64's, dialled in against the three renders: nearly the full
/// ribbon, with just enough darkening at the top of each cell to keep
/// the order positions countable. A list you NAVIGATE has to stay a
/// list, and a map you READ wants the area — this is where both hold.
pub const strip_top: f32 = 0.80;

// ------------------- THE MIXER (M17/I.3b, pixels + text)
//
// The console's meters: one vertical bar per strip in the meter zone,
// PCM ice / SID amber (the density strip's own palette, so the two
// screens speak one colour language), MASTER in the logo's white-ice.
// Glow rides the TOP EDGE of a bar, never its area (the M11 rule —
// a filled shape feeding the blur from its interior drifts white).
pub var MIX_MASTER_LO: V3 = DUET.MIX_MASTER_LO; // master bar, quiet
pub var MIX_MASTER_HI: V3 = DUET.MIX_MASTER_HI; // ... full scale
pub const MIX_CLIP = v3(1.00, 0.16, 0.10); // the honest red
pub var MIX_ADSR: V3 = DUET.MIX_ADSR; // a chip's three envelope minis
/// ... and a SYN strip's one (XIII.b+). It is the SLOT's envelope, so it
/// stays in DUST's own hue — an amber tip on a violet strip would read
/// as a chip, which is the one thing the two colours exist to prevent.
pub const MIX_SYN_ADSR = v3(0.95, 0.66, 1.00);
/// ... and a DUSK strip's (XIV.b+): the software ladder's level, the
/// loudest live instance — in the rose family for the same reason the
/// SYN mini stays violet.
pub const MIX_DUSK_ADSR = v3(1.00, 0.72, 0.78);
pub const mix_glow_top: f32 = 0.32; // the bar's top-edge bloom
pub const mix_glow_clip: f32 = 0.55; // clipping SHOUTS
/// UI meter ballistics: fall per frame (the peaks the audio thread
/// max-accumulates are swap(0)-read, then decay at this rate — fast
/// enough to dance, slow enough to read).
pub const mix_meter_fall: f32 = 0.90;
pub const mix_gamma: f32 = 0.60; // like strip_gamma: open the low end
/// How far a MUTED column's ink recedes toward its paper in the
/// pattern grid (0 = no dim, 1 = invisible). The cursor cell is exempt.
pub const mute_dim: f32 = 0.62;
/// The state words, in the traffic colours every console uses: MUTED
/// is red, SOLO is green (m64) — on the mixer strips, the song
/// screen's table, and the chip titles' saved voice dots.
pub var mute_red: Rgb = DUET.mute_red;
pub var solo_green: Rgb = DUET.solo_green;

// ------------------- THE BOUNCE (M18/I.4b, the export popup)
//
// The progress bar IS the waveform being born: per-chunk peaks fill
// left to right as mini-columns in the popup's pixel zone. Played
// slots run the tape's violet into the DUET pink; the road ahead is
// the mixer's ghost idea one screen over. Glow rides the column TIPS
// and the sweep head, never the area (the M11 rule).
pub const EXPORT_BAR_LO = v3(0.34, 0.16, 0.60); // the tape, quiet
pub const EXPORT_BAR_HI = v3(1.00, 0.36, 0.86); // ... at full peak
pub const EXPORT_HEAD = v3(0.90, 0.96, 1.00); // the sweep head (logo ice)
pub const export_ghost: f32 = 0.16; // unplayed lane: the shape ahead
pub const export_glow_tip: f32 = 0.55; // envelope tip bloom
pub const export_glow_head: f32 = 0.70; // the head SWEEPS, so it shines
pub const export_gamma: f32 = 0.55; // open quiet passages, meter-style
/// The ghosted full-height bar behind every mixer meter: silence shows
/// the bar's SHAPE, not empty lane. A scale on the bar's own gradient,
/// so the ghost is the meter it will become.
pub const mix_ghost: f32 = 0.13;
/// THE GR METERS (I.3e, the DYN tower): gain reduction HANGS from the
/// top — the classic console needle, upside down on purpose. The comp
/// lane runs orange into the ADSR amber family; the limiter lane runs
/// toward the clip red, because the ceiling is the last word before
/// the honest red itself.
pub const MIX_GR_LO = v3(0.30, 0.14, 0.02); // comp lane, first dB
pub const MIX_GR_HI = v3(1.00, 0.52, 0.10); // ... deep reduction
pub const MIX_GRL_LO = v3(0.28, 0.06, 0.04); // limiter lane, first dB
pub const MIX_GRL_HI = v3(1.00, 0.24, 0.14); // ... leaning on the wall
/// Full-scale of the hanging GR bars, in dB of reduction.
pub const mix_gr_range_db: f32 = 18.0;
/// The hanging bar's bottom-tip bloom (mix_glow_top's twin).
pub const mix_glow_gr: f32 = 0.30;

/// THE SEND FX (M32) — ONE COLOUR PER UNIT, and it is the same colour
/// wherever that unit appears: the thin feed bar beside a strip's
/// meter, the tower's own name, its IN/RETURN meters. Four hues that
/// stay apart at a glance and stay out of the two IDENTITY colours
/// (ice = IT, amber = SID): the echo is cyan, the room green, the
/// chorus violet, the drive the ember-red of something overdriven.
pub const FX_LO = [4]V3{
    v3(0.02, 0.18, 0.22), // DELAY
    v3(0.04, 0.20, 0.10), // REVERB
    v3(0.14, 0.06, 0.26), // CHORUS
    v3(0.26, 0.07, 0.03), // DRIVE
};
pub const FX_HI = [4]V3{
    v3(0.30, 0.95, 1.00),
    v3(0.35, 1.00, 0.55),
    v3(0.72, 0.45, 1.00),
    v3(1.00, 0.45, 0.18),
};
/// The same four as TEXT ink, for the send row values and the tower
/// headings (a colour is never the only channel — the words say it too).
pub const FX_INK = [4]Rgb{
    .{ .r = 90, .g = 220, .b = 235 },
    .{ .r = 105, .g = 225, .b = 140 },
    .{ .r = 180, .g = 130, .b = 240 },
    .{ .r = 240, .g = 130, .b = 80 },
};
/// THE FOUR BLOCKS' WASH (XI.2). Each unit's value band sits on a few
/// percent of its own colour, which is what tells four blocks apart
/// where a separator RULE would have been furniture on a page that
/// already speaks in colour (m64's call, s67 — he asked for the line
/// first and then replaced it with this). Low enough that the text
/// contrast is untouched; high enough that the eye finds the edges.
/// **THE KNOB TO TASTE**, and the one m64 dials: 0.11 read too strong
/// beside the seam above it, so the wash sits here and the rule in the
/// meter zone carries the separation where there is no text to tint.
pub const fx_wash: f32 = 0.07;

pub fn fxBg(u: usize) Rgb {
    return mix(bg, FX_INK[@min(u, FX_INK.len - 1)], fx_wash);
}

/// A send's feed bar is THIN beside the strip's own meter — the same
/// idiom as a chip's three ADSR minis, one lane per unit.
pub const fx_feed_w: i32 = 1;

/// Pixel-space lerp — the V3 twin of `mix` (which works in u8 text
/// colours). t clamps to [0,1].
pub fn mixV3(a: V3, b: V3, t: f32) V3 {
    const s = std.math.clamp(t, 0.0, 1.0);
    return .{
        .r = a.r + (b.r - a.r) * s,
        .g = a.g + (b.g - a.g) * s,
        .b = a.b + (b.b - a.b) * s,
    };
}

/// The strip's colour for a density in 0..1. `q == 0` is the empty lane.
pub fn stripRamp(q: f32, sid: bool) V3 {
    if (q <= 0) return STRIP_SLOT;
    const t = std.math.pow(f32, std.math.clamp(q, 0.0, 1.0), strip_gamma);
    const lo = if (sid) STRIP_SID_LO else STRIP_PCM_LO;
    const hi = if (sid) STRIP_SID_HI else STRIP_PCM_HI;
    return .{
        .r = lo.r + (hi.r - lo.r) * t,
        .g = lo.g + (hi.g - lo.g) * t,
        .b = lo.b + (hi.b - lo.b) * t,
    };
}

// ----------------------------- pattern-grid pulses ('g' cycles, V3)
pub var PULSE_BEAT: V3 = DUET.PULSE_BEAT; // beat thump: pink wash
pub var PULSE_NOTE: V3 = DUET.PULSE_NOTE; // PCM note flash: ice
pub var PULSE_NOTE_SID: V3 = DUET.PULSE_NOTE_SID; // SID/SW note flash: amber

// ------------------------ pattern-grid pulse PAPER mode (text cells, Rgb)
// The pixel pulses live UNDER the glyph grid, so they only shine through
// the gaps between cells. PAPER mode inks them into the text background
// itself (ZX slang: ink = glyph, paper = the cell behind it). These are
// the envelope-peak targets the playhead bars lerp toward — dark enough
// that the ink stays readable at full slam.

// ---------------------------------------- HALO rasterbar (text layer)
// HALO mode makes the pulse band read as ONE continuous background
// across pixel gaps and glyph cells: the text boxes reconstruct the
// pixel pulses' light from the SAME V3 colors and live envelopes, in
// movy's own color space (V3.toRgb is clamp*255 — no gamma anywhere).
// The weights fold in the glow buffer's steady-state gain (decay 0.72
// re-seeded every frame ≈ x2 at the line after blur). Retune here.
pub const halo_thump_up: f32 = 0.45; // line above the playhead
pub const halo_thump_down: f32 = 0.60; // line below (the pixel halo is bottom-heavy)
pub const halo_flash_center: f32 = 1.40; // a column's own transport row
pub const halo_flash_side: f32 = 0.55; // the lines flanking it

/// base + light, clamped and quantized exactly like Frame.composite —
/// the text layer's version of what the pixel path does with glow.
pub fn addLight(base: Rgb, light: V3) Rgb {
    return V3.fromRgb(base).add(light).toRgb();
}

/// Text-cell lerp (u8 space) — the pixel layer has V3.lerp; this is the
/// same move for ink/paper colors. t clamps to [0,1].
pub fn mix(a: Rgb, b: Rgb, t: f32) Rgb {
    const tc = std.math.clamp(t, 0.0, 1.0);
    return .{
        .r = mixByte(a.r, b.r, tc),
        .g = mixByte(a.g, b.g, tc),
        .b = mixByte(a.b, b.b, tc),
    };
}

fn mixByte(a: u8, b: u8, t: f32) u8 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    return @intFromFloat(af + (bf - af) * t + 0.5);
}

// ---------------------------------------------------------------- tests

const tst = std.testing;

// THE DEFAULT IS DUET, BYTE FOR BYTE: a session that never picks a scheme
// paints exactly what DUET painted before schemes existed — and the
// shots, the page dumps and lib-ab's baseline depend on that.
test "s166: the vars start as DUET, and apply(0) puts them back" {
    defer apply(0);
    try tst.expectEqual(DUET.text, text);
    apply(1);
    try tst.expect(!std.meta.eql(DUET.text, text));
    // the aliases follow the palette they name
    try tst.expectEqual(text_bright, sw_phrase);
    try tst.expectEqual(dots, section_rule);
    try tst.expectEqual(LOGO_ICE, STRIP_PCM_HI);
    apply(0);
    inline for (std.meta.fields(Palette)) |f|
        try tst.expectEqual(@field(DUET, f.name), @field(@This(), f.name));
    try tst.expectEqual(@as(usize, 0), active);
    apply(99); // out of range is DUET, never a crash
    try tst.expectEqual(@as(usize, 0), active);
}

test "s166: every scheme is found by its own name, case and hyphen free" {
    for (SCHEMES, 0..) |sc, i| {
        try tst.expectEqual(@as(?usize, i), schemeByName(sc.name));
        var low: [32]u8 = undefined;
        try tst.expectEqual(@as(?usize, i), schemeByName(std.ascii.lowerString(&low, sc.name)));
        for (SCHEMES[i + 1 ..]) |other| try tst.expect(!std.mem.eql(u8, sc.name, other.name));
    }
    try tst.expectEqual(@as(?usize, 1), schemeByName("sidwizard"));
    try tst.expectEqual(@as(?usize, null), schemeByName("nope"));
    try tst.expectEqual(@as(?usize, null), schemeByName(""));
}

fn luma(x: Rgb) f32 {
    return 0.2126 * @as(f32, @floatFromInt(x.r)) + 0.7152 * @as(f32, @floatFromInt(x.g)) +
        0.0722 * @as(f32, @floatFromInt(x.b));
}

// A SCHEME MAY MOVE THE ROOM, NEVER HIDE THE WORK: whatever a new scheme
// does, the cursor still reads, the text still stands off its ground and
// a value that is off still recedes behind one that is on.
test "s166: every scheme keeps the cursor, the text and the notes readable" {
    for (SCHEMES) |sc| {
        const p = sc.pal;
        // the page's ground stays BLACK: the terminal's own clear and the
        // GUI's letterbox (term.zig, sdl.zig) paint black around it
        try tst.expectEqual(Rgb{ .r = 0, .g = 0, .b = 0 }, p.bg);
        try tst.expect(@abs(luma(p.cursor_bg) - luma(p.cursor_fg)) > 110);
        try tst.expect(luma(p.text) - luma(p.bg) > 100);
        try tst.expect(luma(p.note_col) - luma(p.bg) > 100);
        try tst.expect(luma(p.text_bright) > luma(p.text));
        try tst.expect(luma(p.text) > luma(p.value_off));
        try tst.expect(luma(p.text) - luma(p.header_bg) > 90);
        try tst.expect(sc.blurb.len > 0 and sc.blurb.len <= 60);
    }
}

test "XXVIII D1: the crossfade walks between two schemes and lands on the new one" {
    defer apply(0);
    defer motion.settled = true;
    motion.settled = false;
    apply(0);
    fadeTo(1, 1000);
    // the first frame is still (almost) the old scheme, the middle is
    // between the two, and the end frame is exactly the new one
    try tst.expectEqual(DUET.text, text);
    tick(1000 + motion.frames(scheme_fade_ms) / 2);
    try tst.expect(!std.meta.eql(DUET.text, text));
    try tst.expect(!std.meta.eql(SCHEMES[1].pal.text, text));
    tick(1000 + motion.frames(scheme_fade_ms));
    inline for (std.meta.fields(Palette)) |f|
        try tst.expectEqual(@field(SCHEMES[1].pal, f.name), @field(@This(), f.name));
    try tst.expectEqual(dots, section_rule); // the aliases re-derive every frame
    // a dump is SETTLED: the fade lands in the frame it starts
    motion.settled = true;
    fadeTo(2, 5000);
    try tst.expectEqual(SCHEMES[2].pal.text, text);
}
