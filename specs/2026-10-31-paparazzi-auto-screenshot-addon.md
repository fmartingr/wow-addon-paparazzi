# Paparazzi: automatic event screenshots for World of Warcraft

## Why

Players want a screenshot of important game moments without having to press PrintScreen at the correct time. Examples are a level up, a boss kill, or a new mount. They also want to know later *why* each screenshot exists. Existing addons (MultiShot, Memento, Ding Auto Screenshots) take the screenshots, but they record no machine-readable metadata.

Paparazzi takes a screenshot when a configured game event occurs. It records the event metadata. A companion CLI writes that metadata as a JSON file next to each image. Downstream tools (for example `games-screenshot-manager` and `gaming-memories`) can then read the reason for each screenshot.

## What

Deliverables:

1. A WoW addon named **Paparazzi** (Lua 5.1). It loads in Retail 12.x, MoP Classic, Classic Era, Forever, TBC Anniversary, and Titan Reforged.
2. A Go CLI named **`paparazzi-export`**. It reads the addon's SavedVariables and writes `<screenshot>.json` sidecar files.
3. GitHub Actions CI for pull requests, and a release pipeline that runs when you push a `v*` tag.
4. A `Makefile` with developer targets and `release-patch`, `release-minor`, and `release-major`.

Acceptance criteria:

- **AC1:** When an enabled trigger fires, the addon calls `Screenshot()` after the trigger's configured delay (0–5 s, 0.5 s steps).
- **AC2:** Triggers that fire while a capture is pending merge into that capture. The capture produces **one** screenshot, and its record lists **every** merged event. The timing follows the debounce rule in Decisions (D5).
- **AC3:** The addon spaces two `Screenshot()` calls by at least 1.0 s.
- **AC4:** After `SCREENSHOT_SUCCEEDED`, the addon appends one capture record to `PaparazziDB.captures`. The record has the predicted file name, local ISO time, Unix time, UTC offset, game info, character info, location, and events. Each event has a trigger key, an event name, a Unix time, and data. The record matches the schema in Task 3.
- **AC5:** The capture log is a ring buffer. When it has more records than the retention setting (default 1000, range 100–5000), the addon removes the oldest records first.
- **AC6:** Each of the 27 triggers in the catalog (Task 3, Task 4, Task 5) can be switched on or off, and each has its own delay. The defaults match the catalog. A trigger is available only in the flavors that the catalog lists, and only if `C_EventUtils.IsEventValid()` accepts all of its events.
- **AC7:** The native Settings panel shows a master switch, the debounce cap (2–10 s, default 5 s), the retention, and a checkbox and a delay slider for each available trigger. `/paparazzi` opens the panel. In Retail, the addon compartment also opens it. `/paparazzi test` makes one test capture.
- **AC8:** The addon stores no secret value. A payload value for which `issecretvalue(v)` is true becomes `nil`.
- **AC9:** `paparazzi-export --wow-dir <flavor dir>` writes `<image basename>.json` next to each matched screenshot. It matches by the exact predicted file name first. If that fails, it uses the nearest unclaimed `WoWScrnShot_*` file within ±2 s. It skips a tie, and it skips an existing `.json` file unless you give `--force`. It never changes an image. It runs no Lua code.
- **AC10:** On each pull request and each push to `main`, CI runs luacheck, StyLua `--check`, busted with coverage on Lua 5.1, gofmt, `go vet`, `go test -race`, and a packager dry run. If one check fails, CI fails.
- **AC11:** When you push a tag `vX.Y.Z`, the release workflow builds the addon zip. It uploads the zip to CurseForge (when the project ID and token exist) and creates a GitHub Release with the zip. Then it adds the exporter binaries for Windows, macOS, and Linux to that release.
- **AC12:** `make release-patch|minor|major` refuses to run on a dirty tree, outside `main`, or when `HEAD` differs from `origin/main`. Otherwise it creates the next annotated semver tag and pushes it.
- **AC13:** `make help` lists the targets. `make lint`, `make fmt`, `make test`, and `make coverage` run the same checks as CI.

## Constraints

- **Must:**
  - Use only APIs that are not protected and that exist in the flavor where the code calls them. Guard each flavor-specific API with an existence check.
  - Keep the addon free of external libraries (no Ace3, no LibStub).
  - Use one account-wide SavedVariables table, `PaparazziDB`.
  - Pin each GitHub Action by full commit SHA, with a `# vX.Y.Z` comment.
  - Use `pull_request` (never `pull_request_target`) for the CI workflow.
  - License the project as GPLv3 (`GPL-3.0-or-later`).
- **Must Not:**
  - Use `COMBAT_LOG_EVENT_UNFILTERED`. Midnight blocks it for addons.
  - Read `CHAT_MSG_SYSTEM` or `CHAT_MSG_SKILL` text. Midnight makes this text secret during chat lockdown.
  - Hide or change the UI (`UIParent:Hide()`, `SetAlpha`) or change CVars.
  - Execute SavedVariables content in the exporter.
  - Overwrite or change an image file.
- **Out of Scope:**
  - Interval or timer screenshots, a custom screenshot keybind, a `/played` overlay, hide UI, close windows, watermark.
  - Extra filters for each trigger. Examples are "first kill only", "rated PvP only", and "minimum loot quality setting".
  - Settings for each character, and profiles.
  - Rare-mob kill shots (the combat log is blocked, and a rare-NPC ID list is necessary).
  - Wago and WoWInterface uploads.
  - Localization other than English.
  - Changes to `games-screenshot-manager` or `gaming-memories`.

## Decisions

- **D1. Metadata goes through SavedVariables plus an exporter CLI.** An addon cannot write files. WoW Lua has no `io` or `os` library. The game writes SavedVariables only on logout, `/reload`, or disconnect. The user chose a Go exporter in this repository.
- **D2. Flavors:** Retail 12.x (`120105`), MoP Classic (`50504`), Titan Reforged (`38002`), TBC Anniversary (`20506`), Forever (`16001`), and Classic Era (`11509`). They go in one TOC with a comma-separated `## Interface:` list. This list is supported since 10.2.7, and the packager supports it.
- **D3. Flavor detection** uses the 4th return value of `GetBuildInfo()` (the TOC version). `WOW_PROJECT_ID` does not separate Forever and Titan reliably. The ranges are:
  - `>= 110000` → `retail`
  - `50000–59999` → `mists`
  - `30000–39999` → `titan`
  - `20000–29999` → `tbc`
  - `16000–16999` → `forever`
  - `11000–11999` → `era`
  - any other value → `unknown`. In this case, every trigger with a valid event is available.
- **D4. Trigger availability:** a trigger is available when the current flavor is in its `flavors` list, **and** `C_EventUtils.IsEventValid(e)` is true for each of its events, **and** its optional `requires()` returns true. `C_EventUtils.IsEventValid` exists in all five Blizzard UI source branches that research checked.
- **D5. Debounce ("extend, capped"):**
  - Let `t0` be the time of the first event of a pending capture, and `due0 = t0 + delay0`.
  - A later event at time `t` with delay `d` requests `t + d`.
  - The capture fires at `due = max(due0, min(max(currentDue, t + d), t0 + cap))`.
  - So the first event always keeps its own full delay. Later events can extend the shot time only up to `t0 + cap`.
  - The cap is a setting: 2–10 s, step 1 s, default 5 s.
- **D6. Shot spacing:** the addon spaces two `Screenshot()` calls by at least 1.0 s, because WoW file names have a resolution of 1 s.
- **D7. Pending-shot tracking:** after `Screenshot()`, the addon waits for `SCREENSHOT_SUCCEEDED` or `SCREENSHOT_FAILED`. Neither event has a payload, so the addon keeps its own "awaiting" flag. After 3 s without one of these events, the addon drops the capture. A manual PrintScreen during this window can still take the metadata (accepted risk R2).
- **D8. File name prediction:** `"WoWScrnShot_" .. date("%m%d%y_%H%M%S", t) .. ext`. Here `t = time()` at `SCREENSHOT_SUCCEEDED`. `ext` comes from `GetCVar("screenshotFormat")`: `jpeg`/`jpg` → `.jpg`, `png` → `.png`, `tga` → `.tga`, any other value → `.jpg`. No API returns the real name.
- **D9. Exporter matching:** for each capture, the exporter first looks for the exact predicted file name. If that fails, it takes the nearest unclaimed `WoWScrnShot_*` file whose time is within ±2 s. It interprets the file name time in the capture's `utcOffset`. Each file matches one capture only. When two candidates have the same distance, the exporter skips the capture with a warning.
- **D10. Exporter parser:** a hand-written parser for the subset of Lua that SavedVariables use. The subset has table constructors, strings, numbers, booleans, `nil`, and `--` comments. The parser runs no code and has no third-party dependencies. It has limits for file size and nesting depth. This is more secure than an embedded Lua VM (for example `gopher-lua` v1.1.2).
- **D11. Scope of state:** settings and captures are account-wide. Each capture records the character name, realm, class, and level. The first-visit record (trigger `firstVisit`) is kept for each character in `PaparazziDB.visited["Name-Realm"]`.
- **D12. Retention:** a ring buffer, default 1000, range 100–5000, step 100.
- **D13. Fixed trigger rules:** each trigger has only `enabled` and `delay`. The filter rules are fixed in code, as in the catalog.
- **D14. Metadata content:** the named payload fields, plus cheap name lookups (for example the achievement name and the mount name). Each event records `trigger`, `name` (the WoW event), `unix`, and `data`.
- **D15. UI:** the native `Settings` API (vertical layout category), the `/paparazzi` slash command, and in Retail an `## AddonCompartmentFunc`. There is no minimap button. `/paparazzi test` exists as a manual verification aid for the checklist and for the exporter.
- **D16. CI tooling:** luacheck 1.2.0, StyLua 2.6.0, busted 2.3.0, luacov 0.17.0 on Lua 5.1 (`leafo/gh-actions-lua` v13.1.0 with `luaVersion: "5.1"`, `leafo/gh-actions-luarocks` v6.1.1), Go from `go.mod`, BigWigsMods/packager v2.6.1 with `-d` (dry run). There is no LuaLS check. Its WoW annotations are Retail-first and give false errors on Classic-only APIs.
- **D17. Release:**
  - The packager uses `CF_API_TOKEN` and `GH_API_TOKEN` (the current names; `CF_API_KEY` and `GITHUB_OAUTH` are deprecated). It uploads to CurseForge and creates the GitHub Release.
  - Then goreleaser adds the exporter archives to that release with `release.mode: keep-existing`.
  - The changelog is the packager's automatic changelog from the commit messages.
