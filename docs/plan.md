# Plan

## Goal

Put Muster's picture of your agents on the Omarchy desktop: what needs you,
in order; what the orchestrator last said; which work has landed that
something else is waiting on. It should be glanceable from the bar and
actionable from a panel, without first switching to herdr.

## Non-goals

- **A generic herdr agent monitor.** Twelve exist; see
  [prior art](research/prior-art.md). If a feature is on that page's "solved"
  list and has nothing to do with Muster's model, it isn't ours to build.
- **A second connection to herdr.** `musterd` already holds one event
  subscription per session. The plugin reads what `musterd` writes and acts
  through Muster's CLI.
- **Its own idea of attention, dismissals, colours or the orchestrator.**
  Muster's overlay and the widget must never disagree, so the widget owns
  none of that state.
- **Replacing the herdr popup.** Typing to agents, the full grid and the
  keyboard flow stay in Muster's overlay.

## Shape

```
herdr server ──events──▶ musterd ──writes──▶ snapshot.json, ui.json
                                                   │
                         Omarchy shell plugin ◀────┘  (FileView watch; display only)
                                   │
                                   └──actions──▶ muster CLI ──▶ herdr socket
                                                 (jump, tell, report, dismiss)
                                   └──raise window──▶ Hyprland
```

This is how Omarchy's own `omarchy.agents` widget works: a collector writes
records and the widget is "strictly a display" (see
[Omarchy shell plugins](research/omarchy-shell-plugins.md)).

## Phases

Each phase is only worth starting if the one before it got used.

### Phase 0: no plugin (Muster-side only)

- Add `muster badge --json` to Muster, returning Waybar-style
  `{text, tooltip, class}`. The tooltip carries the ribbon rows.
- Document a one-line inline bar module for `~/.config/omarchy/shell.json`:
  `{ "id": "muster", "type": "command", "exec": "muster --state-dir … badge --json", "interval": 5, "onClick": "omarchy-launch-terminal-herdr" }`.
- Cost: a small change to `Badge`, and a README section.
- **What it proves:** whether you look at Muster's count from the desktop at all.

### Phase 1: a bar widget with a drop-down panel (read-only)

- **Bar:** Muster's badge, coloured by the top ribbon row (red for blocked, the landed colour for `LANDED`). It hides when nothing needs you, and says "stale" when `generated_at` is older than 30 s.
- **Panel:**
  1. The ribbon, in Muster's order, minus rows dismissed in `ui.json`.
  2. The orchestrator strip: who, status, last said, and how long ago.
  3. One line per repo with its sigil and colour, and counts by status.
- **Click a row:** run `muster jump <pane>`, then raise herdr's window in
  Hyprland.
- **Data:** a `FileView` on `snapshot.json` and `ui.json`, with no polling.
- **Keybinding:** a line for `~/.config/hypr/bindings.lua`, as in
  `o.bind("SUPER + CTRL + M", "Muster", "omarchy-shell shell toggle <id>")`.
  Check `omarchy menu keybindings --print` for a free chord first.

### Phase 2: act from the panel

Each action needs a Muster CLI command first
(see [Muster interfaces](research/muster-interfaces.md)):

| Action | Key | Muster command |
|---|---|---|
| Message the orchestrator | `i` | `muster tell <text>` |
| Tell it a landed row landed | `t` | `muster report <pane>` |
| Dismiss a ribbon row | `x` | `muster dismiss <pane>` |
| Jump to the orchestrator | `M` | `muster jump orchestrator` |

The keys match the overlay's, so muscle memory carries over.

### Phase 3: only if still wanted

- **Pin mode.** Only if jankeesvw's pinned card doesn't already cover the
  need alongside this plugin. If built, copy its behaviour: drag by a handle
  only, resize from a corner, remember geometry per screen in the widget's
  `shell.json` entry, and show the accent border only while focused.
- **Notifications about Muster-only events, off by default.** A `LANDED` row
  appearing; the orchestrator ending a turn with a new message. Nothing about
  plain "blocked" or "done": Udder and others already do that, and doubling up
  is noise.
- **Every herdr session at once.** Read `sessions/*/snapshot.json` too, with a
  session switch in the panel.

## Decisions to make

| Decision | Options | Recommendation |
|---|---|---|
| How the widget reads the snapshot | (a) `FileView` on `snapshot.json`; (b) run `musterd dump --json` | (a) for cost, which is the platform's idiom. It needs Muster to promise the file's shape, or a versioned `dump --json` shape to validate against. |
| Where the plugin's code lives | (a) this repo, later public; (b) a subdirectory of the Muster repo; (c) the root of the Muster repo, next to `herdr-plugin.toml`, as Udder does | (a). `omarchy plugin add` clones the whole repo into `~/.config/omarchy/plugins/<id>/` and rejects any symlink in it, so (c) would clone all of Muster's Go source into the shell's plugin directory. (b) isn't installable by `omarchy plugin add`. |
| Plugin id | Namespaced like the prior art, e.g. `io.github.ofelcan164.muster` | Decide before the first `shell.json` entry exists, because renaming later strands settings. |
| Default session | Default session only, or all | Default only in phase 1, which matches `musterd dump` from a plain shell. |
| First-run setup | No install hooks exist. Options: document the steps; do them from QML on first load (Udder's pattern); or add `muster install --omarchy` | `muster install --omarchy`: Muster already owns "the only code that writes files the user owns", so writing the `bindings.lua` line and the `shell.json` entry belongs there, with the same marked-block discipline. |

## Open questions to answer on a real Omarchy machine

1. Where is a named herdr session's socket? `muster jump` falls back to
   `~/.config/herdr/herdr.sock`, which is only the default session's.
2. How best to find and raise herdr's terminal window in Hyprland. Match on
   the `window_title` Omarchy sets (`"{hostname}: {workspace}"`), or copy
   jankeesvw's approach.
3. Does `FileView` see Muster's atomic rename-over writes of `snapshot.json`?
   `omarchy.agents` watches files written the same way, but confirm it.
4. Does Muster's key installer choose cleanly under Omarchy's
   `prefix = "ctrl+space"`, and insert its badge into Omarchy's existing
   `tab_bar_right` as designed?
5. After `omarchy-refresh-herdr` overwrites the herdr config, how long are
   Muster's keys gone in practice, and should the widget offer to reinstall
   them? (See [herdr in Omarchy](research/omarchy-herdr.md).)
6. Does the orchestrator strip earn its place in a bar panel, or does it only
   matter while you're inside herdr?

## Go / no-go

After phase 0 has run for a week or so:

- **Go** if you notice the bar count and act on it, and you find yourself
  wanting the orchestrator's last line or `LANDED` rows without opening herdr.
- **Stop** if jankeesvw's panel (or Udder's notifications) plus Muster's
  existing tab bar badge already covers it. Then Muster's Omarchy story is
  "phase 0 and a README section", which is a fine outcome.

## Risks

- **Omarchy 4 is new.** The shipped `version` file reads `4.0.0.alpha`, and
  the plugin API and facades are changing fast. Keep the QML small, and keep
  the logic in Muster where it's tested.
- **Coupling to Muster's snapshot.** A widget that parses internal JSON breaks
  on a shape change. That's the argument for a versioned `dump --json`, or for
  Muster owning the widget's data contract outright.
- **The trust ask.** Users install unsandboxed code into their shell. A
  display-only widget that shells out to one known binary is an easy review,
  so keep it that way.
