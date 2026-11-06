# Paparazzi: send screenshot notes to Memories

## Why

The player uses two of their own addons in WoW Forever: Paparazzi (this repo) takes screenshots of game events, and Memories (`~/Code/wow-addon-memories`, spec `specs/2026-11-06-memories-addon-set.md` there) records the character's journey. Memories writes an `ss` line for every screenshot, but it cannot know *why* a screenshot exists. Paparazzi knows the reason (the triggers in the capture). When Paparazzi gives that reason to Memories, the journey shows each Paparazzi screenshot with its reason.

## What

After each successful capture, Paparazzi calls `Memories.RecordScreenshot(source, note, file)` when the Memories API exists.

Acceptance criteria:

- **AC1:** After `SCREENSHOT_SUCCEEDED` for a pending capture, and after the capture record is stored in `PaparazziDB.captures`, Paparazzi calls `Memories.RecordScreenshot("Paparazzi", note, file)` once.
- **AC2:** `file` is the same predicted file name that the capture record stores.
- **AC3:** `note` is the trigger labels of the capture's events, in event order, without duplicates, joined with `", "` (for example `"Level up, Boss kill"`). A trigger key with no registered definition uses the key itself.
- **AC4:** When the global `Memories` is missing, is not a table, or has no function `RecordScreenshot`, Paparazzi makes no call and shows nothing.
- **AC5:** When the call raises an error or returns `false`, Paparazzi still stores its capture as before, prints nothing in chat, and continues to work.
- **AC6:** A failed screenshot (`SCREENSHOT_FAILED`), a manual screenshot (no pending capture) and a late success after the await timeout make no call.
- **AC7:** In flavors where Memories does not exist (Retail, MoP Classic, Classic Era, TBC Anniversary, Titan Reforged), the behavior of Paparazzi does not change.
- **AC8:** `make lint`, `make test` and `make coverage` pass.

## Constraints

- **Must:**
  - Keep the existing dependency-injection style of `Capture.New(opts)`.
  - Treat Memories as optional. Add no `## Dependencies`. `## OptionalDeps` is not needed, because the call happens after login, when both addons have loaded.
  - Call the API through `pcall`, so that an error in Memories cannot break Paparazzi.
- **Must Not:**
  - Change the capture record schema or the exporter.
  - Add a setting (the call is cheap and happens only when Memories exists).
  - Read or write Memories' saved data.
- **Out of Scope:**
  - Any change in Memories. Memories implements `RecordScreenshot` in its own spec (Task 8 there).
  - Reports of failed screenshots to Memories.

## Decisions

- **D1 — Call after the shot.** The user chose that the screenshot note goes to Memories after `SCREENSHOT_SUCCEEDED`, with the predicted file name. The Memories converter joins the note with Memories' own `ss` line by file name, else by time (±2 s).
- **D2 — Source name** is the literal `"Paparazzi"` (`ns.name`), so that the Memories converter shows the source.
- **D3 — Note text** comes from the trigger labels, because the labels are what the player sees in the Settings panel. Memories cuts the note at 200 bytes on a UTF-8 character limit, so Paparazzi does not cut it.
- **D4 — No setting.** A player who does not want the notes can disable the Memories kind `sn` in Memories' settings.

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| Memories raises an error inside `RecordScreenshot`. | Paparazzi could stop recording. | `pcall` around the call; the capture is stored before the call. | 1 |
| Memories is not installed or is an older version without the API. | A nil call error. | Check the global and the function type before the call. | 1 |
| The predicted file name is off by 1 s. | The converter misses the join by name. | The Memories converter falls back to ±2 s. Paparazzi sends the same name it stores, so both tools agree. | 1 |
| No e2e suite. | A behavior can pass the tests and fail in the game. | A named manual check in the game (Validation). | 1 |

## Current State

