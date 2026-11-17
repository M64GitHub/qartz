# qartz — notes for Claude

Zig 0.15.2 + movy (v0.3.1, pinned in build.zig.zon) TUI and CLI for EMS 64M USB Game Boy carts.
A port of ems-qart (`~/chiptune/build/ems-qart`, Qt 6 build in `/Applications/ems-qart.app`).

## Layout

- `src/cart/` — no UI. `protocol.zig` (wire format), `rom.zig` (GB header, checksums), `usb.zig`
  (libusb, timeouts), `fake.zig` (cart in a directory), `worker.zig` (the ONE thread that owns the
  device: hotplug polling + read/write/backup jobs; everyone else reads `snapshot()`).
- `src/cli.zig` — `info|read|write|backup` over the worker.
- `src/app/` — the TUI. `app.zig` (60 fps loop, keys, actions, headless), `ui/stage.zig` (pixel layer:
  layout, carts, bus, packets, logotype), `ui/view.zig` (text layer + overlays), `ui/state.zig`.
- LIFTED FROM DUET (`~/m64/space_64/duetracker/src/app/`): `term.zig`, `event.zig`, `config.zig`,
  `ui/canvas.zig`, `ui/widgets.zig`, `ui/theme.zig` (+ the DMG scheme, ours), `ui/motion.zig`,
  `ui/filedialog.zig` (audition + file-mode narrowing removed). Prefer fixing upstream-style; keep
  them recognisable so DUET fixes can be carried over.

## Rules

- **Never write to the real cart in a test** unless the user asks — it holds their LSDj banks and songs.
  Reads are safe. Exercise writes on `--fake <dir>`.
- Tests and screenshots set `QARTZ_CONFIG=<scratch file>` so they never touch `~/.config/qartz/`.
- `TextCanvas.putStr` and `widgets.frame` titles are ASCII-only; anything with `·`/`▸`/`—` goes through
  `view.text()`.
- Text cells over the pixel layer are opaque: label plates are filled as text cells in the art's plate
  colour (`stage.plateRgb`) so text and art agree.

## Verify

- `zig build test` — protocol, header, fuzzy filter, motion.
- `qartz --fake DIR --dump-screen --size WxH --frames N --keys "f:key,..."` — text layer, scriptable.
- `qartz --fake DIR --shot out.png --frames N [--motion]` — pixel layer only.
- Real look (text + pixels): run it in a new kitty window and `screencapture -l <window id>` (the
  terminal has Screen Recording permission). AeroSpace tiles the window, so sizes vary.
- Hardware: `qartz info`, `qartz read rom 1 x.gb` (the global checksum line must say OK).
