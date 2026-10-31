# Paparazzi

Paparazzi takes a screenshot when a configured game event occurs in World of Warcraft. It records why each screenshot exists.

## Install

Copy this folder to `World of Warcraft/_<flavor>_/Interface/AddOns/Paparazzi`.

## Development

1. Install `lua5.1`, `luarocks`, `go`, and StyLua 2.6.0.
2. Run `make deps`.
3. Run `make check-tools`.
4. Run `make lint test coverage`.
5. Run `make link WOW_DIR=<flavor dir>` to link the addon into the game.

## Usage

- `/paparazzi` opens the settings panel (**Options → AddOns → Paparazzi**). In Retail, the addon compartment opens it too.
- `/paparazzi test` makes one test capture.
- The panel has a master switch, a merge window (2–10 s), the number of records kept (100–5000), and a checkbox and a delay (0–5 s) for each trigger.

## Exporter

The game writes SavedVariables on logout or `/reload` only. The addon cannot write files itself. `paparazzi-export` reads the SavedVariables and writes a `<screenshot>.json` file next to each matched image.

```
paparazzi-export --wow-dir "<...>/World of Warcraft/_retail_"
```

- It matches a record to an image by the exact predicted file name. If that fails, it takes the nearest unclaimed `WoWScrnShot_*` file within ±2 s (`--tolerance`).
- It skips a tie, and it skips an existing `.json` file unless you give `--force`.
- `--dry-run` writes nothing. `--account` limits the run to one account. `--screenshots` sets another screenshots folder.
- It never changes an image. It runs no Lua code.
- Exit codes: 0 on success, 1 on a read, parse, or write error, 2 on a usage error.
- Build it with `make build`. The binary goes to `build/paparazzi-export`.
