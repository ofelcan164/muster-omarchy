.pragma library

// Everything the widget and panel know about Muster's files, as plain
// functions. No QML types here, so the tests can load this file in Node and
// drive it with snapshots shaped like the ones musterd writes.
//
// Muster's Go sources are the reference for every rule below, and each
// function names the one it mirrors. When the two disagree, Muster is right.

// The snapshot_version values this widget can read. A snapshot from before
// Muster wrote the field has none, and reads as 0: its shape is version 1's,
// less the field. (model.Snapshot)
var SNAPSHOT_VERSION = 1

// A snapshot this old means musterd is not running: it rewrites every five
// seconds. (model.StaleAfter)
var STALE_AFTER_MS = 30 * 1000

// The overlay draws at most this many ribbon rows. (triage.RibbonMax)
var RIBBON_MAX = 4

// Repo colours, by the snapshot's color_index. (identity.Palette)
var PALETTE = [
  "#fb4934", "#ff6b6b", "#fe8019", "#fab387", "#fabd2f",
  "#f9e2af", "#b8bb26", "#a6e3a1", "#8ec07c", "#94e2d5",
  "#89dceb", "#74c7ec", "#89b4fa", "#b4befe", "#cba6f7",
  "#d3869b", "#f5c2e7", "#ff79c6", "#83a598", "#d5c4a1"
]

// A workspace with no repository. (identity.NeutralColor, NeutralSigil)
var NEUTRAL_COLOR = "#928374"
var NEUTRAL_SIGIL = "○"

// The overlay's own accents, so a row reads the same in both places.
// (ui/theme.go)
var RED = "#fb4934"
var ORANGE = "#fe8019"
var YELLOW = "#fabd2f"
var GREEN = "#b8bb26"
var DIM = "#928374"
var FAINT = "#665c54"
var FG = "#ebdbb2"
var BG = "#1d2021"
// The pulse's other half: blocked breathes between RED and this.
var RED_DIM = "#cc241d"
// Row backgrounds: the selection, a ribbon row, and the top two ranks.
var SEL_BG = "#3c3836"
var PANEL_BG = "#282828"
var HOT_BG = "#3a2a26"

// Working spins and blocked pulses. Frame 0 is the resting frame; the overlay
// steps one frame every 120ms, and the pulse holds each red for four.
// (ui.spinner, ui.pulseFrames, ui.animInterval)
var SPINNER = ["◐", "◓", "◑", "◒"]
var PULSE_FRAMES = 4
var FRAME_MS = 120

// ------------------------------------------------------------------ reading

// parseSnapshot reads snapshot.json's text. It returns { ok, snapshot, error };
// a snapshot that parses but is not the shape musterd writes is an error, not
// an empty screen.
function parseSnapshot(text) {
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return { ok: false, snapshot: null, error: "snapshot.json is not JSON" }
  }
  if (!isObject(raw)) return { ok: false, snapshot: null, error: "snapshot.json is not an object" }

  var version = raw.snapshot_version === undefined ? 0 : raw.snapshot_version
  if (typeof version !== "number" || version !== Math.floor(version) || version < 0)
    return { ok: false, snapshot: null, error: "snapshot_version is not a number" }

  var orch = isObject(raw.orchestrator) ? raw.orchestrator : {}
  return {
    ok: true,
    error: "",
    snapshot: {
      version: version,
      generatedAtMs: parseTime(raw.generated_at),
      daemonPid: Number(raw.daemon_pid) || 0,
      repos: arrayOf(raw.repos),
      workspaces: arrayOf(raw.workspaces),
      attention: arrayOf(raw.attention),
      orchestrator: {
        found: orch.found === true,
        paneId: String(orch.pane_id || ""),
        name: String(orch.name || ""),
        status: String(orch.status || ""),
        lastSaid: String(orch.last_said || ""),
        saidAtMs: parseTime(orch.said_at),
        statusSinceMs: parseTime(orch.status_since)
      },
      counts: isObject(raw.counts) ? raw.counts : {},
      focusedWorkspace: String(raw.focused_workspace || "")
    }
  }
}

// The sort modes s cycles through, in ui.json's numbering: first seen, a-z,
// attention, herdr. (ui.SortMode)
var SORT_MODES = 4

