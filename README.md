
# Paparazzi

<p align="center">
  <img src="assets/paparazzi-icon.png" alt="Paparazzi icon" width="128">
</p>

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

## Limits

- **Client crash:** the game writes SavedVariables on logout, `/reload`, or disconnect only. A crash loses the captures that are not saved yet, so those screenshots get no JSON.
- **Manual PrintScreen:** a manual screenshot in the 3 s window after an automatic one can take the metadata of the automatic capture. The JSON then describes the wrong image.
- **`/reload` or logout with a pending capture:** the addon drops the pending capture. That event gets no screenshot.

## Releasing

Setup, one time:

1. Create the GitHub repository `fmartingr/wow-addon-paparazzi` and push `main`.
2. Create a CurseForge project. Add the `CF_API_TOKEN` secret from https://authors.curseforge.com/#/settings/api-tokens.
3. Add `## X-Curse-Project-ID: <id>` to `Paparazzi.toc`.

Without the token or the project ID, the packager skips CurseForge. The GitHub Release is still made.

Release:

- Run `make release-patch`, `make release-minor`, or `make release-major` from a clean `main` that equals `origin/main`. Add `DRY_RUN=1` to print the next tag only.
- The tag push starts the release workflow. It builds the addon zip, uploads it, and adds the exporter archives for Windows, macOS, and Linux.
- Tag from a local machine only. A tag that a workflow pushes with `GITHUB_TOKEN` does not start the release workflow.
- Beta: tag `vX.Y.Z-beta1` by hand. The packager marks it as a beta. A `-rc` tag counts as a full release.

Interface numbers:

1. Check the current numbers on https://warcraft.wiki.gg/wiki/TOC_format after each game patch.
2. Update `## Interface:` in `Paparazzi.toc`. Without it, the game shows the addon as out of date.
