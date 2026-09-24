# herdr in Omarchy

Omarchy doesn't just tolerate herdr: it installs and configures it. That makes
Omarchy the most likely desktop for a Muster user, and it creates two points
where the two could collide. Read from `omacom/omarchy` at `28ceaae`.

## What Omarchy ships

- **The package.** `herdr` is in `install/omarchy-base.packages`, and
  migration `1786273938.sh` installs it from the Omarchy package repo on
  existing machines. The manual (`21-tuis.md`) links herdr's repo under
  `omacom-io`, the same organisation as Omarchy.
- **A config.** `config/herdr/config.toml` is copied to
  `~/.config/herdr/config.toml` only if you don't already have one ("Only
  seed").
- **Keybindings.**
  - `SUPER + CTRL + RETURN` launches or attaches to the persistent session
    (`omarchy-launch-terminal-herdr` runs `omarchy-launch-terminal herdr`).
  - `SUPER + CTRL + K` shows the herdr keybindings.
- **Commands.**
  - `omarchy-restart-herdr` reloads a running server's config.
  - `omarchy-refresh-herdr` **overwrites** the user's herdr config with
    Omarchy's default, then reloads it.
- **Shell functions** in `default/bash/fns/herdr`, all built on the herdr CLI
  (`herdr pane split|run`, `herdr tab create|rename`,
  `herdr workspace rename`):
  - `hdl`: editor, AI and terminal layout;
  - `hdlm`: one `hdl` tab per subdirectory;
  - `hds`: a four-pane square;
  - `hsl <n> <cmd>`: a swarm of *n* panes all running the same command.

  `hsl` is exactly the many-agents workflow Muster exists for.
- **An alias**, `h` for `herdr`.

## The shipped herdr config, as it affects Muster

| Setting | Value | What it means for Muster |
|---|---|---|
| `keys.prefix` | `ctrl+space` | Muster's keys become `ctrl+space m`, `ctrl+space shift+m` and `ctrl+space ctrl+m`. The config binds nothing on `m`, so Muster's first-choice letter is free. Check `shift+m` and `ctrl+m` with `herdr config check`, the way `muster install` already does. |
| `ui.tab_bar_right` | `[{ type = "zoom" }, { type = "hostname" }]` | The user already has a `tab_bar_right`. Muster's installer handles exactly this case: it puts its badge entry at the front of the user's own array, outside the marked block, and takes back that exact entry on uninstall. Worth one real test on an Omarchy config. |
| `ui.mouse_capture` | `true` | Needed for Muster's clicks, hover and the new strip drag to reach the popup. |
| `ui.window_title` | `"{hostname}: {workspace}"` | The Hyprland window title of herdr's terminal. A widget that raises that window can match on it. |

## Two collisions to design around

1. **`omarchy-refresh-herdr` wipes Muster's block.** It replaces the whole
   config file, so Muster's key bindings and the badge entry disappear. The
   startup hook (`muster install --auto`) puts them back the next time herdr
   starts, but `omarchy-refresh-herdr` only reloads the config and doesn't
   restart herdr. So until the next restart, the keys are gone. Options:
   - document "run `muster install` after refreshing";
   - have the Omarchy plugin notice the missing block and offer to reinstall;
   - ask Omarchy to re-run plugin startup hooks after a refresh.
2. **Two things may watch the same herdr server.** If an Omarchy herdr
   widget from the prior art is also installed, a second event subscription
   and polling loop runs alongside `musterd`. That's harmless but wasteful.
   Our plugin should add no herdr connection of its own and read only what
   `musterd` writes (see the plan).

## Raising herdr's window

Jumping to an agent from outside herdr takes two steps: focus the pane inside
herdr (over its socket), then bring herdr's terminal window forward in
Hyprland. Prior art shows both halves:
- jankeesvw's plugin finds the window already showing a session and focuses it, and starts one in `foot` if there is none;
- Udder moves you to the right desktop.

Omarchy's own `omarchy-launch-terminal-herdr` attaches to the persistent session, which is a reasonable fallback when no window exists.