// parseUi reads ui.json's text. A missing or broken file is the overlay's
// defaults, never an error: that is how Muster reads it too. (state.LoadUI)
function parseUi(text) {
  var out = { dismissed: {}, colors: {}, sort: 0 }
  var raw
  try {
    raw = JSON.parse(String(text || ""))
  } catch (e) {
    return out
  }
  if (!isObject(raw)) return out
  if (isObject(raw.dismissed)) {
    for (var pane in raw.dismissed)
      if (typeof raw.dismissed[pane] === "string") out.dismissed[pane] = raw.dismissed[pane]
  }
  if (typeof raw.sort === "number" && raw.sort >= 0 && raw.sort < SORT_MODES && raw.sort === Math.floor(raw.sort))
    out.sort = raw.sort
  if (isObject(raw.colors)) {
    for (var key in raw.colors)
      if (typeof raw.colors[key] === "number") out.colors[key] = raw.colors[key]
  }
  return out
}

// parseTime reads a Go time.Time as JSON writes it: RFC 3339 with up to nine
// fractional digits and a zone. Date.parse is not trusted with that many
// digits in every engine, so the fields are taken apart by hand. Go's zero
// time (year 1) is "never" and comes back as NaN, like anything unreadable.
function parseTime(value) {
  var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$/.exec(String(value || ""))
  if (!m) return NaN
  var year = Number(m[1])
  if (year <= 1) return NaN
  var ms = m[7] ? Number((m[7] + "00").slice(0, 3)) : 0
  var t = Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), ms)
  if (m[8] !== "Z") {
    var sign = m[8][0] === "-" ? -1 : 1
    var offset = Number(m[8].slice(1, 3)) * 60 + Number(m[8].slice(4, 6))
    t -= sign * offset * 60 * 1000
  }
  return t
}

// ---------------------------------------------------------------- the state

// isNewer says the snapshot was written by a Muster that has moved past what
// this widget reads. The fix is updating the widget, not Muster.
function isNewer(snap) {
  return !!snap && snap.version > SNAPSHOT_VERSION
}

// isStale says nobody is keeping the snapshot current. An unreadable
// timestamp counts: a count nobody vouches for is worse than none.
// (ui.Badge: time.Since(GeneratedAt) >= StaleAfter)
function isStale(snap, nowMs) {
  if (!snap || isNaN(snap.generatedAtMs)) return true
  return nowMs - snap.generatedAtMs >= STALE_AFTER_MS
}

// undismissed is the attention rows less any dismissed at their current
// status: a status change is what makes a row news again. (ui.undismissed)
function undismissed(attention, dismissed) {
  var out = []
  var d = dismissed || {}
  for (var i = 0; i < (attention || []).length; i++) {
    var a = attention[i]
    if (!a) continue
    if (d[a.pane_id] === a.status) continue
    out.push(a)
  }
  return out
}

// ribbon is what the overlay's ribbon draws: undismissed, then capped, so
// dismissing a row promotes the next one. (ui.ribbonRows)
function ribbon(snap, ui) {
  if (!snap) return []
  return undismissed(snap.attention, ui ? ui.dismissed : null).slice(0, RIBBON_MAX)
}

// needsYou is every undismissed row, not just the ones that fit: the count
// the overlay's header and herdr's tab bar badge both show.
function needsYou(snap, ui) {
  if (!snap) return 0
  return undismissed(snap.attention, ui ? ui.dismissed : null).length
}

// ------------------------------------------------------------------ words

// reasonLabel says why a row is there, not what state the agent is in.
// (ui.reasonLabel)
function reasonLabel(reason, status) {
  switch (reason) {
  case "landed": return "LANDED"
  case "process_stopped": return "STOPPED"
  case "idle_never_done": return "STALE"
  case "blocked": return "BLOCKED"
  case "done_unseen": return "DONE"
  }
  return String(status || "").toUpperCase()
}

// reasonColor is the accent a ribbon row is keyed to. (ui.reasonAccent)
function reasonColor(reason) {
  switch (reason) {
  case "blocked": return RED
  case "landed": return ORANGE
  case "process_stopped": return YELLOW
  case "done_unseen": return GREEN
  }
  return DIM
}

// statusColor colours an agent by what it needs from you. A frame past the
// resting one pulses blocked. (ui.statusStyle)
function statusColor(status, frame) {
  switch (status) {
  case "blocked": return Math.floor((frame || 0) / PULSE_FRAMES) % 2 === 1 ? RED_DIM : RED
  case "done": return GREEN
  case "working": return YELLOW
  case "idle": return DIM
  }
  return FAINT
}