- **D18. Branch:** `main`. Task 1 renames the local `master` branch.
- **D19. E2E:** there is no e2e suite. CI runs unit tests only. A manual in-game checklist (`docs/manual-checklist.md`) covers the full flow for each flavor before each release.
- **D20. Commit convention:** Conventional Commits (`feat:`, `fix:`, `ci:`, `build:`, `docs:`, `test:`, `chore:`). The sibling repositories of this author use this convention.

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| R1. A client crash before logout or `/reload` loses the captures that are not saved. | The JSON is missing for those screenshots. | No fix exists. The README documents it. | 8 |
| R2. A manual PrintScreen during the 3 s "awaiting" window gets the metadata of the automatic capture. | The JSON describes the wrong image. | The awaiting flag is set only around the addon's own `Screenshot()` call. The window closes at the first SUCCEEDED/FAILED event or after 3 s. The README documents the limit. | 3 |
| R3. A `/reload` or logout while a capture is pending drops the capture. | One event has no screenshot. | Accepted. The README documents it. | 3, 8 |
| R4. The predicted file name differs from the real name by 1 s. | The exact match fails. | The exporter uses a ±2 s nearest match (D9). | 7 |
| R5. The docs list some events for a Classic flavor, but the game does not fire them. Examples: `CRITERIA_EARNED` on Forever, `FACTION_STANDING_CHANGED` on Era and TBC. | A trigger is in the UI but never fires. | Gate by the catalog flavors and by `IsEventValid`. The manual checklist checks each trigger in each flavor. | 4, 5 |
| R6. No research covered the Titan Reforged API (China only). | Triggers can fail on Titan. | Titan uses the MoP rules without verification. Each flavor-specific API call has an existence guard. | 4, 5 |
| R7. A Midnight secret value goes into SavedVariables. | The serialization behavior is not known. A Lua error is possible. | `ns.Safe(v)` changes each secret value to `nil` before storage (AC8). | 3 |
| R8. Interface numbers go stale after a game patch. | The game shows the addon as "out of date". | Accepted. You update the TOC by hand. The README lists the step. | 8 |
| R9. The CurseForge project does not exist yet. | No CurseForge upload. | The packager skips CurseForge when `X-Curse-Project-ID` or `CF_API_TOKEN` is missing. See Open Decisions. | 8 |
| R10. Supply-chain risk from GitHub Actions. | A changed action runs with a write token. | Pin each action by SHA. Dependabot updates them. The release job is the only job with `contents: write`. | 2, 8 |
| R11. Hostile or corrupt SavedVariables input to the exporter. | Resource exhaustion, or path traversal through the `file` field. | No code execution. Size limit 64 MiB. Depth limit 64. The exporter accepts a `file` value only if it matches `^WoWScrnShot_\d{6}_\d{6}\.(jpg|png|tga)$`. Atomic writes. | 7 |
| R12. The capture log in SavedVariables becomes large. | Login becomes slower. | Ring buffer (D12). | 3 |
| R13. No e2e suite. | A regression in the event-to-file flow can reach a release. | Manual checklist (D19). Each release runs it. | 3, 8 |
| R14. An event-heavy moment (for example a trainer that teaches many recipes) causes many shots. | Screenshot spam. | Debounce merges the events. Noisy triggers are off by default. | 3 |

## Current State

- **Repository:** `/home/fmartingr/Code/wow-addon-paparazzi`. One empty commit, `ace0604 Initial commit`. The only branch is `master`, and there is no remote. No `specs/` directory existed before this spec.
- **Local tools (observed):**
  - Present: `lua5.1`, `luajit`, `make` 4.4.1, `gh` 2.102.1, `jq` 1.8.2, `go` 1.27.1.
  - Missing: `luarocks`, `luacheck`, `busted`, `stylua`, `git-cliff`.
- **Sibling conventions:** `/home/fmartingr/Code/games-screenshot-manager`.
  - Go 1.27.1, `go-version-file: ./go.mod`.
  - goreleaser `version: 2` with `CGO_ENABLED=0` for linux/windows/darwin and amd64/arm64.
  - Workflows `test.yml` and `release.yml` (`on: push: tags: ["v*"]`, `fetch-depth: 0`, `permissions: contents: write`).
  - Conventional Commits.
  - Its WoW provider parses `WoWScrnShot_` + layout `010206_150405` + `.jpg` (`worldofwarcraft.go`). This confirms the `MMDDYY_HHMMSS` name format.
- **WoW API facts** (Gethe/wow-ui-source generated docs: live 12.1.5, classic 5.5.4, classic_era 1.15.9, classic_anniversary 2.5.6, forever 1.60.1):
  - `Screenshot()` has no arguments and no return values. It is not protected, and it works from a `C_Timer` callback.
  - `SCREENSHOT_STARTED`, `SCREENSHOT_SUCCEEDED`, and `SCREENSHOT_FAILED` have no payload. They also fire for manual screenshots.
  - CVar `screenshotFormat` is `jpeg` (default), `png`, or `tga`.
  - `C_Timer.After`, `C_Timer.NewTimer` (with a handle `:Cancel()`), and `C_Timer.NewTicker` exist in all flavors.
  - `time()` and `date()` mirror `os.time` and `os.date` and use the local clock. `GetTime()` is the uptime and not the wall clock.
  - `C_EventUtils.IsEventValid(eventName) -> bool` exists in all branches.
  - The `Settings` API (`RegisterVerticalLayoutCategory`, `RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, default)`, `CreateCheckbox`, `CreateSlider`, `CreateSliderOptions`, `RegisterAddOnCategory`, `OpenToCategory`) exists in all branches through `Blizzard_Settings_Shared`.
  - The addon compartment (`## AddonCompartmentFunc`) exists in Retail and Forever only.
  - Midnight 12.0:
    - Registering `COMBAT_LOG_EVENT*` causes an error.
    - About 50 `CHAT_MSG_*` events are secret in chat lockdown, including `CHAT_MSG_SYSTEM`.
    - `issecretvalue()` and `canaccessvalue()` detect secret values.
    - None of the catalog events has a secret annotation.
- **Tool versions** (verified 2026-10-31):

| Tool | Version | Pin |
|---|---|---|
| actions/checkout | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| BigWigsMods/packager | v2.6.1 | `e50a250f8705041e40f2fa1ddcb280a686d65aa0` |
| lunarmodules/luacheck (action) | v1.2.0 | `cc089e3f65acdd1ef8716cc73a3eca24a6b845e4` |
| JohnnyMorganz/stylua-action | v5.0.0 (StyLua 2.6.0) | `76fd70c03e6340ceaf673366712db9b20560b402` |
| leafo/gh-actions-lua | v13.1.0 (default Lua 5.5, so set `luaVersion: "5.1"`) | `32909a2dea0a48c433aec79e7fcd31b4cd55800f` |
| leafo/gh-actions-luarocks | v6.1.1 | `1c4a92caecc8f6850f673cbadfd57b3e555417ce` |
| busted / luacov rocks | `2.3.0-1` / `0.17.0-1` (fallback `0.16.0-1` if the 5.1 manifest lags) | — |
| actions/setup-go, actions/upload-artifact, goreleaser/goreleaser-action | not verified | Pin the latest release SHA at task time (inspect) |

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is cheap.
- Lua tests use busted and the fake WoW API in `spec/helpers/wow.lua` (Task 1). The fake replaces only the WoW client API. Load the real addon files through the helper.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: `make coverage`.
  - Lua: luacov line coverage of `src/` (except `src/Settings.lua`, which is UI code) must be ≥ 80%.
  - Go: `go test -coverprofile` total for `./internal/...` must be ≥ 80%.
  - `make coverage` fails below these thresholds.
- E2E: no e2e suite. The user accepted a manual in-game checklist only (see Risks R13 and D19). Add or update a row in `docs/manual-checklist.md` for each changed user-visible flow.

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with Conventional Commits (D20). Do not push.

