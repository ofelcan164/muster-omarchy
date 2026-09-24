# muster-omarchy

Planning and research for an Omarchy shell plugin that brings
[Muster](https://github.com/ofelcan164/muster)'s view of herdr agents out of
the herdr popup and onto the desktop.

**Status: planning only.** This repository holds Markdown and nothing else.
No plugin code gets written until the plan's go/no-go question has an answer.

## The idea in one paragraph

Muster is a herdr plugin: an overlay you open inside herdr that shows every
agent across every repo, ranks what needs you, and keeps the orchestrator and
the dependencies between repos in view. That overlay is modal, and you only see
it once you have opened it. This plugin would put the same picture in the
Omarchy bar and in a panel you can leave pinned on the desktop, so you can see
what needs you without first switching to herdr.

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

## Reading order

1. [`docs/plan.md`](docs/plan.md): positioning, phases, what Muster itself
   would need, decisions, open questions, and the go/no-go.
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
