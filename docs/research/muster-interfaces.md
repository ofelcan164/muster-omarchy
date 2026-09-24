# What Muster offers a program outside herdr

An Omarchy plugin runs inside `omarchy-shell`, not inside herdr. It doesn't
get the environment herdr gives plugin commands (`HERDR_PLUGIN_STATE_DIR`,
`HERDR_SESSION`, `HERDR_SOCKET_PATH`). This page lists what Muster already
exposes that works from there, and what it would have to add. It was read from
`ofelcan164/muster` at `29c602f`.

## Finding the data

- **Where it lives.** herdr gives every plugin one state directory. For Muster
  that's `~/.local/state/herdr/plugins/muster/` (Muster's README).
- **Sessions share that directory.** A named session keeps its files under
  `sessions/<HERDR_SESSION>/` inside it. The default session uses the base
  directory.
- **Muster never guesses the path.** With neither `HERDR_PLUGIN_STATE_DIR` nor
  `--state-dir`, it fails with `ErrNoStateDir`. Both `muster` and `musterd`
  accept `--state-dir DIR` in front of the command, which is how the tab bar
  badge already runs outside the plugin environment.
- **So the widget must be told the base directory.** Default it to
  `~/.local/state/herdr/plugins/muster`, and let a setting override it. To
  cover every session, list `sessions/*/` as well as the base.

## Reading it

| Interface | What it gives | Notes |
|---|---|---|
| `musterd dump --json` | The whole snapshot | Muster's CLAUDE.md calls this "the supported way to read the snapshot". It spawns a process per read. |
| `snapshot.json` | The same, as a file | Written atomically on every reconcile (about every 5 s, sooner on events). Watching it with `FileView` costs nothing between changes, which is the `omarchy.agents` pattern. The file format is internal, not a promise. |
| `muster badge [letter]` | One line: `◆ 2 need you · prefix+m` | Reads files only, never the socket, and never starts a daemon. Counts come from the undismissed ribbon, so they agree with the overlay. Plain text only. |
| `ui.json` | Sort, dismissed rows, picked colours, strip height | Overlays share it under `ui.json.lock`. A widget that honours dismissals has to read `dismissed` here: the daemon's `attention` list doesn't know about them. |

The snapshot's top level has these fields:
- `generated_at`, `daemon_pid`, `herdr_version`
- `repos[]`: key, display name, colour index, sigil, branch, and agents with
  status, task, question, `depends_on`, `depends_on_repo` and `landed_at`
- `workspaces[]`
- `attention[]`: rank, reason, repo key, pane id, agent, status, age, detail,
  and dependents
- `orchestrator`: found, pane id, name, status, `last_said`, `said_at`,
  `detected_by`
- `focused_workspace`, `focused_pane`, `previous_agent`, `focus_history`
- `counts`

`generated_at` older than 30 s (`model.StaleAfter`) means the daemon isn't
running. The widget should treat that as "stale", not as "nothing needs you".

## Acting on it

| Want | Today | Gap |
|---|---|---|
| Jump to an agent | `muster jump <pane-id>` resolves the target and calls herdr's `pane.focus` over the socket | Two gaps. (1) From outside herdr it finds the socket by `HERDR_SOCKET_PATH`, falling back to `~/.config/herdr/herdr.sock`, which is only the default session's. A named session's socket path isn't documented in Muster; it needs checking. (2) Focusing the pane doesn't bring herdr's *window* forward. The widget has to do that in Hyprland. |
| Jump to the orchestrator | `muster jump orchestrator` | Same two gaps. |
| Tell the orchestrator something (`i`) | Only inside the overlay (`agent.prompt`, then `recordTold` writes the task token) | No CLI. Needs something like `muster tell "<text>"`. |
| Report a landed row (`t`) | Only inside the overlay | No CLI. Needs something like `muster report <pane-id>`. |
| Dismiss a ribbon row (`x`) | Only inside the overlay (writes `ui.json`) | No CLI. The widget could write `ui.json` itself under the lock, but that copies Muster's merge logic. A `muster dismiss <pane-id>` is safer. |
| Mark the orchestrator (`o`) | `muster mark-orchestrator` uses the pane in context; the overlay's `o` uses the selection | A widget has no pane context. Needs a pane argument. |
| Make sure the daemon runs | `muster discover`, or `musterd --ensure` | Both need the state directory and the socket. From outside herdr, pass `--state-dir`. The socket gap above applies. |

## Muster-side work this implies

Everything the widget does beyond displaying data should go through Muster's
CLI, not reimplement it in QML. Then the overlay and the widget can't disagree
about what a dismissal or a report means. The candidate additions:

1. `muster badge --json`: Waybar-style `{text, tooltip, class}`, with `class`
   of `needs-you`, `landed`, `working`, `idle` or `stale`. It enables phase 0 with
   no plugin at all.
2. `muster tell <text>`, `muster report <pane>` and `muster dismiss <pane>`,
   each a thin wrapper around what the overlay's `i`, `t` and `x` keys already do.
3. `muster mark-orchestrator <pane>`, an explicit pane argument.
4. A session argument (`--session NAME`), or a documented way to reach a named
   session's socket from outside herdr.
5. A stable, documented JSON shape for `musterd dump --json`, versioned
   separately from the internal snapshot, if the widget is to parse it.
