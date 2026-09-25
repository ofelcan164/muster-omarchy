# Implementation plan

The work is split into milestones M0–M5. Each milestone lists the repo it
lands in, its tasks, and when it is done. M0 and M1 are changes to
`ofelcan164/muster`; M2 to M5 are this repo. Background for every decision is
in [`research/`](research/).

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
- **Two plugins, two installs.** Muster is installed in herdr, through herdr's
  plugin install; this plugin is installed in Omarchy afterwards, through
  Omarchy's plugin marketplace. Neither writes the other's config: Muster
  knows nothing of Omarchy, and anything Omarchy-side (the widget, a
  keybinding, health checks) belongs to this plugin.
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
| Installation | Separate, each through its own tool's marketplace: Muster in herdr first, then this plugin in Omarchy. Muster never writes Omarchy's config and this plugin never writes herdr's. |
| Keybinding | `SUPER + CTRL + M` runs `omarchy-shell shell toggle io.github.ofelcan164.muster`, set up by this plugin (M4), never by Muster. |
| Notifications | None until M5, and then only for `LANDED` rows. |

## Spikes (run on an Omarchy 4 machine before M2)

Each spike answers one question with a command, and its result goes into
`research/`.

| # | Question | How to check |
|---|---|---|
| S1 | Named session socket path | `herdr --session x`, then `ls ~/.config/herdr/sessions/x/` and `env` inside a pane of it (`HERDR_SOCKET_PATH`). |
| S2 | Raising herdr's terminal window | `hyprctl clients -j`, then match `title` against Omarchy's `window_title = "{hostname}: {workspace}"`, then `hyprctl dispatch focuswindow address:<addr>`. Also read `jankeesvw/omarchy-herdr` `bin/` for its method. **Partly answered from source (M2 notes):** Omarchy 4's `hyprctl dispatch` takes Lua, so `focuswindow` is out; still to run on a machine. |
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
  - No Omarchy module in Muster's README: a module pasted into the bar by
    hand would be a third way in, around Omarchy's marketplace. The Omarchy
    side is this plugin. `badge --json` stays for any bar that wants it.
- **Done when:** the count matches the herdr tab bar badge.
- **Status:** released in Muster 0.3.0.

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
- **Status:** released in Muster 0.3.0, except `--session`, which waits on
  S1.

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

### M2 implementation notes

Built against `omacom/omarchy` `93e8cd5` and Muster `ea5b8d6`, and not yet
run on an Omarchy machine. The spikes are still open; where M2 depends on
one, it works either way:

- **S2, raising the window.** `jankeesvw/omarchy-herdr` shows that Omarchy
  4's `hyprctl` parses its argument as Lua, so the command is
  `hyprctl dispatch "hl.dsp.focus({ window = 'address:<addr>' })"`, after the
  same call with `workspace = '<name>'` so a window elsewhere comes into view.
  The window is found by walking each default-session `herdr` client up its
  process tree to the first pid Hyprland knows, not by title, which cannot
  tell the default session's window from a named one's. No window means `omarchy-launch-terminal-herdr`, which
  attaches to the server `muster jump` already moved. This lives in
  `bin/muster-omarchy`.
- **S3, whether `FileView` sees the rename.** Omarchy watches its own
  atomically written `shell.json` the same way, which suggests it does.
  Either way, the 5 s clock tick rereads a snapshot older than 12 s, so a
  missed rename costs a few seconds, not a stuck widget.

Decisions the plan left open:

- **When the widget hides.** Only while there is no snapshot file. Once there
  is one, the diamond stays in the bar, dim when nothing needs you, so the
  panel is always a click away. The keybinding (M4) was the only other way in.
- **Snapshots from before `snapshot_version`.** Read as version 0, the same
  shape as 1 without the field, so M2 works with today's Muster. A version
  newer than the widget knows asks you to update the widget
  (`omarchy plugin update`), since that is the side that is behind.
- **Finding `muster`.** herdr installs plugins outside `PATH`, so a bare
  `muster` that isn't on `PATH` falls back to the absolute path in the tab
  bar entry `muster install` writes to herdr's config.
- **Jump needs nothing from M1.** `muster --state-dir <s> jump <pane>`
  already works from a plain shell for the default session: Muster falls back
  to `~/.config/herdr/herdr.sock`.
- **Ribbon cap.** Four rows, as in the overlay, then "and N more in Muster".
- **Colours.** The reason, status and repo colours are Muster's own, so a
  row reads the same in both places. The panel's surface follows the Omarchy
  theme. The palette was picked for a dark background and may need a pass
  on light themes.

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

### M3 implementation notes

Built on the M1 commands, released in Muster 0.3.0, and not yet run on an
Omarchy machine.

- **Which row `t` reports** is the overlay's rule: the selected row when it is
  landed, else the only landed row, else nothing, with the overlay's notice.
- **`x` waits for the file.** The row leaves when Muster rewrites `ui.json`
  and the watch sees it, so the panel never shows a dismissal that failed.
- **A Muster from before M1** answers `unknown command`. The panel says to
  run the Update Muster action rather than showing Muster's usage text.
- **herdr not running.** Every command reports "herdr is not running" rather
  than a socket error. A jump also opens herdr with
  `omarchy-launch-terminal-herdr`, and says to jump again once the agents
  are back: the pane ids belong to the server that went away.

## M4: the keybinding, health and publishing (this repo)

This used to be `muster install --omarchy`, Muster writing Omarchy's
keybindings and `muster doctor` checking Omarchy. That tied the two installs
together, so it moved here: Muster stays a herdr plugin that knows nothing of
Omarchy.

- **Tasks:**
  - **The keybinding.** `omarchy plugin add` runs no install hook, so first
    find out whether Omarchy 4 lets a plugin declare a binding (in the
    manifest, or through a shell API). If it does, use that. If not, the
    README gives the one `o.bind` line to add to `~/.config/hypr/bindings.lua`
    rather than the plugin editing the user's Hyprland config.
  - **Health, in the panel.** The panel already says when there is no
    snapshot (Muster not installed or herdr not running) and when Muster is
    too old. Add: herdr's keys gone after `omarchy-refresh-herdr` (S5), with
    the fix being herdr's **Install Muster's keybindings** action. The check
    only reads herdr's config; it never writes it.
  - **Publishing.** Omarchy's marketplace lists public repos with a manifest,
    README, license, one category and one to three tags, after a security scan
    of an exact commit and a maintainer's approval. This repo is private, so
    making it public is the user's call; until then `omarchy plugin add
    <url>` is the install.
- **Done when:** a fresh Omarchy machine goes from nothing to working with
  `herdr plugin install ofelcan164/muster` and then installing this plugin
  from Omarchy's marketplace, and removing either one leaves the other
  working.

## M5: after M3 is in daily use

- **Notifications for `LANDED` rows:** `notify-send` with a jump action, off by
  default, controlled by a `notifyLanded` setting.
- **All sessions:** read `sessions/*/snapshot.json`, with a session switch in
  the panel. Needs `--session` from M1.
- **Pin mode:** only if needed alongside `jankeesvw.herdr`. If built, follow
  its model: drag by a handle, resize from a corner, geometry per screen in
  this widget's `shell.json` entry.