// statusIcon is the overlay's icon for each status at an animation frame; 0,
// or none, is the resting one. (ui.statusIcon)
function statusIcon(status, frame) {
  switch (status) {
  case "blocked": return "▲"
  case "done": return "●"
  case "working": return SPINNER[(frame || 0) % SPINNER.length]
  case "idle": return "○"
  }
  return "◌"
}

// ageText is a duration in the overlay's one-unit form: 42s, 7m, 3h, 2d. An
// age the daemon never measured is "-". (ui.ageText)
function ageText(ms, known) {
  if (known === false || isNaN(ms)) return "-"
  var s = Math.max(0, Math.floor(ms / 1000))
  if (s < 60) return s + "s"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h"
  return Math.floor(s / 86400) + "d"
}

// ------------------------------------------------------------------- repos

function repoByKey(snap, key) {
  var repos = snap ? snap.repos : []
  for (var i = 0; i < repos.length; i++)
    if (repos[i] && repos[i].key === key) return repos[i]
  return null
}

// repoColor is a colour picked with c in the overlay when there is one, else
// the hashed one. A scratch workspace stays neutral. (ui.applyColors,
// ui.repoStyle)
function repoColor(repo, colors) {
  if (!repo) return NEUTRAL_COLOR
  var picked = colors ? colors[repo.key] : undefined
  if (repo.is_git && typeof picked === "number" && picked >= 0 && picked < PALETTE.length)
    return PALETTE[picked]
  var i = Number(repo.color_index)
  if (!(i >= 0 && i < PALETTE.length)) return NEUTRAL_COLOR
  return PALETTE[i]
}

function repoSigil(repo) {
  return repo && repo.sigil ? String(repo.sigil) : NEUTRAL_SIGIL
}

// repoName is what the overlay draws: display, widened only on a clash.
// (ui.shortRepo)
function repoName(repo) {
  if (!repo) return ""
  return String(repo.display || repo.name || repo.key || "")
}

// paneHome finds the repo and workspace a pane lives in, agent or not.
function paneHome(snap, paneId) {
  var repos = snap ? snap.repos : []
  for (var i = 0; i < repos.length; i++) {
    var r = repos[i] || {}
    var lists = [r.agents || [], r.other_panes || []]
    for (var l = 0; l < lists.length; l++) {
      for (var j = 0; j < lists[l].length; j++) {
        var p = lists[l][j]
        if (p && p.pane_id === paneId)
          return { repo: r, pane: p, workspace: workspaceById(snap, p.workspace_id) }
      }
    }
  }
  return { repo: null, pane: null, workspace: null }
}

function workspaceById(snap, id) {
  var list = snap ? snap.workspaces : []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].id === id) return list[i]
  return null
}

// ------------------------------------------------------------------- views

// barView is everything the bar button draws, from the snapshot file's state.
// fileState is "missing", "unreadable" or "loaded".
//
// The widget is hidden only when there is no snapshot at all: Muster is not
// installed, or herdr has never run it. Once there is one it stays, so the
// panel is a click away even when nothing needs you.
function barView(fileState, snap, ui, nowMs) {
  if (fileState === "missing" || (fileState !== "loaded" && fileState !== "unreadable"))
    return { visible: false, cls: "missing", text: "", color: "", dimmed: true, tooltip: "" }
  if (fileState === "unreadable" || !snap)
    return { visible: true, cls: "error", text: "◆ !", color: RED, dimmed: false,
             tooltip: "Muster: snapshot.json could not be read" }
  if (isNewer(snap))
    return { visible: true, cls: "update", text: "◆ !", color: ORANGE, dimmed: false,
             tooltip: updateText(snap) }
  if (isStale(snap, nowMs))
    return { visible: true, cls: "stale", text: "◇", color: "", dimmed: true,
             tooltip: staleText(snap, nowMs) }

  var rows = undismissed(snap.attention, ui ? ui.dismissed : null)
  var working = Number(snap.counts.working) || 0
  if (rows.length === 0) {
    return { visible: true, cls: working > 0 ? "working" : "idle", text: "◆", color: "", dimmed: true,
             tooltip: working > 0 ? "Muster · " + working + " working" : "Muster · nothing needs you" }
  }

  var landed = false
  for (var i = 0; i < rows.length; i++) if (rows[i].reason === "landed") landed = true

  var lines = []
  for (var k = 0; k < Math.min(rows.length, RIBBON_MAX); k++) lines.push(tooltipLine(snap, rows[k]))
  if (rows.length > RIBBON_MAX) lines.push("and " + (rows.length - RIBBON_MAX) + " more")

  return {
    visible: true,
    cls: landed ? "landed" : "needs-you",
    text: "◆ " + rows.length,
    color: reasonColor(rows[0].reason),
    dimmed: false,
    tooltip: lines.join("\n")
  }
}