**Local tool setup** (prerequisite for each task that runs Lua checks)
- Install `luarocks` for Lua 5.1 with the system package manager.
- Run `make deps` (Task 1). It installs `busted 2.3.0-1`, `luacov 0.17.0-1`, and `luacheck 1.2.0-1` with `luarocks --lua-version=5.1 --local`.
- Install StyLua 2.6.0 from its GitHub release.
- `make check-tools` reports each missing tool.

## Tasks

### [x] 1. Addon skeleton, Lua tooling, fake WoW API, Makefile dev targets

- **Outcome:** an addon that loads in WoW (it does nothing yet). `make lint`, `make fmt`, `make test`, and `make coverage` run locally and pass. A fake WoW API lets busted load the real addon files.
- **Depends on:** None.
- **Covers:** AC13 (dev targets), D2, D3, D18, D20, the base for R13.
- **Files:**
  - `git branch -m master main`
  - `LICENSE` (GPLv3 full text)
  - `README.md` (short: what it is, install, dev setup)
  - `.gitignore` (`.release/`, `build/`, `luacov.*.out`, `.lua/`, `.luarocks/`, `coverage.out`)
  - `Paparazzi.toc`
  - `src/Init.lua`
  - `spec/helpers/wow.lua`
  - `spec/init_spec.lua`
  - `.busted`, `.luacov`, `.luacheckrc`, `.stylua.toml`, `.pkgmeta`
  - `Makefile`
- **Implementation:**
  - `Paparazzi.toc`:
    ```
    ## Interface: 120105, 50504, 38002, 20506, 16001, 11509
    ## Title: Paparazzi
    ## Notes: Takes screenshots of game events and records why.
    ## Author: Felipe M.
    ## Version: @project-version@
    ## SavedVariables: PaparazziDB
    ## IconTexture: Interface\Icons\INV_Misc_Spyglass_03
    ## X-License: GPL-3.0-or-later
    src\Init.lua
    ```
    - Before you commit, check the current live Interface numbers on https://warcraft.wiki.gg/wiki/TOC_format. Update the numbers if they changed.
    - The icon path is not verified. Inspect it in game, or choose another icon from `Interface\Icons`.
    - Do not add `## X-Curse-Project-ID` yet (Open Decisions).
    - Later tasks add files to the TOC in this order: `src/Init.lua`, `src/DB.lua`, `src/Debouncer.lua`, `src/Capture.lua`, `src/Triggers.lua`, `src/triggers/*.lua`, `src/Settings.lua`, `src/Core.lua`.
  - `src/Init.lua`:
    - It starts with `local addonName, ns = ...`.
    - It defines:
      - `ns.name = addonName`
      - `ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or GetAddOnMetadata(addonName, "Version")`. Guard both forms.
      - `ns.GetFlavor()`: D3 ranges on `select(4, GetBuildInfo())`. It returns one of `retail|mists|titan|tbc|forever|era|unknown`.
      - `ns.GetGameInfo()`: returns `{ flavor, version, build, interface }` from `GetBuildInfo()`.
      - `ns.Safe(v)`: returns `nil` if `issecretvalue and issecretvalue(v)`, else `v`.
      - `ns.Print(msg)`: `DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Paparazzi|r: " .. msg)`.
  - `spec/helpers/wow.lua`: a module that returns `wow`, with:
    - `wow.reset(opts)`: clears `_G` fakes. Then it installs:
      - `CreateFrame`: returns a frame table with `RegisterEvent`, `UnregisterEvent`, `UnregisterAllEvents`, `SetScript`, `GetScript`, `IsEventRegistered`. Each frame is recorded.
      - `C_Timer.After` and `C_Timer.NewTimer`: they queue callbacks on a fake clock. `NewTimer` returns a handle with `:Cancel()` and `:IsCancelled()`.
      - `GetTime()`: returns the fake clock.
      - `time(t)` and `date(fmt, t)`: they delegate to `os.time` and `os.date`, with a fake wall clock that `wow.set_wall(unix)` sets and that `wow.advance(s)` moves.
      - `Screenshot`: a spy that counts calls.
      - `GetCVar(name)`: reads the table `wow.cvars`.
      - `GetBuildInfo()`: returns `opts.build` or the Retail values `"12.1.5", "70688", "Oct 1 2026", 120105`.
      - `C_EventUtils.IsEventValid(e)`: returns true unless `opts.invalidEvents[e]`.
      - `issecretvalue(v)`: true for values that `wow.secret(v)` wrapped.
      - Unit and location stubs: `UnitName`, `GetRealmName`, `UnitClass`, `UnitLevel`, `GetZoneText`, `GetSubZoneText`, `GetInstanceInfo`, `IsInInstance`, `C_Map.GetBestMapForUnit`.
      - `DEFAULT_CHAT_FRAME`: records messages.
      - `C_AddOns.GetAddOnMetadata`.
      - `SlashCmdList`.
    - `wow.advance(seconds)`: moves both clocks and runs the timers that become due, in due order. This includes timers that callbacks schedule during the advance.
    - `wow.fire(event, ...)`: calls the `OnEvent` script of each frame that registered the event.
    - `wow.load_addon(files)`: creates `ns = {}`, runs `assert(loadfile(path))("Paparazzi", ns)` for each path in TOC order, and returns `ns`.
    - `wow.toc_files()`: parses `Paparazzi.toc` and returns its file lines with `\` changed to `/`, so tests load the real TOC order.
  - `.busted`: `return { default = { ROOT = { "spec" }, pattern = "_spec", lpath = "./?.lua;./spec/?.lua", lua = "lua5.1" } }`. Inspect the busted 2.3.0 option names.
  - `.luacov`: `include = { "^src/" }`, `exclude = { "^src/Settings$" }`, `reporter = "default"`.
  - `.luacheckrc`:
    - `std = "lua51"`, `max_line_length = 120`, `codes = true`.
    - `exclude_files = { ".lua/", ".luarocks/", ".release/", "build/" }`.
    - `ignore = { "212/self", "211/_.*", "212/_.*" }`.
    - `globals = { "PaparazziDB", "SLASH_PAPARAZZI1", "SlashCmdList", "Paparazzi_OnAddonCompartmentClick" }`.
    - `read_globals`: each WoW API that `src/` uses. Each later task adds its own APIs.
    - `files["spec/"] = { std = "+busted", globals = { "_G" } }`.
  - `.stylua.toml`: `syntax = "Lua51"`, `column_width = 120`, `indent_type = "Tabs"`, `quote_style = "AutoPreferDouble"`, `line_endings = "Unix"`.
  - `.pkgmeta`:
    ```yaml
    package-as: Paparazzi
    ignore:
      - spec
      - specs
      - docs
      - cmd
      - internal
      - testdata
      - scripts
      - Makefile
      - go.mod
      - go.sum
    ```
  - `Makefile`:
    - It uses `SHELL := bash` and `.SHELLFLAGS := -euo pipefail -c`.
    - `.DEFAULT_GOAL := help`. Each target has a `## description` comment, and `help` greps these comments.
    - Targets:
      - `help`
      - `check-tools`: reports each missing tool (`lua5.1`, `luarocks`, `busted`, `luacheck`, `stylua`, `go`) and exits 1 if one is missing.
      - `deps`: `luarocks --lua-version=5.1 --local install busted 2.3.0-1 && … luacov 0.17.0-1 && … luacheck 1.2.0-1`.
      - `lint`: depends on `lint-lua` and `fmt-check`.
      - `lint-lua`: `luacheck .`
      - `fmt-check`: `stylua --check .`
      - `fmt`: `stylua .`
      - `test`: depends on `test-lua`.
      - `test-lua`: `busted`
      - `coverage`: depends on `coverage-lua`.
      - `coverage-lua`: `busted --coverage && luacov`. Then it reads the `Total` line of `luacov.report.out` with `awk` and fails below `LUA_COVERAGE_MIN ?= 80`.
      - `link`: requires `WOW_DIR`. It runs `ln -sfn "$(CURDIR)" "$(WOW_DIR)/Interface/AddOns/Paparazzi"`. `WOW_DIR` is a flavor folder, for example `…/World of Warcraft/_retail_`.
      - `clean`: `rm -rf build .release luacov.*.out coverage.out`
    - Task 7 adds Go targets. Task 8 adds release targets.
- **Edge cases:**
  - `GetBuildInfo` returns an interface value outside every range → `unknown`.
  - `issecretvalue` is absent (Classic) → `ns.Safe` returns the value unchanged.
  - `make link` without `WOW_DIR` → clear error message, exit 2.
- **Tests:** `spec/init_spec.lua` (unit):
  - `GetFlavor` returns the correct flavor for each of the six D2 interface numbers, and `unknown` for `40402` and `0`.
  - `Safe` changes a wrapped secret value to `nil`, keeps a normal value, and works when `issecretvalue` is nil.
  - `wow.load_addon(wow.toc_files())` loads without error.
- **Verify:** `make check-tools && make lint && make test && make coverage` (unverified: the tools are not installed yet). Also `git branch --show-current` prints `main`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 2. PR CI workflow and Dependabot

