# Implementation plan

The work is split into milestones M0–M5. Each milestone lists the repo it
lands in, its tasks, and when it is done. M0, M1 and M4 are changes to
`ofelcan164/muster`; M2, M3 and M5 are this repo. Background for every
decision is in [`research/`](research/).

## Architecture

```
herdr ──events──▶ musterd ──writes──▶ <state>/snapshot.json, <state>/ui.json
                                              │ FileView (no polling)
                           Omarchy plugin ◀───┘
                                 │ Process
                                 ├──▶ muster --state-dir <state> jump|tell|report|dismiss
                                 └──▶ hyprctl (raise herdr's window)
```

- **The plugin holds no herdr connection and no state of its own.** Ranking,
  dismissals, colours and the orchestrator all come from Muster's files.
- **Every action is a `muster` CLI call**, so the overlay and the widget share
  one implementation.
- `<state>` is `~/.local/state/herdr/plugins/muster`, overridable by the
  `stateDir` setting. M1–M4 use the default herdr session only.

## Settled decisions

| Decision | Choice |
|---|---|
| Plugin id | `io.github.ofelcan164.muster` |
| Code location | This repo, with `manifest.json` at the root. `omarchy plugin add` clones the whole repo and rejects symlinks, so the plugin can't live inside the Muster repo. |
| Kinds | `bar-widget` only. The panel is loaded by the widget, as in `omarchy-hypr-rules-studio`. |
| Data source | `FileView` on `snapshot.json` and `ui.json`. Muster adds `snapshot_version` (M1). The widget shows "update Muster" for any version it doesn't know. |
| Staleness | `now - generated_at > 30s` shows a stale state, never a count. |
| Keybinding | `SUPER + CTRL + M` runs `omarchy-shell shell toggle io.github.ofelcan164.muster`, written by `muster install --omarchy` (M4). |
| Notifications | None until M5, and then only for `LANDED` rows. |

## Spikes (run on an Omarchy 4 machine before M2)

Each spike answers one question with a command, and its result goes into
`research/`.

| # | Question | How to check |
|---|---|---|
| S1 | Named session socket path | `herdr --session x`, then `ls ~/.config/herdr/sessions/x/` and `env` inside a pane of it (`HERDR_SOCKET_PATH`). |
| S2 | Raising herdr's terminal window | `hyprctl clients -j`, then match `title` against Omarchy's `window_title = "{hostname}: {workspace}"`, then `hyprctl dispatch focuswindow address:<addr>`. Also read `jankeesvw/omarchy-herdr` `bin/` for its method. |
| S3 | Whether `FileView` sees atomic rename-over writes | A minimal QML `FileView { path: …/snapshot.json; watchChanges: true }` that logs `onFileChanged` while `musterd` runs. |
| S4 | Muster's key install under Omarchy's `prefix = "ctrl+space"` and existing `tab_bar_right` | `muster install` on the Omarchy default config, then `herdr config check`, then check that `muster badge` shows in the tab bar. |
| S5 | How long keys are gone after `omarchy-refresh-herdr` | Run it, try `ctrl+space m`, restart herdr, try again. |

## M0: `muster badge --json` (muster repo)

- **Tasks:**
  - `cmd/muster`: `badge` accepts `--json`.
  - `internal/ui`: add `BadgeJSON(letter) string` next to `Badge`. It returns
    `{"text","tooltip","class"}`:
    - `text` is the same as `Badge`, without the key hint;
    - `tooltip` is one line per undismissed ribbon row, formatted
      `REASON repo/agent · detail`, capped at `triage.RibbonMax`;
    - `class` is the first of these that applies: `stale`, `landed`,
      `needs-you`, `working`, `idle`.
  - Tests: one per class, a stale snapshot, dismissed rows excluded, and
    output that parses as JSON.
  - README: an inline Omarchy bar module:
    ```json
    { "id": "muster", "type": "command",
      "exec": "muster --state-dir ~/.local/state/herdr/plugins/muster badge --json",
      "interval": 5, "onClick": "omarchy-launch-terminal-herdr" }
    ```
- **Done when:** that module shows in the Omarchy bar, and the count matches
  the herdr tab bar badge.

## M1: CLI for an outside caller (muster repo)