// tooltipLine is one ribbon row as M0's badge --json formats it:
// REASON repo/agent · detail.
function tooltipLine(snap, a) {
  var repo = repoByKey(snap, a.repo_key)
  var who = (repo ? repoName(repo) : String(a.repo_key || "")) + "/" + String(a.agent || "")
  var line = reasonLabel(a.reason, a.status) + " " + who
  if (a.detail) line += " · " + oneLine(a.detail)
  return line
}

function updateText(snap) {
  return "Muster writes snapshot v" + snap.version + " and this widget reads up to v" +
    SNAPSHOT_VERSION + ". Update it: omarchy plugin update io.github.ofelcan164.muster"
}

function staleText(snap, nowMs) {
  if (!snap || isNaN(snap.generatedAtMs)) return "Muster's snapshot has no time on it. Is musterd running?"
  return "Muster's snapshot is " + ageText(nowMs - snap.generatedAtMs, true) +
    " old: musterd is not running. It starts with herdr."
}

// ribbonView is the ribbon rows the panel draws, each with everything its
// delegate needs, in snapshot order. (ui.ribbonLines)
function ribbonView(snap, ui) {
  var rows = ribbon(snap, ui)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var a = rows[i]
    var home = paneHome(snap, a.pane_id)
    var repo = repoByKey(snap, a.repo_key) || home.repo
    // Only an agent's pane leads with its workspace: a stopped process is
    // drawn without one, as the overlay does. (ui.workspaceOf)
    var ws = home.pane && isAgentPane(snap, a.pane_id) ? home.workspace : null
    out.push({
      paneId: String(a.pane_id || ""),
      index: i + 1,
      reason: String(a.reason || ""),
      label: reasonLabel(a.reason, a.status),
      accent: reasonColor(a.reason),
      hot: Number(a.rank) <= 2,
      workspace: ws && ws.label ? ws.number + " " + ws.label : "",
      sigil: repoSigil(repo),
      repo: repo ? repoName(repo) : String(a.repo_key || ""),
      repoColor: repoColor(repo, ui ? ui.colors : null),
      agent: String(a.agent || ""),
      age: ageText(Number(a.age_ns) / 1e6, a.age_known !== false),
      detail: oneLine(a.detail),
      dependents: arrayOf(a.dependents)
    })
  }
  return out
}

// orchestratorView is the strip: who, what state and for how long, and what
// it last said. (ui.stripLines, ui.orchWho, ui.saidLines)
function orchestratorView(snap, ui, nowMs) {
  var o = snap ? snap.orchestrator : null
  if (!o || !o.found) return { found: false }
  var home = paneHome(snap, o.paneId)
  var who, color, sigil
  if (home.repo && home.pane) {
    who = repoName(home.repo).toUpperCase()
    sigil = repoSigil(home.repo)
    color = repoColor(home.repo, ui ? ui.colors : null)
  } else {
    who = (o.name || "orchestrator").toUpperCase()
    sigil = ""
    color = ""
  }
  var said = String(o.lastSaid || "").trim()
  return {
    found: true,
    paneId: o.paneId,
    who: who,
    sigil: sigil,
    color: color,
    status: o.status || "unknown",
    statusIcon: statusIcon(o.status),
    statusColor: statusColor(o.status),
    age: ageText(nowMs - o.statusSinceMs, !isNaN(o.statusSinceMs)),
    said: said,
    saidAge: said !== "" && !isNaN(o.saidAtMs) ? ageText(nowMs - o.saidAtMs, true) : ""
  }
}

