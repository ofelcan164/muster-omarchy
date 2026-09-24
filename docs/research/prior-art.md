# Prior art: herdr on the Omarchy desktop

Omarchy's own manual says to browse the plugin directory "before you start".
This does that. Source: `site/catalog.json` in
`omacom/omarchy-plugin-marketplace`, 4110 plugins, cloned 2026-09-24. I
searched it for "herdr", then read the READMEs of the four plugins closest to
this idea at the commits listed in the repo README. Star counts are from the
catalog and only show relative interest.

## The short version

The bar-and-panel agent monitor for herdr is a solved problem, solved several
times over, and solved well:
- counts in the bar, coloured by the most urgent agent;
- a panel listing every agent;
- click to jump to the exact pane;
- desktop notifications when something finishes or asks a question;
- remote sessions over SSH;
- a panel you can pin to the desktop and resize.

None of them models:
- **Which repo** an agent works in, as a stable identity (colour and sigil)
  shared with another view.
- **A ranking of what needs you** with **dismissals** that persist and agree
  with what you see inside herdr.
- **An orchestrator:** who is coordinating, what it last said and how long
  ago, and a way to send it a message.
- **Dependencies between repos:** this agent depends on `api#412`, that PR
  landed, and the dependent agent hasn't moved since.

That list is Muster. It's the only reason for this plugin to exist.

## The four closest

### jankeesvw.herdr ("Herdr for Omarchy"): 51 stars, the most popular

- **Bar:** a count of running herdr *servers*, with a badge coloured red
  (needs you), green (done, unseen) or amber (working). It disappears when all
  are idle.
- **Panel:** one row per session, each agent under it with a status word,
  ordered by state as herdr's own `agent_panel_sort = "priority"` does. A
  "done" line clears once clicked.
- **Pin mode:** click the pin (or press `p`) and the card becomes a floating
  window on every workspace. It moves by a handle, resizes from the corner,
  and remembers its position, size and screen in its own `shell.json` entry.
  This is the "popped-out Muster" idea, already built and thought through.
- **Actions:** it can also stop or delete herdr servers.
- **Refresh:** every 3 s while open, every 20 s while closed.
- **What an agent is doing:** its terminal title.

### stappmus.udder ("Udder"): 4 stars, notifications done well

- **Bar:** a cow. The panel shows who is working, idle, asking, or done.
- **Jump:** click an agent to reach the exact pane, on the right desktop.
- **Notifications:** one notification when work finishes while you're away,
  with herdr's completion chime. Clicking it returns you to the agent.
- **Remote sessions:** asks before tracking a `herdr --remote` session, then
  keeps an SSH connection to it.
- **Data:** event-driven. It registers a herdr plugin (`herdr-plugin.toml`)
  whose hook runs only on agent lifecycle events, and it doesn't poll the
  local server in the background. It sets that bridge up from QML on first
  load, which shows how to work around Omarchy's lack of install hooks.

### njpatel.omaherdr ("Omaherdr"): 8 stars, closest to Muster's attention model

- **Discovery:** finds every herdr the desktop is attached to (plain,
  `--session`, `--remote`) by inspecting terminal processes.
- **Status:** subscribes to herdr events, so it updates live.
- **Bar:** traffic lights with counts.
- **Panel keys:**
  - `/` filters;
  - `v` cycles between an agents, spaces and **attention** view;
  - `s` snoozes, `m` mutes a workspace;
  - notifications are off by default and toggled with `n`.
- **Attention** is waiting-or-done, with snooze and mute. That overlaps with
  Muster's ribbon and dismissals, but it keeps its own state that Muster can't
  see.

### meviusisback.agent-orchestr ("Agent Orchestrator"): 16 stars

- **Sources:** tracks herdr panes plus several other agent tools (OMP, Hermes,
  Grok, standalone terminals).
- **Panel:** filter tabs, rich cards (model, latest prompt, tool activity),
  and buttons to kill a process or close a pane.
- **Refresh:** polls every second while active.
- Despite the name, it has **no orchestrator concept**: "orchestrator" means
  managing workspaces, not a coordinating agent.

## Everything else that mentions herdr

| id | What it is |
|---|---|
| `io.github.fabean.herdr` | Agent activity and status in the bar (11 stars, verified) |
| `mrpbennett.herdr-agents` | Every agent's state, activity and workspace; click to focus |
| `io.github.eszanon.herdr` | Agents in the bar, flags the ones waiting on you |
| `brownfamilysports.crook` | "Which coding agent under herdr needs you, on the Omarchy bar" |
| `io.github.salemsayed.omaherd` | Local and remote herdr "attention inbox" |
| `io.github.jeremylongshore.crew-chief` | A local attention queue fed by Claude Code, Codex, herdr |
| `io.github.joshuaswarren.fleet-shepherd` | Read-only herdr operations across local and SSH machines |
| `andreconde.herdr` | Workspace monitor with agent status, click to focus |
| `finna.herdr-hud`, `indie.herdr-hud` | Prompt and monitor agents from a gaming HUD |
| `io.github.pjgeutjens.feed-the-flock` | Capture notes and feed them to herdr agents |
| `yordanbuilds.rig` | Bring up a herdr workspace from a small JSON "stack" file |
| `anagrius.resume` | Resume a past AI session in herdr |
| `io.github.andy-spike.herdr-theme-sync` | Keep herdr's colours in sync with the Omarchy theme |
| `io.github.wbarakat.session-restore`, `io.github.dmitry-solomadin.desktop-restore` | Restore windows and herdr sessions after a reboot |
| `keybind-manager` | Rebind Hyprland or herdr keys, with conflict warnings |
| `daocoding.claude-agent` | Claude Code state from hooks rather than screen scraping |
| `adam.codex-threads` | A herdr *replacement* built from native windows |

Also relevant, though not about herdr: the first-party `omarchy.agents` shows
subscription usage and rate limits, and several plugins do the same
(`othavi0.agent-bar`, `robzolkos.agent-usage`, and others). That's a different
question ("how much have I spent?") from Muster's ("what needs me?").

## What this means for the plan

1. **Don't build a generic agent monitor.** Every feature on the "solved"
   list is taken. A Muster widget that competes on those terms loses to a
   51-star plugin that has had a month of polish.
2. **Build only on what Muster knows.** The plugin should be a display of
   Muster's snapshot, so what it shows is by definition what the others can't:
   - repo identity;
   - the ranked ribbon and its dismissals;
   - the orchestrator strip;
   - dependency edges and `LANDED` rows.
3. **Coexist rather than replace.** Someone may well run jankeesvw's panel for
   sessions and Udder for notifications. Ours should add no herdr connection
   and no notification spam of its own by default. Its notifications, if any,
   should be about things only Muster knows, such as a `LANDED` row.
4. **Borrow freely.**
   - jankeesvw's pin-mode behaviour: handle-only drag, remembered geometry per
     screen, focus-only accent border.
   - Udder's QML-registered herdr bridge, as the pattern for first-run setup.
   - Omaherdr's approach to finding which herdr sessions exist.
