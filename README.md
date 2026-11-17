# qartz

Flash **EMS 64M USB** Game Boy carts from the terminal. A Zig + [movy](https://github.com/M64GitHub/movy)
port of [ems-qart](https://github.com/rbino/ems-qart): a 60 fps neon pixel-art TUI, plus a scriptable CLI.

- Two ROM banks and the shared SRAM as three slots: read any of them to a file, write a file into any of them
- Every write is **verified** by reading it back; every ROM read is checked against the ROM's own global checksum
- **Backup** dumps both banks and the SRAM into one folder (files named after the ROM titles)
- The cart is picked up **automatically** when plugged in (hubs are fine) — no "refresh" button
- Transfers can be cancelled; a write's cancel asks twice, since it leaves the bank half-flashed
- USB transfers have timeouts — a pulled cable fails the job instead of hanging the app
- Fuzzy file picker with favorites (from DUET), 11 colour themes (`t`), DMG green by default

## Build

```sh
brew install libusb pkgconf      # Zig 0.15.2 also needed
zig build                        # ReleaseFast by default -> zig-out/bin/qartz
zig build test                   # unit tests
```

movy is fetched by `zig build` (pinned in `build.zig.zon`). No driver is needed on macOS. On Linux, install
`50_ems_gb_flash.rules` from ems-qart into `/etc/udev/rules.d/` for non-root access.

## Use

```sh
qartz                              # the terminal app (kitty-class terminal, at least 80x24)
qartz info                         # cart status and what both banks hold
qartz read rom <1|2> <file.gb>     # dump a ROM bank
qartz read sram <file.sav>         # dump the save RAM
qartz write rom <1|2> <file.gb>    # flash a ROM into a bank (then verify; --no-verify skips)
qartz write sram <file.sav>        # write the save RAM (then verify)
qartz backup <dir>                 # both banks + SRAM into <dir>
```

| key | in the app |
|---|---|
| `←` `→` `1` `2` `3` | pick a slot: BANK 1, BANK 2, SRAM |
| `r` / `w` | read the slot into a file / write a file into it |
| `b` | back up everything into a folder |
| `t` / `T` | next / previous colour theme (remembered) |
| `esc` | cancel a running transfer |
| `?` / `q` | help / quit |

## No hardware? The fake cart

`--fake <dir>` swaps the USB cart for one kept in a directory (`rom.bin` = both banks, `sram.bin`). It
answers at the real cart's measured pace (`--fake-speed 0` = instant), and touching `<dir>/unplugged`
pulls its cable. Everything — app and CLI — works against it.

## Headless (tests, screenshots)

```sh
qartz --fake /tmp/cart --dump-screen --size 90x26 --frames 120 --keys "20:w,40:text=lsdj,60:enter"
qartz --fake /tmp/cart --shot out.png --frames 60 --motion
```

`--dump-screen` prints the text layer, `--shot` saves the pixel layer; `--keys` scripts `frame:key` presses.
`QARTZ_CONFIG=<file>` keeps a test run away from `~/.config/qartz/config.zon`.

## Measured

On an EMS 64M through a USB hub (macOS 26, Apple Silicon): a 1 MB ROM reads in ~24 s (~43 KB/s), the
128 KB SRAM in ~5 s. The firmware answers 4 KB reads and 32-byte writes, as in ems-flasher.

## Credits

The protocol comes from ems-qart (Riccardo Binetti) and ems-flasher (Mike Ryan). The file dialog, form kit,
text canvas, theme and terminal presenter are lifted from DUET; the pixel/glow core is movy's `Frame`.