- **Outcome:** each pull request and each push to `main` runs the Lua lint, format, test, coverage, and packager dry-run jobs. A failure blocks the run.
- **Depends on:** Task 1 (config files and Makefile targets).
- **Covers:** AC10 (Lua and packaging parts), R10.
- **Files:** `.github/workflows/ci.yml`, `.github/dependabot.yml`.
- **Implementation:**
  - `on: pull_request` and `push: branches: [main]`. `permissions: contents: read` at the top. `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`.
  - Job `lua-lint` (`ubuntu-latest`):
    - checkout (SHA from Current State)
    - `lunarmodules/luacheck@cc089e3f… # v1.2.0` with `args: .`
    - `JohnnyMorganz/stylua-action@76fd70c0… # v5.0.0` with `token: ${{ secrets.GITHUB_TOKEN }}`, `version: 2.6.0`, `args: --check .`
  - Job `lua-test`:
    - checkout
    - `leafo/gh-actions-lua@32909a2d… # v13.1.0` with `luaVersion: "5.1"`
    - `leafo/gh-actions-luarocks@1c4a92ca… # v6.1.1`
    - `luarocks install busted 2.3.0-1` and `luarocks install luacov 0.17.0-1`
    - `make test-lua coverage-lua`. The `busted` config uses `lua = "lua5.1"`. In CI, override it with `busted --lua=lua` if the leafo install names the binary `lua` (inspect).
  - Job `package`:
    - checkout with `fetch-depth: 0`
    - `BigWigsMods/packager@e50a250f… # v2.6.1` with `args: -d` and `pandoc: false`
    - `actions/upload-artifact` (pin at task time) with `path: .release/*.zip` and `retention-days: 7`.
  - `.github/dependabot.yml`: `package-ecosystem: github-actions`, `directory: /`, `schedule: weekly`, and `groups: { github-actions: { patterns: ["*"] } }`. Task 7 adds `gomod`.
- **Edge cases:**
  - A fork PR has no secrets. No job needs secrets.
  - luacheck and StyLua must exclude `.lua/` and `.luarocks/`, because the leafo actions install into the workspace. Task 1 config does this; check it.
- **Tests:** the workflow is the test.
  - Push a branch with a deliberate luacheck warning and confirm that `lua-lint` fails. Revert the warning before the commit.
  - Confirm that the `package` artifact zip contains `Paparazzi/Paparazzi.toc` and `Paparazzi/src/Init.lua`, and no `spec/` or `Makefile`.
- **Verify:**
  - `actionlint .github/workflows/ci.yml` (unverified; install `actionlint` if absent).
  - After the user creates the GitHub repository and pushes, check `gh run list --workflow ci.yml`.
  - Local packager dry run: `bash <(curl -s https://raw.githubusercontent.com/BigWigsMods/packager/v2.6.1/release.sh) -d` (unverified; optional).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 3. Capture engine, trigger registry, and the "Level up" trigger

- **Outcome:** in game, a level up makes one screenshot after 1 s and appends one capture record to `PaparazziDB.captures`. Simultaneous triggers merge into one screenshot. This is the full pipeline that the other triggers use.
- **Depends on:** Task 1 (`ns` helpers, fake WoW API, Makefile).
- **Covers:** AC1, AC2, AC3, AC4, AC5, AC6 (registry and gating), AC8, D4–D8, D11, D12, D14, R2, R3, R7, R12, R13, R14.
- **Files:**
  - `src/DB.lua`
  - `src/Debouncer.lua`
  - `src/Capture.lua`
  - `src/Triggers.lua`
  - `src/triggers/Progress.lua` (only `levelUp` in this task)
  - `src/Core.lua`
  - `Paparazzi.toc` (add the files)
  - `spec/db_spec.lua`, `spec/debouncer_spec.lua`, `spec/capture_spec.lua`, `spec/triggers_spec.lua`, `spec/core_spec.lua`
  - `docs/manual-checklist.md`
  - `.luacheckrc` (`read_globals`)
- **Implementation:**
  - **`src/DB.lua`:** `ns.DB`.
    - `ns.DB.defaults = { schema = 1, settings = { enabled = true, debounceCap = 5, retention = 1000, triggers = {} }, captures = {}, visited = {} }`.
    - `ns.DB.Init(saved)`:
      - It returns a table. It deep-fills the missing keys from the defaults and keeps the existing values.
      - For each registered trigger, it fills `settings.triggers[key] = { enabled = def.enabled, delay = def.delay }` when the entry is missing.
      - It clamps `debounceCap` to [2, 10], `retention` to [100, 5000], and each `delay` to [0, 5], snapped to steps of 0.5.
      - When `saved.schema` is greater than 1 (a newer version), it keeps the data and does not change it.
    - `ns.DB.AppendCapture(db, record)`: appends the record, then removes the oldest records with `table.remove(captures, 1)` while `#captures > retention`.
    - `ns.DB.Trim(db)`: the same trim. The settings call it when the retention changes.
  - **`src/Debouncer.lua`:** `ns.Debouncer.New(opts)`. It is pure logic, with no WoW globals except through `opts`.
    - `opts`:
      - `now()`: seconds as a float (`GetTime`)
      - `schedule(delay, fn)`: returns a handle with `:Cancel()` (`C_Timer.NewTimer`)
      - `cap()`: returns the cap in seconds
      - `onFire(batch)`
    - `debouncer:Add(event, delay)`:
      - If no batch is pending, it creates `{ t0 = now, due0 = now + delay, due = now + delay, events = { event } }` and schedules the timer.
      - Otherwise, it appends the event and computes `newDue` with D5. If `newDue ~= due`, it cancels the timer and schedules a new one for `newDue - now`.
    - On timer fire: `batch = pending; pending = nil; onFire(batch)`.
    - `debouncer:IsPending()` and `debouncer:Reset()` (cancels the timer).
  - **`src/Capture.lua`:** `ns.Capture.New(opts)`.
    - `opts`: `db()`, `now()`, `after(delay, fn)`, `newTimer(delay, fn)`, `screenshot()`, `context()`. The production wiring passes `GetTime`, `C_Timer.After`, `C_Timer.NewTimer`, `Screenshot`, and `ns.Capture.BuildContext`.
    - `capture:Take(batch)`:
      - If `awaiting` is set, or `now() - lastShotAt < 1.0`, it calls `after(wait, function() capture:Take(batch) end)`. Here `wait = max(1.0 - (now() - lastShotAt), 0.1)`. When awaiting, `wait` is the remaining awaiting timeout plus 0.1. D6 applies.
      - Otherwise:
        - `awaiting = { batch = batch, context = context() }`
        - `lastShotAt = now()`
        - `screenshot()`
        - `awaitTimer = newTimer(3, function() awaiting = nil end)`
    - `capture:OnSucceeded()`:
      - If `awaiting` is nil, it returns. This ignores manual screenshots.
      - Otherwise:
        - It cancels `awaitTimer`.
        - `t = time()`
        - It builds the record (schema below) and calls `ns.DB.AppendCapture(db(), record)`.
        - It clears `awaiting`.
    - `capture:OnFailed()`: if awaiting, it cancels the timer, clears `awaiting`, and calls `ns.Print("screenshot failed")`.
    - `ns.Capture.FileName(t, format)`: D8.
    - `ns.Capture.UtcOffset(t)`: `os.difftime`-free: `time(date("*t", t)) - time(date("!*t", t))`. Correct the `isdst` field of the second table to `date("*t", t).isdst`.
    - `ns.Capture.IsoTime(t, offset)`: `date("%Y-%m-%dT%H:%M:%S", t) .. string.format("%s%02d:%02d", sign, h, m)`.
    - `ns.Capture.BuildContext()`:
      - `game = ns.GetGameInfo()`
      - `character = { name = UnitName("player"), realm = GetRealmName(), class = select(2, UnitClass("player")), level = UnitLevel("player") }`
      - `location = { zone = GetZoneText(), subzone = GetSubZoneText(), mapID = C_Map and C_Map.GetBestMapForUnit("player") }`
      - When `IsInInstance()` is true, `location.instance = { name, type, difficultyID, instanceID }` from `GetInstanceInfo()` (returns 1, 2, 3, and 8).
      - Each scalar value goes through `ns.Safe`.
  - **Capture record schema 1** (also the exporter contract, Task 7):
    ```lua
    {
      schema = 1,
      file = "WoWScrnShot_103126_201502.jpg",
      time = "2026-10-31T20:15:02+01:00",
      unix = 1793560502,
      utcOffset = 3600,
      addonVersion = "v1.0.0",
      game = { flavor = "retail", version = "12.1.5", build = "70688", interface = 120105 },
      character = { name = "Kaelys", realm = "Ragnaros", class = "MAGE", level = 80 },
      location = { zone = "Dornogal", subzone = "", mapID = 2339,
                   instance = { name = "...", type = "raid", difficultyID = 16, instanceID = 2657 } },
      events = {
        { trigger = "levelUp", name = "PLAYER_LEVEL_UP", unix = 1793560500, data = { level = 80 } },
      },
    }
    ```
    - `data` holds only string, number, and boolean values. Nested tables are not allowed, so the exporter mapping stays simple.
  - **`src/Triggers.lua`:** `ns.Triggers`.
    - `ns.Triggers.Register(def)`:
      - `def = { key, label, category, events = {...}, flavors = {...} or "all", default = { enabled, delay }, requires = fn?, handle = fn(state, event, ...) -> data|nil }`
      - It asserts unique keys, and records the order of registration (for the UI).
    - `ns.Triggers.All()`: in order.
    - `ns.Triggers.Available(flavor)`: applies D4. For `unknown`, it ignores `flavors`.
    - `ns.Triggers.Dispatch(event, ...)`:
      - For each available trigger that is enabled and lists the event, it calls `handle`.
      - A non-nil result becomes `{ trigger = key, name = event, unix = time(), data = sanitize(result) }`. `sanitize` drops non-scalar values and applies `ns.Safe`.
      - It passes the result to `debouncer:Add(record, settings.triggers[key].delay)`.
      - A handler error is caught with `pcall`. Then the addon prints one chat line for each trigger key in each session, and continues.
    - Categories (UI section order): `progress`, `combat`, `pvp`, `collections`, `loot`, `world`.
  - **`src/triggers/Progress.lua`:** register `levelUp`:
    - `events = { "PLAYER_LEVEL_UP" }`, `flavors = "all"`, `default = { enabled = true, delay = 1.0 }`
    - `handle` returns `{ level = level }`.
  - **`src/Core.lua`:**
    - It creates one event frame and registers `ADDON_LOADED`, `SCREENSHOT_SUCCEEDED`, and `SCREENSHOT_FAILED`.
    - On `ADDON_LOADED` with `name == ns.name`:
      - `PaparazziDB = ns.DB.Init(PaparazziDB)`
      - It builds the debouncer and the capture objects with the production wiring.
      - It registers the union of the events of the available triggers.
    - On a trigger event: if `settings.enabled`, it calls `ns.Triggers.Dispatch`.
    - It defines `SLASH_PAPARAZZI1 = "/paparazzi"`.
      - `SlashCmdList.PAPARAZZI` with the argument `test` adds `{ trigger = "test", name = "PAPARAZZI_TEST", unix = time(), data = {} }` with delay 0.
      - Any other argument calls `ns.Settings.Open()` when it exists (Task 6), else it prints the usage.
  - **`docs/manual-checklist.md`:** a table with these columns:
    - Trigger
    - How to cause it
    - one column for each flavor (Retail, MoP, Titan, TBC, Forever, Era)
    - Pass/fail/date
    - Add rows for:
      - `/paparazzi test`
      - level up
      - two triggers at once (a level up with an achievement): one image, two events
      - a manual PrintScreen: no record is added
      - `/reload`: the record is in `WTF/.../Paparazzi.lua`