// headerView is the overlay's title line: workspaces and agents counted, and
// how many rows need you. (ui.header)
function headerView(snap, ui) {
  if (!snap) return { counts: "", needsYou: 0 }
  var c = snap.counts || {}
  var workspaces = Number(c.workspaces)
  if (isNaN(workspaces)) workspaces = snap.workspaces.length
  return {
    counts: plural(workspaces, "workspace") + " · " + plural(Number(c.agents) || 0, "agent"),
    needsYou: needsYou(snap, ui)
  }
}

// attentionAccent colours the NEEDS YOU rule by the top row on screen, not
// one you have dismissed. (ui.attentionRule)
function attentionAccent(snap, ui) {
  var rows = ribbon(snap, ui)
  return rows.length > 0 ? reasonColor(rows[0].reason) : DIM
}

// tile is one cell of the overlay's grid: one per agent, and one per workspace
// holding none, grouped from the repos by workspace. (ui.buildTiles)
function buildTiles(snap) {
  var repos = {}, agents = {}, panes = {}
  var list = snap ? snap.repos : []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r) continue
    var wsIds = arrayOf(r.workspace_ids)
    for (var w = 0; w < wsIds.length; w++) (repos[wsIds[w]] = repos[wsIds[w]] || []).push(r)
    var as = arrayOf(r.agents)
    for (var a = 0; a < as.length; a++)
      if (as[a]) (agents[as[a].workspace_id] = agents[as[a].workspace_id] || []).push({ repo: r, agent: as[a] })
    var ps = arrayOf(r.other_panes)
    for (var p = 0; p < ps.length; p++)
      if (ps[p]) (panes[ps[p].workspace_id] = panes[ps[p].workspace_id] || []).push(ps[p])
  }
  for (var k in repos) repos[k] = stableSort(repos[k], function(x, y) { return cmp(slotOf(x), slotOf(y)) })
  for (var q in panes) panes[q] = stableSort(panes[q], function(x, y) { return cmp(String(x.pane_id), String(y.pane_id)) })

  var out = []
  var wss = snap ? snap.workspaces : []
  for (var n = 0; n < wss.length; n++) {
    var ws = wss[n]
    if (!ws) continue
    var here = stableSort(agents[ws.id] || [], function(x, y) { return cmp(String(x.agent.pane_id), String(y.agent.pane_id)) })
    if (here.length === 0) {
      out.push({ agent: null, repo: null, workspace: ws, repos: repos[ws.id] || [], panes: panes[ws.id] || [], agents: 0 })
      continue
    }
    for (var h = 0; h < here.length; h++)
      out.push({ agent: here[h].agent, repo: here[h].repo, workspace: ws, repos: [], panes: panes[ws.id] || [], agents: here.length })
  }
  return out
}

// orderTiles is the grid in the sort ui.json holds, busy tiles first except in
// herdr's own order. (ui.orderedTiles)
function orderTiles(tiles, snap, sort) {
  var out = tiles.slice()
  if (sort === 1) {
    out = stableSort(out, function(a, b) {
      return cmp(tileLabel(a).toLowerCase(), tileLabel(b).toLowerCase()) ||
        cmp(a.agent ? String(a.agent.name || "") : "", b.agent ? String(b.agent.name || "") : "")
    })
  } else if (sort === 2) {
    var rank = {}
    var att = snap ? snap.attention : []
    for (var i = 0; i < att.length; i++) {
      var r = att[i]
      if (r && (rank[r.pane_id] === undefined || r.rank < rank[r.pane_id])) rank[r.pane_id] = r.rank
    }
    out = stableSort(out, function(a, b) { return cmp(tileRank(a, rank), tileRank(b, rank)) || cmp(tileSlot(a), tileSlot(b)) })
  } else if (sort === 3) {
    return stableSort(out, function(a, b) {
      return cmp(Number(a.workspace.number), Number(b.workspace.number)) ||
        cmp(a.agent ? String(a.agent.pane_id) : "", b.agent ? String(b.agent.pane_id) : "")
    })
  } else {
    out = stableSort(out, function(a, b) { return cmp(tileSlot(a), tileSlot(b)) })
  }
  return stableSort(out, function(a, b) { return (b.agent ? 1 : 0) - (a.agent ? 1 : 0) })
}

