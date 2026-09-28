# Omarchy 4 shell plugins

How the Omarchy desktop is extended as of Omarchy 4 ("Quattro"). Read from
`omacom/omarchy` at `28ceaae`: `manual/32-shell-plugins.md`,
`docs/omarchy-shell.md`, `agents/skills/shell-dev.md`, `shell/plugins/README.md`
and the plugins themselves.

## Waybar is gone

Before Omarchy 4, a bar module meant Waybar. That no longer applies. The
desktop is now one long-running [Quickshell](https://quickshell.org/) process,
`omarchy-shell`, and "almost everything you see on screen is a plugin inside
it": the bar, the panels that drop from it, the overlays, the Omarchy menu, the
lock screen, the polkit dialog, notifications. There is no `config/waybar` in
the repo any more.

Hyprland's config also moved from `.conf` to Lua in Omarchy 4. Anything that
edits keybindings or window rules has to target the Lua files (below).

## What a plugin is

A git repo with a `manifest.json` at its root and some QML. The contract, from
`docs/omarchy-shell.md`:

```json
{
  "schemaVersion": 1,
  "id": "my.org.cool-clock",
  "name": "Cool clock",
  "version": "1.0.0",
  "author": "You",
  "description": "A clock that does cool things",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "Cool clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "left",
    "defaults": { "format": "HH:mm" },
    "schema": [ { "key": "format", "type": "string", "label": "Format" } ]
  }
}
```

`kinds` (a plugin may declare several; the media plugin is both `service` and
`bar-widget`):

| Kind | What it is |
|---|---|
| `bar-widget` | A component the active bar drops into a section |
| `panel` | A persistent or summoned floating window |
| `overlay` | A fullscreen overlay |
| `menu` | A summoned menu surface |
| `service` | A headless singleton with no UI |
| `bar` | A full bar that replaces the built-in one |

Other manifest keys seen in practice:
- `activation: "on-demand"`;
- `keepLoaded: true`, which survives between summons and keeps a service mounted across hot reload;
- `license`;
- `barWidget.aliases`;
- a `barWidget.schema` whose entries have `type` `integer`, `enum`, `path` or `string`, with `min`, `max`, `step` and `options`.

Validate with `omarchy plugin validate ./dir`. It checks:
- the schema version and required fields;
- that the id is not in the reserved `omarchy.` namespace;
- that entry points are safe relative paths that exist, with one for every kind claimed;
- that there are no symlinks inside the folder.

Entry points are QML `Item`s, not `ShellRoot`. Panel, overlay and menu entry
points expose `open(payloadJson)` and `close()`. The host injects
`omarchyPath`, `shell`, `manifest` and the registries.

## Where plugins live and how they are enabled

- First-party: `$OMARCHY_PATH/shell/plugins/`.
- Third-party: `~/.config/omarchy/plugins/<id>/`.
- Enabled state lives in `~/.config/omarchy/shell.json`. A third-party
  plugin is enabled exactly when its id appears there: in `bar.layout.<section>`
  for a bar widget, in `plugins[]` otherwise.
- `omarchy plugin add <git-url> [--enable]` clones into a staging directory,
  validates, and moves the result into place. It **never runs anything from the
  plugin, never executes an install hook, never asks for sudo**. Updates are a
  fast-forward pull that shows the diff first (`omarchy plugin update [id]`).
  `omarchy plugin remove <id>` disables and then deletes.
- Saving any file under `~/.config/omarchy/plugins/` hot-reloads that plugin.
  Hand-installed plugins need `omarchy-shell shell rescanPlugins`.
- Per-widget settings are inline on the widget's entry in `shell.json`, set
  with `omarchy bar set <id> <key> <value> [--json]`.

Consequence for us: **there is no install hook.** Anything the plugin needs
beyond its own files has to be set up some other way: on first load from QML,
by a command the user runs, or by Muster's own installer. Udder, for example,
registers its herdr event bridge from QML on first load, behind a setting you
can turn off.

## Trust model

Plugins are unsandboxed code in the shell process, with the user's full file
and process access. Third-party plugins get "capability-scoped facades"
(their own service and lifecycle, detached bar state) rather than the trusted
host objects. The docs are explicit that these are API boundaries, not a
sandbox. Running external commands from QML (Quickshell's `Process`) and
watching files (`FileView`) are both normal. The first-party `omarchy.agents`
plugin does both.

## Talking to a running shell

`omarchy-shell` is the IPC entry point. The `shell` target has `ping`,
`summon <id> <payload>`, `hide <id>`, `toggle <id> <payload>`,
`call <id> <method> <arg>`, `rescanPlugins`, `reloadConfig`,
`setPluginEnabled`, `listPlugins`, `putBarWidget`, `moveBarWidget` and
`setBarWidget`. Plugins register their own targets named after the plugin. For
example, `omarchy.agents` registers `open|close|toggle|refresh|next` through a
QML `IpcHandler`.

Built-in keybindings toggle panels this way. From
`default/hypr/bindings/utilities.lua`:

```lua
o.bind("SUPER + CTRL + A", "Audio", "omarchy-shell shell toggle omarchy.audio")
```

## Keybindings and window rules (Lua)

User files are `~/.config/hypr/{hyprland,bindings,autostart,input,looknfeel,monitors}.lua`.
`bindings.lua` is where personal bindings go:

```lua
o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")  -- add
o.rebind("SUPER + SHIFT + F", "File manager", { launch = "flea" })   -- replace
hl.unbind("SUPER + SHIFT + B")                                        -- remove
```

`default/hypr/helpers.lua` defines `o.bind`, `o.bind_toggle` and a window-rule
helper that calls `hl.window_rule`. Muster's key would be one `o.bind` line
calling `omarchy-shell shell toggle <our id>`. We don't need a window rule: a
shell panel is a layer-shell surface, not a Hyprland client.

## Bar modules without a plugin

For small things, `shell.json` accepts inline modules. This is the direct
replacement for a Waybar custom module:

```json
{ "id": "vpn", "type": "command", "exec": "~/.config/omarchy/bar/scripts/vpn-status",
  "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" }
```

Output is plain text or **Waybar-style JSON** (`{ "text", "tooltip", "class" }`).
There is also `{ "id": "gpu", "type": "qml" }`, which loads
`~/.config/omarchy/bar/modules/gpu.qml`. That component receives `bar`, with
`run(cmd)`, `showTooltip` and `requestPopout`.

This matters for phase 0 of the plan: a `muster badge --json` plus one inline
entry gets Muster into the bar with no plugin at all.

## Notifications

Omarchy 4 has its own notification daemon, the first-party
`omarchy.notifications` service. It is a Quickshell `NotificationServer` with
`actionsSupported: true`, so a standard `notify-send` with actions shows up
and can call back when clicked. Udder uses this to make "agent finished"
notifications jump to the agent.

## A pattern worth copying: `omarchy.agents`

The first-party Agents widget (`shell/plugins/agents/`) shows AI subscription
usage and limits. It is not about what each agent is doing, so it doesn't
overlap with Muster. Its structure is the one we want:

- A collector (`omarchy-agent-usage-update`) writes one JSON record per
  agent into `~/.local/state/omarchy/agents/usage/`.
- The widget is "strictly a display". It lists that directory and watches each
  file with `FileView`, running the collector only on a timer or when you
  ask it to refresh.
- It hides itself entirely when there is nothing to show, which is why it can
  ship in the default bar.

Muster already works this way. `musterd` is the collector and
`snapshot.json` is the record. A widget that is strictly a display over
Muster's snapshot fits the platform's own idiom.

## Publishing

A public git repo is the whole distribution mechanism. Listing is optional,
through the marketplace at omarchyplugins.com (`omacom/omarchy-plugin-marketplace`).
New listings need a public repo with a manifest, README and license, one
category and one to three tags, an automated security scan of an exact commit,
and a maintainer's approval. Install and update still clone mutable upstream
HEAD. The steps left for this repo are in the plan's M4.