- **Edge cases:**
  - Two events in the same frame.
  - An event with delay 0.
  - An event that arrives after the timer fired but before `SCREENSHOT_SUCCEEDED`: it starts a new batch, and spacing defers it.
  - A cap change while a batch is pending: the next `Add` uses the new cap.
  - `SCREENSHOT_SUCCEEDED` without awaiting (a manual shot).
  - `SCREENSHOT_FAILED`.
  - A 3 s timeout, then a late `SCREENSHOT_SUCCEEDED`: ignored.
  - The retention is lowered under the current count.
  - The master switch is off: nothing is captured.
  - An `ADDON_LOADED` event for another addon: ignored.
  - `PaparazziDB` is nil (first run).
  - `GetCVar("screenshotFormat")` returns nil.
  - A handler raises an error.
- **Tests:**
  - `spec/debouncer_spec.lua` (unit): each D5 example.
    - One event with delay 2 → fires at 2.
    - Level up (2) at 0 and an achievement (1) at 0.3 → one fire at 2 with two events.
    - Add a mount (4) at 1.5 with cap 5 → fire at 5.
    - Cap 2 and a single event with delay 5 → fire at 5 (the first delay is kept).
    - An event after the fire → a new batch.
  - `spec/capture_spec.lua` (unit):
    - spacing: two batches 0.2 s apart → screenshots at least 1.0 s apart
    - a manual `SCREENSHOT_SUCCEEDED` → no record
    - failed → no record and one chat line
    - timeout → a late success is ignored
    - `FileName` for `jpeg`, `png`, `tga`, and nil
    - `UtcOffset` and `IsoTime` for offsets 0, +3600, +7200, and -18000. The test replaces `date` with a stub that returns fixed `"*t"` and `"!*t"` tables, so the result does not depend on the time zone of the test machine.
    - a secret value in the context → nil
  - `spec/db_spec.lua` (unit):
    - defaults fill
    - the existing values are kept
    - each value is clamped
    - the ring buffer drops the oldest record at retention+1
    - `Trim` after the retention is lowered
  - `spec/triggers_spec.lua` (unit):
    - gating by flavor, by `IsEventValid`, and by `requires`
    - a disabled trigger is not dispatched
    - a handler that returns nil → no add
    - `sanitize` drops tables and secret values
    - a handler error is caught, and a chat line is printed once
  - `spec/core_spec.lua` (integration through `wow.load_addon(wow.toc_files())`):
    - `ADDON_LOADED` creates `PaparazziDB`
    - `wow.fire("PLAYER_LEVEL_UP", 80)`, then `wow.advance(1)` → `Screenshot` is called once
    - `wow.fire("SCREENSHOT_SUCCEEDED")` → one record that matches the schema-1 shape, with `events[1].trigger == "levelUp"`
    - `/paparazzi test` → one record
    - master switch off → no screenshot
- **Verify:** `make lint test coverage` (unverified until Task 1 tools exist). Then do the manual checklist rows for `/paparazzi test` and level up in Retail.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 4. Triggers: progress and collections

- **Outcome:** the triggers below exist with the catalog defaults and flavor gates. Each one records its data fields.
- **Depends on:** Task 3 (registry, dispatch, capture pipeline).
- **Covers:** AC6 (these triggers), R5, R6.
- **Files:**
  - `src/triggers/Progress.lua`
  - `src/triggers/Collections.lua`
  - `Paparazzi.toc`
  - `.luacheckrc`
  - `spec/triggers_progress_spec.lua`, `spec/triggers_collections_spec.lua`
  - `docs/manual-checklist.md` (one row for each trigger)
- **Implementation:** each row is one `ns.Triggers.Register` call.
  - Flavor codes: `retail`, `mists`, `titan`, `tbc`, `forever`, `era`.
  - Wrap each name lookup in an existence check, for example `if C_MountJournal then`. A missing lookup leaves the name field nil. It does not cancel the shot.

| key | category | events | flavors | default | handle rule → data |
|---|---|---|---|---|---|
| `achievement` | progress | `ACHIEVEMENT_EARNED` | retail mists titan forever | on, 1.0 | `(id, alreadyEarned)`. Skip if `alreadyEarned`. `isGuild = select(12, GetAchievementInfo(id))`. Skip if `isGuild`. → `achievementID, achievementName (ret 2), points (ret 3)` |
| `guildAchievement` | progress | `ACHIEVEMENT_EARNED` | retail mists | off, 1.0 | Same, but only if `isGuild`. → the same fields |
| `criteria` | progress | `CRITERIA_EARNED` | retail mists titan forever | off, 1.0 | `(achievementID, description)` → `achievementID, achievementName, description` |
| `reputation` | progress | `PLAYER_ENTERING_WORLD`, `FACTION_STANDING_CHANGED` | all | on, 1.0 | On PEW: snapshot the standing of each faction into an upvalue (not saved). On change `(factionID, updatedStanding)`: read the current standing. Shoot only if it is higher than the snapshot. Update the snapshot. → `factionID, factionName, oldStanding, newStanding, standingLabel = _G["FACTION_STANDING_LABEL"..newStanding]`. Retail: `C_Reputation.GetFactionDataByID(id).reaction`. Friendship factions use `C_GossipInfo.GetFriendshipReputation(id)` with `reactionThreshold` as the standing. Classic: `GetFactionInfoByID(id)` (return 3 = standingID). Inspect each API in the Blizzard UI source branch of each flavor. Assumption: `updatedStanding` is not used as the rank. Confirm this in the docs. |
| `renown` | progress | `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` | retail | off, 1.0 | `(majorFactionID, newLevel, oldLevel)`. Shoot only if `newLevel > oldLevel`. → `majorFactionID, factionName (C_MajorFactions.GetMajorFactionData(id).name), newRenownLevel, oldRenownLevel` |
| `recipe` | progress | `NEW_RECIPE_LEARNED` | all | off, 1.0 | `(recipeID)` → `recipeID, recipeName (C_Spell.GetSpellName or GetSpellInfo)` |
| `travelersLog` | progress | `PERKS_ACTIVITY_COMPLETED` | retail forever | off, 1.0 | `(perksActivityID)` → `perksActivityID, activityName (C_PerksActivities.GetPerksActivityInfo(id).activityName, inspect)` |
| `mount` | collections | `NEW_MOUNT_ADDED` | retail mists titan | on, 1.0 | `(mountID)` → `mountID, mountName (C_MountJournal.GetMountInfoByID ret 1)` |
| `pet` | collections | `NEW_PET_ADDED` | retail mists titan | on, 1.0 | `(battlePetGUID)` → `speciesID, petName (C_PetJournal.GetPetInfoByPetID ret 1 and 8, inspect)` |
| `toy` | collections | `NEW_TOY_ADDED` | retail mists titan | on, 1.0 | `(itemID)` → `itemID, toyName (C_ToyBox.GetToyInfo ret 2, fallback C_Item.GetItemNameByID)` |
| `housingItem` | collections | `NEW_HOUSING_ITEM_ACQUIRED` | retail | off, 1.0 | `(itemType, itemName)` → `itemType, itemName` |
| `houseLevel` | collections | `HOUSE_LEVEL_CHANGED` | retail | off, 1.0 | `(newHouseLevelInfo)` → the scalar fields of the info table (inspect `HouseLevelInfo` in `HousingUIDocumentation.lua`) |