// tilesView is the grid as the overlay draws it at one column, each tile with
// what its lines need. key is the tile's target; jump is what muster jump
// takes for it: the agent's pane, or ws:<id> to focus an empty workspace.
// (ui.agentTileLines, ui.emptyTileLines)
function tilesView(snap, ui, nowMs) {
  var colors = ui ? ui.colors : null
  var tiles = orderTiles(buildTiles(snap), snap, ui ? ui.sort : 0)
  var focused = snap ? String(snap.focusedWorkspace || "") : ""
  var out = []
  for (var i = 0; i < tiles.length; i++) {
    var t = tiles[i]
    var ws = t.workspace
    var num = (ws.id && ws.id === focused ? "▸" : " ") + ws.number
    if (!t.agent) {
      var sigils = []
      for (var s = 0; s < t.repos.length; s++) sigils.push({ sigil: repoSigil(t.repos[s]), color: repoColor(t.repos[s], colors) })
      out.push({
        key: "ws:" + ws.id, jump: "ws:" + ws.id, isAgent: false, paneId: "",
        barColor: FAINT, num: num, label: String(ws.label || "").toLowerCase(),
        sigils: sigils, detail: emptyTileDetail(t)
      })
      continue
    }
    var a = t.agent
    var task = taskLine(a)
    out.push({
      key: "pane:" + a.pane_id, jump: String(a.pane_id), isAgent: true, paneId: String(a.pane_id),
      barColor: repoColor(t.repo, colors),
      num: num, label: String(ws.label || ""), chip: "[" + paneChip(a) + "]",
      sigil: repoSigil(t.repo), repo: repoName(t.repo), repoColor: repoColor(t.repo, colors),
      branch: String(t.repo.branch || ""),
      orchestrator: a.is_orchestrator === true,
      status: String(a.status || "unknown"),
      name: String(a.name || ""), kind: String(a.kind || ""),
      age: agentAge(a, nowMs),
      task: task.text, taskColor: task.color,
      dependsOn: dependsOnLine(snap, a, colors, nowMs),
      neededBy: neededBy(snap, t.repo, colors),
      footer: t.panes.length > 0 ? panesFooter(t) : ""
    })
  }
  return out
}

// agentAge is how long an agent has held its status, or "-" when the daemon
// never watched it begin. (model.Agent.Age, ui.ageText)
function agentAge(a, nowMs) {
  var since = parseTime(a.status_since)
  return ageText(isNaN(since) ? 0 : nowMs - since, a.age_known !== false)
}

// taskLine is a tile's says line: the question when it is blocked, the task
// otherwise, marked when it came from the orchestrator's stale word.
// (ui.taskText, ui.tileTaskLine)
function taskLine(a) {
  var q = oneLine(a.question)
  if (q !== "") return { text: "? " + q, color: FG }
  var task = oneLine(a.task)
  if (task === "" || a.task_source === "none") return { text: "", color: DIM }
  if (a.task_source === "orchestrator_stale") return { text: "(stale) " + task, color: FAINT }
  return { text: task, color: DIM }
}

// dependsOnLine is what this agent waits on, and whether it landed yet, or
// null. The repo is drawn in its own colour. (ui.tileEdgeLines)
function dependsOnLine(snap, a, colors, nowMs) {
  if (!a.depends_on) return null
  var up = a.depends_on_repo ? repoByKey(snap, a.depends_on_repo) : null
  var landed = parseTime(a.landed_at)
  return {
    sigil: up ? repoSigil(up) : "",
    repo: up ? repoName(up) : String(a.depends_on),
    color: up ? repoColor(up, colors) : DIM,
    when: isNaN(landed) ? "can't land yet" : "landed " + ageText(nowMs - landed, true) + " ago"
  }
}

// neededBy is each repo with an agent that depends on this one. (ui.tileEdgeLines)
function neededBy(snap, repo, colors) {
  var out = []
  var list = snap ? snap.repos : []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    var as = arrayOf(r && r.agents)
    for (var j = 0; j < as.length; j++) {
      if (as[j] && repo && as[j].depends_on_repo === repo.key) {
        out.push({ sigil: repoSigil(r), repo: repoName(r), color: repoColor(r, colors) })
        break
      }
    }
  }
  return out
}

// paneChip is the pane's name once it has one, its short id until then.
// (ui.paneChip, ui.shortPane)
function paneChip(a) {
  var label = String(a.pane_label || "")
  if (label !== "") return label
  var id = String(a.pane_id || "")
  var at = id.indexOf(":")
  return at >= 0 && at < id.length - 1 ? id.slice(at + 1) : id
}