- `src/Capture.lua:58-130` — `Capture.New(opts)` takes `db`, `now`, `after`, `newTimer`, `screenshot`, `context`. `instance:OnSucceeded()` (:98) returns early when nothing is awaiting, builds the record with `file = Capture.FileName(t, GetCVar("screenshotFormat"))` and stores it with `ns.DB.AppendCapture(opts.db(), record)`. `OnFailed()` (:122) prints "screenshot failed".
- `src/Core.lua:22-31` — wires `ns.capture = ns.Capture.New({...})`. `:54-66` routes `SCREENSHOT_SUCCEEDED` and `SCREENSHOT_FAILED` to the capture.
- `src/Triggers.lua:26` — `Triggers.Get(key)` returns the definition with its `label`.
- A batch is `{ events = { { trigger, name, unix, data }, ... } }` (`src/Debouncer.lua`, `src/Triggers.lua:147-163`).
- Tests: `spec/capture_spec.lua` (describe "events": records a capture on success, failure, manual screenshot, late success), harness `spec/helpers/wow.lua` (`wow.boot`, `wow.take(event, ...)`, `wow.fire`).
- Tooling: `make lint` (luacheck, gofmt, go vet, stylua `--check`), `make test` (busted on Lua 5.1, go test, release test), `make coverage` (Lua ≥ 80 %, Go ≥ 80 %). `.luacheckrc` lists globals in `read_globals`.
- Commits use Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`).
- The Memories API contract (from the Memories spec, Task 8): `Memories.RecordScreenshot(source, note, file)` returns `true`, or `false` and a reason (`"not ready"`, `"read only"`, `"off"`, `"bad source"`, `"bad note"`, `"bad file"`, `"rate limit"`, `"error"`). `file` must match `^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d%.%a%a%a%a?$`. The call never raises by design, but Paparazzi must not rely on that.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is cheap.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: `make coverage` (Lua ≥ 80 %, Go ≥ 80 %).
- E2E: No e2e suite; the user accepted a named manual check in the game (see Risks and Validation).

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention (Conventional Commits). Do not push.

## Tasks

### [x] 1. Call `Memories.RecordScreenshot` after each successful capture
- **Outcome:** Each Paparazzi screenshot reaches Memories as a note with its trigger labels and file name. Nothing changes when Memories is absent.
- **Depends on:** None. (Memories' Task 8 supplies the real API; the tests here use a stub.)
- **Covers:** AC1–AC8; all risks.
- **Files:** `src/Capture.lua` (`Capture.New`, `instance:OnSucceeded`, new `Capture.Note(events)`), `src/Core.lua` (wiring), `spec/capture_spec.lua`, `spec/core_spec.lua` (inspect: the integration test may fit better in a new `spec/memories_spec.lua`), `.luacheckrc` (`read_globals` gets `Memories`), `README.md` (a short "Works with Memories" section).
- **Implementation:**
  - Add `Capture.Note(events, labelOf)`: walk `events` in order, map each `event.trigger` to `labelOf(trigger)` (fallback: the trigger key), drop duplicates, join with `", "`. Return `nil` for an empty list.
  - Add an optional `opts.onCaptured(record)` to `Capture.New`. In `OnSucceeded`, after `ns.DB.AppendCapture(...)`, call `opts.onCaptured(record)` when it exists, inside `pcall`. Ignore its result.
  - In `src/Core.lua`, pass `onCaptured`:
    1. Read `local api = rawget(_G, "Memories")`. Return when `type(api) ~= "table"` or `type(api.RecordScreenshot) ~= "function"`.
    2. Build `note = ns.Capture.Note(record.events, function(key) local def = ns.Triggers.Get(key); return def and def.label end)`. Return when `note` is nil.
    3. `pcall(api.RecordScreenshot, ns.name, note, record.file)`. Ignore the result.
  - Do not print anything for a `false` result or an error.
  - Keep `OnFailed` as it is.
- **Edge cases:** `Memories` is nil; `Memories` is a number or a string; `Memories.RecordScreenshot` is nil or not a function; the API raises an error; the API returns `false, "rate limit"`; a batch with two events of the same trigger (one label); a batch with an unknown trigger key; a label with non-ASCII text (passed as it is); a manual screenshot; a failed screenshot; a success after the 3 s await timeout.
- **Tests:**
  - Unit (`spec/capture_spec.lua`): `Capture.Note` order, duplicates, unknown key fallback, empty list; `onCaptured` is called once with the stored record after `AppendCapture`; it is not called on failure, on a manual screenshot or after the timeout; an `onCaptured` that raises does not stop the capture from being stored, and the next capture still works.
  - Integration (boot with the harness, a stub `_G.Memories` that records calls): a "Level up" capture calls `RecordScreenshot("Paparazzi", "Level up", <file>)` with `<file>` equal to `PaparazziDB.captures[n].file`; with no `Memories` global, no error and the capture is stored; a stub that raises and a stub that returns `false` leave chat output unchanged.
- **Verify:** `make lint`, `make test`, `make coverage` (unverified). In the game (Forever, with Memories installed after its Task 8): level up or use `/paparazzi test`, `/reload`, then check that `Memories.lua` in the character's SavedVariables has an `sn` line with source `Paparazzi`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

1. `make lint && make test && make coverage` pass.
2. In WoW Forever with Paparazzi and Memories enabled: `/paparazzi test`, then `/reload`. Memories' character file has one `sn` line with source `Paparazzi`, a note and the same file name as the newest `PaparazziDB.captures` record.
3. With Memories disabled: `/paparazzi test` works as before, with no Lua error.
4. In Retail or Classic Era (no Memories): Paparazzi works as before.

## References

- Memories spec: `~/Code/wow-addon-memories/specs/2026-11-06-memories-addon-set.md` (Task 8: public API; Task 10: converter join of `sn` and `ss`).
- Blizzard UI source, branch `forever`: `Interface/AddOns/Blizzard_APIDocumentationGenerated/VideoDocumentation.lua` (`SCREENSHOT_SUCCEEDED`, no payload).

## Open Decisions

None.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the file is untracked). Create `specs/done/` if it does not exist. Commit the move.