- **Edge cases:**
  - A guild achievement must not also make a personal shot.
  - `alreadyEarned` is nil in Classic. Treat nil as false.
  - Reputation: a faction that is missing from the snapshot (it was discovered after login) → snapshot it and do not shoot. A standing decrease → no shot.
  - Renown: `newLevel <= oldLevel` → no shot.
  - A lookup API is missing → the name is nil and the shot still happens.
  - `PLAYER_ENTERING_WORLD` after a `/reload`: the snapshot is rebuilt and there is no shot.
- **Tests (unit, through `wow.load_addon` with fakes for each lookup API):**
  - For each trigger: the success path records the listed data fields.
  - For each skip rule: no `Screenshot` call.
  - Flavor gating: `achievement` is not available with `GetBuildInfo` interface 11509 or 20506. `mount` is not available in `era`.
  - Reputation: increase → shot. Decrease → no shot. A faction that is not in the snapshot → no shot.
- **Verify:** `make lint test coverage`. Then do the manual checklist rows on Retail and on at least one Classic flavor.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 5. Triggers: combat, PvP, loot, and world

- **Outcome:** the remaining triggers of the catalog exist with their defaults, flavor gates, and data fields.
- **Depends on:** Task 3 (registry, dispatch, `PaparazziDB.visited`).
- **Covers:** AC6 (these triggers), R5, R6.
- **Files:**
  - `src/triggers/Combat.lua`, `src/triggers/PvP.lua`, `src/triggers/Loot.lua`, `src/triggers/World.lua`
  - `Paparazzi.toc`
  - `.luacheckrc`
  - `spec/triggers_combat_spec.lua`, `spec/triggers_pvp_spec.lua`, `spec/triggers_loot_spec.lua`, `spec/triggers_world_spec.lua`
  - `docs/manual-checklist.md`
- **Implementation:**

| key | category | events | flavors | default | handle rule → data |
|---|---|---|---|---|---|
| `bossKill` | combat | `ENCOUNTER_END` | all | on, 1.0 | `(encounterID, encounterName, difficultyID, groupSize, success)`. Shoot only if `success == 1`. → `encounterID, encounterName, difficultyID, difficultyName (GetDifficultyInfo ret 1), groupSize` |
| `bossWipe` | combat | `ENCOUNTER_END` | all | off, 1.0 | The same, but only if `success == 0` |
| `worldBoss` | combat | `BOSS_KILL` | retail mists titan | on, 1.0 | `(encounterID, encounterName)`. Shoot only if `not IsInInstance()`. → `encounterID, encounterName` |
| `challengeMode` | combat | `CHALLENGE_MODE_COMPLETED` | retail mists | on, 1.0 | Retail: `C_ChallengeMode.GetChallengeCompletionInfo()` → `mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels, practiceRun`, plus `mapName (C_ChallengeMode.GetMapUIInfo ret 1)`. MoP: inspect the completion API in the `classic` branch (`GetCompletionInfo` or similar). Fallback: data `{}`. |
| `challengeModeRecord` | combat | `CHALLENGE_MODE_NEW_RECORD` | retail mists | off, 1.0 | `(mapID, timeMS, medal)` → the same fields |
| `delve` | combat | `SCENARIO_COMPLETED` | retail | off, 1.0 | Shoot only if `C_PartyInfo.IsDelveComplete and C_PartyInfo.IsDelveComplete()`. → `scenarioName` (`C_ScenarioInfo.GetScenarioInfo().name`, inspect). Assumption: `SCENARIO_COMPLETED` fires for delves. The manual checklist checks it. |
| `death` | combat | `PLAYER_DEAD` | all | off, 0.5 | → `{}` (context has the location) |
| `pvpMatch` | pvp | Retail: `PVP_MATCH_COMPLETE`. Others: `UPDATE_BATTLEFIELD_STATUS` | all | off, 1.0 | Wins only. The player's team is `GetBattlefieldArenaFaction()`. Retail `(winner, duration)`: shoot if `winner == myTeam`. → `winner, duration, isArena (C_PvP.IsArena())`. Classic: on each status update, `w = GetBattlefieldWinner()`. Shoot once when `w` changes from nil to a value and `w == myTeam`. Reset the latch when `w` is nil again. → `winner, isArena (IsActiveBattlefieldArena())`. The trigger registers one event set per flavor: `events` is a function of the flavor. Extend `Register` to accept this. |
| `duel` | pvp | `DUEL_FINISHED` | all | off, 1.0 | → `{}`. The outcome is not known (Constraints: no `CHAT_MSG_SYSTEM`). |
| `epicLoot` | loot | `SHOW_LOOT_TOAST` | retail | off, 1.0 | `(typeIdentifier, itemLink, quantity)`. Only `typeIdentifier == "item"`. `quality = C_Item.GetItemQualityByID(itemLink)`. If that is nil, parse the color of the link (`|cffa335ee` = 4, `|cffff8000` = 5). Shoot only if `quality >= 4`. → `itemLink, itemName (from the link), quality, quantity` |
| `legendaryLoot` | loot | `SHOW_LOOT_TOAST_LEGENDARY_LOOTED` | retail | on, 1.0 | `(itemLink)` → `itemLink, itemName` |
| `trade` | world | `TRADE_SHOW`, `TRADE_ACCEPT_UPDATE` | all | off, 0.0 | `TRADE_SHOW` resets a latch and returns nil. `(playerAccepted, targetAccepted)`: shoot once for each trade when exactly one of them is 1. → `playerAccepted, targetAccepted, tradeTarget (UnitName("NPC"), assumption: the trade target unit is "NPC"; inspect)` |
| `login` | world | `PLAYER_ENTERING_WORLD` | all | off, 5.0 | `(isInitialLogin)`. Shoot only if true. → `isInitialLogin = true` |
| `firstVisit` | world | `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA` | all | off, 2.0 | Location key: in an instance, `"i:" .. instanceID` (`GetInstanceInfo` ret 8). Otherwise `"z:" .. zoneMapID`, where `zoneMapID` is the parent map of type Zone of `C_Map.GetBestMapForUnit("player")` (`MapUtil.GetMapParentInfo(id, Enum.UIMapType.Zone, true)`, inspect in Classic). Fallback key: `"n:" .. GetZoneText()`. Store keys in `PaparazziDB.visited["Name-Realm"][key] = true`. On PEW: mark the current location as visited **without** a shot. This prevents a shot at each login after install. On zone change: shoot if the key is new, then mark it. → `zoneName, mapID, instanceID, instanceType` |

- **Edge cases:**
  - `ENCOUNTER_END` and `BOSS_KILL` for the same kill → the debounce merges them into one image with two events.
  - `ENCOUNTER_END` after a `/reload` in the middle of a fight → no error. The trigger keeps no start state.
  - `UPDATE_BATTLEFIELD_STATUS` fires many times after the match ends → one shot.
  - A PvP loss → no shot.
  - `SHOW_LOOT_TOAST` for money or currency → no shot.
  - An item link without a known color and a nil quality → no shot.
  - `TRADE_ACCEPT_UPDATE(1,1)` or `(0,0)` → no shot.
  - A second accept toggle in the same trade → no shot.
  - `firstVisit`: `MapUtil` is absent → fallback key. `GetBestMapForUnit` returns nil (a loading screen) → no shot and no mark.
  - `login` on a `/reload` → no shot.
- **Tests (unit, through `wow.load_addon`):**
  - Each trigger: the success path records the listed fields. Each skip rule → no `Screenshot`.
  - The kill + `BOSS_KILL` merge → one screenshot and two events.
  - PvP Retail win/loss. PvP Classic latch: three status updates after a win → one shot.
  - First visit: PEW marks without a shot. A new zone → shot. The same zone again → no shot. Instance key versus zone key.
  - Flavor gating: `pvpMatch` registers `PVP_MATCH_COMPLETE` on Retail and `UPDATE_BATTLEFIELD_STATUS` on Era.
- **Verify:** `make lint test coverage`. Then do the manual checklist rows (boss kill, death, first visit, PvP win) on Retail and on one Classic flavor.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 6. Settings panel, `/paparazzi`, addon compartment

