
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
6. Run `make install WOW_DIR=<flavor dir>` to copy the addon files into the game instead.

## Usage

- `/paparazzi` opens the settings panel (**Options → AddOns → Paparazzi**). In Retail, the addon compartment opens it too.
- `/paparazzi test` makes one test capture.
- The panel has a master switch, a merge window (2–10 s), the number of records kept (100–5000), and a checkbox and a delay (0–5 s) for each trigger.

## Triggers

Each trigger has an on/off switch and a delay in the settings panel. The delay is in seconds.

| Trigger | Category | Default | Delay | Game versions |
| --- | --- | --- | --- | --- |
| Level up | Progress | On | 1.0 | All |
| Achievement | Progress | On | 1.0 | retail, mists, titan, forever |
| Guild achievement | Progress | Off | 1.0 | retail, mists |
| Achievement criteria | Progress | Off | 1.0 | retail, mists, titan, forever |
| Reputation rank | Progress | On | 1.0 | All |
| Renown level | Progress | Off | 1.0 | retail |
| New recipe | Progress | Off | 1.0 | All |
| Traveler's Log activity | Progress | Off | 1.0 | retail, forever |
| Profession milestone | Progress | On | 1.0 | era, tbc, titan, forever |
| Boss kill | Combat | On | 1.0 | All |
| Boss wipe | Combat | Off | 1.0 | All |
| World boss kill | Combat | On | 1.0 | retail, mists, titan |
| Mythic+ completed | Combat | On | 1.0 | retail, mists |
| Mythic+ new record | Combat | Off | 1.0 | retail, mists |
| Delve completed | Combat | Off | 1.0 | retail |
| Death | Combat | Off | 0.5 | All |
| Close call | Combat | Off | 1.0 | All |
| New mount | Collections | On | 1.0 | retail, mists, titan |
| New pet | Collections | On | 1.0 | retail, mists, titan |
| New toy | Collections | On | 1.0 | retail, mists, titan |
| New housing item | Collections | Off | 1.0 | retail |
| House level | Collections | Off | 1.0 | retail |
| PvP match won | PvP | Off | 1.0 | All |
| Duel finished | PvP | Off | 1.0 | All |
| Epic loot | Loot | Off | 1.0 | retail |
| Legendary loot | Loot | On | 1.0 | retail |
| Trade | World | Off | 0.0 | All |
| Login | World | Off | 5.0 | All |
| First visit to a zone | World | Off | 2.0 | All |

Game versions, by Interface number:

- **retail:** 11.0 and later.
- **mists:** 5.x.
- **titan:** 3.x.
- **tbc:** 2.x.
- **forever:** 1.60.x.
- **era:** 1.15.x.
- **All:** all six.

The **Profession milestone** trigger fires when a profession skill reaches a multiple of 75 (75, 150, 225, and so on). It covers primary and secondary professions. It reads the skill list of the game, so it does not exist in Retail or MoP Classic.

## Works with Memories

- Paparazzi sends a note to the Memories addon after each automatic screenshot. The note lists the trigger labels, for example `Level up, Boss kill`.
- Paparazzi sends the same file name that the capture record stores.
- Memories is optional. The setting is on by default. Without Memories, Paparazzi does nothing extra.
- The checkbox **Send notes to Memories** in the **Memories** settings tab switches the notes on or off. It is locked when Memories is not installed.

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

## CurseForge description

- `.curse/description.txt` is the source of the CurseForge project description.
- CurseForge has no API to change a project description. The upload API changes files only.
- After you change the file, paste its content into the project description on the CurseForge site.

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