- **Tasks:**
  - Add `snapshot_version` (int, starting at 1) to `model.Snapshot`, and
    document the fields the widget relies on in Muster's `docs/`.
  - `muster tell <text>`: the overlay's `i` path (`agent.prompt` then
    `recordTold`), extracted from `internal/ui` so both callers share it.
  - `muster report <pane>`: the overlay's `t` path, extracted the same way.
  - `muster dismiss <pane>`: the overlay's `x` path, with the write to
    `ui.json` done through `state.UIState.Save`.
  - `muster mark-orchestrator [pane]`: an explicit pane that wins over the
    context pane.
  - `--session NAME` on `muster` and `musterd`, which selects
    `sessions/NAME/` and that session's socket (path from S1).
  - Tests for each command against a fake socket, as the existing `ui` tests
    do with injected prompters.
- **Done when:** each of `jump <pane>`, `jump orchestrator`, `tell`, `report`,
  `dismiss` works from a plain shell with only `--state-dir`, with no herdr
  environment.

## M2: bar widget and read-only panel (this repo)

- **Files:**
  ```
  manifest.json      kinds ["bar-widget"], entryPoints.barWidget "BarWidget.qml"
  BarWidget.qml      icon, count and colour class, opens the panel
  Panel.qml          ribbon, orchestrator strip, repo list; IpcHandler open|close|toggle
  Data.qml           FileView on snapshot.json and ui.json, parsing, the stale timer
  Actions.qml        one Process queue for muster and hyprctl calls
  README.md, LICENSE
  ```
- **Manifest `barWidget` block:** `defaultSection "right"`,
  `allowMultiple false`, and `defaults { "stateDir": "", "muster": "muster" }`.
  An empty `stateDir` means the default path. The schema has a `path` entry
  for `stateDir` and a `string` entry for `muster`, the binary to run.
- **Bar widget:**
  - hidden when there's no snapshot file and nothing needs you;
  - the ribbon count otherwise, coloured by the top row's reason;
  - a stale glyph when the snapshot is stale.
- **Panel:**
  1. The ribbon, in snapshot order, minus rows whose `ui.json`
     `dismissed[pane] == status`.
  2. The orchestrator: sigil and repo, status and age, `last_said` on two
     lines, and the said age. "None marked" when `found` is false.
  3. One row per repo: sigil in its colour, display name, and counts by
     status.
- **Click a ribbon or orchestrator row:** run `muster --state-dir <s> jump
  <pane>`, then raise the herdr window (S2 method). Keys: `j`/`k` move,
  `Enter` jumps, `Esc` closes.
- **Repo colours:** port `identity.Palette` (`internal/identity/identity.go`)
  to QML, indexed by `color_index`, overridden by `ui.json` `colors`.
- **Validate** with `omarchy plugin validate .`.
- **Done when:** installed with `omarchy plugin add <this repo> --enable`, it
  shows the same ribbon, orchestrator and counts as Muster's overlay, and a
  click lands on the pane.

## M3: actions in the panel (this repo)

- **Keys:**

  | Key | Command |
  |---|---|
  | `i` | Opens a one-line input, then runs `muster tell <text>` |
  | `t` | `muster report <pane>` on the selected `LANDED` row |
  | `x` | `muster dismiss <pane>` |
  | `M` | `muster jump orchestrator` plus a window raise |

- **Errors:** a failed command shows its stderr on the panel's last line,
  which is the overlay's notice line.
- **Done when:** each action changes what Muster's overlay shows, and vice
  versa, within one refresh.

## M4: `muster install --omarchy` (muster repo)

- **Tasks:**
  - Detect Omarchy: `$OMARCHY_PATH` is set, or `omarchy-shell` is on `PATH`.
  - Write a marked block to `~/.config/hypr/bindings.lua` containing the
    `o.bind` line, with a backup, matching how Muster writes the herdr config.
  - `uninstall` removes the block.
  - `muster doctor` reports:
    - whether the plugin is installed (`omarchy plugin list --json`);
    - whether the bindings block is present;
    - whether the herdr keys are missing after an `omarchy-refresh-herdr`
      (S5), with the fix being `muster install`.
- **Done when:** a fresh Omarchy machine goes from nothing to working with
  `omarchy plugin add … --enable` and `muster install --omarchy`, and back
  with `muster uninstall`.

## M5: after M3 is in daily use

- **Notifications for `LANDED` rows:** `notify-send` with a jump action, off by
  default, controlled by a `notifyLanded` setting.
- **All sessions:** read `sessions/*/snapshot.json`, with a session switch in
  the panel. Needs `--session` from M1.
- **Pin mode:** only if needed alongside `jankeesvw.herdr`. If built, follow
  its model: drag by a handle, resize from a corner, geometry per screen in
  this widget's `shell.json` entry.