- **Outcome:** **Options → AddOns → Paparazzi** shows all the settings. Each change takes effect at once and is saved.
- **Depends on:** Task 3 (DB layout, registry order, `ns.DB.Trim`). It works with any subset of triggers, so it does not need Tasks 4 and 5.
- **Covers:** AC7.
- **Files:** `src/Settings.lua`, `src/Core.lua` (call `ns.Settings.Init(db)` after `ADDON_LOADED`), `Paparazzi.toc`, `.luacheckrc`, `spec/settings_spec.lua`, `docs/manual-checklist.md`, `README.md` (usage).
- **Implementation:**
  - `ns.Settings.Init(db)`:
    - `category = Settings.RegisterVerticalLayoutCategory("Paparazzi")`.
    - Master switch: `Settings.RegisterAddOnSetting(category, "Paparazzi_enabled", "enabled", db.settings, Settings.VarType.Boolean, "Enabled", true)`, then `Settings.CreateCheckbox(category, setting, tooltip)`.
    - Debounce cap slider: 2–10, step 1, label format `"%d s"`. Use `Settings.CreateSliderOptions(2, 10, 1)` and `options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fn)` (inspect the formatter in each Classic branch).
    - Retention slider: 100–5000, step 100. Its `SetValueChangedCallback` calls `ns.DB.Trim(db)`.
    - For each category in order, a section header (`CreateSettingsListSectionHeaderInitializer`, inspect its availability in Classic). Then, for each **available** trigger:
      - a checkbox bound to `db.settings.triggers[key]`, `"enabled"`
      - a delay slider 0–5, step 0.5, format `"%.1f s"`
    - Variable names are `"Paparazzi_" .. key .. "_enabled"` and `"Paparazzi_" .. key .. "_delay"`.
    - `Settings.RegisterAddOnCategory(category)`.
    - `ns.Settings.Open = function() Settings.OpenToCategory(category:GetID()) end`.
  - The global function `Paparazzi_OnAddonCompartmentClick` calls `ns.Settings.Open()`. Add `## AddonCompartmentFunc: Paparazzi_OnAddonCompartmentClick` to `Paparazzi.toc` in this task, so that the TOC never names an undefined function. Flavors without a compartment ignore the TOC key.
  - If `Settings` or `Settings.RegisterAddOnSetting` is absent, skip the panel. Then `/paparazzi` prints `"/paparazzi test"` usage and the message "settings UI unavailable in this client".
- **Edge cases:**
  - A trigger that is not available in this flavor → no control, and its saved values stay.
  - The retention is lowered → the trim happens at once.
  - `Settings` is absent.
  - A delay value that is not on a 0.5 step in old saved data → the DB clamps it (Task 3).
- **Tests (unit, `spec/settings_spec.lua`, with a fake `Settings` in `spec/helpers/wow.lua` that records the categories, the settings, and the initializers):**
  - One checkbox and one slider for each available trigger, in the registry order, under the correct section.
  - No controls for unavailable triggers.
  - The bound tables are the `db.settings` tables (a write through the fake setting changes `PaparazziDB`).
  - The retention callback trims.
  - `/paparazzi` calls `OpenToCategory` with the category ID.
  - `Settings` is absent → no error, and a usage message.
- **Verify:** `make lint test`. Then the manual checklist: open the panel in Retail and in one Classic flavor, switch a trigger off, `/reload`, and confirm that the value persists. Coverage excludes this file (see Tests guidelines).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 7. Go exporter `paparazzi-export`, with its CI jobs and Makefile targets

- **Outcome:** `paparazzi-export --wow-dir "<…>/_retail_"` writes a JSON sidecar for each matched capture. CI checks the Go code.
- **Depends on:** Task 2 (`ci.yml` to extend), Task 3 (capture record schema 1).
- **Covers:** AC9, AC10 (Go part), D9, D10, R4, R11.
- **Files:**
  - `go.mod` (`module github.com/fmartingr/wow-addon-paparazzi`, `go 1.27.1`; no `require`)
  - `cmd/paparazzi-export/main.go`
  - `internal/savedvars/lexer.go`, `internal/savedvars/parser.go`, `internal/savedvars/parser_test.go`
  - `internal/export/capture.go`, `internal/export/match.go`, `internal/export/write.go`, `internal/export/*_test.go`
  - `testdata/` (fixture `WTF/Account/TEST/SavedVariables/Paparazzi.lua` and empty fake screenshots)
  - `.github/workflows/ci.yml` (job `go`)
  - `.github/dependabot.yml` (`gomod`)
  - `Makefile`
  - `README.md`
- **Implementation:**
  - **`savedvars.Parse(r io.Reader) (map[string]any, error)`:**
    - Grammar:
      - `chunk := { Name "=" value }`
      - `value := table | string | number | "true" | "false" | "nil"`
      - `table := "{" [ field { ("," | ";") field } [ "," | ";" ] ] "}"`
      - `field := "[" (string | number) "]" "=" value | Name "=" value | value`
    - Lexer:
      - It skips whitespace and `--` comments to the end of the line. WoW writes `-- [1]` after array items.
      - Strings: `"…"` and `'…'` with escapes `\\ \" \' \n \r \t \a \b \f \v \ddd` and an escaped newline.
      - Numbers: decimal integers and floats, exponents, and a leading `-`. A value that is an integer and fits `int64` → `int64`; otherwise `float64`. Reject `inf` and `nan` tokens with an error.
    - Tables: if the keys are exactly `1..n` → `[]any`; otherwise → `map[string]any` (number keys formatted with `strconv`).
    - Limits: the input over 64 MiB → error (`io.LimitReader` + a check). Nesting over 64 → error. Errors include the line and column.
  - **`export.LoadCaptures(dbFile string) ([]Capture, error)`:**
    - It parses the file and reads `PaparazziDB.captures`.
    - It keeps each record with `schema == 1`. Other values → a warning, and the record is skipped.
    - `Capture` keeps the raw map for the JSON output, plus the typed fields `File`, `Unix`, `UtcOffset`.
    - It rejects a `file` value that does not match `^WoWScrnShot_\d{6}_\d{6}\.(jpg|png|tga)$` (R11).
  - **`export.Match(captures, files []string, tol time.Duration) []Pair`:**
    - It sorts the captures by `Unix`.
    - Pass 1: exact names.
    - Pass 2: for each unmatched capture, it parses each unclaimed file name time with `time.ParseInLocation("010206_150405", s, time.FixedZone("", utcOffset))`. It takes the minimal `|diff| <= tol`. A tie → the capture goes to the `Ambiguous` list.
    - It returns the matched pairs and the lists of unmatched and ambiguous captures.
  - **`export.Write(pair, force, dryRun)`:**
    - The target is `filepath.Join(dir, strings.TrimSuffix(name, ext) + ".json")`.
    - It skips the file if the target exists and not `force`.
    - It marshals the raw capture map with `json.MarshalIndent(…, "", "  ")` and a final newline.
    - It writes atomically: `os.CreateTemp` in the same directory, then `Sync`, `Close`, and `os.Rename`, with mode 0644.
    - It never opens an image for write.
  - **CLI (`flag` package):**
    - `--wow-dir` (required): the flavor folder.
    - `--account` (optional): the account folder name. The default is every `WTF/Account/*/SavedVariables/Paparazzi.lua`.
    - `--screenshots`: default `<wow-dir>/Screenshots`.
    - `--tolerance`: default `2s`.
    - `--force`, `--dry-run`, `--version` (set with `-ldflags "-X main.version=…"`).
    - It prints a summary `written=N skipped=N unmatched=N ambiguous=N` and a line for each warning to stderr.
    - Exit codes: 0 on success, even if some captures are unmatched. 1 on a read, parse, or write error. 2 on a usage error.
  - **Makefile:** add these targets and extend the existing ones.
    - `lint-go`: `test -z "$$(gofmt -l .)" && go vet ./...`
    - `test-go`: `go test -race ./...`
    - `coverage-go`: `go test -coverprofile=coverage.out ./internal/... && go tool cover -func=coverage.out`. It fails below `GO_COVERAGE_MIN ?= 80`.
    - `build`: `CGO_ENABLED=0 go build -o build/paparazzi-export ./cmd/paparazzi-export`
    - `export`: requires `WOW_DIR`, then `go run ./cmd/paparazzi-export --wow-dir "$(WOW_DIR)"`.
    - Add `lint-go` to `lint`, `test-go` to `test`, and `coverage-go` to `coverage`. `fmt` also runs `gofmt -w .`.
  - **CI job `go`:**
    - checkout
    - `actions/setup-go` (pin at task time) with `go-version-file: go.mod`
    - `make lint-go test-go coverage-go`
- **Edge cases:**
  - An empty `captures` table.
  - A missing `PaparazziDB`.
  - A file with only a header comment.
  - A `\ddd` escape over 255 → error.
  - An unterminated string → error with the line number.
  - A deeply nested input (depth 65) → error.
  - A 70 MiB input → error.
  - Two captures that want the same file → only the nearest one gets it.
  - A capture whose file is in `.png` while the CVar said `.jpg` → the tolerance pass matches it.
  - DST: `utcOffset` from the record is used, not the local zone of the machine that runs the exporter.
  - A `.json` file already exists → skip. With `--force` → overwrite.
  - `--dry-run` → no file is written.
  - A `file` field with `../` → rejected.
  - Several accounts.
  - The Screenshots folder is missing → exit 1 with a clear message.