// panesFooter is the line every agent tile in a workspace shares once it also
// holds other panes. (ui.tilePanesFooter)
function panesFooter(t) {
  var labels = []
  for (var i = 0; i < t.panes.length; i++) labels.push(String(t.panes[i].label || ""))
  return plural(t.agents, "agent") + " · " + plural(t.panes.length, "pane") + " · " + labels.join(" · ")
}

// emptyTileDetail is an empty workspace's second line: its one repo and
// branch, or every repo's name, then its panes. (ui.emptyTileDetail)
function emptyTileDetail(t) {
  var parts = []
  if (t.repos.length === 1) {
    var r = t.repos[0]
    parts.push(repoName(r) + (r.branch ? " " + r.branch : ""))
  } else {
    for (var i = 0; i < t.repos.length; i++) parts.push(repoName(t.repos[i]))
  }
  for (var j = 0; j < t.panes.length; j++) parts.push(String(t.panes[j].label || ""))
  return parts.join(" · ")
}

// reportTarget is the landed row t reports: the selected pane's when it has
// one, else the only one there is. With several and none selected it is
// null, because picking for you would send the wrong report. (ui.reportTarget)
function reportTarget(snap, selectedPane) {
  var rows = []
  var att = snap ? snap.attention : []
  for (var i = 0; i < att.length; i++) if (att[i] && att[i].reason === "landed") rows.push(att[i])
  if (rows.length === 0) return null
  if (selectedPane) {
    for (var j = 0; j < rows.length; j++) if (rows[j].pane_id === selectedPane) return rows[j]
  }
  return rows.length === 1 ? rows[0] : null
}

// stripHint is the strip's last line, which says what t would report.
// (ui.stripHint)
function stripHint(snap, selectedPane) {
  var row = reportTarget(snap, selectedPane)
  if (!row) return " › press i to tell it something"
  var dep = agentByPane(snap, row.pane_id)
  var up = dep ? repoByKey(snap, dep.depends_on_repo) : null
  return " › i tells it something · t tells it " + (up ? repoName(up) : "") + " landed"
}

// ----------------------------------------------------------------- helpers

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function arrayOf(v) {
  return Array.isArray(v) ? v : []
}

function plural(n, noun) {
  return n + " " + noun + (n === 1 ? "" : "s")
}

function cmp(a, b) {
  return a < b ? -1 : a > b ? 1 : 0
}

// stableSort sorts a copy, keeping equal items in order, as slices.SortStableFunc.
function stableSort(list, compare) {
  var indexed = list.map(function(v, i) { return { v: v, i: i } })
  indexed.sort(function(a, b) { return compare(a.v, b.v) || a.i - b.i })
  return indexed.map(function(x) { return x.v })
}

function slotOf(repo) {
  var s = Number(repo && repo.grid_slot)
  return isNaN(s) ? 0 : s
}

// tileSlot orders first seen: an agent by its repo's slot, an empty workspace
// by its first repo's, one touching no repo last. (ui.tile.slot)
function tileSlot(t) {
  if (t.agent) return slotOf(t.repo)
  if (t.repos.length > 0) return slotOf(t.repos[0])
  return 1 << 30
}

// tileLabel orders a-z. (ui.tile.label)
function tileLabel(t) {
  return t.agent ? repoName(t.repo) : String(t.workspace.label || "")
}

// tileRank orders attention: a ribbon rank, then working, then the rest.
// (ui.tileRank)
function tileRank(t, rank) {
  if (!t.agent) return 99
  if (rank[t.agent.pane_id] !== undefined) return rank[t.agent.pane_id]
  return t.agent.status === "working" ? 50 : 99
}

function agentByPane(snap, paneId) {
  var list = snap ? snap.repos : []
  for (var i = 0; i < list.length; i++) {
    var as = arrayOf(list[i] && list[i].agents)
    for (var j = 0; j < as.length; j++) if (as[j] && as[j].pane_id === paneId) return as[j]
  }
  return null
}

function isAgentPane(snap, paneId) {
  return agentByPane(snap, paneId) !== null
}

// oneLine folds a pane's text onto one line: details and questions are read
// off a terminal and can carry its line breaks.
function oneLine(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}
