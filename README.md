# muster-omarchy

An Omarchy shell plugin that brings
[Muster](https://github.com/ofelcan164/muster)'s view of herdr agents out of
the herdr popup and onto the desktop.

**Status: M2 written, not yet tried on an Omarchy machine.** The bar widget
and read-only panel are here and tested headless; see [the plan](docs/plan.md)
for what is next.

## The idea in one paragraph

Muster is a herdr plugin: an overlay you open inside herdr that shows every
agent across every repo, ranks what needs you, and keeps the orchestrator and
the dependencies between repos in view. That overlay is modal, and you only see
it once you have opened it. This plugin would put the same picture in the
Omarchy bar and in a panel that drops from it, so you can see what needs you
without first switching to herdr.

## The finding that shapes everything

A dozen Omarchy plugins already show herdr agents in the bar, and the best of
them are good: counts and colours, click to jump, desktop notifications,
remote sessions, a pinned floating card. A plugin that only lists agents would
be the thirteenth. What none of them has is what Muster already works out:
- **Repo identity:** a colour and sigil per repo.
- **Ranked attention with dismissals:** what needs you, in order, less what you've already dealt with.
- **The orchestrator:** its last message and a way to send it one.
- **The dependency chain:** which work depends on which repo, and when that work landed.

The plan is built around that gap. See [the prior art](docs/research/prior-art.md).

## What it does today (M2)

- **In the bar:** Muster's diamond with the count of what needs you, coloured
  by the most urgent reason (red blocked, orange landed, yellow stopped, green
  done). It is dim when nothing needs you and a hollow `◇` with no count when
  the snapshot is stale. It is hidden only while there is no snapshot at all.
  The tooltip lists the rows.
- **In the panel:** the ribbon exactly as Muster's overlay draws it (your
  dismissals and picked colours included), the orchestrator with what it last
  said, and one line per repo with its agents counted by status.
- **Jumping:** click a row, or `j`/`k` then `enter`, to land on its pane.
  herdr's window comes forward, or opens if there is none. `esc` closes.

It reads Muster's files and runs `muster`; it holds no herdr connection of its
own. Only the default herdr session is shown for now.

## Install

Needs [Muster](https://github.com/ofelcan164/muster) installed in herdr, and
Omarchy 4.

```bash
omarchy plugin add https://github.com/ofelcan164/muster-omarchy --enable
```

Two settings, both usually left alone:

| Setting | Default | What it is |
|---|---|---|
| `stateDir` | empty, meaning `~/.local/state/herdr/plugins/muster` | Where `musterd` writes `snapshot.json` |
| `muster` | `muster` | The binary to run. A bare name is looked up on `PATH`, then in the tab bar entry `muster install` wrote to herdr's config |

```bash
omarchy bar set io.github.ofelcan164.muster stateDir ~/some/other/dir
```

## Layout

```
manifest.json        bar-widget, entry BarWidget.qml
BarWidget.qml        the diamond and count; loads the panel
Panel.qml            ribbon, orchestrator, repos; keys and clicks
Data.qml             watches snapshot.json and ui.json, the stale clock
Actions.qml          one queue of commands, each through bin/muster-omarchy
lib/muster.js        everything worked out from Muster's files, plain JS
bin/muster-omarchy   finds muster, runs `muster jump`, raises herdr's window
tests/               node tests, a headless QML run, the snapshot fixture
```

## Development

```bash
node --test tests/*.test.js         # lib/muster.js and bin/muster-omarchy
python3 tests/qml/run.py            # the real QML, headless (pip install PySide6-Essentials)
omarchy plugin validate .           # the manifest, as the shell checks it
tests/fixtures/regen.sh ~/src/muster   # rebuild the fixture after Muster's model changes
```

`tests/qml/stubs/` stands in for Quickshell and Omarchy's `qs.*` modules with
the same properties, signals and functions, read from `omacom/omarchy` at
`93e8cd5`. The run fails on any QML warning, so a typo in a property or a
binding that throws is caught before it reaches a shell.

## Reading order

1. [`docs/plan.md`](docs/plan.md): architecture, settled decisions, spikes,
   and milestones M0–M5 with tasks and done criteria.
2. [`docs/research/prior-art.md`](docs/research/prior-art.md): the existing
   herdr plugins for Omarchy and what each already covers.
3. [`docs/research/omarchy-shell-plugins.md`](docs/research/omarchy-shell-plugins.md):
   how Omarchy 4 plugins work (manifest, kinds, IPC, bar modules,
   notifications, keybindings).
4. [`docs/research/omarchy-herdr.md`](docs/research/omarchy-herdr.md): how
   Omarchy already ships and configures herdr, and where that meets Muster.
5. [`docs/research/muster-interfaces.md`](docs/research/muster-interfaces.md):
   what Muster exposes to a process outside herdr today, and what it lacks.

## Sources

Everything here was read from source on 2026-09-24, not recalled:

| Source | Commit |
|---|---|
| [`omacom/omarchy`](https://github.com/omacom/omarchy) (manual, `docs/omarchy-shell.md`, `shell/`, `config/`, `default/`, `bin/`) | `28ceaae`, 2026-09-23, `version` reads `4.0.0.alpha` |
| [`omacom/omarchy-plugin-marketplace`](https://github.com/omacom/omarchy-plugin-marketplace) `site/catalog.json` (4110 plugins) | cloned 2026-09-24 |
| [`jankeesvw/omarchy-herdr`](https://github.com/jankeesvw/omarchy-herdr) | `49fca4a`, 2026-09-18 |
| [`stappmus/Udder`](https://github.com/stappmus/Udder) | `2aaac75`, 2026-09-21 |
| [`njpatel/omaherdr`](https://github.com/njpatel/omaherdr) | `c20d9b0`, 2026-09-16 |
| [`meviusisback/agent-orchestr`](https://github.com/meviusisback/agent-orchestr) | `cb35aaa`, 2026-09-16 |
| [`FerC10110/omarchy-hypr-rules-studio`](https://github.com/FerC10110/omarchy-hypr-rules-studio) (a third-party plugin as reference) | `196d814`, 2026-09-22 |
| [`ofelcan164/muster`](https://github.com/ofelcan164/muster) | `29c602f`, after #15 |

The Omarchy manual website and a plugin author's blog could not be fetched from
the environment this was researched in. Their content was read from the
manual's source in the Omarchy repo instead. Omarchy 4 is recent and moves
quickly, so recheck anything load-bearing against a current checkout before
building on it.