- **Tests:**
  - `internal/savedvars/parser_test.go` (unit, table-driven): each grammar form, each escape, `-- [n]` comments, the array versus map decision, each error case with its line number.
  - `FuzzParse` with a seed corpus. Plain `go test` runs only the seeds. The fuzz target asserts no panic.
  - `internal/export/match_test.go` (unit): exact, ±1 s, ±3 s (no match), tie → ambiguous, one file claimed once, DST offsets.
  - `internal/export/write_test.go` (unit, `t.TempDir()`): written content equals the expected JSON, skip existing, `--force`, dry run, the image bytes do not change.
  - `cmd/paparazzi-export/main_test.go` (integration): copy `testdata/` to `t.TempDir()`, run `run(args, stdout, stderr)` (factor `main` into `run`), and assert the summary line, the exit code, and the sidecar files.
  - Fixture: generate one realistic `Paparazzi.lua` with the format that the game writes (tabs, `["key"] = value,`, `-- [n]` comments). The manual checklist adds one real file from a game session to `testdata/` after you remove the personal names.
- **Verify:** `make lint-go test-go coverage-go build`. Then `./build/paparazzi-export --wow-dir testdata/wow --dry-run`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 8. Release pipeline, `make release-*`, and release docs

- **Outcome:** `make release-minor` pushes `v0.1.0`. The release workflow publishes the addon zip (CurseForge when configured, and the GitHub Release) and the exporter binaries.
- **Depends on:** Task 1 (Makefile, `.pkgmeta`), Task 2 (pinned action SHAs), Task 7 (exporter build).
- **Covers:** AC11, AC12, D17, R1, R3, R8, R9, R10, R13.
- **Files:** `.github/workflows/release.yml`, `.goreleaser.yaml`, `Makefile`, `README.md` (sections: Install, Usage, Exporter, Limits, Development, Releasing), `docs/manual-checklist.md` (release section).
- **Implementation:**
  - **`release.yml`:** `on: push: tags: ["v*"]`. `permissions: contents: read` at the top.
    - Job `addon`:
      - `permissions: contents: write`
      - `env: CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}`, `GH_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}`
      - checkout `fetch-depth: 0`
      - packager `e50a250f… # v2.6.1` with `pandoc: false`
    - Job `exporter`:
      - `needs: addon`, `permissions: contents: write`
      - checkout `fetch-depth: 0`
      - setup-go `go-version-file: go.mod`
      - `goreleaser/goreleaser-action` (pin at task time) with `args: release --clean`, `env: GITHUB_TOKEN`
  - **`.goreleaser.yaml`** (`version: 2`). Follow `games-screenshot-manager/.goreleaser.yaml`:
    - build `binary: paparazzi-export`, `main: ./cmd/paparazzi-export`, `CGO_ENABLED=0`
    - `ldflags: -s -w -X main.version={{.Version}}`
    - linux/windows/darwin with amd64/arm64
    - archives: zip for windows, tar.gz for the others
    - `changelog: { disable: true }`
    - `release: { mode: keep-existing, prerelease: auto }`. This keeps the packager's release body.
    - `git: { ignore_tags: ["*-alpha*"] }`
  - **Makefile release targets** (bash, `-euo pipefail`):
    - `MAIN ?= main` and `REMOTE ?= origin`.
    - `release-check`:
      - `git status --porcelain` is empty
      - the current branch is `$(MAIN)`
      - `git fetch --quiet --tags $(REMOTE) $(MAIN)`
      - `git rev-parse HEAD` equals `$(REMOTE)/$(MAIN)`
    - `release-patch`, `release-minor`, `release-major` depend on `release-check`:
      - `last=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null || echo v0.0.0)`
      - bump the major, minor, or patch part
      - print `last -> next`
      - `git tag -a "$next" -m "Release $next"`
      - `git push $(REMOTE) "$next"`
    - `DRY_RUN=1` prints the next tag and stops before the tag step.
  - **README:**
    - Setup steps: create the GitHub repository and push `main`. Add the `CF_API_TOKEN` secret (from https://authors.curseforge.com/#/settings/api-tokens). Add `## X-Curse-Project-ID` to the TOC after the CurseForge project exists.
    - The limits R1, R2, and R3.
    - How to update the Interface numbers (R8).
    - Beta releases: tag `vX.Y.Z-beta1` by hand. The packager marks it as beta. A `-rc` tag counts as a full release.
  - **Manual checklist release section:** run all trigger rows in each flavor that is available to you. Run the exporter on the real SavedVariables. Check the zip contents.
- **Edge cases:**
  - No tag exists yet → `v0.0.0` base.
  - Only beta tags exist → they are ignored for the base.
  - A dirty tree, a wrong branch, or a branch that is behind or ahead → exit 1 with a message.
  - `CF_API_TOKEN` or the project ID is missing → the packager skips CurseForge, and the GitHub Release is still made.
  - A tag that a workflow pushed with `GITHUB_TOKEN` does not trigger the release. Tag only from a local machine.
- **Tests:**
  - `scripts/test-release.sh` (integration, run by `make test-release`):
    - It creates a temporary git repository with a bare `origin`.
    - It runs the release targets with `DRY_RUN=1` and with real tags against the bare remote.
    - It asserts: v0.0.0 → v0.0.1, v0.1.0, and v1.0.0. A beta tag is ignored. A dirty tree fails. A wrong branch fails. A branch behind the remote fails.
    - Add `test-release` to `make test`.
  - `goreleaser check` (if goreleaser is installed locally; unverified) and `goreleaser release --snapshot --clean` produce the six archives.
  - `actionlint .github/workflows/release.yml`.
- **Verify:** `make test-release`, `actionlint`. Then, after the GitHub repository exists, push the tag `v0.1.0-beta1` and check the GitHub Release: the addon zip, the six exporter archives, and the beta flag.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Do these checks after the last task.

1. `make check-tools lint test coverage build` passes on a clean clone.
2. CI is green on a pull request that touches Lua and Go.
3. The packager artifact zip contains only `Paparazzi/` with the TOC, `src/`, `LICENSE`, and `README.md`.
4. In game, in Retail and in each Classic flavor that is available to you, run `docs/manual-checklist.md`:
   - each default-on trigger
   - the debounce merge (level up + achievement → one image, two events)
   - shot spacing
   - a manual PrintScreen that is ignored
   - the settings persist after `/reload`
5. Do a `/reload`. Then `paparazzi-export --wow-dir <flavor dir>` writes one `.json` for each auto screenshot. Each JSON matches schema 1, and its `file` names the image next to it.
6. Run the exporter a second time: each capture is skipped, and nothing changes.
7. A beta tag release shows the addon zip and six exporter archives on GitHub. When `CF_API_TOKEN` and the project ID exist, the file is on CurseForge as a beta.

## References

- WoW API:
  - https://warcraft.wiki.gg/wiki/API_Screenshot
  - https://warcraft.wiki.gg/wiki/SCREENSHOT_SUCCEEDED
  - https://warcraft.wiki.gg/wiki/Console_variables/Complete_list
  - https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions
  - https://warcraft.wiki.gg/wiki/TOC_format
  - https://warcraft.wiki.gg/wiki/API_date
  - https://warcraft.wiki.gg/wiki/API_time
  - https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
  - https://warcraft.wiki.gg/wiki/Secret_Values
  - https://warcraft.wiki.gg/wiki/PARTY_KILL
  - https://warcraft.wiki.gg/wiki/FACTION_STANDING_CHANGED
- Blizzard UI source (generated API docs, branches `live`, `classic`, `classic_era`, `classic_anniversary`, `forever`): https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated
- Prior art:
  - https://github.com/lua-wow/screenshots
  - https://github.com/fouronnes/DingPics
  - https://github.com/AnrDaemon/WoW-Multishot
  - https://github.com/Nukme/Multishot
  - https://github.com/arcane-wizard-dev/Memento
  - https://www.curseforge.com/wow/addons/multishot
  - https://www.curseforge.com/wow/addons/memento
  - https://www.curseforge.com/wow/addons/ding-auto-screenshots
- Packager:
  - https://github.com/BigWigsMods/packager
  - https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow
  - https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File
  - https://github.com/BigWigsMods/packager/issues/129
- CurseForge:
  - https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api
  - https://authors.curseforge.com/#/settings/api-tokens
- Lua tooling:
  - https://luacheck.readthedocs.io/en/stable/config.html
  - https://github.com/JohnnyMorganz/StyLua#configuration
  - https://github.com/JohnnyMorganz/stylua-action
  - https://github.com/leafo/gh-actions-lua
  - https://luarocks.org/modules/lunarmodules/luacov
  - https://github.com/Questie/Questie/blob/master/setupTests.lua (fake WoW API pattern)
- GitHub Actions security:
  - https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/
  - https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/
  - https://github.com/actions/checkout/issues/290
- Sibling conventions: `/home/fmartingr/Code/games-screenshot-manager` (`worldofwarcraft.go`, `.goreleaser.yaml`, `.github/workflows/`).

## Open Decisions

- **CurseForge project ID:** the project does not exist yet. Until you add `## X-Curse-Project-ID: <id>` to `Paparazzi.toc` and the `CF_API_TOKEN` secret to GitHub, releases go to GitHub only. Impact: AC11 is only partly met until then.
- **GitHub repository:** there is no remote yet. You must create `github.com/fmartingr/wow-addon-paparazzi` and push `main` before the CI checks in Task 2 and the release checks in Task 8 can run. Impact: those Verify steps wait for it.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the file is untracked). Create `specs/done/` if it does not exist. Commit the move.
